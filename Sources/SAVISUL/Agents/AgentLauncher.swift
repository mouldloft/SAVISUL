import AppKit
import Observation

/// Starts an AI coding agent on a task in a project folder, from the island's Agents tab.
/// Only agents that are actually installed on this Mac are offered: a command-line tool on the
/// user's PATH, the Codex CLI inside the Codex app, or the Cursor app itself.
@MainActor
@Observable
final class AgentLauncher {
    struct Target: Equatable, Identifiable, Sendable {
        enum Style: Equatable, Sendable {
            /// `tool "prompt"` starts an interactive session with the prompt already sent.
            case argument
            /// `tool --flag "prompt"`, for tools whose help lists such a flag.
            case flag(String)
            /// The tool starts in the folder and the prompt waits on the clipboard.
            case clipboard
            /// No command-line tool: the app opens the folder and the prompt waits on the clipboard.
            case app
        }

        let kind: AgentKind
        let executable: URL
        let style: Style
        var id: AgentKind { kind }
    }

    enum Outcome: Equatable {
        case started(AgentKind, String)
        case pasteReady(AgentKind, String)
        case failed(AgentKind)
    }

    private(set) var targets: [Target] = []
    private(set) var projects: [URL] = []
    private(set) var resolved = false
    var composing = false
    var draft = ""
    var selected: AgentKind?
    var project: URL?

    @ObservationIgnored private var resolving = false
    @ObservationIgnored private var resolvedAt = Date.distantPast
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let recentKey = "agentLauncherProjects"
    @ObservationIgnored private let lastKindKey = "agentLauncherKind"
    /// The folder the user picked themselves. It wins over any guess until they pick another.
    @ObservationIgnored private let chosenKey = "agentLauncherProject"

