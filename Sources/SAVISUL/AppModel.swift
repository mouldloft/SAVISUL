import AppKit
import ApplicationServices
import Observation

enum Pane: String, CaseIterable, Identifiable {
    case energy, sound, system, work, tools, features, settings, automations

    static let main: [Pane] = [.energy, .sound, .system, .work, .tools, .features]

    var id: String { rawValue }

    var title: Copy {
        switch self {
        case .energy: .tabEnergy
        case .sound: .tabSound
        case .system: .tabSystem
        case .work: .tabWork
        case .tools: .tabTools
        case .features: .tabFeatures
        case .settings: .tabSettings
        case .automations: .tabAutomations
        }
    }

    var symbol: String {
        switch self {
        case .energy: "bolt"
        case .sound: "speaker.wave.2"
        case .system: "cpu"
        case .work: "chevron.left.forwardslash.chevron.right"
        case .tools: "square.grid.2x2"
        case .features: "wand.and.stars"
        case .settings: "gearshape"
        case .automations: "point.3.connected.trianglepath.dotted"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .energy: "bolt.fill"
        case .sound: "speaker.wave.2.fill"
        case .system: "cpu.fill"
        case .work: "chevron.left.forwardslash.chevron.right"
        case .tools: "square.grid.2x2.fill"
        case .features: "wand.and.stars.inverse"
        case .settings: "gearshape.fill"
        case .automations: "point.3.filled.connected.trianglepath.dotted"
        }
    }
}

enum WorkRange: String, Hashable {
    case today, week
}

@MainActor
@Observable
final class AppModel {
    var language: Language
    var pane: Pane
    var workRange: WorkRange = .today
    var menuOpen = false
    /// Bumped by QA renders to scroll the page down to its last card.
    var scrollToEnd = 0
    var toast: Toast?
    var pinned: Bool
    var showInDock: Bool
    var statusVisible = true
    var hotKeyReady = true
    var panelVisible = false
    var snapshot = SystemSnapshot()
    var cpuHistory: [Double] = []
    var busiest: [BusyApp] = []

    let power = PowerService()
    let audio = AudioService()
    let activity: ActivityTracker
    let capture = CaptureService()
    let utilities = UtilityStore()
    let alerts = AlertCenter()
    let fans = FanControl()
    let permissions = PermissionCenter()
    let browserLink = BrowserLink()

    @ObservationIgnored let preview: Bool
    @ObservationIgnored let sampler = SystemSampler()
    @ObservationIgnored var holdOpen = 0
    @ObservationIgnored var onHide: (() -> Void)?
    @ObservationIgnored var onShow: (() -> Void)?
    @ObservationIgnored var onChromeChange: (() -> Void)?
    @ObservationIgnored var onLanguageChange: (() -> Void)?
    @ObservationIgnored var onDockPreferenceChange: (() -> Void)?
    @ObservationIgnored private var latest = SystemSnapshot()
    @ObservationIgnored private var history: [Double] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var formatters: [String: NumberFormatter] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard

    init(preview: Bool = false) {
        self.preview = preview
        let defaults = UserDefaults.standard
        language = Language(rawValue: defaults.string(forKey: "language") ?? "") ?? .en
        pane = Pane(rawValue: defaults.string(forKey: "pane") ?? "") ?? .energy
        pinned = defaults.bool(forKey: "pinned")
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        activity = ActivityTracker(persist: !preview)
        Suite.shared.language = language
        permissions.assumeGranted = preview
    }

    func start() {
        power.onStateChange = { [weak self] in self?.onChromeChange?() }
        capture.onChange = { [weak self] in self?.onChromeChange?() }
        permissions.onAccessibilityChange = { [weak self] granted in self?.accessibilityChanged(granted) }
        sampler.onSnapshot = { [weak self] snapshot in self?.receive(snapshot) }
        sampler.onProcesses = { [weak self] rows in
            guard let self, self.busiest != rows else { return }
            self.busiest = rows
        }
        power.start()
        audio.start()
        permissions.refresh()
        alerts.start()
        if preview {
            activity.seedPreview()
        } else {
            activity.start()
            if AXIsProcessTrusted() { activity.enableTyping() }
        }
        sampler.start()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if !preview { Suite.shared.start(app: self) }
    }

    func shutdown() {
        fans.shutdown()
        activity.save(synchronously: true)
        if capture.isRecording { capture.stopRecording() }
        Suite.shared.shutdown()
    }

    private func tick() {
        if !preview { activity.tick(visible: panelVisible && pane == .work) }
        if panelVisible && pane == .sound { audio.reload() }
    }

    /// The newest sample, even while the panel is hidden and `snapshot` is not being published.
    var currentSnapshot: SystemSnapshot { latest }

