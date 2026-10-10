import Foundation
import Observation

/// Every switch of the island, mixer, window, clipboard and command features, saved as the user flips it.
@MainActor
@Observable
final class SuiteSettings {
    @ObservationIgnored var onChange: (() -> Void)?

    // Island
    var island: Bool { didSet { put(island, "island") } }
    var islandHover: Bool { didSet { put(islandHover, "islandHover") } }
    var islandMusic: Bool { didSet { put(islandMusic, "islandMusic") } }
    var islandLyrics: Bool { didSet { put(islandLyrics, "islandLyrics") } }
    var islandEqualizer: Bool { didSet { put(islandEqualizer, "islandEqualizer") } }
    var islandCalendar: Bool { didSet { put(islandCalendar, "islandCalendar") } }
    var islandTimers: Bool { didSet { put(islandTimers, "islandTimers") } }
    var islandDownloads: Bool { didSet { put(islandDownloads, "islandDownloads") } }
    var islandAgents: Bool { didSet { put(islandAgents, "islandAgents") } }
    var islandCamera: Bool { didSet { put(islandCamera, "islandCamera") } }
    var islandShelf: Bool { didSet { put(islandShelf, "islandShelf") } }
    var islandNotices: Bool { didSet { put(islandNotices, "islandNotices") } }
    var islandHaptics: Bool { didSet { put(islandHaptics, "islandHaptics") } }
    var islandPower: Bool { didSet { put(islandPower, "islandPower") } }
    var islandDevices: Bool { didSet { put(islandDevices, "islandDevices") } }
    var islandCalls: Bool { didSet { put(islandCalls, "islandCalls") } }
    var islandVolume: Bool { didSet { put(islandVolume, "islandVolume") } }

    // Sound
    var mixer: Bool { didSet { put(mixer, "mixer") } }
    var outputHotkey: Bool { didSet { put(outputHotkey, "outputHotkey") } }
    var headphoneGuard: Bool { didSet { put(headphoneGuard, "headphoneGuard") } }
    var headphoneLevel: Double { didSet { put(headphoneLevel, "headphoneLevel") } }
    var micHotkey: Bool { didSet { put(micHotkey, "micHotkey") } }
    var pinnedInput: String { didSet { put(pinnedInput, "pinnedInput") } }

    // Windows and the Dock
    var switcher: Bool { didSet { put(switcher, "switcher") } }
    var switcherCommandTab: Bool { didSet { put(switcherCommandTab, "switcherCommandTab") } }
    var switcherPreviews: Bool { didSet { put(switcherPreviews, "switcherPreviews") } }
    var snapping: Bool { didSet { put(snapping, "snapping") } }
    var modifierDrag: Bool { didSet { put(modifierDrag, "modifierDrag") } }
    var edgeSnap: Bool { didSet { put(edgeSnap, "edgeSnap") } }
    var dockPreview: Bool { didSet { put(dockPreview, "dockPreview") } }
    var greenButton: Bool { didSet { put(greenButton, "greenButton") } }
    var quitGuard: Bool { didSet { put(quitGuard, "quitGuard") } }
    var quitGuardDouble: Bool { didSet { put(quitGuardDouble, "quitGuardDouble") } }
    var quitOnClose: Bool { didSet { put(quitOnClose, "quitOnClose") } }
    var quitOnCloseApps: [String] { didSet { put(quitOnCloseApps, "quitOnCloseApps") } }

    // Clipboard and files
    var clipboard: Bool { didSet { put(clipboard, "clipboard") } }
    var clipboardLimit: Int { didSet { put(clipboardLimit, "clipboardLimit") } }
    var plainPaste: Bool { didSet { put(plainPaste, "plainPaste") } }
    var shelf: Bool { didSet { put(shelf, "shelf") } }
    var shelfShake: Bool { didSet { put(shelfShake, "shelfShake") } }
    var finderCut: Bool { didSet { put(finderCut, "finderCut") } }
    var finderRename: Bool { didSet { put(finderRename, "finderRename") } }
    var finderImages: Bool { didSet { put(finderImages, "finderImages") } }
    var dmgInstaller: Bool { didSet { put(dmgInstaller, "dmgInstaller") } }
    var dmgTrash: Bool { didSet { put(dmgTrash, "dmgTrash") } }

    // Commands
    var commandBar: Bool { didSet { put(commandBar, "commandBar") } }
    var radial: Bool { didSet { put(radial, "radial") } }
    var radialMouse: Bool { didSet { put(radialMouse, "radialMouse") } }
    var quickPanel: Bool { didSet { put(quickPanel, "quickPanel") } }
    var contextActions: Bool { didSet { put(contextActions, "contextActions") } }
    var automations: Bool { didSet { put(automations, "automations") } }
    var favorites: [String] { didSet { put(favorites, "favorites") } }

