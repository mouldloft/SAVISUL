import AppKit
import Foundation
import Observation

/// Face Unlock. While the Mac is locked, waking it or touching a key starts a scan of a few seconds; when the camera sees
/// the owner's face, blinking if that is asked for, SAVISUL types the password into the lock screen. The faceprints and the
/// password stay in the login keychain, and the camera runs only during a scan.
@MainActor
@Observable
final class FaceUnlock {
    /// A scan is running at the lock screen.
    private(set) var scanning = false
    /// Faces and a password are stored, so the switch can work.
    private(set) var ready = FaceVault.isSetUp

    @ObservationIgnored private var running = false
    /// Waiting for the keychain, which after an update waits for the person to allow this build.
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var firstApply = true
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private var keepAwake: Timer?
    @ObservationIgnored private var policy = UnlockPolicy()
    /// The setup scan's prints, then the ones learned at unlocks since; `prints` is both.
    @ObservationIgnored private var enrolled: [[Float]] = []
    @ObservationIgnored private var learned: [[Float]] = []
    @ObservationIgnored private var prints: [[Float]] = []
    /// The last recognized scan's strong prints, learned from once that unlock goes through.
    @ObservationIgnored private var lastStrong: [[Float]] = []
    @ObservationIgnored private let camera = FaceCamera()
    @ObservationIgnored private let lockIsland = LockIsland()
    @ObservationIgnored private var match: FaceMatch?
    @ObservationIgnored private var scanStarted = Date.distantPast
    @ObservationIgnored private var scanEnded = Date.distantPast
    /// Between a recognized face and the password going in, while the lock screen's field comes up.
    @ObservationIgnored private var entering = false
    @ObservationIgnored private var typedAt: Date?
    @ObservationIgnored private var typedFailed = false

    /// One try at a time: no new scan while one runs or while a password is on its way or already in.
    private var busy: Bool { scanning || entering || typedAt != nil }

    /// How long one scan looks before giving up until the next touch.
    static let scanLength: TimeInterval = 6
    /// The scan right after the lock needs this many matching frames, about half a second of looking at the screen.
    static let steadyFrames = 7
    private static let passwordUsedKey = "suite.faceUnlockPasswordUsed"

    /// Follows the switch. Turning it on before there is a face to compare opens the setup; at launch it just stays off.
    func apply(_ enabled: Bool) {
        defer { firstApply = false }
        ready = FaceVault.isSetUp
        guard enabled else { return stop() }
        guard ready, FaceEngine.available else {
            if firstApply || !FaceEngine.available {
                Suite.shared.settings.faceUnlock = false
            } else {
                FaceSetup.shared.show()
            }
            return
        }
        start()
    }

    /// Stores a finished setup. Keychain calls can wait on a macOS prompt, so callers make them off the main thread
    /// and call `saved()` afterwards.
    nonisolated static func store(prints: [[Float]], password: String) -> Bool {
        guard let revision = FaceEngine.revision else { return false }
        return FaceVault.save(FaceVault.Secret(revision: revision, prints: prints, created: Date(), password: password))
    }

    /// Replaces only the password, after the Mac's password changed, keeping the face that is stored. Off the main thread.
    nonisolated static func replacePassword(_ password: String) -> Bool {
        guard case .success(var secret) = FaceVault.load(prompt: true) else { return false }
        secret.password = password
        return FaceVault.save(secret)
    }

    /// Turns Face Unlock on with what was just stored. Entering the password just now counts as using it.
    func saved() {
        markPasswordUsed()
        stop()
        ready = true
        Suite.shared.settings.faceUnlock = true
        start()
    }

    /// Forgets the face and the password and turns the switch off.
    func remove() {
        stop()
        ready = false
        Suite.shared.settings.faceUnlock = false
        DispatchQueue.global(qos: .utility).async { FaceVault.erase() }
    }

    // MARK: Running

    private func start() {
        guard !running else { return }
        running = true
        loading = true
        policy.lastPasswordUnlock = UserDefaults.standard.object(forKey: Self.passwordUsedKey) as? Date
        // After an update macOS asks once whether this build may read the keychain item, and waits for an answer,
        // so the read happens off the main thread. Asked now, while the person is here; at the lock screen nobody could.
        DispatchQueue.global(qos: .userInitiated).async {
            let result = FaceVault.load(prompt: true)
            DispatchQueue.main.async { MainActor.assumeIsolated { self.loaded(result) } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.running, self.loading else { return }
                FaceLog.write("waiting for keychain access")
                self.askForAccess(waiting: true)
            }
        }
    }

