import Foundation
import Testing
@testable import SAVISUL

@Suite
@MainActor
final class ShelfTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("savisul-shelf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func textLinkAndFileKinds() {
        #expect(ShelfItem.kind(for: "https://savisul.app/license") == .link)
        #expect(ShelfItem.kind(for: "HTTP://Example.com") == .link)
        #expect(ShelfItem.kind(for: "see https://savisul.app") == .text)
        #expect(ShelfItem.kind(for: "a note") == .text)
        #expect(ShelfItem.kind(for: URL(fileURLWithPath: "/tmp/a.png")) == .file)
        #expect(ShelfItem.kind(for: URL(string: "https://savisul.app")!) == .link)
    }

    @Test func addingSortsNewestFirstAndSkipsDuplicates() {
        let shelf = ShelfStore(directory: directory)
        shelf.add(text: "first note")
        shelf.add(text: "https://savisul.app")
        shelf.add(urls: [directory.appendingPathComponent("a.txt")])
        shelf.add(text: "https://savisul.app")
        #expect(shelf.items.count == 3)
        #expect(shelf.items.map(\.kind) == [.file, .link, .text])
        #expect(shelf.items[1].title == "savisul.app")
    }

    @Test func emptyTextIsIgnored() {
        let shelf = ShelfStore(directory: directory)
        shelf.add(text: "   \n")
        #expect(shelf.items.isEmpty)
    }

    @Test func clearAndReloadDropsMissingFiles() throws {
        let file = directory.appendingPathComponent("kept.txt")
        try Data("hi".utf8).write(to: file)
        let shelf = ShelfStore(directory: directory)
        shelf.add(urls: [file, directory.appendingPathComponent("gone.txt")])
        shelf.add(text: "stay")
        let reloaded = ShelfStore(directory: directory)
        #expect(reloaded.items.filter { $0.kind == .file }.count == 1)
        #expect(reloaded.items.first { $0.kind == .text }?.text == "stay")
        reloaded.clear()
        #expect(ShelfStore(directory: directory).items.isEmpty)
    }

    @Test func shelfTitles() {
        #expect(ShelfItem(kind: .file, path: "/tmp/Notes.txt").title == "Notes.txt")
        #expect(ShelfItem(kind: .link, text: "https://example.com/a").title == "example.com")
        #expect(ShelfItem(kind: .text, text: "  hello\nthere").title == "hello")
    }
}
