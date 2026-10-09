import AppKit
import CryptoKit
import Darwin
import Observation

// The browser extension talks to SAVISUL through Chromium native messaging. The browser starts this same
// binary as a short-lived host; the host relays requests to the running app over distributed notifications.

enum BridgeNote {
    static let request = Notification.Name("com.savisul.bridge.request")
    static let reply = Notification.Name("com.savisul.bridge.reply")
    static let push = Notification.Name("com.savisul.bridge.push")
    static let bye = Notification.Name("com.savisul.bridge.bye")
    static let saved = BridgeFiles.savedNote
    static let shelf = BridgeFiles.shelfNote
}

/// Which door a message from the browser extension goes through.
enum BridgeRoute: Equatable {
    case state, command, launch, saveChunk, shelfChunk, shelfAdd, reveal, unknown

    static func classify(_ type: String) -> BridgeRoute {
        switch type {
        case "hello", "state": return .state
        case "set", "lidConfirm", "lidCancel", "displayOff", "open": return .command
        case "launch": return .launch
        case "saveChunk": return .saveChunk
        case "shelfChunk": return .shelfChunk
        case "shelfAdd": return .shelfAdd
        case "reveal": return .reveal
        default: return .unknown
        }
    }
}

enum BridgeJSON {
    static func encode(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ text: String?) -> [String: Any]? {
        guard let data = text?.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

enum AppInstances {
    /// Other copies of SAVISUL that run as real apps. Native messaging hosts never create an
    /// NSApplication, so LaunchServices lists them with the `.prohibited` policy.
    static func others() -> [NSRunningApplication] {
        let identifier = Bundle.main.bundleIdentifier ?? "com.savisul.menu"
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter {
            $0.processIdentifier != getpid() && !$0.isTerminated && $0.activationPolicy != .prohibited
        }
    }
}

// MARK: - Host process

enum BridgeHost {
    static func isRequested(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains { $0.hasPrefix("chrome-extension://") }
    }

    static func run() -> Never {
        signal(SIGPIPE, SIG_IGN)
        MainActor.assumeIsolated { HostSession.shared.start() }
        RunLoop.main.add(Port(), forMode: .default)
        while true {
            _ = RunLoop.main.run(mode: .default, before: .distantFuture)
        }
    }
}

@MainActor
final class HostSession {
    static let shared = HostSession()

    private let center = DistributedNotificationCenter.default()
    private let pid = String(getpid())
    private let browser = HostSession.parentAppName()
    private var counter = 0
    private var pending: [String: (timer: Timer, done: ([String: Any]?) -> Void)] = [:]
    private static let offline: [String: Any] = ["app": ["running": false]]

    func start() {
        center.addObserver(forName: BridgeNote.reply, object: nil, queue: .main) { note in
            let info = note.userInfo
            let pid = info?["pid"] as? String
            let key = info?["id"] as? String
            let body = info?["body"] as? String
            MainActor.assumeIsolated { HostSession.shared.receiveReply(pid: pid, key: key, body: body) }
        }
        center.addObserver(forName: BridgeNote.push, object: nil, queue: .main) { note in
            let body = note.userInfo?["body"] as? String
            MainActor.assumeIsolated { HostSession.shared.receivePush(body) }
        }
        let thread = Thread {
            HostSession.readLoop()
        }
        thread.stackSize = 1 << 20
        thread.start()
    }

    // MARK: Framing

    nonisolated private static func readLoop() {
        var header = [UInt8](repeating: 0, count: 4)
        while readExactly(&header, count: 4) {
            let length = Int(UInt32(header[0]) | UInt32(header[1]) << 8 | UInt32(header[2]) << 16 | UInt32(header[3]) << 24)
            guard length > 0, length <= 96 * 1024 * 1024 else { break }
            var body = [UInt8](repeating: 0, count: length)
            guard readExactly(&body, count: length) else { break }
            let data = Data(body)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HostSession.shared.handle(data) }
            }
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { HostSession.shared.finish() }
        }
    }

