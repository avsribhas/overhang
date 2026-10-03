import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ToolSettings().tabItem { Label("Tools", systemImage: "square.grid.2x2") }
            DataSettings().tabItem { Label("Weather & Stocks", systemImage: "cloud.sun") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Prefs.openOnHover) private var openOnHover = true
    @AppStorage(Prefs.hoverDelay) private var hoverDelay = 0.12
    @AppStorage(Prefs.closeOnMouseExit) private var closeOnMouseExit = true
    @AppStorage(Prefs.hapticFeedback) private var haptics = true
    @AppStorage(Prefs.showStatusItem) private var showStatusItem = true
    @AppStorage(Prefs.showLiveActivities) private var liveActivities = true
    @AppStorage(Prefs.clipboardLimit) private var clipboardLimit = 60
    @AppStorage(Prefs.aiBudget5h) private var aiBudget = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Notch") {
                Toggle("Open on hover", isOn: $openOnHover)
                if openOnHover {
                    Slider(value: $hoverDelay, in: 0...0.8, step: 0.05) {
                        Text("Hover delay: \(Int(hoverDelay * 1000)) ms")
                    }
                }
                Toggle("Close when the pointer leaves", isOn: $closeOnMouseExit)
                Toggle("Haptic feedback on open", isOn: $haptics)
                Toggle("Live activities in the closed notch (music, timers, volume)", isOn: $liveActivities)
                Text("Shortcut: ⌥⌘N toggles the notch from anywhere.").font(.caption).foregroundStyle(.secondary)
            }
            Section("App") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Show menu bar icon", isOn: $showStatusItem)
                Stepper("Clipboard history: \(clipboardLimit) items", value: $clipboardLimit, in: 10...500, step: 10)
                Stepper("AI usage 5-hour budget: \(aiBudget == 0 ? "none" : UsageFormat.tokens(aiBudget))",
                        value: $aiBudget, in: 0...50_000_000, step: 250_000)
            }
        }
        .formStyle(.grouped)
    }
}

enum UsageFormat {
    static func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.2fM tokens", Double(n) / 1_000_000) : "\(n / 1000)K tokens"
    }
}

private struct ToolSettings: View {
    @AppStorage(Prefs.disabledTools) private var disabled = ""

    var body: some View {
        Form {
            Section("Enabled tools") {
                ForEach(Tool.allCases) { tool in
                    Toggle(isOn: Binding(
                        get: { !disabled.split(separator: ",").map(String.init).contains(tool.rawValue) },
                        set: { Prefs.setTool(tool, enabled: $0) }
                    )) {
                        HStack {
                            Image(systemName: tool.symbol).frame(width: 20)
                            VStack(alignment: .leading) {
                                Text(tool.title)
                                Text(tool.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DataSettings: View {
    @AppStorage(Prefs.weatherCity) private var city = "Cupertino"
    @AppStorage(Prefs.weatherFahrenheit) private var fahrenheit = false
    @AppStorage(Prefs.stockSymbols) private var symbols = ""

    var body: some View {
        Form {
            Section("Weather (Open-Meteo)") {
                TextField("City", text: $city)
                Toggle("Use Fahrenheit", isOn: $fahrenheit)
            }
            Section("Stocks (Yahoo Finance)") {
                TextField("Symbols, comma separated", text: $symbols)
                Text("Examples: AAPL, MSFT, BTC-USD, ^GSPC, RELIANCE.NS").font(.caption).foregroundStyle(.secondary)
            }
            Section("Network use") {
                Text("Only Weather, Stocks and currency rates use the network, and only while those tools are open. Everything else stays on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.topthird.inset.filled").font(.system(size: 44))
            Text("Overhang").font(.title2.bold())
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("A personal notch utility with twenty tools.")
            Divider().padding(.vertical, 6)
            Text("Notch window and screen measurement adapted from NotchDrop by Lakr Aream (MIT License).")
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Weather: Open-Meteo · Rates: Frankfurter (ECB) · Quotes: Yahoo Finance")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Quit Overhang") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity)
    }
}
