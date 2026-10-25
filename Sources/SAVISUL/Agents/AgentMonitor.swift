import AppKit
import Observation

/// Follows Claude Code, Codex, Cursor, OpenCode, Copilot and Mould Engine Studio through what they write on disk:
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
    @ObservationIgnored private var studioObserver: NSObjectProtocol?

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
        // Mould Engine Studio says when what it does changes: read at once rather than at the next look.
        studioObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.mouldloft.studio.activity"), object: nil,
                                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStudio() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let studioObserver { DistributedNotificationCenter.default().removeObserver(studioObserver) }
        studioObserver = nil
    }

    func status(_ kind: AgentKind) -> AgentStatus {
        agents.first { $0.kind == kind } ?? AgentStatus(kind: kind)
    }

    /// Studio said what it does now: its reader alone, at once, rather than at the next look, which waits for the other
    /// agents' logs (seconds, with a large Claude session).
    private func refreshStudio() {
        scanner.scanStudio { [weak self] status, finishes in
            MainActor.assumeIsolated {
                guard let self, let index = self.agents.firstIndex(where: { $0.kind == .mould }) else { return }
                let was = self.agents[index]
                if status.working, !was.working {
                    let quiet = self.lastWorking[.mould].map { Date().timeIntervalSince($0) > 120 } ?? true
                    if quiet { self.onStart?(status) }
                }
                if status.working { self.lastWorking[.mould] = Date() }
                if status != was { self.agents[index] = status }
                for finish in finishes {
                    self.recent.insert(finish, at: 0)
                    self.onFinish?(finish)
                }
                if self.recent.count > 8 { self.recent = Array(self.recent.prefix(8)) }
            }
        }
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
    /// Studio's reader keeps a queue of its own, so a look at Studio alone never waits behind the other logs.
    private let studio = MouldReader()
    private let studioQueue = DispatchQueue(label: "com.savisul.agents.studio", qos: .userInitiated)

    func scan(initial: Bool, completion: @escaping @Sendable ([AgentStatus], [AgentFinish]) -> Void) {
        queue.async { [readers, studio, studioQueue] in
            let now = Date()
            var statuses: [AgentStatus] = []
            var finishes: [AgentFinish] = []
            for reader in readers {
                let (status, finished) = reader.scan(now: now, initial: initial)
                statuses.append(status)
                finishes.append(contentsOf: finished)
            }
            let (status, finished) = studioQueue.sync { studio.scan(now: Date(), initial: initial) }
            statuses.append(status)
            finishes.append(contentsOf: finished)
            let order = AgentKind.allCases
            statuses.sort { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
            DispatchQueue.main.async { completion(statuses, finishes) }
        }
    }

    func scanStudio(completion: @escaping @Sendable (AgentStatus, [AgentFinish]) -> Void) {
        studioQueue.async { [studio] in
            let (status, finished) = studio.scan(now: Date(), initial: false)
            DispatchQueue.main.async { completion(status, finished) }
        }
    }
}

/// `SAVISUL --agent-report`: what every reader sees right now, to check the numbers against the logs.
enum AgentReport {
    static func print() {
        let readers: [AgentReader] = [ClaudeReader(), CodexReader(), CursorReader(), OpenCodeReader(), CopilotReader(), MouldReader()]
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

    /// `SAVISUL --agent-watch [seconds]`: the readers kept for as long as the app keeps them, scanned every three seconds
    /// as the island's are, printing each change in what an agent does and every slow scan. For a state the running
    /// app holds that a fresh `--agent-report` doesn't.
    static func watch(seconds: Double) {
        let readers: [AgentReader] = [ClaudeReader(), CodexReader(), CursorReader(), OpenCodeReader(), CopilotReader(), MouldReader()]
        let end = Date().addingTimeInterval(seconds)
        var initial = true
        var shown: [AgentKind: String] = [:]
        var beat = Date()
        func stamp() -> String { ISO8601DateFormatter().string(from: Date()) }
        while Date() < end {
            let started = Date()
            for reader in readers {
                let (status, finished) = reader.scan(now: Date(), initial: initial)
                guard status.installed else { continue }
                let state = "working=\(status.working) runs=\(status.runs) tokens=\(status.tokensToday) model=\(status.model ?? "-")"
                if shown[status.kind] != state || Date().timeIntervalSince(beat) > 30 {
                    let since = status.since.map { "\(Int(-$0.timeIntervalSinceNow))s" } ?? "-"
                    let last = status.lastActive.map { "\(Int(-$0.timeIntervalSinceNow))s ago" } ?? "-"
                    Swift.print("\(stamp()) \(status.kind): \(state) since=\(since) last=\(last)")
                    shown[status.kind] = state
                }
                for finish in finished { Swift.print("\(stamp()) \(finish.kind) finished after \(Int(finish.duration))s") }
            }
            if Date().timeIntervalSince(beat) > 30 { beat = Date() }
            let took = Date().timeIntervalSince(started)
            if took > 1 { Swift.print(String(format: "\(stamp()) slow scan: %.2fs", took)) }
            fflush(stdout)
            initial = false
            Thread.sleep(forTimeInterval: max(0.2, 3 - took))
        }
    }
}
