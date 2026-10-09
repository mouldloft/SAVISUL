import AppKit
import Carbon.HIToolbox
import CoreAudio
import Observation
import SwiftUI

/// Owns the island, sound, window, clipboard and command features, starts and stops each
/// one as its switch changes, and turns their events into island notices.
@MainActor
@Observable
final class Suite {
    static let shared = Suite()

    var language: Language = .en
    let settings = SuiteSettings()
    let island = IslandModel()
    let nowPlaying = NowPlaying()
    let lyrics = Lyrics()
    let timers = TimerCenter()
    let calendar = CalendarFeed()
    let downloads = DownloadWatcher()
    let camera = CameraMirror()
    let agents = AgentMonitor()
    let calls = CallMonitor()
    let launcher = AgentLauncher()
    let shelf = ShelfStore()
    let live = LiveActivityCenter()
    let contextActions = ContextActionsPanel()
    let automations = AutomationEngine()
    let mixer = Mixer()
    let power = PowerEvents()
    @ObservationIgnored let windows = WindowsSuite()
    @ObservationIgnored let clipboard = ClipboardSuite()
    @ObservationIgnored let commands = CommandsSuite()

    var spectrumLevels: [Float] = []
    var micMuted = false

    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored lazy var sound = SoundExtras(suite: self)
    @ObservationIgnored private var islandController: IslandController?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var applying = false
    @ObservationIgnored private var tick: Timer?
    /// The output the call's sound button muted, so it comes back when the call ends.
    private var callMutedOutput: AudioDeviceID?
    /// An output without a mute switch is turned down to zero instead; this is the level to bring back.
    private var callSilenced: (device: AudioDeviceID, volume: Double)?

