import AppKit
import Darwin
import Observation

/// Cooling settings: macOS decides, fans follow the chip temperature, full speed, or a fixed speed.
/// Writing fan speeds needs root, so a small helper (Sources/FanHelper) runs from launchd. It keeps every
/// speed inside the fan's own limits and hands the fans back to macOS if SAVISUL quits or stops checking in.
@MainActor
@Observable
final class FanControl {
    enum Mode: String, CaseIterable, Identifiable {
        case auto, smart, max, manual
        var id: String { rawValue }

        var title: Phrase {
            switch self {
            case .auto: Phrase("Auto", ru: "Авто", uk: "Авто", fr: "Auto")
            case .smart: Phrase("Smart", ru: "Умный", uk: "Розумний", fr: "Intelligent")
            case .max: Phrase("Max", ru: "Максимум", uk: "Максимум", fr: "Max")
            case .manual: Phrase("Manual", ru: "Вручную", uk: "Вручну", fr: "Manuel")
            }
        }
    }

    nonisolated static let socketPath = "/var/run/com.savisul.fans.sock"
    static let helperPath = "/Library/PrivilegedHelperTools/com.savisul.fanhelper"
    static let plistPath = "/Library/LaunchDaemons/com.savisul.fanhelper.plist"
    static let label = "com.savisul.fanhelper"

    private(set) var installed = false
    private(set) var connected = false
    private(set) var busy = false
    private(set) var problem: String?
    /// The speed SAVISUL is holding right now, or nil while macOS controls the fans.
    private(set) var holding: Int?

    var mode: Mode { didSet { defaults.set(mode.rawValue, forKey: "fanMode"); lastSent = nil; apply() } }
    /// Manual speed as a share of each fan's range, 0 = its minimum, 1 = its maximum.
    var level: Double { didSet { defaults.set(level, forKey: "fanLevel"); apply() } }
    /// Smart mode: fans start rising at `start` and reach full speed at `full`.
    var start: Double { didSet { defaults.set(start, forKey: "fanCurveStart"); apply() } }
    var full: Double { didSet { defaults.set(full, forKey: "fanCurveFull"); apply() } }

    @ObservationIgnored private let defaults: UserDefaults
    /// Tests pass false so a curve check never talks to the helper or the real fans.
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private let queue = DispatchQueue(label: "com.savisul.fans", qos: .utility)
    @ObservationIgnored private var lastSent: Int?
    @ObservationIgnored private var lastSentAt = Date.distantPast
    @ObservationIgnored private var temperature: Double?
    @ObservationIgnored private var range: (min: Double, max: Double)?
    /// Set at 95 °C, cleared below 85 °C, so a hot chip never waits on a low manual speed.
    @ObservationIgnored private(set) var hot = false

    init(defaults: UserDefaults = .standard, live: Bool = true) {
        self.defaults = defaults
        self.live = live
        mode = Mode(rawValue: defaults.string(forKey: "fanMode") ?? "") ?? .auto
        level = defaults.object(forKey: "fanLevel") as? Double ?? 0.5
        start = defaults.object(forKey: "fanCurveStart") as? Double ?? 60
        full = defaults.object(forKey: "fanCurveFull") as? Double ?? 88
        if live { refreshInstalled() }
    }

    func refreshInstalled() {
        installed = FileManager.default.fileExists(atPath: Self.plistPath) && FileManager.default.fileExists(atPath: Self.helperPath)
        guard installed else { connected = false; return }
        request("hello") { [weak self] reply in self?.connected = reply?.hasPrefix("ok savisul-fans") == true }
    }

    /// Called with each system sample. Re-sends the target every 20 seconds, which doubles as the heartbeat.
    func update(fans: [FanReading], temperature: Double?) {
        self.temperature = temperature
        if let temperature {
            if temperature >= 95 { hot = true } else if temperature < 85 { hot = false }
        }
        if let first = fans.first, first.maximum > first.minimum {
            range = (fans.map(\.minimum).max() ?? first.minimum, fans.map(\.maximum).min() ?? first.maximum)
        }
        apply()
    }

    /// The speed each mode asks for; nil means macOS decides.
    func target() -> Int? {
        guard let range else { return nil }
        let span = range.max - range.min
        switch mode {
        case .auto:
            return nil
        case .max:
            return Int(range.max)
        case .manual where hot, .smart where hot:
            return Int(range.max)
        case .manual:
            return Int(range.min + span * min(max(level, 0), 1))
        case .smart:
            guard let temperature, temperature >= start else { return nil }
            let share = min(max((temperature - start) / max(full - start, 1), 0), 1)
            return Int(range.min + span * share)
        }
    }

