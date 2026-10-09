import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Finds out what's selected in the app in front. Accessibility first, which leaves the clipboard alone; then ⌘C
/// with the clipboard put back exactly as it was; and when nothing is selected, the clipboard itself stands in.
@MainActor
enum SelectionReader {
    static func read(_ done: @escaping @MainActor (ActionContext) -> Void) {
        if let text = accessibilityText() {
            done(context(text: text))
            return
        }
        guard AX.trusted else {
            done(clipboardContext())
            return
        }
        let board = NSPasteboard.general
        let snapshot = PasteboardSnapshot(board)
        let before = board.changeCount
        let history = Suite.shared.clipboard.history
        history.paused = true
        Keys.whenModifiersReleased {
            Keys.tap(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
            let deadline = Date().addingTimeInterval(0.45)
            @MainActor func check() {
                if board.changeCount != before {
                    // Give the app a moment to finish writing every flavour before reading them.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        MainActor.assumeIsolated {
                            let found = context(from: board)
                            snapshot.restore(board)
                            history.resync()
                            history.paused = false
                            done(found)
                        }
                    }
                } else if Date() > deadline {
                    history.paused = false
                    done(clipboardContext())
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { MainActor.assumeIsolated { check() } }
                }
            }
            check()
        }
    }

    /// The focused text field's selection, when the app reports it.
    private static func accessibilityText() -> String? {
        guard AX.trusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        guard let focused = AX.element(system, kAXFocusedUIElementAttribute),
              let text = AX.string(focused, kAXSelectedTextAttribute) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    /// What the clipboard holds right now, marked as coming from the clipboard.
    static func clipboardContext() -> ActionContext {
        var found = context(from: NSPasteboard.general)
        found.fromClipboard = true
        return found
    }

    static func context(from board: NSPasteboard) -> ActionContext {
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return ActionContext(files: urls)
        }
        let string = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let types = Set(board.types ?? [])
        let hasImage = !types.isDisjoint(with: [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), NSPasteboard.PasteboardType("public.heic")])
        if hasImage, string == nil || link(string ?? "") != nil, let image = NSImage(pasteboard: board) {
            var found = ActionContext(image: image)
            found.url = string.flatMap(link)
            return found
        }
        if let string, !string.isEmpty { return context(text: string) }
        if let url = board.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL {
            return ActionContext(text: url.absoluteString, url: url)
        }
        return ActionContext()
    }

    /// Plain text, recognising a lone link or a path to a file.
    static func context(text: String) -> ActionContext {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = link(trimmed) { return ActionContext(text: trimmed, url: url) }
        let expanded = (trimmed as NSString).expandingTildeInPath
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~"), !trimmed.contains("\n"), FileManager.default.fileExists(atPath: expanded) {
            return ActionContext(text: trimmed, files: [URL(fileURLWithPath: expanded)])
        }
        return ActionContext(text: text)
    }

    /// A single web link and nothing else.
    static func link(_ text: String) -> URL? {
        guard !text.isEmpty, !text.contains(where: \.isWhitespace), let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }
}

/// Every item and every flavour on the clipboard, to put back after borrowing it.
struct PasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    @MainActor init(_ board: NSPasteboard) {
        items = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    @MainActor func restore(_ board: NSPasteboard) {
        board.clearContents()
        guard !items.isEmpty else { return }
        let objects: [NSPasteboardItem] = items.map { flavours in
            let item = NSPasteboardItem()
            for (type, data) in flavours { item.setData(data, forType: type) }
            return item
        }
        board.writeObjects(objects)
    }
}
