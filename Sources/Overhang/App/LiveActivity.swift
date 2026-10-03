import AppKit
import Combine
import SwiftUI

/// What the closed notch shows on either side of the camera, Dynamic Island style.
enum LiveActivity: Equatable {
    case hud(symbol: String, level: Double?)
    case timer(remaining: TimeInterval, progress: Double, paused: Bool)
    case timerDone(label: String)
    case music(isPlaying: Bool)
    case keepAwake

    static func == (lhs: LiveActivity, rhs: LiveActivity) -> Bool {
        switch (lhs, rhs) {
        case let (.hud(a, b), .hud(c, d)): a == c && b == d
        case let (.timer(a, b, c), .timer(d, e, f)): Int(a) == Int(d) && abs(b - e) < 0.001 && c == f
        case let (.timerDone(a), .timerDone(b)): a == b
        case let (.music(a), .music(b)): a == b
        case (.keepAwake, .keepAwake): true
        default: false
        }
    }
}

/// Picks the most important live activity from the background services.
final class ActivityCenter: ObservableObject {
    static let shared = ActivityCenter()

    @Published private(set) var current: LiveActivity?
    @Published private(set) var hud: LiveActivity?

    private var hudClear: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let timer = TimerService.shared
        let music = NowPlayingService.shared
        let awake = KeepAwakeService.shared

        Publishers.MergeMany(
            timer.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            music.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            awake.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            $hud.map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () }.eraseToAnyPublisher()
        )
        // objectWillChange fires before the value changes; hop once so we read the new state.
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.recompute() }
        .store(in: &cancellables)

        VolumeService.shared.externalChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume, muted in
                let symbol = muted || volume == 0 ? "speaker.slash.fill"
                    : volume < 0.34 ? "speaker.wave.1.fill"
                    : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
                self?.flashHUD(.hud(symbol: symbol, level: muted ? 0 : Double(volume)))
            }
            .store(in: &cancellables)
    }

    func flashHUD(_ activity: LiveActivity, duration: TimeInterval = 1.6) {
        hudClear?.cancel()
        hud = activity
        let item = DispatchWorkItem { [weak self] in self?.hud = nil }
        hudClear = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func recompute() {
        let next = compute()
        if next != current { current = next }
    }

    private func compute() -> LiveActivity? {
        guard UserDefaults.standard.bool(forKey: Prefs.showLiveActivities) else { return hud }
        if let hud { return hud }
        let timer = TimerService.shared
        if let done = timer.justFinished { return .timerDone(label: done) }
        if timer.isActive {
            return .timer(remaining: timer.remaining, progress: timer.progress, paused: !timer.isRunning)
        }
        let music = NowPlayingService.shared
        if music.hasTrack, music.isPlaying { return .music(isPlaying: true) }
        if KeepAwakeService.shared.isActive { return .keepAwake }
        return nil
    }
}
