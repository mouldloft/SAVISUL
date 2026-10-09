import SwiftUI
import Testing
@testable import SAVISUL

@Suite
@MainActor
struct ActionEngineTests {
    @Test func unknownIdDoesNotRun() {
        var ran = 0
        let catalog = [action("one") { ran += 1 }]
        #expect(!ActionEngine.perform("missing", in: catalog))
        #expect(ran == 0)
        #expect(!ActionEngine.perform("", in: []))
    }

    @Test func theMatchingActionRunsOnce() {
        var ran: [String] = []
        let catalog = [action("one") { ran.append("one") }, action("two") { ran.append("two") }]
        #expect(ActionEngine.perform("two", in: catalog))
        #expect(ran == ["two"])
    }

    @Test func theFirstDuplicateWins() {
        var ran: [String] = []
        let catalog = [action("same") { ran.append("first") }, action("same") { ran.append("second") }]
        #expect(ActionEngine.perform("same", in: catalog))
        #expect(ran == ["first"])
    }

    @Test func anActionThatRecordsAnErrorStillCountsAsRun() {
        var error: String?
        let catalog = [action("boom") { error = "unavailable" }]
        #expect(ActionEngine.perform("boom", in: catalog))
        #expect(error == "unavailable")
    }

    @Test func catalogCoversTheSurfacesAndTimerTitles() {
        let ids = Set(SuiteActions.all.map(\.id))
        for id in ["clipboard.open", "shelf.open", "command.open", "timer.1", "timer.5", "timer.25", "window.left", "sound.mute", "mic.mute"] {
            #expect(ids.contains(id))
        }
        #expect(Set(SuiteActions.all.map(\.id)).count == SuiteActions.all.count)
        let five = SuiteActions.action("timer.5")
        #expect(five != nil)
        Suite.shared.language = .en
        #expect(SuiteActions.title(five!) == "Timer 5 min")
        Suite.shared.language = .ru
        #expect(SuiteActions.title(five!) == "Таймер 5 мин")
        Suite.shared.language = .en
        #expect(SuiteActions.action("no.such.action") == nil)
    }

    @Test func keywordSearchFindsAnActionWithoutRunningIt() {
        var ran = false
        let catalog = [action("clipboard.open", keywords: ["clipboard", "буфер"]) { ran = true }]
        let hit = catalog.first { item in item.keywords.contains { Fuzzy.score($0, "clip") != nil } }
        #expect(hit?.id == "clipboard.open")
        #expect(!ran)
    }

    private func action(_ id: String, keywords: [String] = [], run: @escaping @MainActor () -> Void) -> SuiteAction {
        SuiteAction(id: id, title: Phrase(id, ru: id, uk: id, fr: id), symbol: "circle", tint: .white, keywords: keywords, run: run)
    }
}
