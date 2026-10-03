// Notch measurement adapted from NotchDrop (https://github.com/Lakr233/NotchDrop), MIT License, Copyright (c) 2024 Lakr Aream.
import AppKit

extension NSScreen {
    /// Size of the camera housing, or `.zero` when the display has no notch.
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else { return .zero }
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        guard leftPadding > 0, rightPadding > 0 else { return .zero }
        return CGSize(width: frame.width - leftPadding - rightPadding, height: safeAreaInsets.top)
    }

    var hasNotch: Bool { notchSize != .zero }

    var menuBarHeight: CGFloat {
        let height = frame.maxY - visibleFrame.maxY
        return height > 0 ? height : 24
    }

    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var isBuiltIn: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) == 1
    }

    /// The built-in notched display if there is one, otherwise the main display.
    static var preferredForNotch: NSScreen? {
        if let notched = screens.first(where: { $0.isBuiltIn && $0.hasNotch }) { return notched }
        if let notched = screens.first(where: { $0.hasNotch }) { return notched }
        return main ?? screens.first
    }
}
