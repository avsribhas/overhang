import AppKit
import ApplicationServices
import OverhangCore
import SwiftUI

struct EmojiPickerView: View {
    @State private var query = ""
    @State private var recents: [String] = UserDefaults.standard.stringArray(forKey: "recentEmoji") ?? []
    @State private var toast: String?
    @State private var hovered: Emoji?

    private var results: [Emoji] { EmojiCatalog.search(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InputField(placeholder: "Search emoji (e.g. “heart”, “rocket”)", text: $query, symbol: "magnifyingglass") {
                    if let first = results.first { pick(first.character) }
                }
                Text(hovered?.name.capitalized ?? "Click to insert · ⌥-click to copy only")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                    .frame(width: 220, alignment: .trailing)
            }
            if query.isEmpty, !recents.isEmpty {
                HStack(spacing: 2) {
                    ForEach(recents, id: \.self) { character in
                        EmojiCell(character: character) { pick(character) }
                    }
                }
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 2), count: 19), spacing: 2) {
                    ForEach(results) { emoji in
                        EmojiCell(character: emoji.character) { pick(emoji.character) }
                            .onHover { inside in hovered = inside ? emoji : (hovered == emoji ? nil : hovered) }
                    }
                }
            }
        }
        .toast($toast)
    }

    /// Copies the emoji; unless ⌥ is held, closes the notch and pastes it into the app you were using.
    private func pick(_ character: String) {
        Clipboard.copy(character)
        recents = Array(([character] + recents.filter { $0 != character }).prefix(18))
        UserDefaults.standard.set(recents, forKey: "recentEmoji")
        let copyOnly = NSEvent.modifierFlags.contains(.option)
        guard !copyOnly, AXIsProcessTrusted() else {
            withAnimation { toast = copyOnly ? "Copied \(character)" : "Copied \(character) · enable Accessibility to auto-insert" }
            return
        }
        NotchController.current?.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { KeyboardPaste.paste() }
    }
}

private struct EmojiCell: View {
    let character: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(character)
                .font(.system(size: 22))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Theme.cardHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Simulates ⌘V in the frontmost app. Needs Accessibility permission.
enum KeyboardPaste {
    static func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
