import AppKit
import SwiftUI

/// Panel renders (--dump-panels): the island's Agents tab over sample agents held in memory, as panels-island-agents.png.
/// The size is the tab's content area in an expanded island (640 x 232), so the render drops into a capture 1:1.
@MainActor
enum IslandAgentsRender {
    static func dump(to folder: URL, completion: @escaping () -> Void) {
        let suite = Suite.shared
        suite.agents.preview(samples())
        let size = NSSize(width: 640, height: 232)
        let content = IslandAgents(suite: suite)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated {
                if let view = window.contentView {
                    view.layoutSubtreeIfNeeded()
                    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("panels-island-agents.png"))
                    }
                }
                window.orderOut(nil)
                completion()
            }
        }
    }

    private static func samples() -> [AgentStatus] {
        let now = Date()
        func files(_ count: Int, _ tag: String) -> Set<String> { Set((0..<count).map { "\(tag)\($0)" }) }

        var claude = AgentStatus(kind: .claude)
        claude.installed = true
        claude.working = true
        claude.since = now.addingTimeInterval(-(12 * 60 + 13))
        claude.lastActive = now
        claude.project = "savisul-site"
        claude.model = "Opus 5.5"
        claude.task = "Polish the hero animation"
        claude.tokensToday = 1_240_000
        claude.costToday = 14.62
        claude.code = CodeTally(added: 1_284, removed: 96, created: files(3, "c"), edited: files(9, "e"))
        claude.limits = [AgentLimit(window: .minutes(300), tokens: 612_000), AgentLimit(window: .days(7), tokens: 5_400_000)]

        var cursor = AgentStatus(kind: .cursor)
        cursor.installed = true
        cursor.lastActive = now.addingTimeInterval(-26 * 60)
        cursor.project = "mobile-app"
        cursor.model = "Sonnet 5.5"
        cursor.code = CodeTally(added: 693, removed: 12, created: files(1, "c"), edited: files(4, "e"))

        var codex = AgentStatus(kind: .codex)
        codex.installed = true
        codex.plan = "Plus"
        codex.lastActive = now.addingTimeInterval(-(2 * 3600 + 10 * 60))
        codex.project = "api-server"
        codex.model = "gpt-6"
        codex.tokensToday = 214_000
        codex.limits = [AgentLimit(window: .minutes(300), used: 0.18), AgentLimit(window: .days(7), used: 0.34)]

        var copilot = AgentStatus(kind: .copilot)
        copilot.installed = true
        copilot.lastActive = now.addingTimeInterval(-5 * 3600)
        copilot.project = "design-system"
        copilot.model = "gpt-5.5"
        copilot.code = CodeTally(added: 120, removed: 18, edited: files(2, "e"))

        return [claude, cursor, codex, copilot]
    }
}
