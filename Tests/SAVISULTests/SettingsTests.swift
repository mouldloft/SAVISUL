import Foundation
import Testing
@testable import SAVISUL

@Suite(.serialized)
@MainActor
final class SettingsTests {
    let suiteName: String
    let previous: UserDefaults

    init() {
        previous = SettingsDefaults.store
        suiteName = "savisul.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        SettingsDefaults.store = suite
    }

    deinit {
        SettingsDefaults.store.removePersistentDomain(forName: suiteName)
        SettingsDefaults.store = previous
    }

    @Test func freshSettingsUseTheDefaults() {
        let settings = SuiteSettings()
        #expect(settings.island)
        #expect(!settings.mixer)
        #expect(settings.clipboardLimit == 1000)
        #expect(settings.favorites == SuiteSettings.defaultFavorites)
        #expect(abs(settings.headphoneLevel - 0.25) < 0.001)
        #expect(SettingsDefaults.store.integer(forKey: "suite.settingsVersion") == SettingsMigration.current)
    }

    @Test func aChangeIsWhatTheNextLaunchReads() {
        let settings = SuiteSettings()
        settings.island = false
        settings.clipboardLimit = 50
        settings.favorites = ["timer.5"]
        settings.pinnedInput = "mic-1"
        let again = SuiteSettings()
        #expect(!again.island)
        #expect(again.clipboardLimit == 50)
        #expect(again.favorites == ["timer.5"])
        #expect(again.pinnedInput == "mic-1")
    }

    @Test func migrationKeepsExistingChoices() {
        SettingsDefaults.store.set(false, forKey: "suite.island")
        SettingsDefaults.store.set(0, forKey: "suite.settingsVersion")
        SettingsMigration.apply()
        #expect(!SuiteSettings().island)
        #expect(SettingsDefaults.store.integer(forKey: "suite.settingsVersion") == 1)
    }

    @Test func aNewerVersionIsNotRewritten() {
        SettingsDefaults.store.set(false, forKey: "suite.commandBar")
        SettingsDefaults.store.set(9, forKey: "suite.settingsVersion")
        SettingsMigration.apply()
        #expect(SettingsDefaults.store.integer(forKey: "suite.settingsVersion") == 9)
        #expect(!SuiteSettings().commandBar)
    }

    @Test func missingKeyFallsBackWithoutWriting() {
        let settings = SuiteSettings()
        #expect(settings.snapping)
        #expect(SettingsDefaults.store.object(forKey: "suite.snapping") == nil)
        settings.snapping = false
        #expect(SettingsDefaults.store.object(forKey: "suite.snapping") as? Bool == false)
    }
}
