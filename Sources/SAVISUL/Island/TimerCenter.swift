import AppKit
import Observation

struct IslandTimer: Identifiable, Codable, Equatable {
    var id = UUID()
    var label: String
    var total: Double
    var endsAt: Date?
    var pausedRemaining: Double?
    var ringing = false

    var running: Bool { endsAt != nil }

    func remaining(at date: Date = Date()) -> Double {
        if let endsAt { return max(endsAt.timeIntervalSince(date), 0) }
        return pausedRemaining ?? 0
    }

    func progress(at date: Date = Date()) -> Double {
        total > 0 ? 1 - remaining(at: date) / total : 1
    }
}

/// Countdown timers shown in the island. They survive relaunches because only end dates are stored.
@MainActor
@Observable
final class TimerCenter {
    private(set) var timers: [IslandTimer] = []
    @ObservationIgnored var onFinish: ((IslandTimer) -> Void)?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var sound: NSSound?
    @ObservationIgnored private var rings = 0

    static let presets: [Double] = [1, 3, 5, 10, 15, 25, 45, 60]

    private let persist: Bool

    init(persist: Bool = true) {
        self.persist = persist
        if persist, let data = UserDefaults.standard.data(forKey: "suite.timers"),
           let saved = try? JSONDecoder().decode([IslandTimer].self, from: data) {
            timers = saved.map { var timer = $0; timer.ringing = false; return timer }
        }
    }

    var nearest: IslandTimer? {
        timers.filter { $0.ringing }.first
            ?? timers.filter(\.running).min { $0.remaining() < $1.remaining() }
            ?? timers.first { $0.pausedRemaining != nil }
    }

    var hasActive: Bool { timers.contains { $0.running || $0.ringing || $0.pausedRemaining != nil } }

    func start() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    func add(minutes: Double, label: String? = nil) {
        let seconds = minutes * 60
        let name = label ?? Self.label(for: seconds)
        timers.append(IslandTimer(label: name, total: seconds, endsAt: Date().addingTimeInterval(seconds)))
        save()
    }

    func pause(_ id: UUID) {
        update(id) { timer in
            timer.pausedRemaining = timer.remaining()
            timer.endsAt = nil
        }
    }

    func resume(_ id: UUID) {
        update(id) { timer in
            timer.endsAt = Date().addingTimeInterval(timer.pausedRemaining ?? 0)
            timer.pausedRemaining = nil
        }
    }

    func toggle(_ id: UUID) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        if timer.ringing { dismiss(id) } else if timer.running { pause(id) } else { resume(id) }
    }

    func extend(_ id: UUID, minutes: Double = 1) {
        update(id) { timer in
            if let endsAt = timer.endsAt {
                timer.endsAt = endsAt.addingTimeInterval(minutes * 60)
            } else if timer.ringing {
                timer.ringing = false
                timer.endsAt = Date().addingTimeInterval(minutes * 60)
            } else {
                timer.pausedRemaining = (timer.pausedRemaining ?? 0) + minutes * 60
            }
            timer.total += minutes * 60
        }
        stopSound()
    }

    func cancel(_ id: UUID) {
        timers.removeAll { $0.id == id }
        if !timers.contains(where: \.ringing) { stopSound() }
        save()
    }

    func dismiss(_ id: UUID) { cancel(id) }

    private func update(_ id: UUID, _ change: (inout IslandTimer) -> Void) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        change(&timers[index])
        save()
    }

    func tick(now: Date = Date(), sound: Bool = true) {
        for index in timers.indices where timers[index].running && timers[index].remaining(at: now) <= 0 {
            timers[index].endsAt = nil
            timers[index].pausedRemaining = nil
            timers[index].ringing = true
            if sound { ring() }
            onFinish?(timers[index])
            save()
        }
    }

    private func ring() {
        rings = 0
        playOnce()
    }

    private func playOnce() {
        guard timers.contains(where: \.ringing), rings < 6 else { return }
        rings += 1
        sound = NSSound(named: NSSound.Name("Glass"))
        sound?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            MainActor.assumeIsolated { self?.playOnce() }
        }
    }

    private func stopSound() {
        rings = 99
        sound?.stop()
    }

    private func save() {
        guard persist else { return }
        let kept = timers.filter { !$0.ringing }
        if let data = try? JSONEncoder().encode(kept) { UserDefaults.standard.set(data, forKey: "suite.timers") }
    }

    static func label(for seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes >= 60, minutes % 60 == 0 {
            return Phrase("%d h", ru: "%d ч", uk: "%d год", fr: "%d h")(minutes / 60)
        }
        return Phrase("%d min", ru: "%d мин", uk: "%d хв", fr: "%d min")(minutes)
    }
}