    nonisolated private static func readExactly(_ buffer: inout [UInt8], count: Int) -> Bool {
        var offset = 0
        while offset < count {
            let read = buffer.withUnsafeMutableBytes { raw in
                Darwin.read(STDIN_FILENO, raw.baseAddress! + offset, count - offset)
            }
            if read < 0 && errno == EINTR { continue }
            if read <= 0 { return false }
            offset += read
        }
        return true
    }

    private func send(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object), data.count < 1_000_000 else { return }
        var length = UInt32(data.count).littleEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(data)
        frame.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(STDOUT_FILENO, raw.baseAddress! + offset, raw.count - offset)
                if written < 0 && errno == EINTR { continue }
                if written <= 0 { exit(0) }
                offset += written
            }
        }
    }

    private func reply(_ id: Any?, _ payload: [String: Any]) {
        var object = payload
        if let id { object["id"] = id }
        send(object)
    }

    private func finish() {
        center.postNotificationName(BridgeNote.bye, object: nil, userInfo: ["pid": pid], deliverImmediately: true)
        exit(0)
    }

    // MARK: Requests

    private func handle(_ data: Data) {
        guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = message["type"] as? String else { return }
        let id = message["id"]
        switch BridgeRoute.classify(type) {
        case .state:
            forward(message, id: id, fallback: ["state": Self.offline])
        case .command:
            forward(message, id: id, fallback: ["error": "offline", "state": Self.offline])
        case .launch:
            launch(id)
        case .saveChunk:
            saveChunk(message, id: id)
        case .shelfChunk:
            reply(id, BridgeFiles.shelf(message))
        case .shelfAdd:
            forward(message, id: id, fallback: ["error": "offline", "state": Self.offline])
        case .reveal:
            reveal(message, id: id)
        case .unknown:
            reply(id, ["error": "unknown"])
        }
    }

    private func ask(_ message: [String: Any], timeout: TimeInterval, done: @escaping ([String: Any]?) -> Void) {
        guard let body = BridgeJSON.encode(message) else {
            done(nil)
            return
        }
        counter += 1
        let key = String(counter)
        let timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            MainActor.assumeIsolated { HostSession.shared.expire(key) }
        }
        pending[key] = (timer, done)
        center.postNotificationName(BridgeNote.request, object: nil,
                                    userInfo: ["pid": pid, "id": key, "body": body, "browser": browser],
                                    deliverImmediately: true)
    }

    private func forward(_ message: [String: Any], id: Any?, fallback: [String: Any]) {
        guard !AppInstances.others().isEmpty else {
            reply(id, fallback)
            return
        }
        ask(message, timeout: 4) { [weak self] payload in
            guard let self else { return }
            if let payload {
                self.reply(id, payload)
            } else {
                self.reply(id, AppInstances.others().isEmpty ? fallback : ["error": "timeout"])
            }
        }
    }

    private func receiveReply(pid: String?, key: String?, body: String?) {
        guard pid == self.pid, let key, let entry = pending.removeValue(forKey: key) else { return }
        entry.timer.invalidate()
        entry.done(BridgeJSON.decode(body) ?? [:])
    }

    private func expire(_ key: String) {
        guard let entry = pending.removeValue(forKey: key) else { return }
        entry.done(nil)
    }

    private func receivePush(_ body: String?) {
        guard let payload = BridgeJSON.decode(body) else { return }
        send(payload)
    }

    // MARK: Launch

    private func launch(_ id: Any?) {
        if AppInstances.others().isEmpty {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["--background"]
            configuration.activates = false
            configuration.addsToRecentItems = false
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in }
        }
        waitForApp(id: id, deadline: Date().addingTimeInterval(12))
    }

    /// The app only answers once it has finished launching, so keep asking until the deadline.
    private func waitForApp(id: Any?, deadline: Date) {
        ask(["type": "state"], timeout: 0.8) { [weak self] payload in
            guard let self else { return }
            if let payload {
                self.reply(id, payload)
            } else if Date() < deadline {
                self.waitForApp(id: id, deadline: deadline)
            } else {
                self.reply(id, ["error": "launch", "state": Self.offline])
            }
        }
    }

    // MARK: Files

    private func saveChunk(_ message: [String: Any], id: Any?) {
        reply(id, BridgeFiles.save(message))
    }

    private func reveal(_ message: [String: Any], id: Any?) {
        reply(id, BridgeFiles.reveal(message))
    }

    /// The browser that started us, e.g. "Google Chrome".
    private static func parentAppName() -> String {
        NSRunningApplication(processIdentifier: getppid())?.localizedName ?? ""
    }
}

