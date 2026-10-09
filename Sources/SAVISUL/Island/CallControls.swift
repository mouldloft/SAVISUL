import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// The microphone, the camera and the hang-up button for whichever app is on the call, a browser tab included.
/// macOS has no way for one app to steer another's call, so each app is driven the way a person would, in this order:
/// 1. the button or menu item that does it, pressed through Accessibility without bringing the app forward;
///    in a browser the call's tab is made current first when another tab hides it;
/// 2. the app's own shortcut, sent only once the app is really in front, so it never lands in another app;
/// 3. the app brought to the front on the call's own window, so the call is finished in it.
/// Apps that let nothing be pressed skip straight to the last step.
enum CallControls {
    enum Action: Equatable { case microphone, camera, hangUp }

    enum Outcome: Equatable {
        /// The app did it.
        case done
        /// The app asks before it acts, like Zoom leaving a meeting; it is in front now.
        case confirmInApp
        /// Nothing to press: the app is in front, the person finishes there.
        case openedApp
        /// The app lets nothing press its call buttons; its call window is in front for the person to use.
        case inAppOnly
        /// Accessibility is off, so nothing can be pressed.
        case needsAccess
        /// The microphone has no button to press here; the caller mutes every microphone instead.
        case notFound
    }

    struct Shortcut: Equatable {
        let key: Int
        let flags: CGEventFlags
        /// The app shows a confirmation instead of acting at once.
        var confirms = false
    }

    private static let zoom = "us.zoom.xos"
    private static let teams: Set<String> = ["com.microsoft.teams2", "com.microsoft.teams"]
    private static let meet = "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"
    private static let discord: Set<String> = ["com.hnc.Discord", "com.hnc.DiscordPTB", "com.hnc.DiscordCanary"]
    private static let apple: Set<String> = ["com.apple.FaceTime", "com.apple.mobilephone"]

    /// Apps whose call window hides its buttons from Accessibility and has no shortcuts for them, so nothing in it can be
    /// pressed from outside. Telegram for macOS draws every control itself, reports none of them, and acts only on a real
    /// click under the pointer. Their microphone is muted along with every other one; the camera and hanging up stay in the app.
    static let closed: Set<String> = ["ru.keepcoder.Telegram"]

    static func shortcut(_ action: Action, bundle: String) -> Shortcut? {
        switch action {
        case .microphone:
            if bundle == zoom { return Shortcut(key: kVK_ANSI_A, flags: [.maskCommand, .maskShift]) }
            if teams.contains(bundle) || discord.contains(bundle) { return Shortcut(key: kVK_ANSI_M, flags: [.maskCommand, .maskShift]) }
            if bundle == meet { return Shortcut(key: kVK_ANSI_D, flags: .maskCommand) }
        case .camera:
            if bundle == zoom { return Shortcut(key: kVK_ANSI_V, flags: [.maskCommand, .maskShift]) }
            if teams.contains(bundle) { return Shortcut(key: kVK_ANSI_O, flags: [.maskCommand, .maskShift]) }
            if bundle == meet { return Shortcut(key: kVK_ANSI_E, flags: .maskCommand) }
        case .hangUp:
            if bundle == zoom { return Shortcut(key: kVK_ANSI_W, flags: .maskCommand, confirms: true) }
            if teams.contains(bundle) || bundle == "com.tinyspeck.slackmacgap" { return Shortcut(key: kVK_ANSI_H, flags: [.maskCommand, .maskShift]) }
        }
        return nil
    }

    // MARK: Labels

    /// Hang-up labels. Phrases only, so nothing like "Log out" or a lone "Leave" can match.
    private static let hangUpPhrases = [
        "end call", "hang up", "leave call", "leave meeting", "end meeting", "leave huddle",
        "завершить звонок", "завершить вызов", "положить трубку", "покинуть звонок", "покинуть встречу", "покинуть видеовстречу",
        "выйти из конференции", "покинуть конференцию", "выйти из встречи",
        "завершити дзвінок", "завершити виклик", "покласти слухавку", "покинути дзвінок", "вийти з конференції",
        "raccrocher", "terminer l’appel", "quitter l’appel", "quitter la réunion"
    ]
    /// The second step after Zoom's toolbar button: leaving, never ending the meeting for everyone.
    static let leaveConfirm = ["leave meeting", "leave call", "выйти из конференции", "покинуть конференцию", "выйти из встречи",
                               "вийти з конференції", "quitter la réunion"]
    /// Zoom's toolbar button that opens the leave confirmation, pressed only in the window that also has the video button.
    private static let zoomLeave = ["leave", "end", "выйти", "завершить", "вийти", "завершити", "quitter", "fin"]

