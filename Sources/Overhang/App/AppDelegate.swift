import AppKit
import Carbon
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_: Notification) {
        Prefs.registerDefaults()

        // Background services that feed live activities or need to watch continuously.
        ClipboardService.shared.start()
        NowPlayingService.shared.start()
        VolumeService.shared.start()
        _ = ActivityCenter.shared

        rebuildController()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildController() }
            .store(in: &cancellables)

        // ⌥⌘N toggles the notch from anywhere.
        hotKey = HotKey(keyCode: kVK_ANSI_N, modifiers: cmdKey | optionKey) { [weak self] in
            self?.controller?.toggle()
        }

        updateStatusItem()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        if !UserDefaults.standard.bool(forKey: Prefs.hasLaunchedBefore) {
            UserDefaults.standard.set(true, forKey: Prefs.hasLaunchedBefore)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.controller?.open()
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        KeepAwakeService.shared.stop()
    }

    /// Re-launching the app from Finder/Spotlight opens the notch.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        controller?.open(focus: true)
        return false
    }

    private func rebuildController() {
        controller?.destroy()
        controller = nil
        guard let screen = NSScreen.preferredForNotch else { return }
        controller = NotchController(screen: screen)
    }

    // MARK: Status item

    private func updateStatusItem() {
        let wanted = UserDefaults.standard.bool(forKey: Prefs.showStatusItem)
        if wanted, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Overhang")
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Notch", action: #selector(openNotch), keyEquivalent: "")
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Overhang", action: #selector(quit), keyEquivalent: "q")
            menu.items.forEach { $0.target = self }
            item.menu = menu
            statusItem = item
        } else if !wanted, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func openNotch() { controller?.open(focus: true) }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
