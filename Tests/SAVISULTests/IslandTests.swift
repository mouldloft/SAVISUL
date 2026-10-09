import Foundation
import Testing
@testable import SAVISUL

private let start = Date(timeIntervalSinceReferenceDate: 1_000)

@Test func aCallStartsOnceTheSameAppHasHeldTheMicrophoneForTwoSeconds() {
    var tracker = CallTracker()
    #expect(tracker.update(heard: "us.zoom.xos", at: start).isEmpty)
    #expect(tracker.update(heard: "us.zoom.xos", at: start.addingTimeInterval(1)).isEmpty)
    #expect(tracker.update(heard: "us.zoom.xos", at: start.addingTimeInterval(2)) == [.started("us.zoom.xos", since: start)])
    #expect(tracker.active == "us.zoom.xos")
    #expect(tracker.update(heard: "us.zoom.xos", at: start.addingTimeInterval(3)).isEmpty)
}

@Test func aMomentOnTheMicrophoneIsNotACall() {
    var tracker = CallTracker()
    _ = tracker.update(heard: "us.zoom.xos", at: start)
    #expect(tracker.update(heard: nil, at: start.addingTimeInterval(1)).isEmpty)
    #expect(tracker.update(heard: "us.zoom.xos", at: start.addingTimeInterval(2)).isEmpty)
    #expect(tracker.active == nil)
}

@Test func aCallEndsAfterThreeQuietSecondsAndSurvivesAShortGap() {
    var tracker = CallTracker()
    _ = tracker.update(heard: "com.hnc.Discord", at: start)
    _ = tracker.update(heard: "com.hnc.Discord", at: start.addingTimeInterval(2))
    #expect(tracker.update(heard: nil, at: start.addingTimeInterval(3)).isEmpty)
    #expect(tracker.update(heard: "com.hnc.Discord", at: start.addingTimeInterval(4)).isEmpty)
    #expect(tracker.update(heard: nil, at: start.addingTimeInterval(6)).isEmpty)
    #expect(tracker.update(heard: nil, at: start.addingTimeInterval(7)) == [.ended("com.hnc.Discord")])
    #expect(tracker.active == nil)
}

@Test func anotherAppTakingTheMicrophoneMovesTheCall() {
    var tracker = CallTracker()
    _ = tracker.update(heard: "us.zoom.xos", at: start)
    _ = tracker.update(heard: "us.zoom.xos", at: start.addingTimeInterval(2))
    let moved = start.addingTimeInterval(10)
    #expect(tracker.update(heard: "com.apple.FaceTime", at: moved) == [.ended("us.zoom.xos"), .started("com.apple.FaceTime", since: moved)])
}

@Test func meetingAppsAndBrowsersCountAsCallsButRecordersDoNot() {
    #expect(CallApps.kind("us.zoom.xos") == .app("Zoom"))
    #expect(CallApps.kind("com.microsoft.teams2") == .app("Microsoft Teams"))
    #expect(CallApps.kind("com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan") == .app("Google Meet"))
    #expect(CallApps.kind("com.google.Chrome") == .browser)
    #expect(CallApps.kind("company.thebrowser.Browser") == .browser)
    #expect(CallApps.kind("com.apple.VoiceMemos") == nil)
    #expect(CallApps.kind("com.apple.QuickTimePlayerX") == nil)
    #expect(CallApps.kind("ru.keepcoder.Telegram") == .app("Telegram"))
    #expect(CallApps.kind("net.whatsapp.WhatsApp") == .app("WhatsApp"))
    #expect(CallApps.kind("com.hnc.Discord") == .app("Discord"))
    #expect(CallApps.kind("com.apple.mobilephone") == .app("Phone"))
}

@Test func callButtonLabelsMatchOnlyAsWholePhrases() {
    #expect(CallControls.normalize("  Turn off camera (⌘ + e) ") == "turn off camera")
    #expect(CallControls.normalize("End  Call…") == "end call")
    let telegram = CallControls.phrases(.hangUp, bundle: "ru.keepcoder.Telegram")
    #expect(CallControls.matches("End Call", telegram))
    #expect(CallControls.matches("Завершить звонок", telegram))
    #expect(!CallControls.matches("Выйти", telegram))
    #expect(!CallControls.matches("Log Out", telegram))
    #expect(!CallControls.matches("End", telegram))
    #expect(CallControls.matches("End", CallControls.phrases(.hangUp, bundle: "com.apple.FaceTime")))
    #expect(CallControls.matches("Disconnect", CallControls.phrases(.hangUp, bundle: "com.hnc.Discord")))
    #expect(!CallControls.matches("Disconnect", CallControls.phrases(.hangUp, bundle: "net.whatsapp.WhatsApp")))
    #expect(CallControls.matches("Leave Meeting", CallControls.leaveConfirm))
    #expect(!CallControls.matches("End Meeting for All", CallControls.leaveConfirm))
    #expect(!CallControls.matches("Завершить конференцию для всех", CallControls.leaveConfirm))
}

@Test func cameraButtonsAreFoundByWhatTheySayNotByAFixedList() {
    for label in ["Stop Video", "Start Video", "Start my video", "Turn Off Camera", "Остановить видео", "Включить видео", "Выключить камеру",
                  "Turn off camera (⌘ + e)", "Désactiver la caméra"] {
        #expect(CallControls.isCameraToggle(label), "\(label)")
    }
    for label in ["Video Settings", "Камера", "Start Recording", "Stop Share", "Choose Virtual Background", "Настройки видео", "Video"] {
        #expect(!CallControls.isCameraToggle(label), "\(label)")
    }
}