    private func apply() {
        guard live, installed else { return }
        let wanted = target()
        let now = Date()
        if let wanted {
            let changed = lastSent.map { abs($0 - wanted) >= 120 } ?? true
            guard changed || now.timeIntervalSince(lastSentAt) > 20 else { return }
            lastSent = wanted
            lastSentAt = now
            request("set \(wanted)") { [weak self] reply in
                guard let self else { return }
                self.connected = reply != nil
                if reply?.hasPrefix("ok") == true {
                    self.holding = wanted
                    self.problem = nil
                } else {
                    self.holding = nil
                    self.problem = reply == nil ? FanPhrases.noHelper.text : FanPhrases.refused.text
                }
            }
        } else if lastSent != nil || holding != nil || now.timeIntervalSince(lastSentAt) > 60 {
            lastSent = nil
            lastSentAt = now
            request("auto") { [weak self] reply in
                self?.connected = reply != nil
                self?.holding = nil
            }
        }
    }

    /// On quit: give the fans back right away, without waiting for the helper's watchdog.
    func shutdown() {
        guard installed, holding != nil || lastSent != nil else { return }
        _ = Self.exchange("auto")
    }

    // MARK: Install

    /// Copies the helper into place and starts it; macOS shows its own password dialog once.
    func install() {
        guard let source = Bundle.main.url(forResource: "savisul-fan-helper", withExtension: nil) else {
            problem = FanPhrases.missingHelper.text
            return
        }
        busy = true
        problem = nil
        let uid = getuid()
        // One line: it travels inside an AppleScript string to the password prompt.
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"
            + "<plist version=\"1.0\"><dict><key>Label</key><string>\(Self.label)</string>"
            + "<key>ProgramArguments</key><array><string>\(Self.helperPath)</string><string>--serve</string>"
            + "<string>--owner</string><string>\(uid)</string></array>"
            + "<key>RunAtLoad</key><true/><key>KeepAlive</key><true/></dict></plist>"
        let command = [
            "launchctl bootout system/\(Self.label) 2>/dev/null; true",
            "mkdir -p /Library/PrivilegedHelperTools",
            "cp \(quote(source.path)) \(Self.helperPath)",
            "chown root:wheel \(Self.helperPath)",
            "chmod 755 \(Self.helperPath)",
            "printf %s \(quote(plist)) > \(Self.plistPath)",
            "chown root:wheel \(Self.plistPath)",
            "chmod 644 \(Self.plistPath)",
            "launchctl bootstrap system \(Self.plistPath)"
        ].joined(separator: " && ")
        let result = Admin.run(command, prompt: FanPhrases.prompt.text)
        busy = false
        switch result {
        case .success:
            refreshInstalled()
            lastSent = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                MainActor.assumeIsolated {
                    self?.refreshInstalled()
                    self?.apply()
                }
            }
        case .failure(.cancelled):
            break
        case .failure(.failed(let message)):
            problem = message
        }
    }

    /// Stops and removes the helper; macOS gets the fans back.
    func uninstall() {
        if installed { _ = Self.exchange("auto") }
        busy = true
        let command = "launchctl bootout system/\(Self.label) 2>/dev/null; rm -f \(Self.plistPath) \(Self.helperPath) \(Self.socketPath); true"
        let result = Admin.run(command, prompt: FanPhrases.removePrompt.text)
        busy = false
        if case .failure(.failed(let message)) = result { problem = message }
        holding = nil
        lastSent = nil
        mode = .auto
        refreshInstalled()
    }

    private func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Socket

    private func request(_ command: String, done: @escaping @MainActor (String?) -> Void) {
        queue.async {
            let reply = Self.exchange(command)
            DispatchQueue.main.async { MainActor.assumeIsolated { done(reply) } }
        }
    }

    /// One request, one reply line, over the helper's local socket.
    nonisolated static func exchange(_ command: String) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            for (index, byte) in path.prefix(raw.count - 1).enumerated() { raw[index] = UInt8(bitPattern: byte) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return nil }
        let line = command + "\n"
        guard line.withCString({ Darwin.send(fd, $0, strlen($0), 0) }) > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: 512)
        let count = recv(fd, &buffer, buffer.count - 1, 0)
        guard count > 0 else { return nil }
        return String(decoding: buffer.prefix(count), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum FanPhrases {
    static let title = Phrase("Fans and cooling", ru: "Вентиляторы и охлаждение", uk: "Вентилятори й охолодження", fr: "Ventilateurs et refroidissement")
    static let enable = Phrase("Enable fan control", ru: "Включить управление", uk: "Увімкнути керування", fr: "Activer le contrôle")
    static let enableBody = Phrase("macOS asks for your password once to install a small helper. If SAVISUL quits or stops responding, the fans go back to automatic.",
                                   ru: "macOS один раз спросит пароль, чтобы поставить небольшой помощник. Если SAVISUL закроется или зависнет, вентиляторы вернутся в автоматический режим.",
                                   uk: "macOS один раз запитає пароль, щоб встановити невеликий помічник. Якщо SAVISUL закриється або зависне, вентилятори повернуться в автоматичний режим.",
                                   fr: "macOS demande votre mot de passe une fois pour installer un petit assistant. Si SAVISUL quitte ou ne répond plus, les ventilateurs repassent en automatique.")
    static let prompt = Phrase("SAVISUL needs your password to install its fan helper.", ru: "SAVISUL нужен пароль, чтобы установить помощник для вентиляторов.",
                               uk: "SAVISUL потрібен пароль, щоб встановити помічник для вентиляторів.", fr: "SAVISUL a besoin de votre mot de passe pour installer son assistant de ventilation.")
    static let removePrompt = Phrase("SAVISUL needs your password to remove its fan helper.", ru: "SAVISUL нужен пароль, чтобы удалить помощник для вентиляторов.",
                                     uk: "SAVISUL потрібен пароль, щоб видалити помічник для вентиляторів.", fr: "SAVISUL a besoin de votre mot de passe pour retirer son assistant de ventilation.")
    static let remove = Phrase("Remove helper", ru: "Удалить помощник", uk: "Видалити помічник", fr: "Retirer l’assistant")
    static let noHelper = Phrase("The fan helper isn’t answering. Turn fan control on again.", ru: "Помощник вентиляторов не отвечает. Включите управление ещё раз.",
                                 uk: "Помічник вентиляторів не відповідає. Увімкніть керування ще раз.", fr: "L’assistant ne répond pas. Réactivez le contrôle.")
    static let refused = Phrase("This Mac didn’t accept the fan speed. macOS keeps control.", ru: "Этот Mac не принял скорость. Управляет macOS.",
                                uk: "Цей Mac не прийняв швидкість. Керує macOS.", fr: "Ce Mac a refusé la vitesse. macOS garde le contrôle.")
    static let missingHelper = Phrase("The helper is missing from this copy of SAVISUL.", ru: "В этой копии SAVISUL нет помощника.",
                                      uk: "У цій копії SAVISUL немає помічника.", fr: "L’assistant manque dans cette copie de SAVISUL.")
    static let automatic = Phrase("macOS controls the fans", ru: "Вентиляторами управляет macOS", uk: "Вентиляторами керує macOS", fr: "macOS gère les ventilateurs")
    static let smartWaiting = Phrase("Fans join in above %@", ru: "Включатся выше %@", uk: "Увімкнуться вище %@", fr: "Démarrent au-dessus de %@")
    static let rise = Phrase("Start rising at", ru: "Начинать с", uk: "Починати з", fr: "Monter à partir de")
    static let top = Phrase("Full speed at", ru: "Полная скорость при", uk: "Повна швидкість при", fr: "Pleine vitesse à")
    static let speed = Phrase("Speed", ru: "Скорость", uk: "Швидкість", fr: "Vitesse")
    static let note = Phrase("Speeds stay within each fan’s own limits. At 95 °C the fans go to full speed in any mode until the chip cools to 85 °C.",
                             ru: "Скорость не выходит за пределы самого вентилятора. При 95 °C вентиляторы в любом режиме идут на максимум, пока чип не остынет до 85 °C.",
                             uk: "Швидкість не виходить за межі самого вентилятора. При 95 °C вентилятори в будь-якому режимі йдуть на максимум, доки чип не охолоне до 85 °C.",
                             fr: "Les vitesses restent dans les limites de chaque ventilateur. À 95 °C, ils passent à fond quel que soit le mode, jusqu’à ce que la puce revienne à 85 °C.")

    @MainActor static func holding(_ rpm: String) -> String {
        Phrase("Holding %@ rpm", ru: "Держим %@ об/мин", uk: "Тримаємо %@ об/хв", fr: "Maintien à %@ tr/min")(rpm)
    }
}