    /// Says that the keychain question needs an answer, with a way to ask again.
    private func askForAccess(waiting: Bool) {
        var retry: (@MainActor () -> Void)?
        if !waiting { retry = { Suite.shared.faceUnlock.retryAccess() } }
        Suite.shared.notify(IslandNotice(symbol: "faceid", tint: Palette.warning, title: FacePhrases.needsAccess.text,
                                         detail: FacePhrases.accessHow.text, style: .warning, duration: 10,
                                         actionTitle: waiting ? nil : FacePhrases.allow.text, action: retry))
    }

    /// Asks the keychain again, after the person said not now.
    func retryAccess() {
        stop()
        if Suite.shared.settings.faceUnlock { start() }
    }

    private func loaded(_ result: Result<FaceVault.Secret, FaceVault.Failure>) {
        loading = false
        guard running else { return }
        let secret: FaceVault.Secret
        switch result {
        case .success(let stored):
            secret = stored
        case .failure(.denied):
            // Stays on: one "Always Allow" and it works.
            FaceLog.write("keychain access not given to this build")
            stop()
            askForAccess(waiting: false)
            return
        case .failure:
            FaceLog.write("nothing usable in the keychain; set up again")
            stop()
            Suite.shared.settings.faceUnlock = false
            Suite.shared.notify(IslandNotice(symbol: "faceid", tint: Palette.warning, title: FacePhrases.setUpAgain.text, detail: nil,
                                             style: .warning, duration: 6, actionTitle: FacePhrases.scan.text,
                                             action: { FaceSetup.shared.show() }))
            return
        }
        guard !secret.prints.isEmpty, secret.revision == FaceEngine.revision else {
            // A macOS update replaced the recognizer, so the old prints no longer compare.
            FaceLog.write("the recognizer changed with macOS; a new scan is needed")
            stop()
            Suite.shared.settings.faceUnlock = false
            Suite.shared.notify(IslandNotice(symbol: "faceid", tint: Palette.warning, title: FacePhrases.needsScan.text, detail: nil,
                                             style: .warning, duration: 6, actionTitle: FacePhrases.scan.text,
                                             action: { FaceSetup.shared.show() }))
            return
        }
        enrolled = secret.prints
        learned = secret.learned ?? []
        prints = enrolled + learned
        FaceLog.write("ready: \(enrolled.count) views from the setup, \(learned.count) learned")
        // Set up now so the first scan at the lock screen only has to start the camera.
        camera.prepare()
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, "com.apple.screenIsLocked") { $0.locked() }
        observe(distributed, "com.apple.screenIsUnlocked") { $0.unlocked() }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification.rawValue) { face in
            face.policy.displayAsleep = true
            face.endScan(accepted: false)
            face.lockIsland.hide()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification.rawValue) { face in
            face.policy.displayAsleep = false
            face.woke()
        }
        if LockScreen.locked { locked() }
    }

    func stop() {
        guard running else { return }
        running = false
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        poll?.invalidate()
        poll = nil
        if scanning { endScan(accepted: false) }
        policy.lockedAt = nil
        enrolled = []
        learned = []
        prints = []
        lastStrong = []
        lockIsland.hide()
    }

    private func observe(_ center: NotificationCenter, _ name: String, _ handle: @escaping @MainActor (FaceUnlock) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handle(self)
            }
        }
        observers.append((center, token))
    }

    // MARK: The lock screen

    private func locked() {
        FaceLog.write("locked")
        policy.lockedAt = Date()
        policy.failures = 0
        entering = false
        typedAt = nil
        typedFailed = false
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        showResting()
        // Like Face ID on a lit iPhone: the lock screen starts looking by itself, a moment after the lock.
        guard Suite.shared.settings.faceUnlockRightAway else { return }
        let lockedAt = policy.lockedAt
        DispatchQueue.main.asyncAfter(deadline: .now() + UnlockPolicy.graceAfterLock + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.policy.lockedAt == lockedAt, !self.busy,
                      self.policy.shouldScan(activityAt: Date(), now: Date()) else { return }
                self.beginScan(steady: true)
            }
        }
    }

    /// The padlock under the camera, or a note that the password is needed this time.
    private func showResting() {
        guard policy.lockedAt != nil, !policy.displayAsleep else { return }
        lockIsland.show(policy.passwordNeeded(now: Date()) || typedFailed ? .needsPassword : .locked)
    }

    /// A key, a click or a touch after the last scan starts the next one.
    private func check() {
        guard !busy else { return }
        let now = Date()
        let touched = now.addingTimeInterval(-LockScreen.secondsSinceInput)
        guard touched > scanEnded else { return }
        if policy.passwordNeeded(now: now) {
            if lockIsland.phase != .needsPassword { showResting() }
            return
        }
        guard policy.shouldScan(activityAt: touched, now: now) else { return }
        beginScan()
    }

    /// Opening the lid or waking the display is the same as a touch: straight to the scan when one may run.
    private func woke() {
        guard policy.lockedAt != nil else { return }
        if !busy, policy.shouldScan(activityAt: Date(), now: Date()) {
            beginScan()
        } else {
            showResting()
        }
    }

    private func unlocked() {
        let byFace = typedAt.map { Date().timeIntervalSince($0) < 8 } ?? false
        let typingFailed = typedFailed
        poll?.invalidate()
        poll = nil
        if scanning { endScan(accepted: false) }
        policy.lockedAt = nil
        policy.failures = 0
        entering = false
        typedAt = nil
        typedFailed = false
        lockIsland.hide()
        if byFace {
            FaceLog.write("unlocked by face")
            Suite.shared.notify(IslandNotice(symbol: "faceid", tint: Palette.positive, title: FacePhrases.unlocked.text, detail: nil,
                                             style: .success, duration: 2.4))
            learn()
        } else {
            FaceLog.write("unlocked without the face")
            markPasswordUsed()
            if typingFailed { checkStoredPassword() }
        }
    }

    private func markPasswordUsed() {
        policy.lastPasswordUnlock = Date()
        UserDefaults.standard.set(policy.lastPasswordUnlock, forKey: Self.passwordUsedKey)
    }

    /// Keeps up with the face after an unlock by face: a new look joins the learned prints in the keychain.
    private func learn() {
        let updated = FaceLearning.learn(learned, from: lastStrong, enrolled: enrolled)
        lastStrong = []
        guard updated != learned else { return }
        learned = updated
        prints = enrolled + learned
        DispatchQueue.global(qos: .utility).async {
            guard case .success(var secret) = FaceVault.load(prompt: false) else { return }
            secret.learned = updated
            if FaceVault.save(secret) { FaceLog.write("learned a new look; \(updated.count) learned views") }
        }
    }

    // MARK: Scanning

    /// `steady` is the scan nobody asked for, right after the lock: it takes a steady look with open eyes, so someone getting
    /// up and glancing back as they leave doesn't unlock the Mac they just locked.
    private func beginScan(steady: Bool = false) {
        guard FaceCamera.allowed, !prints.isEmpty else { return }
        scanning = true
        match = FaceMatch(prints: prints, enrolled: enrolled.count, needsBlink: Suite.shared.settings.faceUnlockBlink,
                          needed: steady ? Self.steadyFrames : FaceMatch.framesNeeded)
        let started = Date()
        scanStarted = started
        lockIsland.show(.scanning)
        // macOS dims the lock screen after a few idle seconds; it stays lit while the camera looks.
        LockScreen.wake()
        keepAwake?.invalidate()
        keepAwake = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in LockScreen.wake() }
        camera.start(printEvery: 2) { [weak self] frame in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.take(frame) } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanLength) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.scanning, self.scanStarted == started else { return }
                self.endScan(accepted: false)
            }
        }
    }

    private func take(_ frame: FaceFrame?) {
        guard scanning, var current = match else { return }
        if let frame { current.add(frame) }
        match = current
        if current.accepted {
            endScan(accepted: true)
        } else if current.waitingForBlink, Date().timeIntervalSince(scanStarted) > 1 {
            lockIsland.askForBlink()
        }
    }

    private func endScan(accepted: Bool) {
        guard scanning else { return }
        scanning = false
        camera.stop()
        keepAwake?.invalidate()
        keepAwake = nil
        scanEnded = Date()
        let result = match
        match = nil
        if let result {
            let kind = result.needed > FaceMatch.framesNeeded ? "after the lock" : "after a touch"
            FaceLog.write("scan \(kind): \(result.seen) frames with a face (usually \(Int((result.typicalSize * 100).rounded()))% of the frame), "
                          + "\(result.matched) matched, \(result.unlike) unlike, \(result.notLooking) not looking, best \(String(format: "%.3f", result.best)), "
                          + "blink \(result.blink.blinked ? "yes" : "no")\(result.needsBlink ? "" : " (not asked)") → \(accepted ? "recognized" : "not recognized")")
        }
        if accepted {
            entering = true
            lastStrong = result?.strong ?? []
            lockIsland.show(.recognized)
            enterPassword()
            return
        }
        if result?.stranger == true { policy.failures += 1 }
        guard policy.lockedAt != nil, !policy.displayAsleep else { return }
        // A face that wasn't the owner's gets the shake; nobody in front of the camera just leaves the padlock.
        if (result?.seen ?? 0) > 0 {
            lockIsland.show(.failed)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.scanning, self.lockIsland.phase == .failed else { return }
                    self.showResting()
                }
            }
        } else {
            showResting()
        }
    }

    // MARK: The password

    /// Types the password once the lock screen's own field holds the keyboard, and never anywhere else.
    private func enterPassword(attempt: Int = 0) {
        guard entering, policy.lockedAt != nil else { return }
        guard LockScreen.passwordFieldIsUp else {
            // The lock screen is still waking; its field takes the keyboard within a moment.
            if attempt < 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    MainActor.assumeIsolated { self?.enterPassword(attempt: attempt + 1) }
                }
            } else {
                entering = false
                showResting()
                FaceLog.write("not typed: the lock screen's password field never took the keyboard (secure input: \(LockScreen.keyboardOwner))")
            }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = FaceVault.load(prompt: false)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard case .success(let secret) = result else {
                        self.entering = false
                        self.showResting()
                        FaceLog.write("not typed: the keychain didn't give the password without asking")
                        return
                    }
                    self.type(secret.password)
                }
            }
        }
    }

    private func type(_ password: String) {
        defer { entering = false }
        guard entering, policy.lockedAt != nil, LockScreen.passwordFieldIsUp else { return }
        let typed = Date()
        typedAt = typed
        let owner = LockScreen.keyboardOwner
        guard LockScreen.type(password) else {
            // The Mac unlocked another way while the keys were going in; whatever is left was never sent.
            typedAt = nil
            FaceLog.write("stopped typing: the screen was no longer locked")
            return
        }
        FaceLog.write("typed the password (secure input: \(owner))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.policy.lockedAt != nil, self.typedAt == typed else { return }
                // Still locked after the password went in: no more typing until a person unlocks.
                self.typedFailed = true
                self.showResting()
                FaceLog.write("typed, but the Mac stayed locked")
            }
        }
    }

    /// After typing didn't unlock and the person did: if the stored password is no longer the Mac's, turn off and say so.
    private func checkStoredPassword() {
        DispatchQueue.global(qos: .utility).async {
            // Only a password that was read and rejected counts; a keychain that didn't answer proves nothing.
            guard case .success(let secret) = FaceVault.load(prompt: false) else { return }
            let valid = FaceVault.verify(secret.password)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard !valid else { return }
                    FaceLog.write("the stored password is no longer the Mac's; Face Unlock turned off")
                    Suite.shared.settings.faceUnlock = false
                    Suite.shared.notify(IslandNotice(symbol: "faceid", tint: Palette.warning, title: FacePhrases.turnedOff.text,
                                                     detail: FacePhrases.passwordChanged.text, style: .warning, duration: 8,
                                                     actionTitle: FacePhrases.enterPassword.text,
                                                     action: { FaceSetup.shared.show(passwordOnly: true) }))
                }
            }
        }
    }
}

