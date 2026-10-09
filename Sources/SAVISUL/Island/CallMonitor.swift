import AppKit
import CoreMediaIO
import Darwin
import Observation

/// Notices calls: a meeting app, or a browser tab, holding the microphone. Nothing is recorded or read;
/// Core Audio only says which processes are using an input right now.
@MainActor
@Observable
final class CallMonitor {
    struct Call: Equatable {
        var bundle: String
        var name: String
        var appPath: String?
        var browser: Bool
        var since: Date
        var camera = false
        /// The app the call's controls talk to.
        var pid: pid_t = 0
        /// What the call's own microphone button says, when it has one to read.
        var micMuted: Bool?
    }

    private(set) var current: Call?
    @ObservationIgnored var onStart: ((Call) -> Void)?
    @ObservationIgnored var onEnd: ((Call) -> Void)?
    @ObservationIgnored private var tracker = CallTracker()
    @ObservationIgnored private var callers: [String: Call] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let reader = DispatchQueue(label: "com.savisul.calls", qos: .utility)
    @ObservationIgnored private var reading = false
    @ObservationIgnored private var ticks = 0

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tracker = CallTracker()
        current = nil
    }

    /// Panel renders (--dump-panels) show a sample call without listening to anything.
    func preview(_ call: Call?) {
        stop()
        current = call
    }

    private func poll() {
        let caller = Self.caller()
        if let caller { callers[caller.bundle] = caller }
        let now = Date()
        for event in tracker.update(heard: caller?.bundle, at: now) {
            switch event {
            case .started(let bundle, let since):
                guard var call = callers[bundle] else { continue }
                call.since = since
                call.camera = Self.cameraRunning()
                current = call
                onStart?(call)
            case .ended:
                if let call = current { onEnd?(call) }
                current = nil
            }
        }
        // The island's own camera mirror would read as the call's camera, so the state holds while it runs.
        if var call = current, !Suite.shared.camera.running {
            call.camera = Self.cameraRunning()
            if call != current { current = call }
        }
        ticks += 1
        if let call = current, ticks % 2 == 0, !reading, !CallControls.closed.contains(call.bundle) { readMicrophone(call) }
    }

    /// Reads the call's own microphone button off the main thread; a browser page can take a moment.
    private func readMicrophone(_ call: Call) {
        reading = true
        let pid = call.pid, browser = call.browser
        reader.async { [weak self] in
            let muted = CallControls.micMuted(pid: pid, browser: browser)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reading = false
                    if var call = self.current, call.pid == pid, call.micMuted != muted {
                        call.micMuted = muted
                        self.current = call
                    }
                }
            }
        }
    }

    /// What the microphone button will say once the app has caught up with a press.
    func expectMicrophone(muted: Bool) {
        guard var call = current else { return }
        call.micMuted = muted
        current = call
    }

    /// The app on a call: a known meeting app first, then a browser holding the microphone.
    private static func caller() -> Call? {
        let me = getpid()
        var browser: Call?
        for pid in CA.inputPIDs() {
            if processName(pid) == "avconferenced", let app = conferencingApp() {
                return Call(bundle: app.bundleIdentifier ?? "com.apple.FaceTime", name: app.localizedName ?? "FaceTime",
                            appPath: app.bundleURL?.path, browser: false, since: Date(), pid: app.processIdentifier)
            }
            let owner = responsible(pid)
            guard owner != me, let app = NSRunningApplication(processIdentifier: owner) ?? NSRunningApplication(processIdentifier: pid),
                  let bundle = app.bundleIdentifier else { continue }
            switch CallApps.kind(bundle) {
            case .app(let name):
                return Call(bundle: bundle, name: name, appPath: app.bundleURL?.path, browser: false, since: Date(), pid: app.processIdentifier)
            case .browser:
                if browser == nil {
                    browser = Call(bundle: bundle, name: app.localizedName ?? bundle, appPath: app.bundleURL?.path, browser: true,
                                   since: Date(), pid: app.processIdentifier)
                }
            case nil:
                continue
            }
        }
        return browser
    }

    /// FaceTime and the Phone app both talk through avconferenced: an iPhone call relayed to the Mac shows in Phone.
    private static func conferencingApp() -> NSRunningApplication? {
        let phone = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mobilephone").first
        let faceTime = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.FaceTime").first
        if let phone, faceTime == nil || phone.isActive { return phone }
        return faceTime ?? phone
    }

    /// Whether any camera is running, from Core Media IO. AVFoundation hides other apps' camera use
    /// from an app that has not been given the camera itself, which left the island showing the camera as off.
    private static func cameraRunning() -> Bool {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == 0 else { return false }
        var running = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        return devices.contains { device in
            var value: UInt32 = 0
            var read: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &read, &value) == 0 && value != 0
        }
    }

    private typealias Responsible = @convention(c) (pid_t) -> pid_t
    /// Helpers and XPC services, like a browser's audio process, belong to the app that started them.
    private static let responsibleFor: Responsible? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: Responsible.self)
    }()

    private static func responsible(_ pid: pid_t) -> pid_t {
        guard let responsibleFor else { return pid }
        let owner = responsibleFor(pid)
        return owner > 0 ? owner : pid
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        return String(cString: buffer)
    }
}

