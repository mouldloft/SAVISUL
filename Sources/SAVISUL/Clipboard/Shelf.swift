import AppKit
import Observation
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case file, text, link }

    var id = UUID()
    var kind: Kind
    var path: String?
    var text: String?
    var added = Date()

    var url: URL? {
        switch kind {
        case .file: path.map { URL(fileURLWithPath: $0) }
        case .link: text.flatMap(URL.init(string:))
        case .text: nil
        }
    }

    var title: String {
        switch kind {
        case .file: (path as NSString?)?.lastPathComponent ?? ""
        case .link: url?.host ?? text ?? ""
        case .text: text?.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
        }
    }
}

/// Files, links and snippets parked mid-drag, from the notch or from the floating shelf.
@MainActor
@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []
    @ObservationIgnored var onAdd: ((Int) -> Void)?

    nonisolated private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SAVISUL", isDirectory: true)
    }

    nonisolated static var drops: URL { folder.appendingPathComponent("Shelf", isDirectory: true) }

    private let directory: URL

    init() {
        directory = Self.folder
        load()
    }

    /// A shelf that reads and writes only inside `directory`, for tests.
    init(directory: URL) {
        self.directory = directory
        load()
    }

    private var storeURL: URL { directory.appendingPathComponent("shelf.json") }

    private func load() {
        if let data = try? Data(contentsOf: storeURL), let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            items = saved.filter { $0.kind != .file || FileManager.default.fileExists(atPath: $0.path ?? "") }
        }
    }

    var files: [URL] { items.compactMap { $0.kind == .file ? $0.url : nil } }

    func add(urls: [URL]) {
        var added = 0
        for url in urls {
            if url.isFileURL {
                guard !items.contains(where: { $0.path == url.path }) else { continue }
                items.insert(ShelfItem(kind: .file, path: url.path), at: 0)
            } else {
                guard !items.contains(where: { $0.text == url.absoluteString }) else { continue }
                items.insert(ShelfItem(kind: .link, text: url.absoluteString), at: 0)
            }
            added += 1
        }
        finish(added)
    }

    func add(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch ShelfItem.kind(for: trimmed) {
        case .link:
            if let url = URL(string: trimmed) { add(urls: [url]) }
        case .text:
            items.insert(ShelfItem(kind: .text, text: trimmed), at: 0)
            finish(1)
        case .file:
            break
        }
    }

    func add(image: NSImage) {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: Self.drops, withIntermediateDirectories: true)
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: ".")
        let url = Self.drops.appendingPathComponent("Image \(stamp).png")
        guard (try? png.write(to: url)) != nil else { return }
        add(urls: [url])
    }

    /// Accepts whatever a drag carries: files first, then links, images and plain text.
    @discardableResult
    func accept(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: NSURL.self) { [weak self] object, _ in
                    guard let url = (object as? NSURL) as URL? else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.add(urls: [url]) } }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSImage.self) { [weak self] object, _ in
                    guard let image = object as? NSImage else { return }
                    nonisolated(unsafe) let picture = image
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.add(image: picture) } }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
                    guard let text = object as? String else { return }
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.add(text: text) } }
                }
            }
        }
        return handled
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        if let path = item.path, path.hasPrefix(Self.drops.path) { try? FileManager.default.removeItem(atPath: path) }
        save()
    }

    func clear() {
        for item in items { if let path = item.path, path.hasPrefix(Self.drops.path) { try? FileManager.default.removeItem(atPath: path) } }
        items = []
        save()
    }

    func provider(for item: ShelfItem) -> NSItemProvider {
        switch item.kind {
        case .file: return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        case .link: return item.url.map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
        case .text: return NSItemProvider(object: (item.text ?? "") as NSString)
        }
    }

    func open(_ item: ShelfItem) {
        switch item.kind {
        case .file, .link: if let url = item.url { NSWorkspace.shared.open(url) }
        case .text: copy(item)
        }
    }

    func copy(_ item: ShelfItem) {
        let board = NSPasteboard.general
        board.clearContents()
        switch item.kind {
        case .file: if let url = item.url { board.writeObjects([url as NSURL]) }
        case .link, .text: board.setString(item.text ?? "", forType: .string)
        }
    }

    func reveal(_ list: [ShelfItem]? = nil) {
        let urls = (list ?? items).compactMap { $0.kind == .file ? $0.url : nil }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    func airDrop(_ list: [ShelfItem]? = nil) {
        let objects: [Any] = (list ?? items).compactMap { $0.url }
        guard !objects.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: objects)
    }

    private func finish(_ added: Int) {
        guard added > 0 else { return }
        if items.count > 60 { items = Array(items.prefix(60)) }
        save()
        onAdd?(added)
    }

    private func save() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: storeURL) }
    }
}

extension ShelfItem {
    /// A dropped string is a link only when the whole string is an http or https URL.
    static func kind(for text: String) -> Kind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), !trimmed.contains(" ") {
            return .link
        }
        return .text
    }

    static func kind(for url: URL) -> Kind { url.isFileURL ? .file : .link }
}
