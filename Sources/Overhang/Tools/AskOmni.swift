import AppKit
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Chat with Apple's on-device Foundation Model (macOS 26+, Apple Intelligence enabled).
/// Prompts never leave the Mac. Builds made with an older SDK compile this tool out gracefully.
final class AskOmniModel: ObservableObject {
    static let shared = AskOmniModel()

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let fromUser: Bool
        var text: String
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var responding = false
    @Published private(set) var unavailableReason: String?

    private var session: AnyObject?

    init() { checkAvailability() }

    func checkAvailability() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                unavailableReason = nil
            case let .unavailable(reason):
                let text = String(describing: reason)
                if text.contains("NotEligible") {
                    unavailableReason = "This Mac doesn't support Apple Intelligence."
                } else if text.contains("NotEnabled") {
                    unavailableReason = "Turn on Apple Intelligence in System Settings to use Ask."
                } else if text.contains("NotReady") {
                    unavailableReason = "The on-device model is still downloading. Try again later."
                } else {
                    unavailableReason = "The on-device model is unavailable (\(text))."
                }
            @unknown default:
                unavailableReason = "The on-device model is unavailable."
            }
            return
        }
        unavailableReason = "Ask needs macOS 26 or later with Apple Intelligence."
        #else
        unavailableReason = "This build was compiled without the macOS 26 SDK, so Ask is unavailable. Rebuild with Xcode 26."
        #endif
    }

    func newChat() {
        guard !responding else { return }
        messages.removeAll()
        session = nil
    }

    func send(_ input: String) {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !responding else { return }
        checkAvailability()
        messages.append(Message(fromUser: true, text: prompt))
        guard unavailableReason == nil else {
            messages.append(Message(fromUser: false, text: unavailableReason ?? ""))
            return
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = (self.session as? LanguageModelSession)
                ?? LanguageModelSession(instructions: "You are Omni, a concise assistant that lives in the Mac's notch. Answer briefly and directly. Prefer short paragraphs or compact bullet lists.")
            self.session = session
            responding = true
            Task { @MainActor [weak self] in
                do {
                    let response = try await session.respond(to: prompt)
                    self?.messages.append(Message(fromUser: false, text: response.content))
                } catch {
                    self?.messages.append(Message(fromUser: false, text: "⚠︎ \(error.localizedDescription)"))
                    // Most failures (e.g. context window exceeded) are fixed by a fresh session.
                    self?.session = nil
                }
                self?.responding = false
            }
        }
        #endif
    }
}

struct AskOmniView: View {
    @ObservedObject private var model = AskOmniModel.shared
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 8) {
            if model.messages.isEmpty {
                VStack(spacing: 8) {
                    EmptyState(symbol: "sparkles", title: "Ask Omni",
                               message: model.unavailableReason ?? "Runs entirely on-device with Apple Intelligence. Nothing you type leaves this Mac.")
                    HStack(spacing: 6) {
                        ForEach(["Summarize what I copied", "Write a polite follow-up email", "Explain a regex"], id: \.self) { idea in
                            PillButton(title: idea) { send(idea == "Summarize what I copied" ? summarizeClipboardPrompt() : idea) }
                        }
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(model.messages) { message in
                                Bubble(message: message).id(message.id)
                            }
                            if model.responding {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Thinking…").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                    Spacer()
                                }
                                .id("thinking")
                            }
                        }
                    }
                    .onChange(of: model.messages) { _, messages in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
            }
            HStack(spacing: 8) {
                InputField(placeholder: "Ask anything…", text: $draft, symbol: "sparkles") { send(draft) }
                IconButton(symbol: "arrow.up", size: 28, tint: Theme.accent, filled: true) { send(draft) }
                IconButton(symbol: "square.and.pencil", size: 28, help: "New chat") { model.newChat() }
            }
        }
    }

    private func send(_ text: String) {
        model.send(text)
        draft = ""
    }

    private func summarizeClipboardPrompt() -> String {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        return "Summarize this in three bullet points:\n\n" + String(text.prefix(6000))
    }
}

private struct Bubble: View {
    let message: AskOmniModel.Message

    var body: some View {
        HStack {
            if message.fromUser { Spacer(minLength: 80) }
            Text(LocalizedStringKey(message.text))
                .font(.system(size: 13))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(message.fromUser ? Theme.accent.opacity(0.28) : Theme.card))
                .contextMenu {
                    Button("Copy") { Clipboard.copy(message.text) }
                }
            if !message.fromUser { Spacer(minLength: 80) }
        }
    }
}
