import AppKit
import ApplicationServices
import Combine
import OverhangCore
import SwiftUI

/// Tracks Music and Spotify through the distributed notifications they post on every
/// state change, and controls them through AppleScript (asks for Automation permission once).
///
/// We deliberately avoid the private MediaRemote framework: since macOS 15.4 it no longer
/// returns now-playing info to third-party processes.
final class NowPlayingService: ObservableObject {
    static let shared = NowPlayingService()

    enum Player: String {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"

        var appName: String { self == .music ? "Music" : "Spotify" }
        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty }
    }

    @Published private(set) var player: Player?
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var position: Double = 0
    @Published private(set) var artwork: NSImage?

    var hasTrack: Bool { player != nil && !title.isEmpty }

    private let scriptQueue = DispatchQueue(label: "overhang.applescript")
    private var tickTimer: Timer?
    private var artworkKey = ""
    private var observers: [NSObjectProtocol] = []
    private var ticks = 0

    func start() {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] note in
            self?.handle(note.userInfo ?? [:], from: .music)
        })
        observers.append(center.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] note in
            self?.handle(note.userInfo ?? [:], from: .spotify)
        })
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        refreshFromRunningPlayers()
    }

    // MARK: State

    private func handle(_ info: [AnyHashable: Any], from source: Player) {
        let state = info["Player State"] as? String ?? ""
        if state == "Stopped" {
            if player == source { clear() }
            return
        }
        // Prefer whichever app is actually playing.
        if player != nil, player != source, isPlaying, state != "Playing" { return }

        player = source
        title = info["Name"] as? String ?? title
        artist = info["Artist"] as? String ?? ""
        album = info["Album"] as? String ?? ""
        isPlaying = state == "Playing"
        switch source {
        case .music:
            if let ms = info["Total Time"] as? Double { duration = ms / 1000 }
            else if let ms = info["Total Time"] as? Int { duration = Double(ms) / 1000 }
        case .spotify:
            if let ms = info["Duration"] as? Double { duration = ms / 1000 }
            else if let ms = info["Duration"] as? Int { duration = Double(ms) / 1000 }
            if let seconds = info["Playback Position"] as? Double { position = seconds }
        }
        syncPosition()
        loadArtworkIfNeeded()
    }

    private func clear() {
        player = nil
        title = ""
        artist = ""
        album = ""
        isPlaying = false
        duration = 0
        position = 0
        artwork = nil
        artworkKey = ""
    }

    private func tick() {
        guard let player else { return }
        guard player.isRunning else {
            clear()
            return
        }
        if isPlaying {
            position = min(duration > 0 ? duration : .infinity, position + 1)
            ticks += 1
            if ticks % 10 == 0 { syncPosition() }
        }
    }

    /// Reads current state once at launch (notifications only arrive on changes).
    private func refreshFromRunningPlayers() {
        for candidate in [Player.spotify, Player.music] where candidate.isRunning {
            let durationExpr = candidate == .music ? "(duration of t)" : "((duration of t) / 1000)"
            let source = """
            tell application "\(candidate.appName)"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as text) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & \(durationExpr) & linefeed & (player position)
            end tell
            """
            runScript(source) { [weak self] result in
                guard let self, let text = result?.stringValue, text != "stopped" else { return }
                let parts = text.components(separatedBy: "\n")
                guard parts.count >= 6, self.player == nil || parts[0] == "playing" else { return }
                self.player = candidate
                self.isPlaying = parts[0] == "playing"
                self.title = parts[1]
                self.artist = parts[2]
                self.album = parts[3]
                self.duration = Self.number(parts[4])
                self.position = Self.number(parts[5])
                self.loadArtworkIfNeeded()
            }
        }
    }

    private func syncPosition() {
        guard let player, player.isRunning else { return }
        runScript("tell application \"\(player.appName)\" to return player position") { [weak self] result in
            guard let self, let text = result?.stringValue else { return }
            self.position = Self.number(text)
        }
    }

    private static func number(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func loadArtworkIfNeeded() {
        guard let player, player.isRunning else { return }
        let key = "\(player.rawValue)|\(title)|\(artist)|\(album)"
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        switch player {
        case .music:
            let source = """
            tell application "Music"
                if (count of artworks of current track) > 0 then return raw data of artwork 1 of current track
            end tell
            """
            runScript(source) { [weak self] result in
                guard let self, self.artworkKey == key, let data = result?.data, let image = NSImage(data: data) else { return }
                self.artwork = image
            }
        case .spotify:
            runScript("tell application \"Spotify\" to return artwork url of current track") { [weak self] result in
                guard let text = result?.stringValue, let url = URL(string: text) else { return }
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        guard let self, self.artworkKey == key else { return }
                        self.artwork = image
                    }
                }.resume()
            }
        }
    }

    // MARK: Controls

    func playPause() {
        guard let player, player.isRunning else {
            MediaKeys.post(.playPause)
            return
        }
        isPlaying.toggle()
        runScript("tell application \"\(player.appName)\" to playpause")
    }

    func next() {
        guard let player, player.isRunning else { return MediaKeys.post(.next) }
        runScript("tell application \"\(player.appName)\" to next track")
    }

    func previous() {
        guard let player, player.isRunning else { return MediaKeys.post(.previous) }
        runScript("tell application \"\(player.appName)\" to previous track")
    }

    func seek(to seconds: Double) {
        guard let player, player.isRunning else { return }
        position = seconds
        runScript("tell application \"\(player.appName)\" to set player position to \(String(format: "%.2f", seconds))")
    }

    func openPlayerApp() {
        let id = player?.rawValue ?? Player.music.rawValue
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func runScript(_ source: String, completion: ((NSAppleEventDescriptor?) -> Void)? = nil) {
        scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let output = error == nil ? result : nil
            DispatchQueue.main.async { completion?(output) }
        }
    }
}

