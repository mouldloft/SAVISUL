import Foundation
import Testing
@testable import SAVISUL

struct AgentHooksTests {
    @Test func saysWhatTheToolIsAboutToTouch() {
        #expect(AgentHook.describe(tool: "Bash", input: ["command": "rm -rf build"]) == "rm -rf build")
        #expect(AgentHook.describe(tool: "Edit", input: ["file_path": "/tmp/project/App.swift"]) == "App.swift")
        #expect(AgentHook.describe(tool: "WebFetch", input: ["url": "https://example.com"]) == "https://example.com")
        #expect(AgentHook.describe(tool: "Task", input: [:]) == "Task")
    }

    @Test func addsAndTakesOutOnlySAVISULsHook() throws {
        let command = "'/Applications/SAVISUL.app/Contents/MacOS/SAVISUL' --agent-hook"
        let original: [String: Any] = ["model": "opus", "hooks": ["Notification": [["hooks": [["type": "command", "command": "say done"]]]]]]
        let added = try #require(ClaudeHooks.merged(original, enabled: true, command: command))
        #expect(added["model"] as? String == "opus")
        let hooks = try #require(added["hooks"] as? [String: Any])
        #expect((hooks["PermissionRequest"] as? [[String: Any]])?.count == 1)
        #expect((hooks["Notification"] as? [[String: Any]])?.count == 2)
        #expect(ClaudeHooks.merged(added, enabled: true, command: command) == nil)
        let removed = try #require(ClaudeHooks.merged(added, enabled: false, command: command))
        let left = try #require(removed["hooks"] as? [String: Any])
        #expect(left["PermissionRequest"] == nil)
        #expect((left["Notification"] as? [[String: Any]])?.count == 1)
        #expect(ClaudeHooks.merged(original, enabled: false, command: command) == nil)
    }
}
