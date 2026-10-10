import AppKit
@preconcurrency import AVFoundation
import Observation
import SwiftUI

/// The Face Unlock setup window: what it does and what it can't promise, the face scan, then the Mac password.
@MainActor
final class FaceSetup: NSObject, NSWindowDelegate {
    static let shared = FaceSetup()

    private var window: NSWindow?
    private var model: FaceSetupModel?

    /// `passwordOnly` asks just for the password, after the Mac's password changed.
    func show(passwordOnly: Bool = false) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = FaceSetupModel(passwordOnly: passwordOnly) { [weak self] in self?.window?.close() }
        let size = NSSize(width: 440, height: 600)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = FacePhrases.title.text
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        let hosting = NSHostingView(rootView: FaceSetupView(model: model).environment(\.colorScheme, .dark))
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]
        glass.addSubview(hosting)
        window.contentView = glass
        window.center()
        window.delegate = self
        self.window = window
        self.model = model
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.stopCamera()
        // Closed before the end: a switch turned on to start the setup goes back off.
        if !FaceVault.isSetUp { Suite.shared.settings.faceUnlock = false }
        window = nil
        model = nil
    }
}

@MainActor
@Observable
final class FaceSetupModel {
    enum Step { case intro, scanning, password, done }
    enum Hint { case look, closer, move, onlyYou, farther }

    var step: Step
    var hint: Hint = .look
    var progress: Double = 0
    var password = ""
    var checking = false
    var wrongPassword = false
    var failed = false
    var cameraDenied = false
    let passwordOnly: Bool
    let close: () -> Void

    @ObservationIgnored let camera = FaceCamera()
    @ObservationIgnored private var enrollment = FaceEnrollment()
    @ObservationIgnored private var scanStarted = Date()
    /// When the close views were done and the scan started asking for the face from farther back.
    @ObservationIgnored private var farStarted: Date?

    init(passwordOnly: Bool, close: @escaping () -> Void) {
        self.passwordOnly = passwordOnly
        self.close = close
        step = passwordOnly ? .password : .intro
    }

    func begin() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startScan()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if granted { self.startScan() } else { self.cameraDenied = true }
                    }
                }
            }
        default:
            cameraDenied = true
        }
    }

    private func startScan() {
        enrollment = FaceEnrollment()
        progress = 0
        hint = .look
        scanStarted = Date()
        farStarted = nil
        step = .scanning
        camera.start(printEvery: 2) { [weak self] frame in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.take(frame) } }
        }
    }

    func stopCamera() { camera.stop() }

    private func take(_ frame: FaceFrame?) {
        guard step == .scanning else { return }
        guard let frame, frame.eyes != nil else {
            hint = .look
            return
        }
        let wantsFar = enrollment.nearDone
        if wantsFar {
            if farStarted == nil { farStarted = Date() }
            // Across the desk: a face a twentieth to a seventh of the frame wide.
            guard frame.size <= 0.15 else {
                hint = .farther
                return
            }
        } else {
            guard frame.size >= 0.2 else {
                hint = .closer
                return
            }
        }
        if let print = frame.print {
            let first = enrollment.prints.first
            if !enrollment.add(print, far: wantsFar), let first, FaceMath.similarity(print, first) < (wantsFar ? 0.75 : 0.8) {
                hint = .onlyYou
            } else {
                hint = wantsFar ? .farther : .move
            }
        }
        progress = enrollment.progress
        // Someone who barely moves, or has no room to lean back, still finishes, with fewer views.
        let farTooLong = farStarted.map { Date().timeIntervalSince($0) > 15 } ?? false
        if enrollment.complete || farTooLong || (Date().timeIntervalSince(scanStarted) > 30 && enrollment.prints.count >= 6) {
            camera.stop()
            progress = 1
            step = .password
        }
    }

    func submitPassword() {
        let password = password
        guard !password.isEmpty, !checking else { return }
        checking = true
        wrongPassword = false
        let passwordOnly = passwordOnly
        let prints = enrollment.prints
        // Checking the password and writing the keychain can both wait, the keychain on a macOS prompt.
        DispatchQueue.global(qos: .userInitiated).async {
            let valid = FaceVault.verify(password)
            let saved = valid && (passwordOnly ? FaceUnlock.replacePassword(password) : FaceUnlock.store(prints: prints, password: password))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.checking = false
                    self.password = ""
                    guard valid else {
                        self.wrongPassword = true
                        return
                    }
                    guard saved else {
                        self.failed = true
                        return
                    }
                    Suite.shared.faceUnlock.saved()
                    self.step = .done
                }
            }
        }
    }

    func openCameraSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }
}

