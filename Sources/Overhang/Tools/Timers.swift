import AppKit
import OverhangCore
import SwiftUI
import UserNotifications

final class TimerService: ObservableObject {
    static let shared = TimerService()

    enum Mode: Equatable { case countdown, pomodoro }

    @Published private(set) var mode: Mode?
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var label = ""
    @Published private(set) var cycle = PomodoroCycle()
    @Published private(set) var now = Date()
    /// Set briefly after a timer finishes so the closed notch can show it.
    @Published private(set) var justFinished: String?

    private var ticker: Timer?

    var isActive: Bool { mode != nil }
    var isRunning: Bool { endDate != nil }

    var remaining: TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        return pausedRemaining ?? 0
    }

    var progress: Double { total > 0 ? 1 - remaining / total : 0 }

    // MARK: Commands

    func startCountdown(_ seconds: TimeInterval, label: String = "Timer") {
        mode = .countdown
        self.label = label
        begin(seconds)
    }

    func startPomodoro() {
        let every = UserDefaults.standard.integer(forKey: Prefs.pomodoroEvery)
        cycle = PomodoroCycle(sessionsBeforeLongBreak: every)
        mode = .pomodoro
        beginPhase()
    }

    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        stopTicker()
    }

    func resume() {
        guard let remaining = pausedRemaining, mode != nil else { return }
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(remaining)
        startTicker()
    }

    func stop() {
        mode = nil
        endDate = nil
        pausedRemaining = nil
        total = 0
        stopTicker()
    }

    func skipPhase() {
        guard mode == .pomodoro else { return stop() }
        cycle.advance()
        beginPhase()
    }

    func addTime(_ seconds: TimeInterval) {
        if let endDate {
            self.endDate = endDate.addingTimeInterval(seconds)
        } else if let paused = pausedRemaining {
            pausedRemaining = paused + seconds
        }
        total += seconds
    }

    // MARK: Internals

    private func beginPhase() {
        let d = UserDefaults.standard
        let duration = cycle.duration(
            work: d.double(forKey: Prefs.pomodoroWork) * 60,
            shortBreak: d.double(forKey: Prefs.pomodoroShort) * 60,
            longBreak: d.double(forKey: Prefs.pomodoroLong) * 60
        )
        label = cycle.phase.rawValue
        begin(max(duration, 1))
    }

    private func begin(_ seconds: TimeInterval) {
        Notifier.requestAuthorizationIfNeeded()
        total = seconds
        pausedRemaining = nil
        now = Date()
        endDate = now.addingTimeInterval(seconds)
        startTicker()
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        now = Date()
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        now = Date()
        guard let endDate, now >= endDate else { return }
        finish()
    }

    private func finish() {
        let finishedLabel = label
        NSSound(named: "Glass")?.play()
        flash(finishedLabel)
        if mode == .pomodoro {
            let next = cycle.advance()
            Notifier.post(title: "\(finishedLabel) finished", body: "Up next: \(next.rawValue)")
            beginPhase()
        } else {
            Notifier.post(title: "\(finishedLabel) finished", body: "Your timer is done.")
            stop()
        }
    }

    private func flash(_ text: String) {
        justFinished = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.justFinished = nil }
    }
}

/// Local notifications. Only works when running as a bundled .app.
enum Notifier {
    private static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }
    private static var requested = false

    static func requestAuthorizationIfNeeded() {
        guard available, !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

struct TimerToolView: View {
    @ObservedObject private var service = TimerService.shared
    @State private var custom = ""
    @AppStorage(Prefs.pomodoroWork) private var work = 25.0
    @AppStorage(Prefs.pomodoroShort) private var shortBreak = 5.0
    @AppStorage(Prefs.pomodoroLong) private var longBreak = 15.0

    var body: some View {
        if service.isActive { running } else { idle }
    }

    private var running: some View {
        HStack(spacing: 24) {
            ZStack {
                RingGauge(value: service.progress, color: service.isRunning ? Theme.accent : Theme.secondary, lineWidth: 8)
                VStack(spacing: 2) {
                    Text(DurationFormatter.clock(service.remaining))
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(service.label).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: 170, height: 170)

            VStack(alignment: .leading, spacing: 12) {
                if service.mode == .pomodoro {
                    Text("Session \(service.cycle.completedWorkSessions + (service.cycle.phase == .work ? 1 : 0))")
                        .font(.system(size: 13, weight: .semibold))
                }
                HStack(spacing: 10) {
                    IconButton(symbol: service.isRunning ? "pause.fill" : "play.fill", size: 40, tint: Theme.accent, filled: true) {
                        service.isRunning ? service.pause() : service.resume()
                    }
                    IconButton(symbol: "stop.fill", size: 34, help: "Stop") { service.stop() }
                    if service.mode == .pomodoro {
                        IconButton(symbol: "forward.end.fill", size: 34, help: "Skip phase") { service.skipPhase() }
                    }
                }
                HStack(spacing: 6) {
                    PillButton(title: "+1 min") { service.addTime(60) }
                    PillButton(title: "+5 min") { service.addTime(300) }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var idle: some View {
        HStack(alignment: .top, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Timer", systemImage: "timer").font(.system(size: 13, weight: .semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach([1, 3, 5, 10, 15, 30], id: \.self) { minutes in
                            PillButton(title: "\(minutes) min") { service.startCountdown(Double(minutes) * 60, label: "\(minutes) min timer") }
                        }
                    }
                    InputField(placeholder: "Custom: 90s, 1h30m, 2:30", text: $custom, symbol: "keyboard") {
                        if let seconds = DurationFormatter.parse(custom) {
                            service.startCountdown(seconds, label: DurationFormatter.short(seconds) + " timer")
                            custom = ""
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Pomodoro", systemImage: "brain.head.profile").font(.system(size: 13, weight: .semibold))
                    Stepper("Focus: \(Int(work)) min", value: $work, in: 5...120, step: 5)
                    Stepper("Short break: \(Int(shortBreak)) min", value: $shortBreak, in: 1...30)
                    Stepper("Long break: \(Int(longBreak)) min", value: $longBreak, in: 5...60, step: 5)
                    PillButton(title: "Start focus", symbol: "play.fill", prominent: true) { service.startPomodoro() }
                }
                .font(.system(size: 12))
            }
        }
    }
}
