import OverhangCore
import SwiftUI

struct CalculatorView: View {
    struct Entry: Identifiable, Codable {
        var id = UUID()
        let expression: String
        let result: String
    }

    @State private var input = ""
    @State private var history: [Entry] = JSONStore.load([Entry].self, from: "calculator.json") ?? []
    @State private var toast: String?

    private var live: String? {
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty,
              let value = try? Calculator.evaluate(input) else { return nil }
        return Calculator.format(value)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                InputField(placeholder: "2 * (3 + 4) ^ 2, sqrt(2), 10 % 3", text: $input, symbol: "function") { commit() }
                Card(padding: 14) {
                    HStack {
                        Text(live.map { "= \($0)" } ?? (input.isEmpty ? "Type an expression" : "…"))
                            .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(live == nil ? Theme.secondary : .white)
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .textSelection(.enabled)
                        Spacer()
                        if let live {
                            IconButton(symbol: "doc.on.doc", size: 28, help: "Copy") {
                                Clipboard.copy(live)
                                withAnimation { toast = "Copied" }
                            }
                        }
                    }
                }
                Text("Supports + − × ÷ % ^, parentheses, pi, e, sqrt, sin, cos, tan, ln, log, abs, round. Press Return to save to the tape.")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TAPE").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
                    Spacer()
                    if !history.isEmpty {
                        Button("Clear") { history = []; save() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .trailing, spacing: 6) {
                        ForEach(history) { entry in
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(entry.expression).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                Text(entry.result).font(.system(size: 14, weight: .semibold).monospacedDigit())
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .contentShape(Rectangle())
                            .onTapGesture { input = entry.result }
                        }
                    }
                }
            }
            .frame(width: 200)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        }
        .toast($toast)
    }

    private func commit() {
        guard let live else { return }
        history.insert(Entry(expression: input, result: live), at: 0)
        history = Array(history.prefix(100))
        save()
        input = live
    }

    private func save() { JSONStore.save(history, to: "calculator.json") }
}
