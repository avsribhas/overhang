import SwiftUI

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var updated = Date()

    var title: String {
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return firstLine.isEmpty ? "New note" : firstLine
    }
}

final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    @Published var notes: [Note]
    @Published var selectedID: UUID?
    private let saver = Debouncer(delay: 0.5)

    private init() {
        let stored = JSONStore.load([Note].self, from: "notes.json") ?? []
        notes = stored.isEmpty ? [Note(text: "")] : stored
        selectedID = notes.first?.id
    }

    var selectedIndex: Int? { notes.firstIndex { $0.id == selectedID } }

    func update(_ text: String) {
        guard let index = selectedIndex, notes[index].text != text else { return }
        notes[index].text = text
        notes[index].updated = Date()
        scheduleSave()
    }

    func create() {
        let note = Note(text: "")
        notes.insert(note, at: 0)
        selectedID = note.id
        scheduleSave()
    }

    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        if notes.isEmpty { notes = [Note(text: "")] }
        if selectedIndex == nil { selectedID = notes.first?.id }
        scheduleSave()
    }

    private func scheduleSave() {
        saver.call { [weak self] in
            guard let self else { return }
            JSONStore.save(self.notes, to: "notes.json")
        }
    }
}

struct NotesView: View {
    @ObservedObject private var store = NoteStore.shared

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 4) {
                HStack {
                    Text("NOTES").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
                    Spacer()
                    IconButton(symbol: "square.and.pencil", size: 22, help: "New note") { store.create() }
                }
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.notes) { note in
                            NoteRow(note: note, selected: note.id == store.selectedID) { store.selectedID = note.id }
                        }
                    }
                }
            }
            .frame(width: 170)

            TextEditor(text: Binding(
                get: { store.selectedIndex.map { store.notes[$0].text } ?? "" },
                set: { store.update($0) }
            ))
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(note.updated, style: .date).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
            }
            Spacer()
            if hovering {
                Button { NoteStore.shared.delete(note) } label: {
                    Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.accent.opacity(0.25) : (hovering ? Theme.card : .clear)))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
    }
}