    static func phrases(_ action: Action, bundle: String) -> [String] {
        switch action {
        case .microphone, .camera:
            return []
        case .hangUp:
            // In these apps the single words only ever sit on the call's own button.
            if apple.contains(bundle) { return hangUpPhrases + ["end", "завершить", "завершити", "terminer"] }
            if discord.contains(bundle) { return hangUpPhrases + ["disconnect", "отключиться", "відключитися"] }
            return hangUpPhrases
        }
    }

    /// Lowercased, single-spaced, without a trailing ellipsis or a shortcut hint like "(⌘ + e)".
    static func normalize(_ label: String) -> String {
        var text = label.lowercased().replacingOccurrences(of: "'", with: "’").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(")"), let open = text.range(of: " (", options: .backwards) { text = String(text[..<open.lowerBound]) }
        text = text.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func matches(_ label: String, _ phrases: [String]) -> Bool {
        let text = normalize(label)
        return !text.isEmpty && phrases.contains(text)
    }

    private static let verbs = ["start", "stop", "turn", "enable", "disable", "on", "off", "mute", "unmute",
                                "activer", "désactiver", "réactiver", "arrêter", "démarrer", "couper"]
    private static let stems = ["включ", "выключ", "отключ", "останов", "начать", "запуст", "увімк", "вимк", "зупин", "почат"]
    /// Beginnings of words that make a control something else, like settings or a background; matched per word, so "фон" never hits "микрофон".
    private static let notToggles = ["setting", "filter", "background", "record", "shar", "effect", "test", "volume", "level", "choose", "select",
                                     "настро", "фильтр", "фон", "запис", "демонстр", "эффект", "провер", "громк", "уровень", "выбр",
                                     "налашт", "réglage", "filtre", "arrière", "enregistr", "partag", "choisir"]

    private static func says(_ text: String, one nouns: [String]) -> Bool {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 6, nouns.contains(where: { text.contains($0) }),
              !words.contains(where: { word in notToggles.contains(where: { word.hasPrefix($0) }) })
        else { return false }
        return words.contains { word in verbs.contains(word) || stems.contains(where: { word.hasPrefix($0) }) }
    }

    /// A button that turns the camera on or off: it names the camera or the video and says what to do with it,
    /// like "Stop Video", "Start my video", "Turn Off Camera" or "Остановить видео". "Video Settings" is not one.
    static func isCameraToggle(_ label: String) -> Bool {
        says(normalize(label), one: ["camera", "video", "камер", "видео", "відео", "caméra", "vidéo"])
    }

    /// A button that mutes or unmutes the call's microphone. A bare "Mute" counts only outside a browser,
    /// where on a web page it could just as well belong to a video player.
    static func isMicToggle(_ label: String, browser: Bool) -> Bool {
        let text = normalize(label)
        if !browser, ["mute", "unmute", "mute audio", "unmute audio", "выключить звук", "включить звук", "вимкнути звук", "увімкнути звук",
                      "couper le son", "réactiver le son"].contains(text) { return true }
        return says(text, one: ["mic", "микрофон", "мікрофон", "micro"])
    }

    /// Whether a microphone button says the microphone is off now: it offers to turn it back on.
    static func micMuted(fromLabel label: String) -> Bool? {
        let text = normalize(label)
        if text.contains("unmute") || text.hasPrefix("turn on") || text.hasPrefix("включить") || text.hasPrefix("увімкнути")
            || text.hasPrefix("activer") || text.hasPrefix("réactiver") { return true }
        if text.hasPrefix("mute") || text.hasPrefix("turn off") || text.hasPrefix("выключить") || text.hasPrefix("отключить")
            || text.hasPrefix("вимкнути") || text.hasPrefix("couper") || text.hasPrefix("désactiver") { return false }
        return nil
    }

    // MARK: Doing it

    @MainActor
    static func perform(_ action: Action, on call: CallMonitor.Call, done: @escaping @MainActor (Outcome) -> Void) {
        guard let app = NSRunningApplication(processIdentifier: call.pid) ?? NSRunningApplication.runningApplications(withBundleIdentifier: call.bundle).first else {
            done(action == .microphone ? .notFound : .openedApp)
            return
        }
        if closed.contains(call.bundle) {
            if action == .microphone { return done(.notFound) }
            bringForward(app)
            return done(.inAppOnly)
        }
        guard AX.trusted else {
            if action != .microphone { app.activate() }
            done(.needsAccess)
            return
        }
        let pid = app.processIdentifier
        let bundle = call.bundle
        let browser = call.browser
        attempt(action, pid: pid, bundle: bundle, browser: browser) { pressed in
            if pressed == .done {
                done(.done)
            } else if pressed == .waiting {
                bringForward(app)
                done(.confirmInApp)
            } else if browser, CallTabs.select(bundle: bundle) {
                // The call's tab was behind another one; now it is current, try again.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    attempt(action, pid: pid, bundle: bundle, browser: browser) { again in
                        if again == .done { return done(.done) }
                        finish(action, app: app, bundle: bundle, browser: browser, done: done)
                    }
                }
            } else {
                finish(action, app: app, bundle: bundle, browser: browser, done: done)
            }
        }
    }

    /// Searches and presses in the background, then answers on the main thread.
    @MainActor
    private static func attempt(_ action: Action, pid: pid_t, bundle: String, browser: Bool, _ then: @escaping @MainActor (Pressed) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let pressed = pressInApp(action, pid: pid, bundle: bundle, browser: browser)
            DispatchQueue.main.async { MainActor.assumeIsolated { then(pressed) } }
        }
    }

    /// Nothing could be pressed: the app's shortcut when it has one, otherwise the app comes forward.
    @MainActor
    private static func finish(_ action: Action, app: NSRunningApplication, bundle: String, browser: Bool,
                               done: @escaping @MainActor (Outcome) -> Void) {
        if let shortcut = shortcut(action, bundle: bundle) {
            send(shortcut, to: app) { sent in
                if !sent { record(action, pid: app.processIdentifier, bundle: bundle) }
                done(sent ? (shortcut.confirms ? .confirmInApp : .done) : (action == .microphone ? .notFound : .openedApp))
            }
            return
        }
        record(action, pid: app.processIdentifier, bundle: bundle)
        if action == .microphone { return done(.notFound) }
        bringForward(app, browser: browser)
        done(.openedApp)
    }

    private enum Pressed { case done, waiting, missing }

    /// Finds the control in the app's windows, web pages and menus and presses it, in the background.
    private static func pressInApp(_ action: Action, pid: pid_t, bundle: String, browser: Bool) -> Pressed {
        switch action {
        case .microphone:
            if let control = find(pid: pid, menus: !browser, { isMicToggle($0, browser: browser) }), AX.perform(control, kAXPressAction) { return .done }
            return .missing
        case .camera:
            if let control = find(pid: pid, menus: !browser, isCameraToggle), AX.perform(control, kAXPressAction) { return .done }
            return .missing
        case .hangUp:
            let phrases = phrases(.hangUp, bundle: bundle)
            if let control = find(pid: pid, menus: !browser, { matches($0, phrases) }), AX.perform(control, kAXPressAction) { return .done }
            guard bundle == zoom, let first = zoomLeaveButton(pid: pid), AX.perform(first, kAXPressAction) else { return .missing }
            // Zoom asks first; take "Leave meeting" when it appears, never "End meeting for all".
            for _ in 0..<8 {
                Thread.sleep(forTimeInterval: 0.15)
                if let confirm = find(pid: pid, menus: false, { matches($0, leaveConfirm) }), AX.perform(confirm, kAXPressAction) { return .done }
            }
            return .waiting
        }
    }

    /// Whether the call's own microphone button says it is muted, or nil when there is no such button to read.
    nonisolated(unsafe) private static var micButton: (pid: pid_t, element: AXUIElement)?

    static func micMuted(pid: pid_t, browser: Bool) -> Bool? {
        guard AX.trusted else { return nil }
        if let cached = micButton, cached.pid == pid {
            for label in labels(cached.element) {
                if let muted = micMuted(fromLabel: label) { return muted }
            }
        }
        micButton = nil
        guard let element = find(pid: pid, menus: false, { isMicToggle($0, browser: browser) && micMuted(fromLabel: $0) != nil }) else { return nil }
        micButton = (pid, element)
        return labels(element).lazy.compactMap { micMuted(fromLabel: $0) }.first
    }

    /// Zoom's toolbar "Leave" or "End": only in the window that also holds the video button, which is the meeting.
    private static func zoomLeaveButton(pid: pid_t) -> AXUIElement? {
        for window in AX.windows(pid) {
            var leave: AXUIElement?
            var hasVideo = false
            var pages: [AXUIElement] = []
            walk(window, pages: &pages) { element, label in
                if leave == nil, matches(label, zoomLeave) { leave = element }
                if isCameraToggle(label) { hasVideo = true }
                return leave != nil && hasVideo
            }
            if let leave, hasVideo { return leave }
        }
        return nil
    }

    /// The first control whose label passes the test: native controls in the windows front to back, then those on web pages,
    /// found through the page's own element search, then the menu bar.
    private static func find(pid: pid_t, menus: Bool, _ test: (String) -> Bool) -> AXUIElement? {
        let application = AX.app(pid)
        // Electron and Chromium apps build their accessibility tree only when asked to.
        _ = AX.set(application, "AXManualAccessibility", kCFBooleanTrue)
        var found: AXUIElement?
        var pages: [AXUIElement] = []
        for window in AX.windows(pid) where found == nil {
            walk(window, pages: &pages) { element, label in
                if test(label) { found = element }
                return found != nil
            }
        }
        if let found { return found }
        for page in pages {
            for element in pressable(onPage: page) where labels(element).contains(where: test) { return element }
        }
        if menus, let bar = AX.element(application, kAXMenuBarAttribute) {
            var none: [AXUIElement] = []
            walk(bar, pages: &none) { element, label in
                if test(label) { found = element }
                return found != nil
            }
        }
        return found
    }

    /// Visits the pressable elements under a root with each of their labels until `stop` says so.
    /// Web pages are not walked into; they are collected for the page's own search, which is far faster on a big page.
    private static func walk(_ root: AXUIElement, pages: inout [AXUIElement], _ stop: (AXUIElement, String) -> Bool) {
        let pressable: Set<String> = [kAXButtonRole, kAXCheckBoxRole, kAXMenuItemRole, "AXToggle"]
        var queue = [root]
        var visited = 0
        while !queue.isEmpty, visited < 5_000 {
            let element = queue.removeFirst()
            visited += 1
            let role = AX.role(element)
            if role == "AXWebArea" {
                pages.append(element)
                continue
            }
            if let role, pressable.contains(role) {
                for label in labels(element) where stop(element, label) { return }
            }
            queue.append(contentsOf: AX.elements(element, kAXChildrenAttribute))
        }
    }

    /// Every button and checkbox on a web page, through the search VoiceOver uses; a walk of the page when it is not offered.
    private static func pressable(onPage page: AXUIElement) -> [AXUIElement] {
        let parameters: [String: Any] = ["AXSearchKey": ["AXButtonSearchKey", "AXCheckBoxSearchKey"], "AXResultsLimit": 800,
                                         "AXDirection": "AXDirectionNext", "AXVisibleOnly": false]
        var result: AnyObject?
        if AXUIElementCopyParameterizedAttributeValue(page, "AXUIElementsForSearchPredicate" as CFString, parameters as CFDictionary, &result) == .success,
           let items = result as? [AnyObject], !items.isEmpty {
            return items.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
        }
        var found: [AXUIElement] = []
        var queue = AX.elements(page, kAXChildrenAttribute)
        var visited = 0
        while !queue.isEmpty, visited < 20_000 {
            let element = queue.removeFirst()
            visited += 1
            if let role = AX.role(element), role == kAXButtonRole || role == kAXCheckBoxRole { found.append(element) }
            queue.append(contentsOf: AX.elements(element, kAXChildrenAttribute))
        }
        return found
    }

    private static func labels(_ element: AXUIElement) -> [String] {
        [AX.title(element), AX.string(element, kAXDescriptionAttribute), AX.string(element, kAXHelpAttribute)].compactMap { $0 }.filter { !$0.isEmpty }
    }

    /// Brings the app forward through Accessibility, which works while SAVISUL is in the background,
    /// and sends the shortcut only when the app really is in front.
    @MainActor
    private static func send(_ shortcut: Shortcut, to app: NSRunningApplication, sent: @escaping @MainActor (Bool) -> Void) {
        let previous = NSWorkspace.shared.frontmostApplication
        bringForward(app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            MainActor.assumeIsolated {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                    sent(false)
                    return
                }
                Keys.tap(CGKeyCode(shortcut.key), flags: shortcut.flags)
                sent(true)
                guard !shortcut.confirms, let previous, previous != app, previous.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { _ = previous.activate() }
            }
        }
    }

    /// An app comes forward on its call's window; a browser on its front window, where the call's tab has been made current.
    @MainActor
    static func bringForward(_ app: NSRunningApplication, browser: Bool = false) {
        let pid = app.processIdentifier
        let windows = AX.windows(pid)
        let facts = windows.map { WindowFacts(id: AX.windowID($0), title: AX.title($0), size: AX.size($0), standard: AX.isStandardWindow($0)) }
        if let index = browser ? (windows.isEmpty ? nil : 0) : callWindow(facts, appName: app.localizedName) {
            AX.focus(windows[index], pid: pid)
        } else {
            app.activate()
        }
    }

    struct WindowFacts: Equatable {
        var id: CGWindowID?
        var title: String?
        var size: CGSize?
        var standard: Bool
    }

    /// Which of an app's windows holds its call: the newest standard window big enough for one, other than the window
    /// named after the app, which is its main window. The newest is the one the call opened, like Telegram's call
    /// behind its chat list. The front window when none qualifies.
    static func callWindow(_ windows: [WindowFacts], appName: String?) -> Int? {
        let candidates = windows.indices.filter { index in
            let window = windows[index]
            guard window.standard, let size = window.size, size.width >= 300, size.height >= 300 else { return false }
            return appName == nil || window.title != appName
        }
        return candidates.max { (windows[$0].id ?? 0) < (windows[$1].id ?? 0) } ?? (windows.isEmpty ? nil : 0)
    }

    // MARK: When nothing matched

    /// Writes the labels the app shows to ~/Library/Logs/SAVISUL/call-controls.txt, so the phrases can be taught to match it.
    /// Only pressable controls of the app on the call, only after a control failed, replaced each time.
    @MainActor
    private static func record(_ action: Action, pid: pid_t, bundle: String) {
        DispatchQueue.global(qos: .utility).async {
            let name = switch action { case .microphone: "microphone"; case .camera: "camera"; case .hangUp: "hang up" }
            var lines = ["\(Date()) \(bundle) \(name): nothing matched"]
            var pages: [AXUIElement] = []
            for window in AX.windows(pid) {
                walk(window, pages: &pages) { element, label in
                    lines.append("\(AX.role(element) ?? "?")\t\(label)")
                    return lines.count > 400
                }
            }
            for page in pages {
                for element in pressable(onPage: page).prefix(300) {
                    for label in labels(element) { lines.append("web \(AX.role(element) ?? "?")\t\(label)") }
                }
            }
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SAVISUL", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? lines.joined(separator: "\n").write(to: folder.appendingPathComponent("call-controls.txt"), atomically: true, encoding: .utf8)
        }
    }
}