struct FaceSetupView: View {
    @Bindable var model: FaceSetupModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 34)
            switch model.step {
            case .intro: intro
            case .scanning: scanning
            case .password: passwordStep
            case .done: done
            }
            Spacer(minLength: 24)
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 26)
        .frame(width: 440, height: 600)
        .animation(.panelSpring, value: model.step)
    }

    private var intro: some View {
        VStack(spacing: 18) {
            Image(systemName: "faceid")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Palette.accent)
                .symbolEffect(.pulse, options: .repeating)
                .padding(.bottom, 4)
            Text(FacePhrases.title.text).font(.system(size: 24, weight: .bold)).foregroundStyle(Palette.ink)
            Text(SetupPhrases.introBody.text).font(.system(size: 13.5)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Note(symbol: "exclamationmark.shield.fill", tint: Palette.warning, text: SetupPhrases.introSafety.text)
            Note(symbol: "lock.fill", tint: Palette.positive, text: SetupPhrases.introPrivacy.text)
            Spacer(minLength: 8)
            if !FaceEngine.available {
                Text(SetupPhrases.noRecognizer.text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.danger).multilineTextAlignment(.center)
                SetupButton(title: SetupPhrases.close.text, prominent: false, action: model.close)
            } else if model.cameraDenied {
                Text(SetupPhrases.noCamera.text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.warning).multilineTextAlignment(.center)
                SetupButton(title: SetupPhrases.openSettings.text, prominent: true, action: model.openCameraSettings)
            } else {
                SetupButton(title: SetupPhrases.start.text, prominent: true, action: model.begin)
            }
            Button(SetupPhrases.cancel.text, action: model.close).buttonStyle(.plain).font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.secondary)
        }
    }

    private var scanning: some View {
        VStack(spacing: 26) {
            ZStack {
                ScanRing(progress: model.progress)
                CameraPreview(session: model.camera.session)
                    .frame(width: 236, height: 236)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .frame(width: 300, height: 300)
            Text(hintText).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: model.hint)
            Text(SetupPhrases.scanBody.text).font(.system(size: 12.5)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(SetupPhrases.cancel.text, action: model.close).buttonStyle(.plain).font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.secondary)
        }
    }

    private var hintText: String {
        switch model.hint {
        case .look: SetupPhrases.look.text
        case .closer: SetupPhrases.closer.text
        case .move: SetupPhrases.move.text
        case .onlyYou: SetupPhrases.onlyYou.text
        case .farther: SetupPhrases.farther.text
        }
    }

    private var passwordStep: some View {
        VStack(spacing: 18) {
            Image(systemName: model.passwordOnly ? "key.fill" : "checkmark.circle.fill")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(model.passwordOnly ? Palette.accent : Palette.positive)
                .symbolEffect(.bounce, value: model.step)
            Text(model.passwordOnly ? SetupPhrases.passwordTitle.text : SetupPhrases.scanned.text)
                .font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.ink)
            Text(SetupPhrases.passwordBody.text).font(.system(size: 13)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            SecureField(SetupPhrases.passwordPrompt.text, text: $model.password)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.3)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(model.wrongPassword ? Palette.danger.opacity(0.8) : Color.white.opacity(0.14), lineWidth: 0.8))
                .onSubmit(model.submitPassword)
                .disabled(model.checking)
            if model.wrongPassword {
                Text(SetupPhrases.wrongPassword.text).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.danger)
            } else if model.failed {
                Text(SetupPhrases.couldNotSave.text).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.danger)
            }
            Spacer(minLength: 8)
            SetupButton(title: SetupPhrases.continueTitle.text, prominent: true, busy: model.checking, action: model.submitPassword)
                .disabled(model.password.isEmpty)
            Button(SetupPhrases.cancel.text, action: model.close).buttonStyle(.plain).font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.secondary)
        }
    }

    private var done: some View {
        VStack(spacing: 18) {
            Image(systemName: "faceid")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Palette.positive)
                .symbolEffect(.bounce, value: model.step)
            Text(SetupPhrases.doneTitle.text).font(.system(size: 24, weight: .bold)).foregroundStyle(Palette.ink)
            Text(SetupPhrases.doneBody.text).font(.system(size: 13.5)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            KeyCaps(keys: ["⌃", "⌘", "Q"], size: 26)
            Spacer(minLength: 8)
            SetupButton(title: SetupPhrases.done.text, prominent: true, action: model.close)
        }
    }
}