    func start(app: AppModel) {
        guard !started else { return }
        started = true
        self.app = app
        language = app.language
        settings.onChange = { [weak self] in self?.scheduleApply() }
        wireEvents()
        automations.start()
        timers.start()
        sound.start()
        power.start()
        mixer.onLevels = { [weak self] levels in self?.spectrumLevels = levels }
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { Suite.shared.housekeeping() }
        }
        apply()
        // Any process can post a distributed notification, so the screenshot hooks only listen when asked for at launch.
        if CommandLine.arguments.contains("--qa") {
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.savisul.qa"), object: nil, queue: .main) { note in
                let command = note.object as? String ?? ""
                MainActor.assumeIsolated { Suite.shared.qa(command) }
            }
        }
    }

    /// Lets screenshots of every state be taken without a person at the pointer.
    private func qa(_ command: String) {
        let parts = command.split(separator: ".").map(String.init)
        switch parts.first {
        case "island":
            if parts.count > 2, parts[1] == "expand" {
                island.pinned = true
                island.expand(IslandTab(rawValue: parts[2]) ?? .home)
            } else if parts.count > 1, parts[1] == "collapse" {
                island.pinned = false
                island.collapse()
            } else if parts.count > 1, parts[1] == "notice" {
                notify(IslandNotice(symbol: "checkmark.seal.fill", tint: AgentKind.codex.tint, title: Phrases.agentDone("Codex"),
                                    detail: "SAVISUL · 12 мин", style: .success, duration: 6))
            } else if parts.count > 1, parts[1] == "timer" {
                timers.add(minutes: 5)
            } else if parts.count > 1, parts[1] == "compose" {
                island.pinned = true
                island.expand(.agents)
                launcher.refresh(force: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    MainActor.assumeIsolated {
                        let suite = Suite.shared
                        suite.launcher.begin(parts.count > 2 ? AgentKind(rawValue: parts[2]) : nil, monitor: suite.agents)
                        if parts.count > 3 { suite.launcher.draft = parts[3...].joined(separator: ".") }
                    }
                }
            }
        case "context":
            // context.text, context.url, context.file.<path>, context.run.<action id>, context.close
            let rest = parts.count > 2 ? parts[2...].joined(separator: ".") : ""
            switch parts.count > 1 ? parts[1] : "" {
            case "text":
                contextActions.open(with: SelectionReader.context(text: "SAVISUL turns the notch into a living island: music, timers, files and AI agents, with one shortcut for everything you select."))
            case "url":
                contextActions.open(with: SelectionReader.context(text: "https://www.apple.com/macbook-pro/?utm_source=newsletter&utm_campaign=fall&fbclid=abc"))
            case "file":
                contextActions.open(with: ActionContext(files: [URL(fileURLWithPath: rest)]))
            case "run":
                if let action = contextActions.model.actions.first(where: { $0.id == rest }) { contextActions.choose(action) }
            case "close":
                contextActions.close()
            default:
                break
            }
        case "panel":
            // panel.<pane>, panel.<pane>.end (scrolled to the last card), panel.hide
            if parts.count > 1, parts[1] == "hide" {
                app?.onHide?()
            } else if parts.count > 1, let pane = Pane(rawValue: parts[1]) {
                app?.select(pane)
                app?.onShow?()
                guard parts.count > 2, parts[2] == "end" else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    MainActor.assumeIsolated { Suite.shared.app?.scrollToEnd += 1 }
                }
            }
        default:
            break
        }
    }

    func shutdown() {
        nowPlaying.stop()
        camera.stop()
        mixer.stop()
        sound.shutdown()
        windows.shutdown()
    }

    /// Window, Finder and switcher features act on other apps and need Accessibility.
    func askAccessibility() {
        notify(IslandNotice(symbol: "hand.raised.fill", tint: Palette.warning, title: Phrases.needsAccessibility.text,
                            detail: nil, style: .warning, duration: 4,
                            actionTitle: Phrases.allow.text, action: { [weak self] in self?.app?.permissions.requestAccessibility() }))
    }

    /// Once a second: point the real equalizer at whatever the island is showing.
    private func housekeeping() {
        let showsMedia: Bool
        switch island.mode {
        case .expanded: showsMedia = island.tab == .home
        default: showsMedia = IslandActivity.current(self) == .media
        }
        let wantsSpectrum = settings.mixer && settings.islandEqualizer && showsMedia && nowPlaying.playing
        mixer.spectrumFor = wantsSpectrum ? (nowPlaying.item?.pid ?? 0) : 0
        if !wantsSpectrum, !spectrumLevels.isEmpty { spectrumLevels = [] }
    }

    private func bind(_ name: String, _ enabled: Bool, _ combo: KeyCombo, release: (() -> Void)? = nil, press: @escaping () -> Void) {
        if enabled {
            if !HotKeyCenter.shared.isRegistered(name) { _ = HotKeyCenter.shared.register(name, combo, press: press, release: release) }
        } else {
            HotKeyCenter.shared.unregister(name)
        }
    }

    private func scheduleApply() {
        guard !applying else { return }
        applying = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.applying = false
                self?.apply()
            }
        }
    }

    /// Brings every feature in line with its switch. Safe to call any number of times.
    func apply() {
        let s = settings
        if s.island {
            if islandController == nil { islandController = IslandController(suite: self) }
            islandController?.show()
        } else {
            islandController?.hide()
        }
        if s.island && s.islandMusic { nowPlaying.start() } else { nowPlaying.stop() }
        if s.island && s.islandCalendar { calendar.start() } else { calendar.stop() }
        if s.island && s.islandDownloads { downloads.start() } else { downloads.stop() }
        if s.island && s.islandAgents { agents.start() } else { agents.stop() }
        if s.island && s.islandCalls { calls.start() } else { calls.stop() }
        if s.mixer { mixer.start() } else { mixer.stop() }
        bind("sound.output", s.outputHotkey, .control(kVK_ANSI_O)) { Suite.shared.sound.cycleOutput() }
        bind("sound.mics", s.micHotkey, .control(kVK_ANSI_M)) { Suite.shared.sound.toggleMics() }
        windows.apply(s)
        clipboard.apply(s)
        commands.apply(s)
    }

    /// Expands the island on a tab, turning the island on first if needed.
    func openIsland(_ tab: IslandTab) {
        if !settings.island {
            settings.island = true
            apply()
        }
        islandController?.open(tab)
    }

    func accessibilityGranted() {
        apply()
    }

    /// Opens the SAVISUL panel on the features page.
    func openSettings() {
        app?.select(.features)
        app?.onShow?()
    }

    // MARK: Events into the island

    private func wireEvents() {
        nowPlaying.onTrackChange = { [weak self] item in
            guard let self else { return }
            if self.settings.islandLyrics { self.lyrics.load(for: item) }
        }
        timers.onFinish = { [weak self] timer in
            guard let self else { return }
            self.notify(IslandNotice(symbol: "timer", tint: Palette.accent, title: Phrases.timerDone.text,
                                     detail: timer.label, style: .alert, duration: 8,
                                     actionTitle: Phrases.plusMinute.text, action: { [weak self] in self?.timers.extend(timer.id) }))
        }
        calendar.onSoon = { [weak self] (event: CalendarFeed.Event) in
            guard let self else { return }
            let minutes = max(Int((event.start.timeIntervalSinceNow / 60).rounded()), 1)
            var notice = IslandNotice(symbol: "calendar", tint: event.color, title: event.title,
                                      detail: Phrases.startsIn(minutes), duration: 7)
            if event.meeting != nil {
                notice.actionTitle = Phrases.join.text
                notice.action = { [weak self] in self?.calendar.open(event) }
            }
            self.notify(notice)
        }
        downloads.onFinished = { [weak self] item in
            guard let self else { return }
            self.notify(IslandNotice(symbol: "arrow.down.circle.fill", tint: Palette.positive, title: Phrases.downloaded.text,
                                     detail: item.name, image: NSWorkspace.shared.icon(forFile: item.url.path), style: .success,
                                     actionTitle: Phrases.open.text, action: { [weak self] in self?.downloads.open(item) }))
        }
        agents.onFinish = { [weak self] finish in
            guard let self else { return }
            let minimum = self.settings.agentMinimumMinutes * 60
            guard finish.limitHit || finish.duration >= minimum else { return }
            self.automations.agentFinished(finish)
            let title = finish.limitHit ? Phrases.agentLimit(finish.kind.short) : Phrases.agentDone(finish.kind.short)
            let detail = [finish.project, Say.duration(finish.duration)].compactMap { $0 }.joined(separator: " · ")
            self.notify(IslandNotice(symbol: finish.limitHit ? "exclamationmark.octagon.fill" : "checkmark.seal.fill",
                                     tint: finish.limitHit ? Palette.danger : finish.kind.tint, title: title, detail: detail,
                                     style: finish.limitHit ? .warning : .success, duration: 6))
            if self.settings.agentChime { NSSound(named: NSSound.Name(finish.limitHit ? "Basso" : "Hero"))?.play() }
        }
        agents.onStart = { [weak self] status in
            guard let self else { return }
            let detail = [status.project, status.model].compactMap { $0 }.joined(separator: " · ")
            self.notify(IslandNotice(symbol: status.kind.symbol, tint: status.kind.tint, title: Phrases.agentWorking(status.kind.short),
                                     detail: detail.isEmpty ? nil : detail, duration: 2.8))
        }
        calls.onStart = { [weak self] call in
            guard let self else { return }
            let icon = call.appPath.map { NSWorkspace.shared.icon(forFile: $0) }
            self.notify(IslandNotice(symbol: "phone.fill", tint: Palette.positive, title: call.browser ? Phrases.callIn(call.name) : Phrases.onCall(call.name),
                                     detail: self.micMuted ? SoundPhrases.micsOff.text : Phrases.muteHint.text, image: icon, style: .success, duration: 5,
                                     actionTitle: self.callMicOff ? Phrases.unmute.text : Phrases.mute.text,
                                     action: { Suite.shared.toggleCallMic() }))
        }
        calls.onEnd = { [weak self] call in
            guard let self else { return }
            self.restoreCallSound()
            if self.island.tab == .call { self.island.tab = .home }
            let length = Say.duration(Date().timeIntervalSince(call.since))
            if self.micMuted {
                self.notify(IslandNotice(symbol: "mic.slash.fill", tint: Palette.warning, title: Phrases.callEnded.text,
                                         detail: Phrases.micsStillOff.text, style: .warning, duration: 6,
                                         actionTitle: Phrases.unmute.text, action: { Suite.shared.sound.toggleMics() }))
            } else {
                self.notify(IslandNotice(symbol: "phone.down.fill", tint: Palette.secondary, title: Phrases.callEnded.text,
                                         detail: "\(call.name) · \(length)", duration: 2.6))
            }
        }
        power.onEvent = { [weak self] event in
            guard let self, self.settings.islandPower else { return }
            switch event {
            case .plugged(let percent, let charging):
                self.notify(IslandNotice(symbol: charging ? "bolt.fill" : "powerplug.fill", tint: Palette.positive,
                                         title: charging ? Phrases.charging.text : Phrases.onPower.text, detail: Say.percent(Double(percent)),
                                         style: .success, level: Double(percent) / 100, duration: 2.6))
            case .unplugged(let percent):
                self.notify(IslandNotice(symbol: "battery.75percent", tint: Palette.ink, title: Phrases.onBattery.text,
                                         detail: Say.percent(Double(percent)), level: Double(percent) / 100, duration: 2.4))
            case .full:
                self.notify(IslandNotice(symbol: "battery.100percent.bolt", tint: Palette.positive, title: Phrases.charged.text,
                                         detail: nil, style: .success, level: 1, duration: 3))
            case .low(let level):
                self.notify(IslandNotice(symbol: level <= 10 ? "battery.0percent" : "battery.25percent", tint: Palette.danger,
                                         title: Phrases.batteryLow.text, detail: Say.percent(Double(level)),
                                         style: .warning, level: Double(level) / 100, duration: 5))
            }
        }
        shelf.onAdd = { [weak self] count in
            guard let self, self.island.mode != .expanded else { return }
            self.notify(IslandNotice(symbol: "tray.and.arrow.down.fill", tint: Palette.accent, title: Phrases.onShelf.text,
                                     detail: Phrases.items(count), style: .success, duration: 2.4))
        }
    }

    // MARK: The call's controls

    /// Turns the call's camera off or on, or hangs up, in whichever app the call is in.
    func callAction(_ action: CallControls.Action, done: (@MainActor () -> Void)? = nil) {
        guard let call = calls.current else {
            done?()
            return
        }
        CallControls.perform(action, on: call) { [weak self] outcome in
            done?()
            guard let self else { return }
            switch outcome {
            case .done, .notFound:
                break
            case .confirmInApp:
                self.notify(IslandNotice(symbol: "phone.down.fill", tint: Palette.warning, title: Phrases.confirmIn(call.name), detail: nil, duration: 3))
            case .openedApp:
                self.notify(IslandNotice(symbol: action == .hangUp ? "phone.down.fill" : "video.fill", tint: Palette.accent,
                                         title: action == .hangUp ? Phrases.finishIn(call.name) : Phrases.cameraIn(call.name), detail: nil, duration: 3))
            case .needsAccess:
                self.notify(IslandNotice(symbol: "hand.raised.fill", tint: Palette.warning, title: Phrases.callNeedsAccess.text, detail: nil,
                                         style: .warning, duration: 5, actionTitle: Phrases.allow.text,
                                         action: { [weak self] in self?.app?.permissions.requestAccessibility() }))
            }
        }
    }

    /// Whether the call's microphone is off: as its own button says, or because every microphone is muted.
    var callMicOff: Bool { micMuted || calls.current?.micMuted == true }

    /// Mutes or unmutes the call the way its own button does, so the meeting shows it too. Apps and pages
    /// without a button to press get every microphone muted instead, which nobody on the call can hear past.
    func toggleCallMic() {
        guard let call = calls.current, !micMuted else {
            sound.toggleMics()
            return
        }
        let wanted = !(call.micMuted ?? false)
        CallControls.perform(.microphone, on: call) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .done, .confirmInApp:
                self.calls.expectMicrophone(muted: wanted)
            case .needsAccess:
                self.sound.toggleMics()
                self.notify(IslandNotice(symbol: "hand.raised.fill", tint: Palette.warning, title: Phrases.callNeedsAccess.text, detail: nil,
                                         style: .warning, duration: 5, actionTitle: Phrases.allow.text,
                                         action: { [weak self] in self?.app?.permissions.requestAccessibility() }))
            case .notFound, .openedApp:
                self.sound.toggleMics()
            }
        }
    }

    /// Whether the call's speakers are off, by their mute switch or turned down to zero.
    var callSoundOff: Bool { app?.audio.currentOutput?.muted == true || callSilenced != nil }

    /// Mutes or unmutes the speakers for the call; whatever this turned off comes back when the call ends.
    func toggleCallSound() {
        guard let audio = app?.audio, let output = audio.currentOutput else { return }
        if let silenced = callSilenced {
            audio.setVolume(silenced.volume, device: silenced.device, scope: .output)
            callSilenced = nil
        } else if output.muted != nil {
            let mute = !(output.muted ?? false)
            audio.setMuted(mute, device: output.id, scope: .output)
            callMutedOutput = mute ? output.id : nil
        } else {
            callSilenced = (output.id, output.volume ?? 0.5)
            audio.setVolume(0, device: output.id, scope: .output)
        }
    }

    private func restoreCallSound() {
        if let device = callMutedOutput {
            app?.audio.setMuted(false, device: device, scope: .output)
            callMutedOutput = nil
        }
        if let silenced = callSilenced {
            app?.audio.setVolume(silenced.volume, device: silenced.device, scope: .output)
            callSilenced = nil
        }
    }

    /// Brings the app on the call to the front; a browser comes forward on the call's own tab.
    func openCallApp() {
        guard let call = calls.current,
              let app = NSRunningApplication(processIdentifier: call.pid) ?? NSRunningApplication.runningApplications(withBundleIdentifier: call.bundle).first
        else { return }
        if call.browser {
            CallTabs.open(bundle: call.bundle, app: app)
        } else {
            CallControls.bringForward(app)
        }
    }

    /// Posts to the island when it is on, otherwise to the SAVISUL panel toast.
    func notify(_ notice: IslandNotice) {
        if settings.island && settings.islandNotices {
            island.post(notice)
            if settings.islandHaptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        } else {
            app?.showToast(Toast(symbol: notice.symbol, text: [notice.title, notice.detail].compactMap { $0 }.joined(separator: " · "),
                                 tone: notice.style == .warning || notice.style == .alert ? .warning : .success))
        }
    }
}

