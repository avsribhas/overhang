import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let added: Date

    var url: URL { ShelfService.directory.appendingPathComponent(id.uuidString).appendingPathComponent(name) }
}

/// Files dropped on the notch are copied here so they survive the original being moved or deleted.
final class ShelfService: ObservableObject {
    static let shared = ShelfService()

    @Published private(set) var items: [ShelfItem]
    @Published private(set) var isImporting = false

    static let directory = AppPaths.directory("Shelf")
    private let storeName = "shelf.json"
    private let ioQueue = DispatchQueue(label: "overhang.shelf")

    private init() {
        let stored = JSONStore.load([ShelfItem].self, from: storeName) ?? []
        items = stored.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    func add(providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in self?.add(urls: urls) }
    }

    func add(urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        let directory = Self.directory
        ioQueue.async {
            var added: [ShelfItem] = []
            for url in urls {
                let item = ShelfItem(id: UUID(), name: url.lastPathComponent, added: Date())
                let folder = directory.appendingPathComponent(item.id.uuidString)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(item.name))
                    added.append(item)
                } catch {
                    NSLog("Overhang shelf copy failed: \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                self.items.insert(contentsOf: added, at: 0)
                self.isImporting = false
                self.save()
            }
        }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
        save()
    }

    func removeAll() {
        items.forEach { try? FileManager.default.removeItem(at: $0.url.deletingLastPathComponent()) }
        items.removeAll()
        save()
    }

    func airDrop(_ items: [ShelfItem]) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        let urls = items.map(\.url)
        if service.canPerform(withItems: urls) { service.perform(withItems: urls) }
    }

    func open(_ item: ShelfItem) { NSWorkspace.shared.open(item.url) }
    func reveal(_ item: ShelfItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }

    private func save() { JSONStore.save(items, to: storeName) }
}

struct ShelfView: View {
    @ObservedObject private var service = ShelfService.shared

    var body: some View {
        VStack(spacing: 8) {
            if service.items.isEmpty {
                EmptyState(symbol: "tray.and.arrow.down", title: "Drop files on the notch",
                           message: "Drag files onto the notch to park them here. Drag them back out, or AirDrop them.")
            } else {
                HStack {
                    Text("\(service.items.count) item\(service.items.count == 1 ? "" : "s")")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    if service.isImporting { ProgressView().controlSize(.small) }
                    Spacer()
                    PillButton(title: "AirDrop All", symbol: "airplayaudio") { service.airDrop(service.items) }
                    PillButton(title: "Clear", symbol: "trash") { service.removeAll() }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(service.items) { item in
                            ShelfTile(item: item)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 56, height: 56)
            Text(item.name)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 92)
        }
        .padding(8)
        .frame(width: 108, height: 120)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Theme.cardHover : Theme.card))
        .overlay(alignment: .topTrailing) {
            if hovering {
                HStack(spacing: 4) {
                    IconButton(symbol: "airplayaudio", size: 20, help: "AirDrop") { ShelfService.shared.airDrop([item]) }
                    IconButton(symbol: "xmark", size: 20, help: "Remove") { ShelfService.shared.remove(item) }
                }
                .padding(4)
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { ShelfService.shared.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { ShelfService.shared.open(item) }
            Button("Show in Finder") { ShelfService.shared.reveal(item) }
            Button("AirDrop") { ShelfService.shared.airDrop([item]) }
            Divider()
            Button("Remove from Shelf") { ShelfService.shared.remove(item) }
        }
    }
}