/// When a scan may start at the lock screen. Like Face ID: not from the touch that locked the Mac, not after five
/// strangers in a row, and not once the password hasn't been used for six and a half days.
struct UnlockPolicy {
    /// No scan in the first second after the lock.
    static let graceAfterLock: TimeInterval = 1
    /// Keys and clicks this close to the lock are the gesture that locked it; later ones are new touches, even within
    /// the grace second, and start a scan as soon as it is over.
    static let lockGesture: TimeInterval = 0.5
    static let passwordEvery: TimeInterval = 156 * 3600
    static let strangersBeforePassword = 5

    var lockedAt: Date?
    var lastPasswordUnlock: Date?
    var failures = 0
    var displayAsleep = false

    func shouldScan(activityAt: Date, now: Date) -> Bool {
        guard let lockedAt, !displayAsleep, !passwordNeeded(now: now),
              activityAt >= lockedAt.addingTimeInterval(Self.lockGesture),
              now >= lockedAt.addingTimeInterval(Self.graceAfterLock)
        else { return false }
        return true
    }

    /// Five strangers in a row, or a week without the password: only the password opens the Mac now.
    func passwordNeeded(now: Date) -> Bool {
        guard failures < Self.strangersBeforePassword, let lastPasswordUnlock else { return true }
        return now.timeIntervalSince(lastPasswordUnlock) >= Self.passwordEvery
    }
}

