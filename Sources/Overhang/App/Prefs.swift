import Foundation

/// UserDefaults keys and defaults. Views read these with @AppStorage using the same keys.
enum Prefs {
    static let openOnHover = "openOnHover"
    static let hoverDelay = "hoverDelay"
    static let closeOnMouseExit = "closeOnMouseExit"
    static let showStatusItem = "showStatusItem"
    static let hapticFeedback = "hapticFeedback"
    static let disabledTools = "disabledTools"
    static let lastTool = "lastTool"
    static let showLiveActivities = "showLiveActivities"
    static let weatherCity = "weatherCity"
    static let weatherFahrenheit = "weatherFahrenheit"
    static let stockSymbols = "stockSymbols"
    static let pomodoroWork = "pomodoroWork"
    static let pomodoroShort = "pomodoroShort"
    static let pomodoroLong = "pomodoroLong"
    static let pomodoroEvery = "pomodoroEvery"
    static let aiBudget5h = "aiBudget5h"
    static let clipboardLimit = "clipboardLimit"
    static let teleprompterScript = "teleprompterScript"
    static let teleprompterSpeed = "teleprompterSpeed"
    static let teleprompterFontSize = "teleprompterFontSize"
    static let teleprompterMirror = "teleprompterMirror"
    static let hasLaunchedBefore = "hasLaunchedBefore"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            openOnHover: true,
            hoverDelay: 0.12,
            closeOnMouseExit: true,
            showStatusItem: true,
            hapticFeedback: true,
            disabledTools: "",
            lastTool: Tool.nowPlaying.rawValue,
            showLiveActivities: true,
            weatherCity: "Cupertino",
            weatherFahrenheit: Locale.current.measurementSystem == .us,
            stockSymbols: "AAPL,MSFT,NVDA,^GSPC",
            pomodoroWork: 25,
            pomodoroShort: 5,
            pomodoroLong: 15,
            pomodoroEvery: 4,
            aiBudget5h: 0,
            clipboardLimit: 60,
            teleprompterScript: "Paste your script here.\n\nPress play and read along. The text scrolls right under your camera, so your eyes stay close to the lens.",
            teleprompterSpeed: 30.0,
            teleprompterFontSize: 22.0,
            teleprompterMirror: false,
        ])
    }

    static var defaults: UserDefaults { .standard }

    static var enabledTools: [Tool] {
        let disabled = Set((defaults.string(forKey: disabledTools) ?? "").split(separator: ",").map(String.init))
        return Tool.allCases.filter { !disabled.contains($0.rawValue) }
    }

    static func setTool(_ tool: Tool, enabled: Bool) {
        var disabled = Set((defaults.string(forKey: disabledTools) ?? "").split(separator: ",").map(String.init))
        if enabled { disabled.remove(tool.rawValue) } else { disabled.insert(tool.rawValue) }
        defaults.set(disabled.sorted().joined(separator: ","), forKey: disabledTools)
    }
}
