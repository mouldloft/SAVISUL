import AppKit
import SwiftUI

/// Panel renders (--dump-panels): the closed and peeking island in its live states, over sample data held in memory,
/// as panels-island-<state>.png. Nothing is listened to: the call, the agent and the device are made up.
@MainActor
enum IslandStatesRender {
    private struct Shot {
        let name: String
        let setup: @MainActor (Suite) -> Void
    }

    static func dump(to folder: URL, completion: @escaping () -> Void) {
        let suite = Suite.shared
        let model = suite.island
        let zoom = sampleCall()
        var agent = AgentStatus(kind: .codex)
        agent.installed = true
        agent.working = true
        agent.since = Date().addingTimeInterval(-(4 * 60 + 12))
        agent.project = "api-server"
        agent.model = "gpt-6"
        let reset: @MainActor (Suite) -> Void = { suite in
            suite.island.dismissNotice()
            suite.island.endHUD()
            suite.micMuted = false
            suite.calls.preview(nil)
            suite.agents.preview([])
            suite.island.mode = .collapsed
        }
        let shots: [Shot] = [
            Shot(name: "call") { suite in
                reset(suite)
                suite.calls.preview(zoom)
                suite.agents.preview([agent])
            },
            Shot(name: "call-muted") { suite in
                reset(suite)
                suite.calls.preview(zoom)
                suite.micMuted = true
            },
            Shot(name: "call-start") { suite in
                reset(suite)
                suite.calls.preview(zoom)
                suite.island.post(IslandNotice(symbol: "phone.fill", tint: Palette.positive, title: Phrases.onCall(zoom.name),
                                               detail: Phrases.muteHint.text, image: zoom.appPath.map { NSWorkspace.shared.icon(forFile: $0) },
                                               style: .success, duration: 60, actionTitle: Phrases.mute.text, action: {}))
            },
            Shot(name: "volume") { suite in
                reset(suite)
                suite.island.show(hud: IslandHUD(symbol: "airpodspro", title: "AirPods Pro", level: 0.62, muted: false))
            },
            Shot(name: "airpods") { suite in
                reset(suite)
                suite.island.post(IslandNotice(symbol: "airpodspro", tint: Palette.positive, title: "AirPods Pro",
                                               detail: SoundPhrases.connectedPlaying.text, style: .success, level: 0.5, duration: 60))
            },
            Shot(name: "call-tab") { suite in
                reset(suite)
                suite.calls.preview(zoom)
                suite.island.expand(.call)
            },
            Shot(name: "call-tab-muted") { suite in
                reset(suite)
                suite.calls.preview(zoom)
                suite.micMuted = true
                suite.island.expand(.call)
            },
            Shot(name: "home-call") { suite in
                reset(suite)
                suite.calls.preview(zoom)
                suite.island.expand(.home)
            },
            Shot(name: "agent-start") { suite in
                reset(suite)
                suite.agents.preview([agent])
                suite.island.post(IslandNotice(symbol: AgentKind.codex.symbol, tint: AgentKind.codex.tint, title: Phrases.agentWorking(AgentKind.codex.short),
                                               detail: "api-server · gpt-6", duration: 60))
            }
        ]
        let size = IslandController.panelSize
        let content = IslandRoot(suite: suite, model: model)
            .environment(\.colorScheme, .dark)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.orderFrontRegardless()

        func shoot(_ index: Int) {
            guard index < shots.count else {
                reset(suite)
                window.orderOut(nil)
                completion()
                return
            }
            shots[index].setup(suite)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                MainActor.assumeIsolated {
                    if let view = window.contentView {
                        view.layoutSubtreeIfNeeded()
                        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                            view.cacheDisplay(in: view.bounds, to: bitmap)
                            try? bitmap.representation(using: .png, properties: [:])?
                                .write(to: folder.appendingPathComponent("panels-island-\(shots[index].name).png"))
                        }
                    }
                    shoot(index + 1)
                }
            }
        }
        shoot(0)
    }

    /// A call drawn with the island's own phone glyph: renders don't carry another company's logo.
    private static func sampleCall() -> CallMonitor.Call {
        CallMonitor.Call(bundle: "us.zoom.xos", name: "Zoom", appPath: nil, browser: false,
                         since: Date().addingTimeInterval(-(23 * 60 + 41)), camera: true)
    }
}
