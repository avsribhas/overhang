import SwiftUI

enum Tool: String, CaseIterable, Identifiable, Codable {
    case askOmni, nowPlaying, clipboard, shelf, aiUsage, timer, weather, stocks, stats, calendar
    case todos, notes, emoji, converter, calculator, keepAwake, volume, teleprompter, mirror, colorPicker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askOmni: "Ask"
        case .nowPlaying: "Now Playing"
        case .clipboard: "Clipboard"
        case .shelf: "Shelf"
        case .aiUsage: "AI Usage"
        case .timer: "Timer"
        case .weather: "Weather"
        case .stocks: "Stocks"
        case .stats: "System"
        case .calendar: "Calendar"
        case .todos: "To-dos"
        case .notes: "Notes"
        case .emoji: "Emoji"
        case .converter: "Convert"
        case .calculator: "Calculator"
        case .keepAwake: "Keep Awake"
        case .volume: "Volume"
        case .teleprompter: "Teleprompter"
        case .mirror: "Mirror"
        case .colorPicker: "Color Picker"
        }
    }

    var symbol: String {
        switch self {
        case .askOmni: "sparkles"
        case .nowPlaying: "music.note"
        case .clipboard: "doc.on.clipboard"
        case .shelf: "tray.full"
        case .aiUsage: "gauge.with.dots.needle.67percent"
        case .timer: "timer"
        case .weather: "cloud.sun"
        case .stocks: "chart.line.uptrend.xyaxis"
        case .stats: "cpu"
        case .calendar: "calendar"
        case .todos: "checklist"
        case .notes: "note.text"
        case .emoji: "face.smiling"
        case .converter: "arrow.left.arrow.right"
        case .calculator: "plus.forwardslash.minus"
        case .keepAwake: "cup.and.saucer"
        case .volume: "speaker.wave.2"
        case .teleprompter: "text.alignleft"
        case .mirror: "camera"
        case .colorPicker: "eyedropper"
        }
    }

    var summary: String {
        switch self {
        case .askOmni: "Chat with Apple's on-device model (macOS 26+)"
        case .nowPlaying: "Music & Spotify controls with artwork"
        case .clipboard: "Searchable clipboard history"
        case .shelf: "Drop files, drag them out, AirDrop"
        case .aiUsage: "Token usage from local Claude Code & Codex logs"
        case .timer: "Countdown timers and Pomodoro"
        case .weather: "Current conditions and 5-day forecast"
        case .stocks: "Watchlist with intraday sparklines"
        case .stats: "CPU, memory, disk, network, battery"
        case .calendar: "Today's and upcoming events"
        case .todos: "A quick local task list"
        case .notes: "Scratch notes, autosaved"
        case .emoji: "Search and insert emoji"
        case .converter: "Units and currencies"
        case .calculator: "Expression calculator with history"
        case .keepAwake: "Prevent sleep for a while"
        case .volume: "Output volume and HUD"
        case .teleprompter: "Scrolling script under your camera"
        case .mirror: "Camera preview"
        case .colorPicker: "Sample any pixel on screen"
        }
    }
}

struct ToolContentView: View {
    let tool: Tool

    var body: some View {
        switch tool {
        case .askOmni: AskOmniView()
        case .nowPlaying: NowPlayingView()
        case .clipboard: ClipboardView()
        case .shelf: ShelfView()
        case .aiUsage: AIUsageView()
        case .timer: TimerToolView()
        case .weather: WeatherView()
        case .stocks: StocksView()
        case .stats: SystemStatsView()
        case .calendar: CalendarToolView()
        case .todos: TodosView()
        case .notes: NotesView()
        case .emoji: EmojiPickerView()
        case .converter: ConverterView()
        case .calculator: CalculatorView()
        case .keepAwake: KeepAwakeView()
        case .volume: VolumeView()
        case .teleprompter: TeleprompterView()
        case .mirror: MirrorView()
        case .colorPicker: ColorPickerView()
        }
    }
}