    var target: Target? { targets.first { $0.kind == selected } ?? targets.first }
    var canSend: Bool { target != nil && project != nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Discovery

    /// Looks for installed agents at most once a minute; the work runs off the main thread.
    func refresh(force: Bool = false) {
        guard !resolving, force || Date().timeIntervalSince(resolvedAt) > 60 else { return }
        resolving = true
        let apps = Self.appBundles()
        DispatchQueue.global(qos: .utility).async {
            let found = Self.resolve(apps: apps)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.targets = found
                    self.resolved = true
                    self.resolving = false
                    self.resolvedAt = Date()
                    if let kind = self.selected, !found.contains(where: { $0.kind == kind }) { self.selected = found.first?.kind }
                }
            }
        }
    }

    /// App bundles are looked up on the main thread, where NSWorkspace is happiest.
    private static func appBundles() -> [AgentKind: URL] {
        var apps: [AgentKind: URL] = [:]
        let workspace = NSWorkspace.shared
        if let codex = workspace.urlsForApplications(withBundleIdentifier: "com.openai.codex").first { apps[.codex] = codex }
        if let cursor = workspace.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") { apps[.cursor] = cursor }
        return apps
    }

    private nonisolated static let tools: [(AgentKind, [String])] = [
        (.claude, ["claude"]), (.codex, ["codex"]), (.cursor, ["cursor-agent", "agent"]), (.opencode, ["opencode"]), (.copilot, ["copilot"])
    ]

    private nonisolated static func resolve(apps: [AgentKind: URL]) -> [Target] {
        let paths = shellPaths(for: tools.flatMap(\.1))
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let fallbackDirs = ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin",
                            "\(home)/.bun/bin", "\(home)/.volta/bin", "\(home)/.opencode/bin", "\(home)/.cargo/bin", "/usr/bin"]
        func locate(_ name: String) -> URL? {
            if let path = paths[name], fm.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
            for dir in fallbackDirs where fm.isExecutableFile(atPath: "\(dir)/\(name)") { return URL(fileURLWithPath: "\(dir)/\(name)") }
            return nil
        }
        var targets: [Target] = []
        for (kind, names) in tools {
            if let tool = names.lazy.compactMap(locate).first {
                targets.append(Target(kind: kind, executable: tool, style: style(for: kind, tool: tool)))
                continue
            }
            if kind == .codex, let app = apps[.codex] {
                let bundled = app.appendingPathComponent("Contents/Resources/codex")
                if fm.isExecutableFile(atPath: bundled.path) { targets.append(Target(kind: .codex, executable: bundled, style: .argument)) }
            } else if kind == .cursor, let app = apps[.cursor] {
                targets.append(Target(kind: .cursor, executable: app, style: .app))
            }
        }
        return targets
    }

    /// GUI apps don't inherit the shell's PATH, so ask the user's login shell where each tool lives.
    private nonisolated static func shellPaths(for names: [String]) -> [String: String] {
        let script = names.map { "p=$(whence -p \($0)) && print -r -- \"\($0)=$p\"" }.joined(separator: "; ")
        guard let output = Shell.run("/bin/zsh", ["-lic", script], timeout: 6) else { return [:] }
        var paths: [String: String] = [:]
        for line in output.text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, names.contains(parts[0]), parts[1].hasPrefix("/") { paths[parts[0]] = parts[1] }
        }
        return paths
    }

    /// Claude Code, Codex and the Cursor agent take the prompt as an argument; the others are checked in their own help.
    private nonisolated static func style(for kind: AgentKind, tool: URL) -> Target.Style {
        switch kind {
        case .claude, .codex, .cursor:
            return .argument
        case .opencode:
            let help = Shell.run(tool.path, ["--help"], timeout: 4)?.text ?? ""
            return help.contains("--prompt") ? .flag("--prompt") : .clipboard
        case .copilot:
            let help = Shell.run(tool.path, ["--help"], timeout: 4)?.text ?? ""
            return help.contains("--interactive") ? .flag("--interactive") : .clipboard
        }
    }

    // MARK: Composer

    func begin(_ kind: AgentKind?, monitor: AgentMonitor) {
        refresh()
        collectProjects(monitor)
        if let kind, targets.contains(where: { $0.kind == kind }) {
            selected = kind
        } else if selected == nil {
            let last = defaults.string(forKey: lastKindKey).flatMap(AgentKind.init(rawValue:))
            selected = targets.first { $0.kind == last }?.kind ?? targets.first?.kind
        }
        project = preferredProject(monitor)
        composing = true
    }

    /// The user's own pick first, then the folder the selected agent last worked in, then the newest recent one.
    private func preferredProject(_ monitor: AgentMonitor) -> URL? {
        if let chosen = defaults.string(forKey: chosenKey), isProject(chosen) { return URL(fileURLWithPath: chosen) }
        if let project, isProject(project.path) { return project }
        if let kind = selected, let path = monitor.status(kind).projectPath, isProject(path) { return URL(fileURLWithPath: path) }
        return projects.first
    }

    /// Picking a folder, from the menu or the folder panel, sticks across agents, sessions and relaunches.
    func pick(_ url: URL) {
        project = url
        defaults.set(url.path, forKey: chosenKey)
        remember(url)
    }

    /// False when the chosen folder was moved or deleted since; the composer then asks for a new one.
    var projectExists: Bool { project.map { isProject($0.path) } ?? false }

    func cancel() {
        composing = false
    }

    func chooseFolder(done: @escaping () -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = AgentPhrases.choose.text
        panel.message = AgentPhrases.chooseMessage.text
        if let project { panel.directoryURL = project.deletingLastPathComponent() }
        NSApp.activate()
        panel.begin { [weak self] response in
            MainActor.assumeIsolated {
                if response == .OK, let url = panel.url { self?.pick(url) }
                done()
            }
        }
    }

    /// Starts the selected agent on the draft in the chosen folder.
    func send() -> Outcome? {
        guard let target, let project else { return nil }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }
        let name = project.lastPathComponent
        defaults.set(target.kind.rawValue, forKey: lastKindKey)
        remember(project)
        let outcome: Outcome
        switch target.style {
        case .app:
            copy(prompt)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([project], withApplicationAt: target.executable, configuration: configuration) { _, _ in }
            outcome = .pasteReady(target.kind, name)
        case .clipboard:
            copy(prompt)
            outcome = runInTerminal(target, prompt: nil, in: project) ? .pasteReady(target.kind, name) : .failed(target.kind)
        case .argument, .flag:
            outcome = runInTerminal(target, prompt: prompt, in: project) ? .started(target.kind, name) : .failed(target.kind)
        }
        if case .failed = outcome { return outcome }
        draft = ""
        composing = false
        return outcome
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Writes a one-shot .command script and opens it, which starts a new Terminal window
    /// (or whatever app the user set for .command files) without any automation permission.
    private func runInTerminal(_ target: Target, prompt: String?, in folder: URL) -> Bool {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVISUL/Agent Runs", isDirectory: true)
        do { try fm.createDirectory(at: support, withIntermediateDirectories: true) } catch { return false }
        prune(support)
        var command = [quote(target.executable.path)]
        if let prompt {
            if case .flag(let flag) = target.style { command.append(flag) } else if prompt.hasPrefix("-") { command.append("--") }
            command.append(quote(prompt))
        }
        let title = "\(target.kind.title) · \(folder.lastPathComponent)"
        let script = """
        #!/bin/zsh -l
        # Started from the SAVISUL island. Safe to delete.
        cd -- \(quote(folder.path)) || exit 1
        printf '\\033]0;%s\\007' \(quote(title))
        clear
        \(command.joined(separator: " "))
        exec /bin/zsh -l
        """
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let url = support.appendingPathComponent("\(target.kind.rawValue)-\(stamp).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            return false
        }
        let terminal = NSWorkspace.shared.urlForApplication(toOpen: url)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        guard let terminal else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: configuration) { _, _ in }
        return true
    }

    /// Single quotes keep the prompt and the path literal: nothing in them reaches the shell as code.
    private func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func prune(_ folder: URL) {
        let fm = FileManager.default
        let old = Date().addingTimeInterval(-86_400)
        for file in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if file.pathExtension == "command", date < old { try? fm.removeItem(at: file) }
        }
    }

    // MARK: Projects

    private func remember(_ url: URL) {
        var recent = defaults.stringArray(forKey: recentKey) ?? []
        recent.removeAll { $0 == url.path }
        recent.insert(url.path, at: 0)
        defaults.set(Array(recent.prefix(12)), forKey: recentKey)
        collectProjects(nil)
    }

    /// Recent folders: ones used here first, then what the agents are working in, then Claude Code's history.
    private func collectProjects(_ monitor: AgentMonitor?) {
        var paths = defaults.stringArray(forKey: recentKey) ?? []
        if let monitor { paths += monitor.agents.compactMap(\.projectPath) }
        paths += Self.claudeHistoryProjects()
        var seen = Set<String>()
        projects = paths.filter { isProject($0) && seen.insert($0).inserted }.prefix(8).map { URL(fileURLWithPath: $0) }
    }

    private func isProject(_ path: String) -> Bool {
        var directory: ObjCBool = false
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path != home && path != "/" && FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }

    private static func claudeHistoryProjects() -> [String] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/history.jsonl")
        guard let text = LogTail(url).tail(bytes: 200_000) else { return [] }
        let pattern = try! NSRegularExpression(pattern: #""project"\s*:\s*"([^"]{2,400})""#)
        let range = NSRange(text.startIndex..., in: text)
        var ordered: [String] = []
        for match in pattern.matches(in: text, range: range).reversed() {
            guard let value = Range(match.range(at: 1), in: text) else { continue }
            let path = String(text[value]).replacingOccurrences(of: "\\/", with: "/")
            if !ordered.contains(path) { ordered.append(path) }
        }
        return ordered
    }
}

