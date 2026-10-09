import AppKit
import ApplicationServices
import CoreGraphics
import Observation
import ServiceManagement
import UserNotifications

enum PermissionState: Equatable {
    case granted, denied, notDetermined, requiresApproval
}

enum PermissionKind {
    case accessibility, screen, notifications, login
}

@MainActor
@Observable
final class PermissionCenter {
    var accessibility: PermissionState = .notDetermined
    var screen: PermissionState = .notDetermined
    var notifications: PermissionState = .notDetermined
    var login: PermissionState = .denied
    var loginError: String?

    @ObservationIgnored var onAccessibilityChange: ((Bool) -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var polls = 0
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var accessibilityAskedAt: Date?
    @ObservationIgnored private var liveScreenGrant = false
    @ObservationIgnored private var probing = false
    @ObservationIgnored private var lastProbe = Date.distantPast
    @ObservationIgnored private let defaults = UserDefaults.standard
    /// Panel renders (--dump-panels) draw the panes as someone who has granted everything sees them.
    @ObservationIgnored var assumeGranted = false

    var accessibilityGranted: Bool { accessibility == .granted }
    var screenGranted: Bool { screen == .granted }
    var notificationsGranted: Bool { notifications == .granted }
    var screenRequested: Bool { defaults.bool(forKey: "screenRequested") }

    func refresh() {
        refreshFast()
        guard !assumeGranted else { return }
        refreshLogin()
        if screenRequested && !CGPreflightScreenCaptureAccess() && Date().timeIntervalSince(lastProbe) > 6 { probeScreen(nil) }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let state: PermissionState = switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: .granted
            case .denied: .denied
            default: .notDetermined
            }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    if self?.notifications != state { self?.notifications = state }
                }
            }
        }
    }

    /// Cheap checks that are safe to run every second.
    private func refreshFast() {
        if assumeGranted {
            if accessibility != .granted { accessibility = .granted }
            if screen != .granted { screen = .granted }
            return
        }
        let trusted = AXIsProcessTrusted()
        let ax: PermissionState = trusted ? .granted : defaults.bool(forKey: "axRequested") ? .denied : .notDetermined
        if ax != accessibility {
            let wasGranted = accessibility == .granted
            accessibility = ax
            if wasGranted != trusted { onAccessibilityChange?(trusted) }
        }
        let captured: PermissionState = CGPreflightScreenCaptureAccess() || liveScreenGrant ? .granted
            : screenRequested ? .denied : .notDetermined
        if captured != screen { screen = captured }
    }

    /// The in-process screen answer is frozen at launch, so a grant made later is invisible to it.
    /// A short-lived copy of this binary is a new process with the same signature and reads the live grant;
    /// every capture runs in a child process too, so that live answer is the one that matters.
    private func probeScreen(_ completion: ((Bool) -> Void)?) {
        guard !probing, let executable = Bundle.main.executablePath else {
            completion?(screenGranted)
            return
        }
        probing = true
        lastProbe = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            let output = Shell.run(executable, ["--probe-screen"], timeout: 5)
            let granted = output?.text.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.probing = false
                    self.liveScreenGrant = granted
                    self.refreshFast()
                    completion?(self.screenGranted)
                }
            }
        }
    }

    /// Resolves with the live Screen Recording answer, without needing a relaunch after a fresh grant.
    func confirmScreen(_ completion: @escaping (Bool) -> Void) {
        if screenGranted {
            completion(true)
        } else {
            probeScreen(completion)
        }
    }

    func refreshLogin() {
        let state: PermissionState = switch SMAppService.mainApp.status {
        case .enabled: .granted
        case .requiresApproval: .requiresApproval
        default: .denied
        }
        if state != login { login = state }
    }

    /// After a request the grant usually happens in System Settings while the panel is closed.
    private var awaitingAccessibility: Bool {
        guard accessibility != .granted, let asked = accessibilityAskedAt else { return false }
        return Date().timeIntervalSince(asked) < 900
    }

    func startPolling() {
        visible = true
        scheduleTimer()
    }

    func stopPolling() {
        visible = false
        if !awaitingAccessibility { cancelTimer() }
    }

    private func scheduleTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.polls += 1
                self.refreshFast()
                if self.visible && self.polls % 4 == 0 { self.refresh() }
                if !self.visible && !self.awaitingAccessibility { self.cancelTimer() }
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    func requestAccessibility() {
        accessibilityAskedAt = Date()
        scheduleTimer()
        if accessibility == .notDetermined {
            defaults.set(true, forKey: "axRequested")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        } else {
            openSettings(.accessibility)
        }
        refreshFast()
    }

    func requestScreenRecording() {
        if screen == .notDetermined {
            defaults.set(true, forKey: "screenRequested")
            _ = CGRequestScreenCaptureAccess()
        } else {
            openSettings(.screen)
        }
        refreshFast()
    }

    func requestNotifications(_ completion: @escaping (Bool) -> Void) {
        if notifications == .denied {
            openSettings(.notifications)
            completion(false)
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.notifications = granted ? .granted : .denied
                    completion(granted)
                }
            }
        }
    }

    func setLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = error.localizedDescription
        }
        refreshLogin()
        if enabled && login == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    func openSettings(_ kind: PermissionKind) {
        let link: String
        switch kind {
        case .accessibility:
            link = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screen:
            link = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .notifications:
            link = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "com.savisul.menu")"
        case .login:
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    /// Starts a fresh copy once this process has exited; Screen Recording grants apply only to new processes.
    func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$0\"",
                          Bundle.main.bundlePath, "\(getpid())"]
        try? task.run()
        NSApp.terminate(nil)
    }
}
