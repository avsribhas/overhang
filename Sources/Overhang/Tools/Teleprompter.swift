import SwiftUI

struct TeleprompterView: View {
    @AppStorage(Prefs.teleprompterScript) private var script = ""
    @AppStorage(Prefs.teleprompterSpeed) private var speed = 30.0
    @AppStorage(Prefs.teleprompterFontSize) private var fontSize = 22.0
    @AppStorage(Prefs.teleprompterMirror) private var mirror = false

    @State private var playing = false
    @State private var presenting = false
    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    private let ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            if presenting { prompter } else { editor }
            controls
        }
        .onReceive(ticker) { _ in
            guard playing, presenting else { return }
            offset += CGFloat(speed / 30.0)
            if offset > contentHeight { playing = false }
        }
        .onDisappear {
            playing = false
            NotchController.current?.vm.pinned = false
        }
    }

    private var editor: some View {
        TextEditor(text: $script)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
    }

    private var prompter: some View {
        GeometryReader { geo in
            Text(script)
                .font(.system(size: fontSize, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(width: geo.size.width)
                .background(GeometryReader { inner in
                    Color.clear.onAppear { contentHeight = inner.size.height }
                        .onChange(of: inner.size.height) { _, height in contentHeight = height }
                })
                .offset(y: 12 - offset)
                .scaleEffect(x: mirror ? -1 : 1, y: 1)
        }
        .clipped()
        .mask(LinearGradient(colors: [.clear, .black, .black, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom))
        .contentShape(Rectangle())
        .onTapGesture { playing.toggle() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            IconButton(symbol: playing ? "pause.fill" : "play.fill", size: 30, tint: Theme.accent, filled: true) {
                if !presenting {
                    presenting = true
                    offset = 0
                }
                playing.toggle()
                // Keep the notch open while reading, even if the pointer wanders off.
                NotchController.current?.vm.pinned = playing
            }
            IconButton(symbol: "backward.end.fill", size: 26, help: "Restart") { offset = 0 }
            IconButton(symbol: presenting ? "pencil" : "eye", size: 26, help: presenting ? "Edit script" : "Preview") {
                presenting.toggle()
                playing = false
                offset = 0
            }
            Image(systemName: "tortoise").foregroundStyle(Theme.secondary)
            Slider(value: $speed, in: 5...120).frame(width: 120).controlSize(.small)
            Image(systemName: "hare").foregroundStyle(Theme.secondary)
            Image(systemName: "textformat.size").foregroundStyle(Theme.secondary)
            Slider(value: $fontSize, in: 14...44).frame(width: 90).controlSize(.small)
            Toggle("Mirror", isOn: $mirror).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
            Spacer()
        }
    }
}