enum AgentPhrases {
    static let newTask = Phrase("New task", ru: "Новая задача", uk: "Нове завдання", fr: "Nouvelle tâche")
    static let send = Phrase("Start", ru: "Запустить", uk: "Запустити", fr: "Lancer")
    static let choose = Phrase("Choose", ru: "Выбрать", uk: "Вибрати", fr: "Choisir")
    static let chooseFolder = Phrase("Choose folder…", ru: "Выбрать папку…", uk: "Вибрати теку…", fr: "Choisir un dossier…")
    static let chooseMessage = Phrase("Choose the project folder the agent should work in.",
                                      ru: "Выберите папку проекта, в которой будет работать агент.",
                                      uk: "Виберіть теку проєкту, в якій працюватиме агент.",
                                      fr: "Choisissez le dossier du projet où l’agent doit travailler.")
    static let noProject = Phrase("Choose a project", ru: "Выберите проект", uk: "Виберіть проєкт", fr: "Choisir un projet")
    static let hint = Phrase("↩ start · ⌥↩ new line · esc close", ru: "↩ запустить · ⌥↩ новая строка · esc закрыть",
                             uk: "↩ запустити · ⌥↩ новий рядок · esc закрити", fr: "↩ lancer · ⌥↩ nouvelle ligne · esc fermer")
    static let pasteNote = Phrase("Opens the app in this folder with your task on the clipboard",
                                  ru: "Откроет приложение в этой папке, а задача будет в буфере",
                                  uk: "Відкриє застосунок у цій теці, а завдання буде в буфері",
                                  fr: "Ouvre l’app dans ce dossier, la tâche est dans le presse-papiers")
    static let close = Phrase("Close", ru: "Закрыть", uk: "Закрити", fr: "Fermer")

    @MainActor static func placeholder(_ name: String) -> String {
        Phrase("Ask %@ or give it a task…", ru: "Спросите %@ или дайте задачу…", uk: "Запитайте %@ або дайте завдання…",
               fr: "Demandez à %@ ou confiez une tâche…")(name)
    }
    @MainActor static func started(_ name: String) -> String {
        Phrase("%@ started", ru: "%@ запущен", uk: "%@ запущено", fr: "%@ lancé")(name)
    }
    @MainActor static func paste(_ name: String) -> String {
        Phrase("%@ is open · task copied", ru: "%@ открыт · задача в буфере", uk: "%@ відкрито · завдання в буфері",
               fr: "%@ est ouvert · tâche copiée")(name)
    }
    @MainActor static func failed(_ name: String) -> String {
        Phrase("Couldn’t start %@", ru: "Не удалось запустить %@", uk: "Не вдалося запустити %@", fr: "Impossible de lancer %@")(name)
    }
}
