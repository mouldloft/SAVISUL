import Foundation
import Testing
@testable import SAVISUL

/// The "What's new" screen comes once after an update, never after a fresh install, and says only what is new.
@Suite(.serialized)
@MainActor
struct WhatsNewTests {
    private func defaults() -> UserDefaults {
        let name = "savisul-whatsnew-\(UUID().uuidString)"
        return UserDefaults(suiteName: name) ?? .standard
    }

    @Test func aFreshInstallHasNothingToTell() {
        let store = defaults()
        #expect(WhatsNew.due(current: "2.9", defaults: store, ranBefore: false).isEmpty)
        #expect(store.string(forKey: "whatsNew.seen") == "2.9")
    }

    @Test func anUpdateShowsWhatCameSinceOnce() {
        let store = defaults()
        // From a version that kept nothing yet: this one and the one before it.
        #expect(WhatsNew.due(current: "2.9", defaults: store, ranBefore: true).map(\.version) == ["2.9", "2.8"])
        // Next launch of the same version: nothing.
        #expect(WhatsNew.due(current: "2.9", defaults: store, ranBefore: true).isEmpty)
        // From 2.8 to 2.9: only 2.9.
        store.set("2.8", forKey: "whatsNew.seen")
        #expect(WhatsNew.due(current: "2.9", defaults: store, ranBefore: true).map(\.version) == ["2.9"])
    }

    @Test func notesNeverRunAheadOfTheApp() {
        #expect(ReleaseNotes.since(nil, current: "2.8").map(\.version) == ["2.8"])
        #expect(ReleaseNotes.since("2.9", current: "2.9").isEmpty)
        #if MOULD_ENGINE
        #expect(ReleaseNotes.since("2.7", current: "3.0").map(\.version).prefix(3) == ["2.9.2", "2.9.1", "2.9"])
        #expect(ReleaseNotes.since("2.9", current: "2.9.1").map(\.version) == ["2.9.1"])
        #expect(ReleaseNotes.since("2.9.1", current: "2.9.2").map(\.version) == ["2.9.2"])
        #else
        // The open-source build has no assistant, and 2.9.1 and 2.9.2 brought only the assistant's news.
        #expect(ReleaseNotes.since("2.7", current: "3.0").map(\.version) == ["2.9", "2.8"])
        #expect(ReleaseNotes.since("2.9", current: "2.9.2").isEmpty)
        #endif
    }

    @Test func everyNoteIsWrittenInEveryLanguage() {
        for note in ReleaseNotes.all {
            #expect(!note.items.isEmpty)
            for item in note.items {
                for language in Language.allCases {
                    #expect(!item.title.text(language).isEmpty && !item.detail.text(language).isEmpty, "\(note.version) \(item.title.en) in \(language)")
                }
            }
        }
        // The newest notes are this build's.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        if let version, version != "0" { #expect(!Updater.isNewer(version, than: ReleaseNotes.all[0].version) || ReleaseNotes.all[0].version == version) }
    }
}