/// What Face Unlock did, for when it doesn't: ~/Library/Logs/SAVISUL/face-unlock.txt, the last 300 lines.
/// Scores and steps only; never a password or a faceprint.
enum FaceLog {
    private static let queue = DispatchQueue(label: "com.savisul.face-log", qos: .utility)

    static func write(_ line: String) {
        let stamp = Date()
        queue.async {
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SAVISUL", isDirectory: true)
            let file = folder.appendingPathComponent("face-unlock.txt")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var lines = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            lines.append("\(stamp) \(line)")
            try? lines.suffix(300).joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        }
    }
}

enum FacePhrases {
    static let title = Phrase("Face Unlock", ru: "Вход по лицу", uk: "Вхід за обличчям", fr: "Déverrouillage facial")
    static let unlocked = Phrase("Unlocked with your face", ru: "Открыто по лицу", uk: "Відкрито за обличчям", fr: "Déverrouillé par votre visage")
    static let needsScan = Phrase("Face Unlock needs a new scan after the macOS update", ru: "После обновления macOS нужно заново отсканировать лицо",
                                  uk: "Після оновлення macOS треба заново відсканувати обличчя", fr: "Après la mise à jour de macOS, refaites le scan du visage")
    static let scan = Phrase("Scan", ru: "Сканировать", uk: "Сканувати", fr: "Scanner")
    static let turnedOff = Phrase("Face Unlock is off", ru: "Вход по лицу выключен", uk: "Вхід за обличчям вимкнено", fr: "Déverrouillage facial désactivé")
    static let passwordChanged = Phrase("Your Mac password changed", ru: "Пароль Mac изменился", uk: "Пароль Mac змінився", fr: "Le mot de passe du Mac a changé")
    static let enterPassword = Phrase("Enter it", ru: "Ввести", uk: "Ввести", fr: "Le saisir")
    static let enterPasswordHint = Phrase("Enter password", ru: "Введите пароль", uk: "Введіть пароль", fr: "Mot de passe")
    static let needsAccess = Phrase("Face Unlock is waiting for permission", ru: "Вход по лицу ждёт разрешения", uk: "Вхід за обличчям чекає на дозвіл",
                                    fr: "Le déverrouillage facial attend une autorisation")
    static let accessHow = Phrase("Enter your Mac password and choose Always Allow", ru: "Введите пароль Mac и нажмите «Всегда разрешать»",
                                  uk: "Введіть пароль Mac і натисніть «Завжди дозволяти»", fr: "Saisissez le mot de passe du Mac et choisissez Toujours autoriser")
    static let allow = Phrase("Allow", ru: "Разрешить", uk: "Дозволити", fr: "Autoriser")
    static let setUpAgain = Phrase("Scan your face again", ru: "Отсканируйте лицо заново", uk: "Відскануйте обличчя знову", fr: "Refaites le scan du visage")
    static let blink = Phrase("Blink", ru: "Моргните", uk: "Кліпніть", fr: "Clignez des yeux")
}
