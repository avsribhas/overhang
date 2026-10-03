import Foundation

public enum DurationFormatter {
    /// `65` → `1:05`, `3725` → `1:02:05`. Negative values clamp to zero.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// Compact form for tight spaces: `25m`, `1h 5m`, `40s`.
    public static func short(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s" }
        let h = total / 3600
        let m = (total % 3600) / 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Parses `5`, `5m`, `90s`, `1h30m`, `1:30` (minutes:seconds) into seconds. Bare numbers are minutes.
    public static func parse(_ input: String) -> TimeInterval? {
        let text = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return nil }
        if text.contains(":") {
            let parts = text.split(separator: ":").map { Double($0) }
            guard parts.allSatisfy({ $0 != nil }) else { return nil }
            let values = parts.compactMap { $0 }
            switch values.count {
            case 2: return values[0] * 60 + values[1]
            case 3: return values[0] * 3600 + values[1] * 60 + values[2]
            default: return nil
            }
        }
        if let minutes = Double(text) { return minutes > 0 ? minutes * 60 : nil }
        var total: Double = 0
        var number = ""
        var matchedAny = false
        for c in text where !c.isWhitespace {
            if c.isNumber || c == "." {
                number.append(c)
            } else {
                guard let value = Double(number) else { return nil }
                switch c {
                case "h": total += value * 3600
                case "m": total += value * 60
                case "s": total += value
                default: return nil
                }
                number = ""
                matchedAny = true
            }
        }
        guard matchedAny, number.isEmpty, total > 0 else { return nil }
        return total
    }
}

/// Pure Pomodoro phase sequencing: work → short break → … → long break every N work sessions.
public struct PomodoroCycle: Equatable, Codable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case work = "Focus"
        case shortBreak = "Short Break"
        case longBreak = "Long Break"
    }

    public var phase: Phase = .work
    public var completedWorkSessions = 0
    public var sessionsBeforeLongBreak: Int

    public init(sessionsBeforeLongBreak: Int = 4) {
        self.sessionsBeforeLongBreak = max(1, sessionsBeforeLongBreak)
    }

    /// Advances to the next phase and returns it.
    @discardableResult
    public mutating func advance() -> Phase {
        switch phase {
        case .work:
            completedWorkSessions += 1
            phase = completedWorkSessions % sessionsBeforeLongBreak == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            phase = .work
        }
        return phase
    }

    public func duration(work: TimeInterval, shortBreak: TimeInterval, longBreak: TimeInterval) -> TimeInterval {
        switch phase {
        case .work: work
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}