// MARK: - App side

@MainActor
@Observable
final class BrowserLink {
    var browser: String?
    var seen: Date?
    var live = false

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        browser = defaults.string(forKey: "bridgeBrowser")
        seen = defaults.object(forKey: "bridgeSeen") as? Date
    }

    var installed: Bool { seen != nil }

    func mark(_ name: String) {
        if !name.isEmpty, browser != name {
            browser = name
            defaults.set(name, forKey: "bridgeBrowser")
        }
        if seen == nil || Date().timeIntervalSince(seen ?? .distantPast) > 60 {
            seen = Date()
            defaults.set(seen, forKey: "bridgeSeen")
        }
        if !live { live = true }
    }
}

@MainActor
final class BridgeServer {
    private let model: AppModel
    var onOpen: (() -> Void)?
    private var hosts: [String: Date] = [:]
    private var timer: Timer?
    private var signature = ""
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: BridgeNote.request, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo
            let pid = info?["pid"] as? String ?? ""
            let id = info?["id"] as? String ?? ""
            let body = info?["body"] as? String
            let browser = info?["browser"] as? String ?? ""
            MainActor.assumeIsolated { self?.receive(pid: pid, id: id, body: body, browser: browser) }
        }
        center.addObserver(forName: BridgeNote.bye, object: nil, queue: .main) { [weak self] note in
            let pid = note.userInfo?["pid"] as? String ?? ""
            MainActor.assumeIsolated { self?.forget(pid) }
        }
        center.addObserver(forName: BridgeNote.shelf, object: nil, queue: .main) { note in
            let path = note.userInfo?["path"] as? String
            MainActor.assumeIsolated {
                guard let path, path.hasPrefix(ShelfStore.drops.path + "/"), FileManager.default.fileExists(atPath: path) else { return }
                Suite.shared.shelf.add(urls: [URL(fileURLWithPath: path)])
            }
        }
        center.addObserver(forName: BridgeNote.saved, object: nil, queue: .main) { [weak self] note in
            let path = note.userInfo?["path"] as? String
            MainActor.assumeIsolated {
                guard let path, path.hasPrefix(CaptureService.picturesFolder.path) else { return }
                self?.model.capture.adopt(URL(fileURLWithPath: path))
            }
        }
    }

    private func receive(pid: String, id: String, body: String?, browser: String) {
        guard !pid.isEmpty else { return }
        hosts[pid] = Date()
        model.browserLink.mark(browser)
        watch()
        let message = BridgeJSON.decode(body) ?? [:]
        switch message["type"] as? String {
        case "set": apply(message["key"] as? String, message["value"])
        case "lidConfirm": model.confirmLidOnBattery()
        case "lidCancel": model.power.cancelConfirm()
        case "displayOff": model.power.displayOff()
        case "open": onOpen?()
        case "shelfAdd":
            if let text = message["text"] as? String, !text.isEmpty, text.count <= 200_000 { Suite.shared.shelf.add(text: text) }
        default: break
        }
        let current = state()
        signature = Self.signature(of: current)
        let payload: [String: Any] = ["ok": true, "state": current]
        guard let text = BridgeJSON.encode(payload) else { return }
        DistributedNotificationCenter.default().postNotificationName(BridgeNote.reply, object: nil,
                                                                     userInfo: ["pid": pid, "id": id, "body": text],
                                                                     deliverImmediately: true)
    }

    private func apply(_ key: String?, _ value: Any?) {
        let audio = model.audio
        switch key {
        case "lid":
            if let on = value as? Bool, on != model.power.lidAwake, !model.power.busy { model.toggleLid() }
        case "idle":
            if let on = value as? Bool { model.power.setIdle(on) }
        case "mute":
            if let on = value as? Bool, audio.defaultOutput != 0 { audio.setMuted(on, device: audio.defaultOutput, scope: .output) }
        case "volume":
            guard let level = value as? Double, audio.defaultOutput != 0 else { return }
            if level > 0, audio.currentOutput?.muted == true { audio.setMuted(false, device: audio.defaultOutput, scope: .output) }
            audio.setVolume(level, device: audio.defaultOutput, scope: .output)
        default:
            break
        }
    }

    func state() -> [String: Any] {
        model.audio.reload()
        let snapshot = model.currentSnapshot
        let power = model.power
        let output = model.audio.currentOutput
        var audio: [String: Any] = ["hasVolume": output?.volume != nil, "muted": output?.muted ?? false]
        if let output { audio["device"] = output.name }
        if let volume = output?.volume { audio["volume"] = volume }
        var state: [String: Any] = [
            "app": ["running": true, "version": version, "language": model.language.rawValue],
            "lid": ["on": power.lidAwake, "busy": power.busy, "confirm": power.confirmBattery, "known": power.known],
            "idle": ["on": power.idleHeld],
            "audio": audio,
            "battery": ["present": power.battery.present, "percent": power.battery.percent,
                        "charging": power.battery.charging, "adapter": power.battery.onAdapter],
            "memory": snapshot.memoryFraction * 100
        ]
        if snapshot.cpuReady { state["cpu"] = snapshot.cpu }
        if let temperature = snapshot.temperature { state["temperature"] = temperature }
        return state
    }

    /// Fields worth pushing the moment they change; CPU and memory travel with the regular polls.
    private static func signature(of state: [String: Any]) -> String {
        var copy = state
        copy.removeValue(forKey: "cpu")
        copy.removeValue(forKey: "memory")
        copy.removeValue(forKey: "temperature")
        if var battery = copy["battery"] as? [String: Any] {
            battery["percent"] = Int((battery["percent"] as? Double ?? 0).rounded())
            copy["battery"] = battery
        }
        guard let data = try? JSONSerialization.data(withJSONObject: copy, options: [.sortedKeys]) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func watch() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date()
        hosts = hosts.filter { pid, seen in
            guard let number = Int32(pid), kill(number, 0) == 0 || errno == EPERM else { return false }
            return now.timeIntervalSince(seen) < 45
        }
        guard !hosts.isEmpty else {
            timer?.invalidate()
            timer = nil
            model.browserLink.live = false
            return
        }
        let current = state()
        let next = Self.signature(of: current)
        guard next != signature, let text = BridgeJSON.encode(["state": current]) else { return }
        signature = next
        DistributedNotificationCenter.default().postNotificationName(BridgeNote.push, object: nil,
                                                                     userInfo: ["body": text], deliverImmediately: true)
    }

    private func forget(_ pid: String) {
        hosts.removeValue(forKey: pid)
        if hosts.isEmpty { model.browserLink.live = false }
    }
}

