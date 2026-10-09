import Foundation
import Testing
@testable import SAVISUL

@Test func kindOfLinksTextAndColour() {
    #expect(ClipClassify.kind(of: "https://savisul.app") == .link)
    #expect(ClipClassify.kind(of: "http://example.com/a") == .link)
    #expect(ClipClassify.kind(of: "mailto:hi@example.com") == .link)
    #expect(ClipClassify.kind(of: "ftp://files.example.com/a") == .link)
    #expect(ClipClassify.kind(of: "see https://savisul.app") == .text)
    #expect(ClipClassify.kind(of: "just a note") == .text)
    #expect(ClipClassify.kind(of: "#1a2b3c") == .color)
    #expect(ClipClassify.kind(of: "abc") == .color)
    #expect(ClipClassify.kind(of: "11223344") == .color)
    #expect(ClipClassify.kind(of: "rgb(10, 20, 30)") == .color)
    #expect(ClipClassify.kind(of: "rgba(10, 20, 30, 0.5)") == .color)
    #expect(ClipClassify.kind(of: "gggggg") == .text)
    #expect(ClipClassify.kind(of: "") == .text)
}

@Test func colourParser() {
    #expect(ClipColor.parse("#336699") != nil)
    #expect(ClipColor.parse("abc") != nil)
    #expect(ClipColor.parse("rgb(0, 128, 255)") != nil)
    #expect(ClipColor.parse("not a colour") == nil)
    #expect(ClipColor.parse("rgb(1, 2)") == nil)
}

@Test func clipboardTitles() {
    #expect(clip(.text, text: "  first line\nsecond").title == "first line")
    #expect(clip(.files, files: ["/tmp/a.png", "/tmp/b.png"]).title == "a.png +1")
    #expect(clip(.image, width: 40, height: 20).title == "40 × 20")
}

@Test func trimKeepsPinnedAndDropsTheRest() {
    let pinned = (0..<3).map { clip(.text, text: "p\($0)", pinned: true) }
    let loose = (0..<5).map { clip(.text, text: "u\($0)") }
    let kept = ClipHistoryRules.trimmed(pinned + loose, limit: 2)
    #expect(kept.filter(\.pinned).count == 3)
    #expect(kept.filter { !$0.pinned }.map(\.title) == ["u0", "u1"])
}

@Test func trimZeroDropsEveryUnpinnedItem() {
    let items = [clip(.text, text: "a", pinned: true), clip(.text, text: "b")]
    #expect(ClipHistoryRules.trimmed(items, limit: 0).map(\.title) == ["a"])
}

@Test func clipboardRoundTrip() throws {
    let original = clip(.link, text: "https://savisul.app")
    let data = try JSONEncoder().encode([original])
    let decoded = try JSONDecoder().decode([ClipItem].self, from: data)
    #expect(decoded.first?.kind == .link)
    #expect(decoded.first?.text == "https://savisul.app")
    #expect(decoded.first?.pinned == false)
}

@Test func damagedHistoryJSONIsNotAList() {
    let data = Data("{not json".utf8)
    #expect((try? JSONDecoder().decode([ClipItem].self, from: data)) == nil)
}

private func clip(_ kind: ClipItem.Kind, text: String? = nil, files: [String]? = nil, width: Int? = nil, height: Int? = nil, pinned: Bool = false) -> ClipItem {
    ClipItem(kind: kind, text: text, files: files, width: width, height: height, date: Date(timeIntervalSince1970: 1), pinned: pinned, signature: text ?? kind.rawValue)
}