/// Under the Face Unlock switches in Features: whether a face is saved, a new scan, and a way to forget it.
struct FaceUnlockRow: View {
    let face: FaceUnlock

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: face.ready ? "checkmark.seal.fill" : "faceid")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(face.ready ? Palette.positive : Palette.secondary)
            Text(face.ready ? SetupPhrases.saved.text : SetupPhrases.notSaved.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            PillButton(title: face.ready ? SetupPhrases.scanAgain.text : SetupPhrases.setUp.text, symbol: "faceid") { FaceSetup.shared.show() }
            if face.ready {
                PillButton(title: SetupPhrases.remove.text, tint: Palette.danger) { face.remove() }
            }
        }
        .padding(.vertical, 7)
    }
}

/// Sixty ticks around the camera that light up as the scan sees the face from more sides.
private struct ScanRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            ForEach(0..<60, id: \.self) { index in
                Capsule()
                    .fill(Double(index) / 60 < progress ? Palette.positive : Color.white.opacity(0.16))
                    .frame(width: 3, height: 15)
                    .offset(y: -138)
                    .rotationEffect(.degrees(Double(index) * 6))
            }
        }
        .animation(.easeOut(duration: 0.3), value: progress)
    }
}

private struct Note: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint).frame(width: 18)
            Text(text).font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