    // AI agents
    var agentChime: Bool { didSet { put(agentChime, "agentChime") } }
    var agentMinimumMinutes: Double { didSet { put(agentMinimumMinutes, "agentMinimumMinutes") } }

    // Face Unlock
    var faceUnlock: Bool { didSet { put(faceUnlock, "faceUnlock") } }
    var faceUnlockBlink: Bool { didSet { put(faceUnlockBlink, "faceUnlockBlink") } }
    var faceUnlockRightAway: Bool { didSet { put(faceUnlockRightAway, "faceUnlockRightAway") } }

    static let defaultFavorites = [
        "capture.area", "clipboard.open", "shelf.open", "timer.5", "sound.mute", "mic.mute", "display.off", "command.open"
    ]

    init() {
        SettingsMigration.apply()
        island = Self.read("island", true)
        islandHover = Self.read("islandHover", true)
        islandMusic = Self.read("islandMusic", true)
        islandLyrics = Self.read("islandLyrics", true)
        islandEqualizer = Self.read("islandEqualizer", true)
        islandCalendar = Self.read("islandCalendar", true)
        islandTimers = Self.read("islandTimers", true)
        islandDownloads = Self.read("islandDownloads", true)
        islandAgents = Self.read("islandAgents", true)
        islandCamera = Self.read("islandCamera", true)
        islandShelf = Self.read("islandShelf", true)
        islandNotices = Self.read("islandNotices", true)
        islandHaptics = Self.read("islandHaptics", true)
        islandPower = Self.read("islandPower", true)
        islandDevices = Self.read("islandDevices", true)
        islandCalls = Self.read("islandCalls", true)
        islandVolume = Self.read("islandVolume", true)

        mixer = Self.read("mixer", false)
        outputHotkey = Self.read("outputHotkey", true)
        headphoneGuard = Self.read("headphoneGuard", true)
        headphoneLevel = Self.read("headphoneLevel", 0.25)
        micHotkey = Self.read("micHotkey", true)
        pinnedInput = Self.read("pinnedInput", "")

        switcher = Self.read("switcher", true)
        switcherCommandTab = Self.read("switcherCommandTab", false)
        switcherPreviews = Self.read("switcherPreviews", true)
        snapping = Self.read("snapping", true)
        modifierDrag = Self.read("modifierDrag", true)
        edgeSnap = Self.read("edgeSnap", false)
        dockPreview = Self.read("dockPreview", true)
        greenButton = Self.read("greenButton", true)
        quitGuard = Self.read("quitGuard", true)
        quitGuardDouble = Self.read("quitGuardDouble", false)
        quitOnClose = Self.read("quitOnClose", false)
        quitOnCloseApps = Self.read("quitOnCloseApps", ["com.apple.Preview", "com.apple.TextEdit", "com.apple.QuickTimePlayerX"])

        clipboard = Self.read("clipboard", true)
        clipboardLimit = Self.read("clipboardLimit", 1000)
        plainPaste = Self.read("plainPaste", true)
        shelf = Self.read("shelf", true)
        shelfShake = Self.read("shelfShake", true)
        finderCut = Self.read("finderCut", true)
        finderRename = Self.read("finderRename", true)
        finderImages = Self.read("finderImages", true)
        dmgInstaller = Self.read("dmgInstaller", true)
        dmgTrash = Self.read("dmgTrash", true)

        commandBar = Self.read("commandBar", true)
        radial = Self.read("radial", true)
        radialMouse = Self.read("radialMouse", false)
        quickPanel = Self.read("quickPanel", true)
        contextActions = Self.read("contextActions", true)
        automations = Self.read("automations", true)
        favorites = Self.read("favorites", Self.defaultFavorites)

        agentChime = Self.read("agentChime", true)
        agentMinimumMinutes = Self.read("agentMinimumMinutes", 1)

        faceUnlock = Self.read("faceUnlock", false)
        faceUnlockBlink = Self.read("faceUnlockBlink", false)
        faceUnlockRightAway = Self.read("faceUnlockRightAway", true)
    }

    private static func read<T>(_ key: String, _ fallback: T) -> T {
        SettingsDefaults.store.object(forKey: "suite.\(key)") as? T ?? fallback
    }

    private func put(_ value: Any, _ key: String) {
        SettingsDefaults.store.set(value, forKey: "suite.\(key)")
        onChange?()
    }
}

/// Where settings are read and written. Tests point this at a private suite.
enum SettingsDefaults {
    nonisolated(unsafe) static var store = UserDefaults.standard
}

/// Bumps `suite.settingsVersion` without erasing choices the user already made.
enum SettingsMigration {
    static let current = 1

    static func apply(_ defaults: UserDefaults = SettingsDefaults.store) {
        if defaults.integer(forKey: "suite.settingsVersion") < current {
            defaults.set(current, forKey: "suite.settingsVersion")
        }
    }
}
