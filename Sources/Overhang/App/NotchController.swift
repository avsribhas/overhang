import AppKit
import Combine
import SwiftUI

/// Owns the notch panel for one screen and decides when it opens and closes.
final class NotchController {
    /// The live controller, so tools can ask the notch to close (e.g. before sampling a color).
    static weak var current: NotchController?

    let screen: NSScreen
    let vm: NotchViewModel
    let panel: NotchPanel

    private var monitors: [EventMonitor] = []
    private var cancellables = Set<AnyCancellable>()
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount

    private let shadowPadding: CGFloat = 24

    init(screen: NSScreen) {
        self.screen = screen
        vm = NotchViewModel(screen: screen)

        let width = vm.openContentSize.width + 2 * 14 + 2 * shadowPadding
        let height = vm.openContentSize.height + shadowPadding
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        panel = NotchPanel(contentRect: frame)

        let root = NotchRootView(vm: vm)
            .environment(\.colorScheme, .dark)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        panel.onEscape = { [weak self] in self?.close() }

        NotchController.current = self
        startMonitoring()
    }

    deinit {
        monitors.forEach { $0.stop() }
    }

    func destroy() {
        monitors.forEach { $0.stop() }
        monitors.removeAll()
        cancellables.removeAll()
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: Geometry (screen coordinates, origin bottom-left)

    private var closedBodyRect: CGRect {
        let size = vm.bodySize(activity: ActivityCenter.shared.current)
        return CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private var openRect: CGRect {
        let size = vm.openContentSize
        return CGRect(x: screen.frame.midX - size.width / 2 - 14, y: screen.frame.maxY - size.height,
                      width: size.width + 28, height: size.height)
    }

    /// The hover target: the notch plus a little slack, and the full top edge above it.
    private var hoverRect: CGRect {
        closedBodyRect.insetBy(dx: -6, dy: -4)
    }

    // MARK: Monitoring

    private func startMonitoring() {
        let move = EventMonitor(mask: [.mouseMoved]) { [weak self] _ in self?.mouseMoved() }
        let down = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in self?.mouseDown(event) }
        let drag = EventMonitor(mask: [.leftMouseDragged]) { [weak self] _ in self?.mouseDragged() }
        monitors = [move, down, drag]
        monitors.forEach { $0.start() }

        vm.$pinned
            .dropFirst()
            .sink { [weak self] pinned in
                if !pinned { DispatchQueue.main.async { self?.mouseMoved() } }
            }
            .store(in: &cancellables)
    }

    private func mouseMoved() {
        let point = NSEvent.mouseLocation
        switch vm.state {
        case .closed:
            guard UserDefaults.standard.bool(forKey: Prefs.openOnHover) else { return }
            if hoverRect.contains(point) {
                guard openWork == nil else { return }
                let delay = max(0, UserDefaults.standard.double(forKey: Prefs.hoverDelay))
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.openWork = nil
                    if self.hoverRect.contains(NSEvent.mouseLocation) { self.open() }
                }
                openWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            } else {
                openWork?.cancel()
                openWork = nil
            }
        case .open:
            if openRect.insetBy(dx: -18, dy: -18).contains(point) {
                closeWork?.cancel()
                closeWork = nil
            } else if shouldAutoClose {
                scheduleClose()
            }
        }
    }

    private var shouldAutoClose: Bool {
        UserDefaults.standard.bool(forKey: Prefs.closeOnMouseExit) && !vm.pinned && NSEvent.pressedMouseButtons == 0
    }

    private func scheduleClose() {
        guard closeWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closeWork = nil
            guard self.vm.state == .open, self.shouldAutoClose,
                  !self.openRect.insetBy(dx: -18, dy: -18).contains(NSEvent.mouseLocation)
            else { return }
            self.close()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func mouseDown(_ event: NSEvent) {
        dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        let point = NSEvent.mouseLocation
        switch vm.state {
        case .closed:
            if hoverRect.contains(point) { open() }
        case .open:
            // Clicks inside our own panel arrive with a window; clicks elsewhere close unless pinned.
            if event.window !== panel, !openRect.contains(point), !vm.pinned {
                close()
            }
        }
    }

    private func mouseDragged() {
        guard vm.state == .closed else {
            closeWork?.cancel()
            closeWork = nil
            return
        }
        // Only react to real drag sessions (files, text), not window drags.
        let dragging = NSPasteboard(name: .drag).changeCount != dragChangeCountAtMouseDown
        guard dragging else { return }
        let target = closedBodyRect.insetBy(dx: -40, dy: -30)
        if target.contains(NSEvent.mouseLocation) {
            if vm.enabledTools.contains(.shelf) { vm.selectedTool = .shelf }
            open()
        }
    }

    // MARK: Open / close

    func open(tool: Tool? = nil, focus: Bool = false) {
        openWork?.cancel()
        openWork = nil
        closeWork?.cancel()
        closeWork = nil
        if let tool, vm.enabledTools.contains(tool) { vm.selectedTool = tool }
        guard vm.state != .open || focus else { return }
        panel.ignoresMouseEvents = false
        if vm.state != .open {
            withAnimation(vm.animation) { vm.state = .open }
            if UserDefaults.standard.bool(forKey: Prefs.hapticFeedback) {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
        if focus { panel.makeKey() }
    }

    func close() {
        openWork?.cancel()
        openWork = nil
        closeWork?.cancel()
        closeWork = nil
        guard vm.state == .open else { return }
        vm.pinned = false
        withAnimation(vm.animation) { vm.state = .closed }
        panel.ignoresMouseEvents = true
        if panel.isKeyWindow {
            // Hand keyboard focus back to the app underneath.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    func toggle() {
        if vm.state == .open { close() } else { open(focus: true) }
    }
}