/// Which apps count as calls when they hold the microphone.
enum CallApps {
    enum Kind: Equatable {
        case app(String)
        case browser
    }

    private static let apps: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams", "com.microsoft.teams": "Microsoft Teams",
        "com.apple.FaceTime": "FaceTime", "com.apple.mobilephone": "Phone",
        "com.cisco.webexmeetingsapp": "Webex", "Cisco-Systems.Spark": "Webex",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.hnc.Discord": "Discord", "com.hnc.DiscordPTB": "Discord", "com.hnc.DiscordCanary": "Discord",
        "com.skype.skype": "Skype",
        "ru.keepcoder.Telegram": "Telegram", "org.telegram.desktop": "Telegram",
        "net.whatsapp.WhatsApp": "WhatsApp", "desktop.WhatsApp": "WhatsApp",
        "org.whispersystems.signal-desktop": "Signal",
        "com.viber.osx": "Viber", "im.riot.app": "Element", "jp.naver.line.mac": "LINE",
        "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan": "Google Meet"
    ]

    private static let browsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "org.chromium.Chromium",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "company.thebrowser.Browser",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev",
        "com.brave.Browser", "com.brave.Browser.beta", "org.mozilla.firefox", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "ru.yandex.desktop.yandex-browser"
    ]

    static func kind(_ bundle: String) -> Kind? {
        if let name = apps[bundle] { return .app(name) }
        if browsers.contains(bundle) { return .browser }
        if bundle.hasPrefix("com.google.Chrome.app.") { return .browser }
        return nil
    }
}

/// Turns "who holds the microphone, once a second" into calls that start and end.
/// A call starts after the same app has held the microphone for two seconds, so a dictation
/// or a sound check is not a call, and ends after three quiet seconds, so a device switch is not an end.
struct CallTracker {
    enum Event: Equatable {
        case started(String, since: Date)
        case ended(String)
    }

    static let startAfter: TimeInterval = 2
    static let endAfter: TimeInterval = 3

    private(set) var active: String?
    private var candidate: (bundle: String, since: Date)?
    private var lastHeard = Date.distantPast

    mutating func update(heard bundle: String?, at now: Date) -> [Event] {
        guard let bundle else {
            candidate = nil
            if let active, now.timeIntervalSince(lastHeard) >= Self.endAfter {
                self.active = nil
                return [.ended(active)]
            }
            return []
        }
        lastHeard = now
        if let active {
            guard active != bundle else { return [] }
            self.active = bundle
            return [.ended(active), .started(bundle, since: now)]
        }
        if let candidate, candidate.bundle == bundle {
            guard now.timeIntervalSince(candidate.since) >= Self.startAfter else { return [] }
            self.candidate = nil
            active = bundle
            return [.started(bundle, since: candidate.since)]
        }
        candidate = (bundle, now)
        return []
    }
}
