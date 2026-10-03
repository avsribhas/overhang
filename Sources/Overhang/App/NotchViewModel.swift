import AppKit
import Combine
import SwiftUI

final class NotchViewModel: ObservableObject {
    enum State { case closed, open }

    @Published var state: State = .closed
    @Published var selectedTool: Tool {
        didSet { UserDefaults.standard.set(selectedTool.rawValue, forKey: Prefs.lastTool) }
    }
    @Published var pinned = false
    @Published var showingDropHint = false
    @Published var enabledTools: [Tool] = Prefs.enabledTools

    /// The camera housing (or a floating stand-in on Macs without a notch).
    let notchSize: CGSize
    let hasPhysicalNotch: Bool
    let openContentSize = CGSize(width: 700, height: 330)
    /// Width added on each side of the notch when a live activity is shown while closed.
    let activitySideWidth: CGFloat = 52

    let animation = Animation.spring(response: 0.38, dampingFraction: 0.8)

    private var cancellables = Set<AnyCancellable>()

    init(screen: NSScreen) {
        hasPhysicalNotch = screen.hasNotch
        if screen.hasNotch {
            notchSize = screen.notchSize
        } else {
            notchSize = CGSize(width: 190, height: min(max(screen.menuBarHeight, 24), 32))
        }
        let last = UserDefaults.standard.string(forKey: Prefs.lastTool).flatMap(Tool.init(rawValue:)) ?? .nowPlaying
        selectedTool = last

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let tools = Prefs.enabledTools
                if tools != self.enabledTools { self.enabledTools = tools }
                if !tools.contains(self.selectedTool), let first = tools.first { self.selectedTool = first }
            }
            .store(in: &cancellables)
    }

    var topCornerRadius: CGFloat { state == .open ? 14 : 6 }
    var bottomCornerRadius: CGFloat { state == .open ? 26 : 10 }

    /// Size of the black body (excluding the flared top corners).
    func bodySize(activity: LiveActivity?) -> CGSize {
        switch state {
        case .open:
            return openContentSize
        case .closed:
            let extra = activity == nil ? 0 : activitySideWidth * 2
            return CGSize(width: notchSize.width + extra, height: notchSize.height)
        }
    }
}
