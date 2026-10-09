import AppKit
import Carbon.HIToolbox

/// Finder gains Cut (⌘X then ⌘V moves), F2 to rename, and ⌘V of a picture or text saves it as a file.
@MainActor
final class FinderTweaks {
    private var cut: (count: Int, change: Int)?
    private var cutOn = false
    private var renameOn = false
    private var imagesOn = false

    func apply(_ settings: SuiteSettings) {
        cutOn = settings.finderCut
        renameOn = settings.finderRename
        imagesOn = settings.finderImages
        if cutOn || renameOn || imagesOn {
            if !InputTap.shared.has("finder") {
                InputTap.shared.add("finder", priority: 30, types: [.keyDown]) { [weak self] type, event in
                    guard let self else { return event }
                    return self.key(event)
                }
            }
        } else {
            InputTap.shared.remove("finder")
            cut = nil
        }
    }

    private static var finderFront: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    /// Text fields keep their own ⌘X, ⌘V and F2: renaming, the search field, Go to Folder.
    private static func typing() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let focused = AX.element(AX.app(pid), kAXFocusedUIElementAttribute) else { return false }
        let role = AX.role(focused) ?? ""
        return role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole || role == "AXSearchField"
    }

    private func key(_ event: CGEvent) -> CGEvent? {
        guard Self.finderFront else { return event }
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return event }
        switch (code, flags) {
        case (kVK_F2, []):
            guard renameOn, !Self.typing() else { return event }
            Keys.tap(CGKeyCode(kVK_Return))
            return nil
        case (kVK_ANSI_X, .maskCommand):
            guard cutOn, !Self.typing() else { return event }
            Keys.tap(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                MainActor.assumeIsolated { Suite.shared.clipboard.finder.markCut() }
            }
            return nil
        case (kVK_ANSI_V, .maskCommand):
            guard !Self.typing() else { return event }
            let board = NSPasteboard.general
            if cutOn, let cut, cut.change == board.changeCount {
                self.cut = nil
                Keys.tap(CGKeyCode(kVK_ANSI_V), flags: [.maskCommand, .maskAlternate])
                Suite.shared.notify(IslandNotice(symbol: "folder.fill", tint: Palette.accent, title: ClipPhrases.moved.text,
                                                 detail: Phrases.items(cut.count), style: .success, duration: 2))
                return nil
            }
            if imagesOn, Self.hasPastableContent(board) {
                DispatchQueue.main.async { MainActor.assumeIsolated { Suite.shared.clipboard.finder.pasteAsFile() } }
                return nil
            }
            return event
        default:
            return event
        }
    }

    fileprivate func markCut() {
        let board = NSPasteboard.general
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            cut = nil
            return
        }
        cut = (urls.count, board.changeCount)
        Suite.shared.notify(IslandNotice(symbol: "scissors", tint: Palette.accent, title: ClipPhrases.cutReady.text,
                                         detail: Phrases.items(urls.count), duration: 2.2))
    }

    private static func hasPastableContent(_ board: NSPasteboard) -> Bool {
        let types = board.types ?? []
        if types.contains(.fileURL) { return false }
        return types.contains(.png) || types.contains(.tiff)
    }

    /// Saves the clipboard picture into the folder of the front Finder window and selects it.
    fileprivate func pasteAsFile() {
        let board = NSPasteboard.general
        guard let data = board.data(forType: .png) ?? board.data(forType: .tiff) else { return }
        guard let folder = Self.finderFolder() else {
            NSSound.beep()
            return
        }
        let png = board.data(forType: .png) ?? NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
        let target = Self.free(folder.appendingPathComponent("\(ClipPhrases.pastedImage.text) \(Self.stamp()).png"))
        guard let png, (try? png.write(to: target, options: .withoutOverwriting)) != nil else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([target])
        Suite.shared.notify(IslandNotice(symbol: "doc.badge.plus", tint: Palette.positive, title: ClipPhrases.savedAsFile.text,
                                         detail: target.lastPathComponent, image: NSWorkspace.shared.icon(forFile: target.path),
                                         style: .success, duration: 2.4))
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }

    private static func free(_ url: URL) -> URL {
        var candidate = url
        var index = 2
        let base = url.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) \(index)").appendingPathExtension(url.pathExtension)
            index += 1
        }
        return candidate
    }

    /// The folder Finder would paste into: the front window's, or the Desktop.
    static func finderFolder() -> URL? {
        let source = """
        tell application "Finder"
            try
                return POSIX path of (insertion location as alias)
            on error
                return POSIX path of (desktop as alias)
            end try
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue, error == nil else { return nil }
        return URL(fileURLWithPath: result, isDirectory: true)
    }
}

extension ClipPhrases {
    static let moved = Phrase("Moved", ru: "Перемещено", uk: "Переміщено", fr: "Déplacé")
    static let cutReady = Phrase("Cut — press ⌘V in the destination", ru: "Вырезано — нажмите ⌘V в нужной папке",
                                 uk: "Вирізано — натисніть ⌘V у потрібній теці", fr: "Coupé — ⌘V dans le dossier cible")
    static let pastedImage = Phrase("Pasted image", ru: "Вставленное изображение", uk: "Вставлене зображення", fr: "Image collée")
    static let savedAsFile = Phrase("Saved as a file", ru: "Сохранено файлом", uk: "Збережено файлом", fr: "Enregistré en fichier")
}