// MARK: - Browser setup

enum BrowserIntegration {
    static let hostName = "com.savisul.bridge"

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVISUL/Extension", isDirectory: true)
    }

    private static var bundled: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Extension", isDirectory: true)
    }

    /// Chromium browsers keep native messaging manifests next to their profiles.
    private static let profiles: [(path: String, app: String)] = [
        ("Google/Chrome", "com.google.Chrome"), ("Google/Chrome Beta", "com.google.Chrome.beta"),
        ("Google/Chrome Dev", "com.google.Chrome.dev"), ("Google/Chrome Canary", "com.google.Chrome.canary"),
        ("Chromium", "org.chromium.Chromium"), ("Microsoft Edge", "com.microsoft.edgemac"),
        ("Microsoft Edge Beta", "com.microsoft.edgemac.Beta"), ("Microsoft Edge Dev", "com.microsoft.edgemac.Dev"),
        ("BraveSoftware/Brave-Browser", "com.brave.Browser"), ("BraveSoftware/Brave-Browser-Beta", "com.brave.Browser.beta"),
        ("Vivaldi", "com.vivaldi.Vivaldi"), ("Arc/User Data", "company.thebrowser.Browser"),
        ("Yandex/YandexBrowser", "ru.yandex.desktop.yandex-browser"), ("com.operasoftware.Opera", "com.operasoftware.Opera")
    ]

    static func extensionID(manifest: URL) -> String? {
        guard let data = try? Data(contentsOf: manifest),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let key = json["key"] as? String, let der = Data(base64Encoded: key) else { return nil }
        let letters = Array("abcdefghijklmnop")
        return SHA256.hash(data: der).prefix(16).map { "\(letters[Int($0 >> 4)])\(letters[Int($0 & 0x0F)])" }.joined()
    }

    /// Mirrors the bundled extension to a folder people can drag into the browser and registers the host.
    static func prepare() {
        guard let bundled, FileManager.default.fileExists(atPath: bundled.appendingPathComponent("manifest.json").path) else { return }
        mirror(from: bundled, to: folder)
        guard let id = extensionID(manifest: bundled.appendingPathComponent("manifest.json")),
              let executable = Bundle.main.executablePath else { return }
        registerHost(id: id, executable: executable)
    }

    private static func fingerprint(of root: URL) -> String? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
        var files: [(String, URL)] = []
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let relative = String(url.path.dropFirst(root.path.count))
            if relative.hasSuffix(".DS_Store") || relative.hasPrefix("/_metadata/") { continue }
            files.append((relative, url))
        }
        var hash = SHA256()
        for (relative, url) in files.sorted(by: { $0.0 < $1.0 }) {
            hash.update(data: Data(relative.utf8))
            hash.update(data: (try? Data(contentsOf: url)) ?? Data())
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func mirror(from source: URL, to target: URL) {
        let manager = FileManager.default
        guard let wanted = fingerprint(of: source) else { return }
        if manager.fileExists(atPath: target.path), fingerprint(of: target) == wanted { return }
        let staging = target.deletingLastPathComponent().appendingPathComponent(".Extension-\(UUID().uuidString)", isDirectory: true)
        do {
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: source, to: staging)
            if manager.fileExists(atPath: target.path) {
                _ = try manager.replaceItemAt(target, withItemAt: staging)
            } else {
                try manager.moveItem(at: staging, to: target)
            }
        } catch {
            try? manager.removeItem(at: staging)
        }
    }

    private static func registerHost(id: String, executable: String) {
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "SAVISUL for Mac",
            "path": executable,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(id)/"]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
        for profile in profiles {
            let root = support.appendingPathComponent(profile.path, isDirectory: true)
            guard manager.fileExists(atPath: root.path) else { continue }
            let hosts = root.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            let file = hosts.appendingPathComponent("\(hostName).json")
            if (try? Data(contentsOf: file)) == data { continue }
            try? manager.createDirectory(at: hosts, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    @MainActor
    static func revealFolder() {
        if !FileManager.default.fileExists(atPath: folder.path) { prepare() }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// The first installed Chromium browser, preferring the one that already talked to SAVISUL.
    @MainActor
    static func preferredBrowser(named name: String?) -> URL? {
        let workspace = NSWorkspace.shared
        let apps = profiles.compactMap { workspace.urlForApplication(withBundleIdentifier: $0.app) }
        if let name, let match = apps.first(where: { $0.deletingPathExtension().lastPathComponent == name }) { return match }
        return apps.first
    }

    @MainActor
    static func openExtensionsPage(browser name: String?) {
        guard let app = preferredBrowser(named: name) else {
            revealFolder()
            return
        }
        revealFolder()
        let path = app.path
        let page = if path.contains("Microsoft Edge") { "edge://extensions" }
            else if path.contains("Brave") { "brave://extensions" }
            else if path.contains("Opera") { "opera://extensions" }
            else if path.contains("Vivaldi") { "vivaldi://extensions" }
            else if path.contains("Yandex") { "browser://extensions" }
            else { "chrome://extensions" }
        if openBrowserPage(app, page) { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let url = URL(string: page) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, _ in }
        }
    }

    /// Chromium ignores `chrome://` links opened from another app, so ask the browser itself to open the tab.
    @MainActor
    private static func openBrowserPage(_ app: URL, _ page: String) -> Bool {
        let name = app.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "\(name)"
          activate
          if (count of windows) = 0 then make new window
          tell front window to make new tab with properties {URL:"\(page)"}
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&error)
        return error == nil
    }
}