extension Phrases {
    static let timerDone = Phrase("Time is up", ru: "Время вышло", uk: "Час вийшов", fr: "C’est l’heure")
    static let plusMinute = Phrase("+1 min", ru: "+1 мин", uk: "+1 хв", fr: "+1 min")
    static let join = Phrase("Join", ru: "Войти", uk: "Увійти", fr: "Rejoindre")
    static let downloaded = Phrase("Downloaded", ru: "Загружено", uk: "Завантажено", fr: "Téléchargé")
    static let onShelf = Phrase("On the shelf", ru: "На полке", uk: "На полиці", fr: "Sur l’étagère")
    static let charging = Phrase("Charging", ru: "Заряжается", uk: "Заряджається", fr: "En charge")
    static let onPower = Phrase("On power adapter", ru: "От сети", uk: "Від мережі", fr: "Sur secteur")
    static let onBattery = Phrase("On battery", ru: "От батареи", uk: "Від батареї", fr: "Sur batterie")
    static let charged = Phrase("Fully charged", ru: "Полностью заряжен", uk: "Повністю заряджено", fr: "Chargé")
    static let batteryLow = Phrase("Battery low", ru: "Батарея садится", uk: "Батарея сідає", fr: "Batterie faible")
    @MainActor static func startsIn(_ minutes: Int) -> String {
        Phrase("Starts in %d min", ru: "Начнётся через %d мин", uk: "Почнеться через %d хв", fr: "Commence dans %d min")(minutes)
    }
    @MainActor static func items(_ count: Int) -> String {
        Phrase("%d item", ru: "Объектов: %d", uk: "Обʼєктів: %d", fr: "%d élément(s)")(count)
    }
    @MainActor static func agentDone(_ name: String) -> String {
        Phrase("%@ finished", ru: "%@ закончил", uk: "%@ завершив", fr: "%@ a terminé")(name)
    }
    @MainActor static func agentLimit(_ name: String) -> String {
        Phrase("%@ hit the limit", ru: "%@ упёрся в лимит", uk: "%@ досяг ліміту", fr: "%@ a atteint la limite")(name)
    }
    @MainActor static func agentWorking(_ name: String) -> String {
        Phrase("%@ is working", ru: "%@ работает", uk: "%@ працює", fr: "%@ travaille")(name)
    }
    @MainActor static func onCall(_ name: String) -> String {
        Phrase("%@ call", ru: "Звонок в %@", uk: "Дзвінок у %@", fr: "Appel %@")(name)
    }
    @MainActor static func callIn(_ name: String) -> String {
        Phrase("Call in %@", ru: "Звонок в %@", uk: "Дзвінок у %@", fr: "Appel dans %@")(name)
    }
    static let callEnded = Phrase("Call ended", ru: "Звонок завершён", uk: "Дзвінок завершено", fr: "Appel terminé")
    static let onCallNow = Phrase("On a call", ru: "Идёт звонок", uk: "Триває дзвінок", fr: "En appel")
    static let muteHint = Phrase("⌃⌥M mutes every microphone", ru: "⌃⌥M выключает все микрофоны", uk: "⌃⌥M вимикає всі мікрофони", fr: "⌃⌥M coupe tous les micros")
    static let micsStillOff = Phrase("Microphones are still off", ru: "Микрофоны всё ещё выключены", uk: "Мікрофони досі вимкнені", fr: "Les micros sont toujours coupés")
    static let mute = Phrase("Mute", ru: "Выключить", uk: "Вимкнути", fr: "Couper")
    static let unmute = Phrase("Unmute", ru: "Включить", uk: "Увімкнути", fr: "Activer")
    static let camera = Phrase("Camera on", ru: "Камера включена", uk: "Камеру ввімкнено", fr: "Caméra active")
    static let cameraButton = Phrase("Camera", ru: "Камера", uk: "Камера", fr: "Caméra")
    static let soundButton = Phrase("Sound", ru: "Звук", uk: "Звук", fr: "Son")
    static let outputButton = Phrase("Output", ru: "Выход", uk: "Вихід", fr: "Sortie")
    static let hangUp = Phrase("End", ru: "Сбросить", uk: "Скинути", fr: "Raccrocher")
    static let callNeedsAccess = Phrase("Allow Accessibility to control calls", ru: "Разрешите Универсальный доступ, чтобы управлять звонками",
                                        uk: "Дозвольте Універсальний доступ, щоб керувати дзвінками", fr: "Autorisez l’accessibilité pour piloter les appels")
    @MainActor static func confirmIn(_ name: String) -> String {
        Phrase("Confirm in %@", ru: "Подтвердите в %@", uk: "Підтвердьте в %@", fr: "Confirmez dans %@")(name)
    }
    @MainActor static func finishIn(_ name: String) -> String {
        Phrase("End the call in %@", ru: "Завершите звонок в %@", uk: "Завершіть дзвінок у %@", fr: "Raccrochez dans %@")(name)
    }
    @MainActor static func cameraIn(_ name: String) -> String {
        Phrase("Switch the camera in %@", ru: "Переключите камеру в %@", uk: "Перемкніть камеру в %@", fr: "Changez la caméra dans %@")(name)
    }
}