private struct SetupButton: View {
    let title: String
    let prominent: Bool
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy {
                    Spinner(size: 15, color: prominent ? Palette.onLight : Palette.ink)
                } else {
                    Text(title).font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(prominent ? Palette.onLight : Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Capsule().fill(prominent ? Palette.ink : Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .keyboardShortcut(prominent ? .defaultAction : nil)
    }
}

enum SetupPhrases {
    static let introBody = Phrase(
        "Look at your Mac to unlock it. SAVISUL learns your face once. Then, when the screen is locked and you wake the Mac, the camera checks that it's you and types your password for you.",
        ru: "Посмотрите на Mac — и он откроется. SAVISUL один раз запоминает ваше лицо. Потом, когда экран заблокирован и вы будите Mac, камера проверяет, что это вы, и сама вводит пароль.",
        uk: "Подивіться на Mac — і він відкриється. SAVISUL один раз запамʼятовує ваше обличчя. Потім, коли екран заблоковано й ви будите Mac, камера перевіряє, що це ви, і сама вводить пароль.",
        fr: "Regardez votre Mac pour le déverrouiller. SAVISUL apprend votre visage une fois. Ensuite, quand l’écran est verrouillé et que vous réveillez le Mac, la caméra vérifie que c’est vous et saisit votre mot de passe.")
    static let introSafety = Phrase(
        "A convenience, not Face ID: the camera sees in 2D, so a good video of you might get through. Your password is still needed after a restart and at least once a week.",
        ru: "Это удобство, а не Face ID: камера видит плоско, поэтому хорошее видео с вами может пройти. После перезагрузки и минимум раз в неделю пароль всё равно понадобится.",
        uk: "Це зручність, а не Face ID: камера бачить пласко, тож добре відео з вами може пройти. Після перезавантаження й щонайменше раз на тиждень пароль усе одно знадобиться.",
        fr: "Un confort, pas Face ID : la caméra voit en 2D, une bonne vidéo de vous pourrait passer. Le mot de passe reste nécessaire après un redémarrage et au moins une fois par semaine.")
    static let introPrivacy = Phrase(
        "Your face data and password stay in the keychain on this Mac and never leave it. The camera turns on only while it looks for you.",
        ru: "Данные лица и пароль хранятся в связке ключей на этом Mac и никуда не уходят. Камера включается только на время проверки.",
        uk: "Дані обличчя й пароль зберігаються у звʼязці ключів на цьому Mac і нікуди не йдуть. Камера вмикається лише на час перевірки.",
        fr: "Les données du visage et le mot de passe restent dans le trousseau de ce Mac. La caméra ne s’allume que pendant qu’elle vous cherche.")
    static let start = Phrase("Scan my face", ru: "Сканировать лицо", uk: "Сканувати обличчя", fr: "Scanner mon visage")
    static let cancel = Phrase("Cancel", ru: "Отмена", uk: "Скасувати", fr: "Annuler")
    static let close = Phrase("Close", ru: "Закрыть", uk: "Закрити", fr: "Fermer")
    static let look = Phrase("Look at the camera", ru: "Посмотрите в камеру", uk: "Подивіться в камеру", fr: "Regardez la caméra")
    static let closer = Phrase("Come a little closer", ru: "Подвиньтесь чуть ближе", uk: "Підсуньтеся трохи ближче", fr: "Approchez-vous un peu")
    static let move = Phrase("Slowly move your head in a circle", ru: "Медленно поводите головой по кругу", uk: "Повільно поведіть головою по колу",
                             fr: "Tournez lentement la tête en cercle")
    static let farther = Phrase("Now lean back, farther from the Mac", ru: "Теперь отодвиньтесь подальше от Mac", uk: "Тепер відсуньтеся далі від Mac",
                                fr: "Reculez maintenant, plus loin du Mac")
    static let onlyYou = Phrase("Only you in front of the camera", ru: "Перед камерой должны быть только вы", uk: "Перед камерою маєте бути лише ви",
                                fr: "Vous seul devant la caméra")
    static let scanBody = Phrase("Keep your face inside the circle until the ring fills up.", ru: "Держите лицо в круге, пока кольцо не заполнится.",
                                 uk: "Тримайте обличчя в колі, доки кільце не заповниться.", fr: "Gardez votre visage dans le cercle jusqu’à ce que l’anneau soit plein.")
    static let scanned = Phrase("Face scanned", ru: "Лицо отсканировано", uk: "Обличчя відскановано", fr: "Visage scanné")
    static let passwordTitle = Phrase("Your Mac password", ru: "Пароль от Mac", uk: "Пароль від Mac", fr: "Le mot de passe du Mac")
    static let passwordBody = Phrase(
        "Enter your Mac password. SAVISUL types it at the lock screen when it recognizes you. macOS checks it now; it is kept in your keychain.",
        ru: "Введите пароль от Mac. SAVISUL вводит его на экране блокировки, когда узнаёт вас. Сейчас его проверит macOS, а храниться он будет в связке ключей.",
        uk: "Введіть пароль від Mac. SAVISUL вводить його на екрані блокування, коли впізнає вас. Зараз його перевірить macOS, а зберігатиметься він у звʼязці ключів.",
        fr: "Saisissez le mot de passe du Mac. SAVISUL le tape à l’écran verrouillé quand il vous reconnaît. macOS le vérifie maintenant ; il reste dans votre trousseau.")
    static let passwordPrompt = Phrase("Password", ru: "Пароль", uk: "Пароль", fr: "Mot de passe")
    static let wrongPassword = Phrase("That isn't this Mac's password", ru: "Это не пароль от этого Mac", uk: "Це не пароль від цього Mac",
                                      fr: "Ce n’est pas le mot de passe de ce Mac")
    static let couldNotSave = Phrase("Couldn't save to the keychain", ru: "Не удалось сохранить в связку ключей", uk: "Не вдалося зберегти у звʼязку ключів",
                                     fr: "Impossible d’enregistrer dans le trousseau")
    static let continueTitle = Phrase("Continue", ru: "Продолжить", uk: "Продовжити", fr: "Continuer")
    static let doneTitle = Phrase("Face Unlock is on", ru: "Вход по лицу включён", uk: "Вхід за обличчям увімкнено", fr: "Déverrouillage facial activé")
    static let doneBody = Phrase("Lock your Mac, then wake it and look at the camera.", ru: "Заблокируйте Mac, потом разбудите его и посмотрите в камеру.",
                                 uk: "Заблокуйте Mac, потім розбудіть його й подивіться в камеру.", fr: "Verrouillez le Mac, puis réveillez-le et regardez la caméra.")
    static let done = Phrase("Done", ru: "Готово", uk: "Готово", fr: "Terminé")
    static let noRecognizer = Phrase("This version of macOS doesn't let apps recognize faces.", ru: "Эта версия macOS не даёт приложениям распознавать лица.",
                                     uk: "Ця версія macOS не дає застосункам розпізнавати обличчя.", fr: "Cette version de macOS ne permet pas aux apps de reconnaître les visages.")
    static let noCamera = Phrase("SAVISUL needs the camera. Allow it in System Settings → Privacy & Security → Camera.",
                                 ru: "SAVISUL нужна камера. Разрешите её в Системных настройках → Конфиденциальность и безопасность → Камера.",
                                 uk: "SAVISUL потрібна камера. Дозвольте її в Системних параметрах → Приватність і безпека → Камера.",
                                 fr: "SAVISUL a besoin de la caméra. Autorisez-la dans Réglages Système → Confidentialité et sécurité → Caméra.")
    static let openSettings = Phrase("Open Settings", ru: "Открыть настройки", uk: "Відкрити параметри", fr: "Ouvrir les réglages")
    static let saved = Phrase("Your face is saved", ru: "Лицо сохранено", uk: "Обличчя збережено", fr: "Visage enregistré")
    static let notSaved = Phrase("No face saved yet", ru: "Лицо ещё не сохранено", uk: "Обличчя ще не збережено", fr: "Aucun visage enregistré")
    static let scanAgain = Phrase("Scan again", ru: "Заново", uk: "Знову", fr: "Refaire")
    static let setUp = Phrase("Set up", ru: "Настроить", uk: "Налаштувати", fr: "Configurer")
    static let remove = Phrase("Remove", ru: "Удалить", uk: "Видалити", fr: "Supprimer")
}
