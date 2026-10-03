import Foundation
import OverhangCore
import SwiftUI

/// Sums token usage from coding agents' local session logs. Nothing is sent anywhere.
/// - Claude Code: ~/.claude/projects/**/*.jsonl (and ~/.config/claude/projects)
/// - Codex CLI:   ~/.codex/sessions/**/*.jsonl
final class AIUsageModel: ObservableObject {
    static let shared = AIUsageModel()

    @Published private(set) var summaries: [UsageRecord.Source: UsageSummary] = [:]
    @Published private(set) var foundSources: Set<UsageRecord.Source> = []
    @Published private(set) var scanning = false
    @Published private(set) var updated: Date?

    private let queue = DispatchQueue(label: "overhang.aiusage", qos: .utility)
    private var cache: [String: (modified: Date, size: Int, records: [(String?, UsageRecord)])] = [:]
    private var timer: Timer?

    func startAutoRefresh() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !scanning else { return }
        scanning = true
        queue.async { [weak self] in
            guard let self else { return }
            let home = FileManager.default.homeDirectoryForCurrentUser
            let claudeDirs = [home.appendingPathComponent(".claude/projects"), home.appendingPathComponent(".config/claude/projects")]
            let codexDir = home.appendingPathComponent(".codex/sessions")

            var found = Set<UsageRecord.Source>()
            var claudeRecords: [UsageRecord] = []
            var seen = Set<String>()
            for dir in claudeDirs where FileManager.default.fileExists(atPath: dir.path) {
                found.insert(.claudeCode)
                for file in self.recentFiles(in: dir) {
                    for (key, record) in self.records(in: file, source: .claudeCode) {
                        if let key { guard seen.insert(key).inserted else { continue } }
                        claudeRecords.append(record)
                    }
                }
            }
            var codexRecords: [UsageRecord] = []
            if FileManager.default.fileExists(atPath: codexDir.path) {
                found.insert(.codex)
                for file in self.recentFiles(in: codexDir) {
                    codexRecords += self.records(in: file, source: .codex).map { $0.1 }
                }
            }
            let result: [UsageRecord.Source: UsageSummary] = [
                .claudeCode: UsageLogParser.summarize(claudeRecords),
                .codex: UsageLogParser.summarize(codexRecords),
            ]
            DispatchQueue.main.async {
                self.summaries = result
                self.foundSources = found
                self.scanning = false
                self.updated = Date()
            }
        }
    }

    /// JSONL files modified in the last 7 days.
    private func recentFiles(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return [] }
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= cutoff
            else { continue }
            files.append(url)
        }
        return files
    }

    private func records(in file: URL, source: UsageRecord.Source) -> [(String?, UsageRecord)] {
        guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate
        else { return [] }
        let size = values.fileSize ?? 0
        if let cached = cache[file.path], cached.modified == modified, cached.size == size { return cached.records }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var output: [(String?, UsageRecord)] = []
        var codexModel = "codex"
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let string = String(line)
            switch source {
            case .claudeCode:
                if let parsed = UsageLogParser.parseClaudeCodeLine(string) { output.append((parsed.key, parsed.record)) }
            case .codex:
                if string.contains("turn_context"), let model = UsageLogParser.codexModel(fromLine: string) { codexModel = model }
                if let record = UsageLogParser.parseCodexLine(string, model: codexModel) { output.append((nil, record)) }
            }
        }
        cache[file.path] = (modified, size, output)
        return output
    }
}

struct AIUsageView: View {
    @ObservedObject private var model = AIUsageModel.shared
    @AppStorage(Prefs.aiBudget5h) private var budget = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("From local logs · cache reads excluded from totals")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer()
                if model.scanning { ProgressView().controlSize(.small) }
                IconButton(symbol: "arrow.clockwise", size: 24) { model.refresh() }
            }
            if model.updated != nil, model.foundSources.isEmpty {
                EmptyState(symbol: "gauge.with.dots.needle.0percent", title: "No agent logs found",
                           message: "Reads Claude Code (~/.claude/projects) and Codex CLI (~/.codex/sessions) session logs on this Mac.")
            } else {
                HStack(spacing: 10) {
                    ForEach(UsageRecord.Source.allCases.filter { model.foundSources.contains($0) }, id: \.self) { source in
                        SourceCard(source: source, summary: model.summaries[source] ?? UsageSummary(), budget: budget)
                    }
                }
            }
        }
        .onAppear { model.startAutoRefresh() }
        .onDisappear { model.stopAutoRefresh() }
    }
}

private struct SourceCard: View {
    let source: UsageRecord.Source
    let summary: UsageSummary
    let budget: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(source.rawValue).font(.system(size: 13, weight: .semibold))
            window("Last 5 hours", summary.last5Hours, showBudget: true)
            window("Today", summary.today, showBudget: false)
            window("Last 7 days", summary.last7Days, showBudget: false)
            if !summary.byModel.isEmpty {
                Divider().overlay(Color.white.opacity(0.1))
                ForEach(summary.byModel.prefix(3), id: \.self) { entry in
                    HStack {
                        Text(entry.model).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1)
                        Spacer()
                        Text(UsageLogParser.compactCount(entry.tokens)).font(.system(size: 10).monospacedDigit())
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
    }

    private func window(_ title: String, _ window: UsageWindow, showBudget: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(UsageLogParser.compactCount(window.billableTokens)) tok · \(window.requests) req")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            if showBudget, budget > 0 {
                let fraction = Double(window.billableTokens) / Double(budget)
                ProgressBar(value: fraction, color: fraction > 0.9 ? Theme.negative : fraction > 0.7 ? .orange : Theme.accent, height: 5)
            }
        }
    }
}
