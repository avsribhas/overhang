import SwiftUI

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var done = false
    var created = Date()
}

final class TodoStore: ObservableObject {
    static let shared = TodoStore()
    @Published var items: [TodoItem] = JSONStore.load([TodoItem].self, from: "todos.json") ?? [] {
        didSet { JSONStore.save(items, to: "todos.json") }
    }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.insert(TodoItem(title: trimmed), at: 0)
    }

    func toggle(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].done.toggle()
    }

    func delete(_ item: TodoItem) { items.removeAll { $0.id == item.id } }
    func clearDone() { items.removeAll(where: \.done) }
}

struct TodosView: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var draft = ""

    private var open: [TodoItem] { store.items.filter { !$0.done } }
    private var done: [TodoItem] { store.items.filter(\.done) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                InputField(placeholder: "Add a to-do and press Return", text: $draft, symbol: "plus.circle") {
                    store.add(draft)
                    draft = ""
                }
                if !done.isEmpty {
                    PillButton(title: "Clear done (\(done.count))", symbol: "checkmark") { store.clearDone() }
                }
            }
            if store.items.isEmpty {
                EmptyState(symbol: "checklist", title: "Nothing to do", message: "Your list lives on this Mac only.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(open + done) { item in
                            TodoRow(item: item)
                        }
                    }
                }
            }
        }
    }
}

private struct TodoRow: View {
    let item: TodoItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button { withAnimation { TodoStore.shared.toggle(item) } } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.done ? Theme.positive : Theme.secondary)
            }
            .buttonStyle(.plain)
            Text(item.title)
                .font(.system(size: 13))
                .strikethrough(item.done)
                .foregroundStyle(item.done ? Theme.secondary : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hovering {
                IconButton(symbol: "trash", size: 22) { withAnimation { TodoStore.shared.delete(item) } }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovering ? Theme.cardHover : Theme.card))
        .onHover { hovering = $0 }
    }
}