@Test func appsWithTheirOwnCallShortcutsGetThem() {
    #expect(CallControls.shortcut(.camera, bundle: "us.zoom.xos") == CallControls.Shortcut(key: 9, flags: [.maskCommand, .maskShift]))
    #expect(CallControls.shortcut(.hangUp, bundle: "us.zoom.xos")?.confirms == true)
    #expect(CallControls.shortcut(.hangUp, bundle: "com.microsoft.teams2") == CallControls.Shortcut(key: 4, flags: [.maskCommand, .maskShift]))
    #expect(CallControls.shortcut(.hangUp, bundle: "ru.keepcoder.Telegram") == nil)
    #expect(CallControls.shortcut(.camera, bundle: "net.whatsapp.WhatsApp") == nil)
}

@MainActor
@Test func theVolumeShowsHeadphonesOrHowLoudTheSpeakersAre() {
    #expect(SoundExtras.volumeSymbol(silent: true, volume: 0.5, device: "airpodspro") == "speaker.slash.fill")
    #expect(SoundExtras.volumeSymbol(silent: false, volume: 0.5, device: "airpodspro") == "airpodspro")
    #expect(SoundExtras.volumeSymbol(silent: false, volume: 0.2, device: "laptopcomputer") == "speaker.wave.1.fill")
    #expect(SoundExtras.volumeSymbol(silent: false, volume: 0.5, device: "display") == "speaker.wave.2.fill")
    #expect(SoundExtras.volumeSymbol(silent: false, volume: 0.9, device: nil) == "speaker.wave.3.fill")
}

@MainActor
@Test func aLevelUnderTheNotchUpdatesInPlaceAndGoesAway() {
    let model = IslandModel()
    model.show(hud: IslandHUD(symbol: "speaker.wave.2.fill", title: "Speakers", level: 0.4, muted: false))
    #expect(model.mode == .peek)
    model.show(hud: IslandHUD(symbol: "speaker.wave.2.fill", title: "Speakers", level: 0.5, muted: false))
    #expect(model.hud?.level == 0.5)
    model.endHUD()
    #expect(model.hud == nil)
    #expect(model.mode == .collapsed)
}

@Test func microphoneButtonsAreKnownWithTheStateTheyShow() {
    #expect(CallControls.isMicToggle("Mute", browser: false))
    #expect(CallControls.isMicToggle("Выключить звук", browser: false))
    #expect(!CallControls.isMicToggle("Mute", browser: true))
    #expect(CallControls.isMicToggle("Turn off microphone (⌘ + d)", browser: true))
    #expect(CallControls.isMicToggle("Включить микрофон", browser: true))
    #expect(!CallControls.isMicToggle("Microphone settings", browser: true))
    #expect(!CallControls.isMicToggle("Test speaker and microphone", browser: false))
    #expect(CallControls.micMuted(fromLabel: "Unmute") == true)
    #expect(CallControls.micMuted(fromLabel: "Mute") == false)
    #expect(CallControls.micMuted(fromLabel: "Turn on microphone (⌘ + d)") == true)
    #expect(CallControls.micMuted(fromLabel: "Turn off microphone") == false)
    #expect(CallControls.micMuted(fromLabel: "Включить звук") == true)
    #expect(CallControls.micMuted(fromLabel: "Выключить микрофон") == false)
    #expect(CallControls.micMuted(fromLabel: "Microphone") == nil)
}

@Test func theCallsWindowIsTheNewestOneThatCanHoldACall() {
    typealias Facts = CallControls.WindowFacts
    let main = Facts(id: 120, title: "Telegram", size: CGSize(width: 1180, height: 820), standard: true)
    let call = Facts(id: 5_310, title: "", size: CGSize(width: 720, height: 560), standard: true)
    #expect(CallControls.callWindow([main, call], appName: "Telegram") == 1)
    #expect(CallControls.callWindow([call, main], appName: "Telegram") == 0)
    // Only the main window: it is the one to show.
    #expect(CallControls.callWindow([main], appName: "Telegram") == 0)
    // A meeting window beats an older main window and a newer floating toolbar.
    let zoomMain = Facts(id: 300, title: "Zoom Workplace", size: CGSize(width: 1000, height: 700), standard: true)
    let meeting = Facts(id: 4_100, title: "Zoom Meeting", size: CGSize(width: 1280, height: 800), standard: true)
    let toolbar = Facts(id: 4_200, title: nil, size: CGSize(width: 420, height: 52), standard: true)
    let panel = Facts(id: 4_300, title: nil, size: CGSize(width: 400, height: 500), standard: false)
    #expect(CallControls.callWindow([toolbar, zoomMain, panel, meeting], appName: "zoom.us") == 3)
    #expect(CallControls.callWindow([], appName: "Telegram") == nil)
}

@Test func appsThatHideTheirCallButtonsAreKnown() {
    #expect(CallControls.closed.contains("ru.keepcoder.Telegram"))
    #expect(!CallControls.closed.contains("us.zoom.xos"))
    #expect(!CallControls.closed.contains("com.apple.FaceTime"))
}

@Test func callPagesAreKnownByTheirAddress() {
    #expect(CallTabs.isCallPage("https://meet.google.com/abc-defg-hij"))
    #expect(CallTabs.isCallPage("https://app.zoom.us/wc/123/join"))
    #expect(CallTabs.isCallPage("https://telemost.yandex.ru/j/123"))
    #expect(!CallTabs.isCallPage("https://www.google.com/search?q=meet"))
}
