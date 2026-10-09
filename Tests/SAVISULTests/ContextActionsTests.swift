import AppKit
import Foundation
import Testing
@testable import SAVISUL

@Suite
@MainActor
final class ContextActionsTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("savisul-context-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func plainTextIsText() {
        let context = SelectionReader.context(text: "Привет, мир")
        #expect(context.primary == .text)
        #expect(context.url == nil)
        #expect(context.files.isEmpty)
    }

    @Test func aLoneLinkIsALink() {
        let context = SelectionReader.context(text: "  https://example.com/page?utm_source=x \n")
        #expect(context.primary == .url)
        #expect(context.url?.host == "example.com")
        // A sentence with a link in it stays text.
        #expect(SelectionReader.context(text: "see https://example.com now").primary == .text)
        #expect(SelectionReader.link("ftp://example.com") == nil)
    }

    @Test func anExistingPathIsAFile() throws {
        let file = directory.appendingPathComponent("note.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        let context = SelectionReader.context(text: file.path)
        #expect(context.primary == .file)
        #expect(context.files == [file])
        #expect(SelectionReader.context(text: directory.appendingPathComponent("missing.txt").path).primary == .text)
    }

    @Test func aFolderIsAFolderAndAnImageFileIsBoth() throws {
        let image = directory.appendingPathComponent("shot.png")
        try pngData(text: "Hi").write(to: image)
        let picture = ActionContext(files: [image])
        #expect(picture.inputs.isSuperset(of: [.file, .image]))
        #expect(picture.primary == .image)
        #expect(ActionContext(files: [directory]).primary == .folder)
    }

    @Test func actionsFollowWhatIsSelected() {
        let text = Set(ActionRegistry.actions(for: SelectionReader.context(text: "hello")).map(\.id))
        #expect(text.isSuperset(of: ["ai.summarize", "ai.translate", "text.count", "text.qr"]))
        #expect(!text.contains("image.ocr"))
        #expect(!text.contains("file.compress"))

        let link = Set(ActionRegistry.actions(for: SelectionReader.context(text: "https://example.com")).map(\.id))
        #expect(link.isSuperset(of: ["url.clean", "url.open", "ai.page"]))
        #expect(!link.contains("ai.translate"))
        // A link's own actions lead.
        #expect(ActionRegistry.actions(for: SelectionReader.context(text: "https://example.com")).first?.id == "url.open")
        #expect(!link.contains("text.count"))

        let folder = Set(ActionRegistry.actions(for: ActionContext(files: [directory])).map(\.id))
        #expect(folder.isSuperset(of: ["file.compress", "folder.terminal", "file.rename"]))
        #expect(!folder.contains("ai.summarize"))
        #expect(!folder.contains("ai.file"))
        #expect(ActionRegistry.actions(for: ActionContext()).isEmpty)
    }

    @Test func everyActionHasAUniqueID() {
        let ids = ActionRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ActionRegistry.action("context.open") != nil)
    }

    @Test func clipboardFlavoursBecomeTheRightContext() {
        let board = NSPasteboard(name: NSPasteboard.Name("savisul.test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("https://example.com/a", forType: .string)
        #expect(SelectionReader.context(from: board).primary == .url)

        board.clearContents()
        board.writeObjects([directory as NSURL])
        #expect(SelectionReader.context(from: board).primary == .folder)

        board.clearContents()
        board.writeObjects([NSImage(data: pngData(text: "A"))!])
        #expect(SelectionReader.context(from: board).primary == .image)
    }

    @Test func theClipboardComesBackAsItWas() {
        let board = NSPasteboard(name: NSPasteboard.Name("savisul.test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setString("<b>rich</b>", forType: .html)
        board.writeObjects([item])
        let snapshot = PasteboardSnapshot(board)
        board.clearContents()
        board.setString("borrowed", forType: .string)
        snapshot.restore(board)
        #expect(board.string(forType: .string) == "plain")
        #expect(board.string(forType: .html) == "<b>rich</b>")
    }

    @Test func renameKeepsTheExtensionAndNumbersSeveral() throws {
        let one = directory.appendingPathComponent("IMG_0001.jpg")
        let two = directory.appendingPathComponent("IMG_0002.jpg")
        for url in [one, two] { try Data([1]).write(to: url) }
        let single = try FileWork.rename([one], to: "Trip")
        #expect(single.map(\.lastPathComponent) == ["Trip.jpg"])
        let typedExtension = try FileWork.rename(single, to: "Beach.jpg")
        #expect(typedExtension.map(\.lastPathComponent) == ["Beach.jpg"])
        let three = directory.appendingPathComponent("IMG_0003.jpg")
        try Data([1]).write(to: three)
        let batch = try FileWork.rename([two, three], to: "Day")
        #expect(batch.map(\.lastPathComponent) == ["Day 1.jpg", "Day 2.jpg"])
        #expect(throws: ActionError.self) { try FileWork.rename(batch, to: "  ") }
    }

    @Test func freeNamesNeverOverwrite() throws {
        let file = directory.appendingPathComponent("a.txt")
        try Data().write(to: file)
        #expect(ActionFiles.free(file).lastPathComponent == "a 2.txt")
        #expect(ActionFiles.free(directory.appendingPathComponent("b.txt")).lastPathComponent == "b.txt")
    }

    @Test func textComesOffAnImage() async throws {
        let image = try #require(NSImage(data: pngData(text: "SAVISUL 2026")).flatMap(ImageWork.cgImage))
        let text = try await TextRecognizer.text(in: image)
        #expect(text.uppercased().contains("SAVISUL"))
    }

    @Test func imagesConvertAndZipsAreMade() throws {
        let source = directory.appendingPathComponent("pic.png")
        try pngData(text: "Z").write(to: source)
        let image = try #require(ImageWork.cgImage(source))
        let jpeg = directory.appendingPathComponent("pic.jpg")
        try ImageWork.write(image, to: jpeg, type: .jpeg, quality: 0.8)
        #expect(NSImage(contentsOf: jpeg) != nil)
        let archive = try Archive.zip([source, jpeg])
        #expect(archive.lastPathComponent == "Archive.zip")
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test func liveActivitiesComeAndGo() {
        let center = LiveActivityCenter()
        let activity = center.start(symbol: "bolt", title: "Test")
        #expect(center.current?.id == activity.id)
        activity.update(progress: 1.7, detail: "1 of 2")
        #expect(activity.progress == 1)
        activity.finish(nil)
        #expect(center.current == nil)
        activity.update(progress: 0.2)
        #expect(activity.progress == 1)
    }

    /// A white PNG with black text on it.
    private func pngData(text: String) -> Data {
        let size = NSSize(width: 520, height: 140)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(at: NSPoint(x: 24, y: 40), withAttributes: [.font: NSFont.systemFont(ofSize: 56, weight: .bold), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }
}