    private func receive(_ snapshot: SystemSnapshot) {
        latest = snapshot
        if snapshot.cpuReady {
            history.append(snapshot.cpu)
            if history.count > 60 { history.removeFirst(history.count - 60) }
        }
        power.update(from: snapshot)
        alerts.evaluate(snapshot, lidAwake: power.lidAwake, model: self)
        if !preview { fans.update(fans: snapshot.fans, temperature: snapshot.temperature) }
        if panelVisible { publish() }
    }

    private func publish() {
        if snapshot != latest { snapshot = latest }
        if cpuHistory != history { cpuHistory = history }
    }

    // MARK: Panel lifecycle

    func panelWillShow() {
        panelVisible = true
        publish()
        permissions.refresh()
        permissions.startPolling()
        audio.reload(force: true)
        activity.publish()
        sampler.refreshPower()
        sampler.setWantsProcesses(pane == .system)
        utilities.refreshHiddenFiles()
    }

    func panelDidHide() {
        panelVisible = false
        menuOpen = false
        permissions.stopPolling()
        sampler.setWantsProcesses(false)
    }

    func select(_ pane: Pane) {
        menuOpen = false
        guard self.pane != pane else { return }
        self.pane = pane
        defaults.set(pane.rawValue, forKey: "pane")
        sampler.setWantsProcesses(panelVisible && pane == .system)
        if pane == .sound { audio.reload(force: true) }
        if pane == .work { activity.publish() }
        permissions.refresh()
    }

    func toggleMenu() { menuOpen.toggle() }

    func closeMenu() { menuOpen = false }

    func togglePinned() {
        pinned.toggle()
        defaults.set(pinned, forKey: "pinned")
    }

    func setShowInDock(_ show: Bool) {
        showInDock = show
        defaults.set(show, forKey: "showInDock")
        onDockPreferenceChange?()
    }

    func setLanguage(_ language: Language) {
        guard language != self.language else { return }
        self.language = language
        Suite.shared.language = language
        defaults.set(language.rawValue, forKey: "language")
        onLanguageChange?()
    }

    func showToast(_ toast: Toast) {
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Actions

    func toggleLid() {
        power.toggleLid(promptOn: text(.adminPromptOn), promptOff: text(.adminPromptOff))
    }

    func confirmLidOnBattery() {
        power.confirmOnBattery(prompt: text(.adminPromptOn))
    }

    func shoot(_ mode: CaptureMode) {
        menuOpen = false
        permissions.confirmScreen { [weak self] granted in
            guard let self else { return }
            if granted { self.takeShot(mode) } else { self.askForScreenRecording() }
        }
    }

    private func takeShot(_ mode: CaptureMode) {
        let reopen = pinned
        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            MainActor.assumeIsolated {
                self?.capture.shoot(mode) { outcome in
                    guard let self else { return }
                    switch outcome {
                    case .saved:
                        self.showToast(Toast(symbol: "checkmark.circle.fill", text: self.text(.capSaved), tone: .success))
                    case .failed:
                        self.showToast(Toast(symbol: "exclamationmark.triangle.fill", text: self.text(.captureFailed), tone: .warning))
                    case .cancelled:
                        break
                    }
                    if reopen { self.onShow?() }
                }
            }
        }
    }

    func toggleRecording() {
        menuOpen = false
        if capture.isRecording {
            capture.stopRecording()
            return
        }
        permissions.confirmScreen { [weak self] granted in
            guard let self else { return }
            if granted { self.beginRecording() } else { self.askForScreenRecording() }
        }
    }