/// The tab of a call in a browser, found by the meeting sites' addresses and made the current tab of its window,
/// without bringing the browser forward. macOS asks once whether SAVISUL may control the browser.
enum CallTabs {
    static let sites = ["meet.google.com", "zoom.us/wc", "zoom.us/j/", "app.zoom.us", "teams.microsoft.com", "teams.live.com",
                        "telemost.yandex", "telemost.360.yandex", "whereby.com", "meet.jit.si", "webex.com", "discord.com/channels",
                        "web.telegram.org", "web.whatsapp.com", "app.slack.com/huddle", "facetime.apple.com"]

    private static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    private static let chromium: Set<String> = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
                                                "org.chromium.Chromium", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev",
                                                "com.brave.Browser", "com.brave.Browser.beta", "com.vivaldi.Vivaldi", "ru.yandex.desktop.yandex-browser"]

    static func isCallPage(_ url: String) -> Bool {
        let lower = url.lowercased()
        return sites.contains { lower.contains($0) }
    }

    @MainActor
    static func select(bundle: String) -> Bool {
        let condition = sites.map { "URL of t contains \"\($0)\"" }.joined(separator: " or ")
        let body: String
        if safari.contains(bundle) {
            body = """
            repeat with w in windows
                repeat with t in tabs of w
                    if \(condition) then
                        set current tab of w to t
                        return true
                    end if
                end repeat
            end repeat
            """
        } else if chromium.contains(bundle) {
            body = """
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    if \(condition) then
                        set active tab index of w to i
                        return true
                    end if
                end repeat
            end repeat
            """
        } else {
            return false
        }
        let source = "tell application id \"\(bundle)\"\n\(body)\nend tell\nreturn false"
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error).booleanValue == true
    }

    /// Brings the browser forward on the call's tab.
    @MainActor
    static func open(bundle: String, app: NSRunningApplication) {
        _ = select(bundle: bundle)
        CallControls.bringForward(app, browser: true)
    }
}
