import AppKit
import Foundation

/// How Claude Code's hooks reach the running SAVISUL: distributed notifications, which need no server or port.
enum AgentHookNote {
    static let permission = Notification.Name("com.savisul.agent.permission")
    static let reply = Notification.Name("com.savisul.agent.permission.reply")
    static let attention = Notification.Name("com.savisul.agent.attention")
}

/// `SAVISUL --agent-hook`: what Claude Code runs for its PermissionRequest and Notification hooks.
/// A permission request goes to the island, and this waits for the Allow or Deny pressed there and prints Claude Code's
/// decision. With SAVISUL closed, or no answer in time, it prints nothing, and Claude Code asks in the terminal as usual.
enum AgentHook {
    private final class Answer: @unchecked Sendable {
        var decision: String?
    }

    static func run() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = input["hook_event_name"] as? String else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.savisul.menu").contains(where: { $0.processIdentifier != me })
        else { return }
        let project = (input["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        let center = DistributedNotificationCenter.default()
        switch event {
        case "PermissionRequest":
            let id = UUID().uuidString
            let tool = input["tool_name"] as? String ?? "Tool"
            let answer = Answer()
            let observer = center.addObserver(forName: AgentHookNote.reply, object: id, queue: nil) { note in
                answer.decision = note.userInfo?["decision"] as? String
            }
            center.postNotificationName(AgentHookNote.permission, object: id,
                                        userInfo: ["tool": tool, "summary": describe(tool: tool, input: input["tool_input"] as? [String: Any] ?? [:]),
                                                   "project": project],
                                        deliverImmediately: true)
            let deadline = Date().addingTimeInterval(110)
            while answer.decision == nil, Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
            }
            center.removeObserver(observer)
            guard let decision = answer.decision, decision == "allow" || decision == "deny" else { return }
            var verdict: [String: Any] = ["behavior": decision]
            if decision == "deny" { verdict["message"] = "Declined in the SAVISUL island." }
            let output = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": verdict]]
            if let json = try? JSONSerialization.data(withJSONObject: output) { FileHandle.standardOutput.write(json) }
        case "Notification":
            center.postNotificationName(AgentHookNote.attention, object: nil,
                                        userInfo: ["message": input["message"] as? String ?? "", "project": project],
                                        deliverImmediately: true)
        default:
            return
        }
    }

    /// One line on what the tool is about to touch: the command, the file, the address or the search.
    static func describe(tool: String, input: [String: Any]) -> String {
        if let command = input["command"] as? String { return command }
        for key in ["file_path", "notebook_path", "path"] {
            if let path = input[key] as? String { return URL(fileURLWithPath: path).lastPathComponent }
        }
        if let url = input["url"] as? String { return url }
        if let pattern = input["pattern"] as? String { return pattern }
        if let query = input["query"] as? String { return query }
        return tool
    }
}

/// The running side: Claude Code's questions arrive here and go to the island, with the panda and the buttons.
@MainActor
final class AgentApprovals {
    private var observers: [NSObjectProtocol] = []
    private var answered: Set<String> = []

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: AgentHookNote.permission, object: nil, queue: .main) { note in
            let id = note.object as? String
            let info = note.userInfo as? [String: String] ?? [:]
            MainActor.assumeIsolated {
                guard let id else { return }
                Suite.shared.agentAsks(id: id, tool: info["tool"] ?? "Claude", summary: info["summary"] ?? "", project: info["project"] ?? "")
            }
        })
        observers.append(center.addObserver(forName: AgentHookNote.attention, object: nil, queue: .main) { note in
            let info = note.userInfo as? [String: String] ?? [:]
            MainActor.assumeIsolated {
                Suite.shared.agentNeedsYou(message: info["message"] ?? "", project: info["project"] ?? "")
            }
        })
    }

    func reply(_ id: String, _ decision: String) {
        guard !answered.contains(id) else { return }
        answered.insert(id)
        DistributedNotificationCenter.default().postNotificationName(AgentHookNote.reply, object: id, userInfo: ["decision": decision],
                                                                    deliverImmediately: true)
    }
}

/// Adds SAVISUL's hook to Claude Code's user settings (~/.claude/settings.json), or takes it out again. Only entries
/// that run SAVISUL's own `--agent-hook` are touched; everything else in the file stays as it was, and the first
/// change keeps a copy of the original next to it.
enum ClaudeHooks {
    static let marker = "--agent-hook"
    static let events = ["PermissionRequest", "Notification"]

    static var file: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }

    static var command: String {
        "'\((Bundle.main.executablePath ?? "/Applications/SAVISUL.app/Contents/MacOS/SAVISUL").replacingOccurrences(of: "'", with: "'\\''"))' \(marker)"
    }

    static func sync(enabled: Bool) {
        let command = command
        DispatchQueue.global(qos: .utility).async {
            let url = file
            let exists = FileManager.default.fileExists(atPath: url.path)
            var settings: [String: Any] = [:]
            if exists {
                // A file this can't read as plain JSON is left alone rather than rewritten.
                guard let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                settings = object
            } else if !enabled {
                return
            }
            guard let updated = merged(settings, enabled: enabled, command: command),
                  let data = try? JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys]) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let backup = url.appendingPathExtension("savisul-backup")
            if exists, !FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.copyItem(at: url, to: backup) }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// The settings with SAVISUL's hook added or taken out; nil when they already are as asked.
    static func merged(_ settings: [String: Any], enabled: Bool, command: String) -> [String: Any]? {
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var changed = false
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let ours = groups.contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) == true }
            }
            if enabled && !ours {
                var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": event == "PermissionRequest" ? 120 : 10]]]
                if event == "PermissionRequest" { group["matcher"] = "*" }
                groups.append(group)
                changed = true
            } else if !enabled && ours {
                groups = groups.compactMap { group in
                    let kept = (group["hooks"] as? [[String: Any]] ?? []).filter { ($0["command"] as? String)?.contains(marker) != true }
                    guard !kept.isEmpty else { return nil }
                    var group = group
                    group["hooks"] = kept
                    return group
                }
                changed = true
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        guard changed else { return nil }
        var updated = settings
        updated["hooks"] = hooks.isEmpty ? nil : hooks
        return updated
    }
}

enum PandaPhrases {
    static let asks = Phrase("Claude asks to use %@", ru: "Claude просит: %@", uk: "Claude просить: %@", fr: "Claude demande : %@")
    static let allow = Phrase("Allow", ru: "Разрешить", uk: "Дозволити", fr: "Autoriser")
    static let deny = Phrase("Deny", ru: "Отклонить", uk: "Відхилити", fr: "Refuser")
    static let waiting = Phrase("Claude is waiting for you", ru: "Claude ждёт вас", uk: "Claude чекає на вас", fr: "Claude vous attend")
    static let companion = Phrase("Your panda: it types along with agents, dances to music and sleeps at night",
                                  ru: "Ваша панда: печатает вместе с агентами, танцует под музыку и спит ночью",
                                  uk: "Ваша панда: друкує разом з агентами, танцює під музику й спить уночі",
                                  fr: "Votre panda : il tape avec les agents, danse sur la musique et dort la nuit")
}