    private func beginRecording() {
        onHide?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                self?.capture.startRecording { outcome in
                    guard let self else { return }
                    switch outcome {
                    case .saved:
                        self.showToast(Toast(symbol: "checkmark.circle.fill", text: self.text(.videoSaved), tone: .success))
                        self.onShow?()
                    case .failed:
                        self.showToast(Toast(symbol: "exclamationmark.triangle.fill", text: self.text(.recordFailed), tone: .warning))
                        self.onShow?()
                    case .cancelled:
                        break
                    }
                }
            }
        }
    }

    func openCaptureToolbar() {
        menuOpen = false
        onHide?()
        capture.openToolbar()
    }

    private func askForScreenRecording() {
        select(.tools)
        permissions.requestScreenRecording()
        showToast(Toast(symbol: "lock.fill", text: text(.screenBody), tone: .warning))
    }

    func toggleAlerts() {
        if alerts.enabled {
            alerts.enabled = false
            return
        }
        permissions.requestNotifications { [weak self] granted in
            guard let self else { return }
            self.alerts.enabled = granted
            if !granted {
                self.showToast(Toast(symbol: "bell.slash.fill", text: self.text(.notifOff), tone: .warning))
            }
        }
    }

    func sendTestAlert() {
        guard permissions.notificationsGranted else {
            permissions.requestNotifications { [weak self] granted in
                guard let self, granted else { return }
                self.alerts.sendTest(body: self.text(.nTest))
            }
            return
        }
        alerts.sendTest(body: text(.nTest))
    }

    func requestTyping() {
        permissions.requestAccessibility()
    }

    private func accessibilityChanged(_ granted: Bool) {
        guard granted, !preview else { return }
        Suite.shared.accessibilityGranted()
        activity.enableTyping()
        if activity.typingActive {
            showToast(Toast(symbol: "keyboard", text: text(.typingOn), tone: .success))
        }
    }

    func run(_ builtin: BuiltinUtility) {
        if builtin == .activity || builtin == .terminal || builtin == .settings || builtin == .disk || builtin == .displayOff {
            onHide?()
        }
        utilities.run(builtin) { [weak self] outcome in self?.report(outcome) }
    }

    func launch(_ item: UtilityItem) {
        if !item.isCommand { onHide?() }
        utilities.launch(item) { [weak self] outcome in self?.report(outcome) }
    }

    func chooseUtilityApp() {
        holdOpen += 1
        utilities.chooseApp()
        holdOpen -= 1
    }

    private func report(_ outcome: UtilityOutcome) {
        switch outcome {
        case .done(let name):
            showToast(Toast(symbol: "checkmark.circle.fill", text: format(.runDone, name), tone: .success))
        case .failed(let name, let detail):
            showToast(Toast(symbol: "xmark.octagon.fill", text: format(.runFailed, name, detail), tone: .danger))
        case .couldNotOpen(let name):
            showToast(Toast(symbol: "exclamationmark.triangle.fill", text: format(.openFailed, name), tone: .warning))
        case .ipCopied(let address):
            showToast(Toast(symbol: "network", text: format(.ipCopied, address), tone: .success))
        case .noAddress:
            showToast(Toast(symbol: "wifi.slash", text: text(.ipNone), tone: .warning))
        case .hiddenFiles(let visible):
            showToast(Toast(symbol: visible ? "eye" : "eye.slash", text: text(visible ? .hiddenShown : .hiddenHidden)))
        case .silent:
            break
        }
    }

    // MARK: Text

    func text(_ key: Copy) -> String { L10n.text(key, language) }

    func format(_ key: Copy, _ arguments: String...) -> String { L10n.format(key, language, arguments) }

    func duration(_ seconds: Double) -> String { L10n.duration(seconds, language) }

    func subtitle(for pane: Pane) -> String {
        switch pane {
        case .energy:
            return power.lidAwake ? text(.energyOn) : text(.energyOff)
        case .sound:
            guard let device = audio.currentOutput else { return text(.noDevices) }
            if device.muted == true { return "\(device.name) · \(text(.muted))" }
            if let volume = device.volume { return "\(device.name) · \(finePercent(volume * 100))" }
            return device.name
        case .system:
            let cpu = snapshot.cpuReady ? percent(snapshot.cpu) : "—"
            return format(.systemSubtitle, cpu, percent(snapshot.memoryFraction * 100))
        case .work:
            let seconds = activity.seconds(workRange, .editor)
            return format(workRange == .today ? .workSubtitleToday : .workSubtitleWeek, duration(seconds))
        case .tools:
            return text(.toolsSubtitle)
        case .features:
            let tally = FeatureTally(Suite.shared.settings)
            return format(.featuresSubtitle, integer(tally.on), integer(tally.total))
        case .settings:
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            return format(.settingsSubtitle, version)
        case .automations:
            return AutomationsPhrases.subtitle(Suite.shared.automations.items)
        }
    }

    // MARK: Numbers

    private func formatter(_ digits: Int) -> NumberFormatter {
        let key = "\(language.rawValue)-\(digits)"
        if let cached = formatters[key] { return cached }
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatters[key] = formatter
        return formatter
    }

    func integer(_ value: Int) -> String {
        formatter(0).string(from: NSNumber(value: value)) ?? "\(value)"
    }

    func decimal(_ value: Double, digits: Int) -> String {
        formatter(digits).string(from: NSNumber(value: value)) ?? String(format: "%.\(digits)f", value)
    }

    func percent(_ value: Double) -> String {
        let number = integer(Int(value.rounded()))
        return language == .fr ? "\(number)\u{202F}%" : "\(number)%"
    }

    /// Keeps the tenth only when there is one, matching the 0.1 % volume steps.
    func finePercent(_ value: Double) -> String {
        let tenths = (value * 10).rounded()
        guard tenths.truncatingRemainder(dividingBy: 10) != 0 else { return percent(value) }
        let number = decimal(tenths / 10, digits: 1)
        return language == .fr ? "\(number)\u{202F}%" : "\(number)%"
    }

    func gigabytes(_ bytes: Double) -> String {
        let unit = switch language {
        case .en: "GB"
        case .fr: "Go"
        case .ru, .uk: "ГБ"
        }
        return "\(decimal(bytes / 1_073_741_824, digits: 1)) \(unit)"
    }

    func celsius(_ value: Double) -> String {
        "\(Int(value.rounded()))°C"
    }
}
