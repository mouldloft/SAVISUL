import AppKit

/// The panda's own voice: a short sound for each mood, played as it brings a notice. It stays quiet during calls,
/// never talks over itself, and can be turned off in Features → Island → Panda sounds.
@MainActor
enum PandaVoice {
    private static var sounds: [String: NSSound] = [:]
    private static var last = Date.distantPast

    /// The sound for a mood, a file in the app's resources; the working panda types along without one.
    nonisolated static func resource(for mood: PandaMood) -> String? {
        switch mood {
        case .done: "panda-happy"
        case .ask: "panda-ask"
        case .limit: "panda-sad"
        case .alarm: "panda-alarm"
        case .sleepy: "panda-sleepy"
        case .hello: "panda-hello"
        case .dance: "panda-giggle"
        case .working: nil
        }
    }

    /// Whether the panda would speak right now, so the system chime it replaces can stay quiet.
    static var speaks: Bool {
        let suite = Suite.shared
        return suite.app != nil && suite.settings.islandPanda && suite.settings.pandaSounds && suite.calls.current == nil
    }

    static func speak(_ mood: PandaMood) {
        guard speaks, Date().timeIntervalSince(last) > 1.2, let name = resource(for: mood) else { return }
        let sound = sounds[name] ?? Bundle.main.url(forResource: name, withExtension: "m4a").flatMap { NSSound(contentsOf: $0, byReference: true) }
        guard let sound else { return }
        sounds[name] = sound
        last = Date()
        sound.stop()
        sound.volume = 0.55
        sound.play()
    }
}