/// Posts hardware media key events so any player (browsers, Podcasts…) responds.
/// Requires Accessibility permission to post events.
enum MediaKeys {
    enum Key: Int { case playPause = 16, next = 17, previous = 18 }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func post(_ key: Key) {
        guard isTrusted else {
            requestTrust()
            return
        }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (key.rawValue << 16) | ((down ? 0xA : 0xB) << 8)
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                           timestamp: 0, windowNumber: 0, context: nil,
                                           subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

struct NowPlayingView: View {
    @ObservedObject private var service = NowPlayingService.shared
    @State private var scrubbing: Double?

    var body: some View {
        if service.hasTrack {
            HStack(spacing: 16) {
                artwork
                VStack(alignment: .leading, spacing: 6) {
                    Text(service.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Text([service.artist, service.album].filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    progress
                    controls
                }
            }
            .padding(.vertical, 6)
        } else {
            VStack(spacing: 10) {
                EmptyState(symbol: "music.note", title: "Nothing playing",
                           message: "Play something in Music or Spotify. Other players respond to the media keys below (needs Accessibility).")
                HStack(spacing: 10) {
                    IconButton(symbol: "backward.fill", size: 30) { service.previous() }
                    IconButton(symbol: "playpause.fill", size: 34, tint: Theme.accent, filled: true) { service.playPause() }
                    IconButton(symbol: "forward.fill", size: 30) { service.next() }
                    PillButton(title: "Open Music", symbol: "arrow.up.forward.app") { service.openPlayerApp() }
                }
            }
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card)
            if let image = service.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: 34)).foregroundStyle(Theme.secondary)
            }
        }
        .frame(width: 150, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { service.openPlayerApp() }
    }

    private var progress: some View {
        let duration = max(service.duration, 1)
        let current = scrubbing ?? service.position
        return VStack(spacing: 2) {
            Slider(value: Binding(get: { min(current, duration) }, set: { scrubbing = $0 }), in: 0...duration, onEditingChanged: { editing in
                if !editing, let value = scrubbing {
                    service.seek(to: value)
                    scrubbing = nil
                }
            })
            .controlSize(.small)
            .tint(Theme.accent)
            HStack {
                Text(DurationFormatter.clock(current))
                Spacer()
                Text("-" + DurationFormatter.clock(duration - current))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(Theme.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            IconButton(symbol: "backward.fill", size: 32) { service.previous() }
            IconButton(symbol: service.isPlaying ? "pause.fill" : "play.fill", size: 40, tint: Theme.accent, filled: true) {
                service.playPause()
            }
            IconButton(symbol: "forward.fill", size: 32) { service.next() }
            Spacer()
            if let player = service.player {
                Text(player.appName).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
        }
    }
}
