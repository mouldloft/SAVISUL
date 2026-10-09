import AppKit
import Observation

/// Follows Claude Code, Codex, Cursor, OpenCode and Copilot through the logs they write on disk:
/// whether they are working, on which project and model, how many tokens today, and their limits.
@MainActor
@Observable
final class AgentMonitor {
    private(set) var agents: [AgentStatus] = AgentKind.allCases.map { AgentStatus(kind: $0) }
    private(set) var recent: [AgentFinish] = []
    private(set) var ready = false

    @ObservationIgnored var onFinish: ((AgentFinish) -> Void)?
    /// An agent started working after a quiet spell, not each time it takes a new turn.
    @ObservationIgnored var onStart: ((AgentStatus) -> Void)?
    @ObservationIgnored private var lastWorking: [AgentKind: Date] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let scanner = AgentScanner()
    @ObservationIgnored private var busy = false

    var installed: [AgentStatus] { agents.filter(\.installed) }
    var working: [AgentStatus] { agents.filter(\.working) }
    var tokensToday: Int { agents.reduce(0) { $0 + $1.tokensToday } }

    func tokens(week: Bool) -> Int { agents.reduce(0) { $0 + (week ? $1.tokensWeek : $1.tokensToday) } }

    func code(week: Bool) -> CodeTally {
        agents.reduce(into: CodeTally()) { $0.add(week ? $1.codeWeek : $1.code) }
    }

    /// Everything the agents did inside one editor (or the terminal), today or over the week.
    func usage(_ surface: AgentSurface, week: Bool) -> SurfaceUsage {
        agents.reduce(into: SurfaceUsage()) { total, agent in
            if let usage = (week ? agent.surfacesWeek : agent.surfaces)[surface] { total.add(usage) }
        }
    }

    /// Panel renders (--dump-panels) show sample agents held in memory: no logs are read.
    func preview(_ sample: [AgentStatus]) {
        agents = sample
        ready = true
    }

    func start() {
        guard timer == nil else { return }
        scan(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan(initial: false) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func status(_ kind: AgentKind) -> AgentStatus {
        agents.first { $0.kind == kind } ?? AgentStatus(kind: kind)
    }

    private func scan(initial: Bool) {
        guard !busy else { return }
        busy = true
        scanner.scan(initial: initial) { [weak self] statuses, finishes in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.busy = false
                self.ready = true
                let now = Date()
                for status in statuses where status.working {
                    let quiet = self.lastWorking[status.kind].map { now.timeIntervalSince($0) > 120 } ?? true
                    if !initial && quiet { self.onStart?(status) }
                    self.lastWorking[status.kind] = now
                }
                if statuses != self.agents { self.agents = statuses }
                for finish in finishes {
                    self.recent.insert(finish, at: 0)
                    self.onFinish?(finish)
                }
                if self.recent.count > 8 { self.recent = Array(self.recent.prefix(8)) }
            }
        }
    }
}

final class AgentScanner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.savisul.agents", qos: .utility)
    private let readers: [AgentReader] = [ClaudeReader(), CodexReader(), CursorReader(), OpenCodeReader(), CopilotReader()]

    func scan(initial: Bool, completion: @escaping @Sendable ([AgentStatus], [AgentFinish]) -> Void) {
        queue.async { [readers] in
            let now = Date()
            var statuses: [AgentStatus] = []
            var finishes: [AgentFinish] = []
            for reader in readers {
                let (status, finished) = reader.scan(now: now, initial: initial)
                statuses.append(status)
                finishes.append(contentsOf: finished)
            }
            let order = AgentKind.allCases
            statuses.sort { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
            DispatchQueue.main.async { completion(statuses, finishes) }
        }
    }
}

/// `SAVISUL --agent-report`: what every reader sees right now, to check the numbers against the logs.
enum AgentReport {
    static func print() {
        let readers: [AgentReader] = [ClaudeReader(), CodexReader(), CursorReader(), OpenCodeReader(), CopilotReader()]
        let started = Date()
        for reader in readers {
            let (status, _) = reader.scan(now: Date(), initial: true)
            guard status.installed else {
                Swift.print("\(status.kind): not installed")
                continue
            }
            Swift.print("\(status.kind): working=\(status.working) runs=\(status.runs) model=\(status.model ?? "-") surface=\(status.surface?.rawValue ?? "-")")
            Swift.print("  project=\(status.projectPath ?? "-") lastActive=\(status.lastActive.map { "\(Int(-$0.timeIntervalSinceNow))s ago" } ?? "-")")
            Swift.print("  today: tokens=\(status.tokensToday) cache=\(status.cacheToday) cost=\(status.costToday.map { String(format: "%.2f", $0) } ?? "-") sessions=\(status.sessionsToday)")
            Swift.print("  code today: +\(status.code.added) -\(status.code.removed) new=\(status.code.filesCreated) edited=\(status.code.filesEdited)")
            Swift.print("  week: tokens=\(status.tokensWeek) code=+\(status.codeWeek.added) -\(status.codeWeek.removed) new=\(status.codeWeek.filesCreated)")
            for (surface, usage) in status.surfaces.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                Swift.print("  \(surface.rawValue): tokens=\(usage.tokens) cache=\(usage.cache) model=\(usage.model ?? "-") code=+\(usage.code.added) -\(usage.code.removed) new=\(usage.code.filesCreated)")
            }
        }
        Swift.print(String(format: "scanned in %.2fs", Date().timeIntervalSince(started)))
    }
}
