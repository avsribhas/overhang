import Foundation

/// One model call's token usage, read from a local agent log.
public struct UsageRecord: Equatable, Sendable {
    public enum Source: String, Sendable, CaseIterable {
        case claudeCode = "Claude Code"
        case codex = "Codex"
    }

    public let source: Source
    public let model: String
    public let timestamp: Date
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int

    public var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }
    /// Tokens excluding cache reads, which dominate raw totals but are cheap.
    public var billableTokens: Int { inputTokens + outputTokens + cacheCreationTokens }

    public init(source: Source, model: String, timestamp: Date, inputTokens: Int, outputTokens: Int,
                cacheCreationTokens: Int = 0, cacheReadTokens: Int = 0)
    {
        self.source = source
        self.model = model
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
    }
}

public struct UsageWindow: Equatable, Sendable {
    public var requests = 0
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheCreationTokens = 0
    public var cacheReadTokens = 0

    public init() {}

    public var billableTokens: Int { inputTokens + outputTokens + cacheCreationTokens }
    public var totalTokens: Int { billableTokens + cacheReadTokens }

    mutating func add(_ record: UsageRecord) {
        requests += 1
        inputTokens += record.inputTokens
        outputTokens += record.outputTokens
        cacheCreationTokens += record.cacheCreationTokens
        cacheReadTokens += record.cacheReadTokens
    }
}

public struct ModelUsage: Hashable, Sendable {
    public let model: String
    public let tokens: Int

    public init(model: String, tokens: Int) {
        self.model = model
        self.tokens = tokens
    }
}

public struct UsageSummary: Equatable, Sendable {
    public var last5Hours = UsageWindow()
    public var today = UsageWindow()
    public var last7Days = UsageWindow()
    /// Billable tokens in the last 7 days, per model, sorted descending.
    public var byModel: [ModelUsage] = []
    /// Oldest record inside the rolling 5-hour window, if any.
    public var oldestInLast5Hours: Date?

    public init() {}
}

public enum UsageLogParser {
    // ISO8601DateFormatter is thread-safe for parsing once configured.
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parseDate(_ text: String) -> Date? {
        fractionalFormatter.date(from: text) ?? plainFormatter.date(from: text)
    }

    private static func int(_ any: Any?) -> Int {
        if let n = any as? Int { return n }
        if let n = any as? Double { return Int(n) }
        if let n = any as? NSNumber { return n.intValue }
        return 0
    }

    /// Parses one line of a Claude Code session log (`~/.claude/projects/**/*.jsonl`).
    /// Returns a dedupe key (message id + request id) because Claude Code can write
    /// the same assistant message to the log more than once.
    public static func parseClaudeCodeLine(_ line: String) -> (key: String?, record: UsageRecord)? {
        guard line.contains("\"usage\""),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let timestampText = object["timestamp"] as? String,
              let timestamp = parseDate(timestampText)
        else { return nil }
        let model = message["model"] as? String ?? "unknown"
        if model == "<synthetic>" { return nil }
        let record = UsageRecord(
            source: .claudeCode,
            model: model,
            timestamp: timestamp,
            inputTokens: int(usage["input_tokens"]),
            outputTokens: int(usage["output_tokens"]),
            cacheCreationTokens: int(usage["cache_creation_input_tokens"]),
            cacheReadTokens: int(usage["cache_read_input_tokens"])
        )
        var key: String?
        if let id = message["id"] as? String {
            key = id + ":" + (object["requestId"] as? String ?? "")
        }
        return (key, record)
    }

    /// Parses one line of a Codex CLI rollout log (`~/.codex/sessions/**/*.jsonl`).
    /// Uses `token_count` events' `last_token_usage`, which is per-turn usage.
    public static func parseCodexLine(_ line: String, model: String = "codex") -> UsageRecord? {
        guard line.contains("token_count"),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let last = info["last_token_usage"] as? [String: Any],
              let timestampText = object["timestamp"] as? String,
              let timestamp = parseDate(timestampText)
        else { return nil }
        let cached = int(last["cached_input_tokens"])
        let input = max(0, int(last["input_tokens"]) - cached)
        return UsageRecord(
            source: .codex,
            model: model,
            timestamp: timestamp,
            inputTokens: input,
            outputTokens: int(last["output_tokens"]),
            cacheCreationTokens: 0,
            cacheReadTokens: cached
        )
    }

    /// Extracts the model name from a Codex `turn_context` line, if present.
    public static func codexModel(fromLine line: String) -> String? {
        guard line.contains("\"model\""),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              let model = payload["model"] as? String
        else { return nil }
        return model
    }

    public static func summarize(_ records: [UsageRecord], now: Date = Date(), calendar: Calendar = .current) -> UsageSummary {
        var summary = UsageSummary()
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86400)
        let startOfToday = calendar.startOfDay(for: now)
        var models: [String: Int] = [:]
        for record in records where record.timestamp <= now {
            if record.timestamp >= sevenDaysAgo {
                summary.last7Days.add(record)
                models[record.model, default: 0] += record.billableTokens
            }
            if record.timestamp >= startOfToday { summary.today.add(record) }
            if record.timestamp >= fiveHoursAgo {
                summary.last5Hours.add(record)
                if summary.oldestInLast5Hours.map({ record.timestamp < $0 }) ?? true {
                    summary.oldestInLast5Hours = record.timestamp
                }
            }
        }
        summary.byModel = models.map { ModelUsage(model: $0.key, tokens: $0.value) }
            .sorted { $0.tokens == $1.tokens ? $0.model < $1.model : $0.tokens > $1.tokens }
        return summary
    }

    public static func compactCount(_ n: Int) -> String {
        let value = Double(n)
        switch n {
        case ..<1000: return "\(n)"
        case ..<1_000_000: return String(format: "%.1fK", value / 1000)
        case ..<1_000_000_000: return String(format: "%.1fM", value / 1_000_000)
        default: return String(format: "%.2fB", value / 1_000_000_000)
        }
    }
}
