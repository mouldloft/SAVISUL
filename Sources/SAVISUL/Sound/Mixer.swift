import AppKit
import CoreAudio
import Observation

/// Per-app volume, boost and output. Apps left at 100 % on the system output are never touched;
/// the others are tapped and replayed with their own gain to their own device.
@MainActor
@Observable
final class Mixer {
    struct App: Identifiable, Equatable {
        var id: String
        var name: String
        var path: String?
        var objects: [AudioObjectID]
        var playing: Bool
        var lastHeard: Date
    }

    struct Rule: Codable, Equatable {
        var volume: Double = 1
        var muted = false
        var output: String?

        var isDefault: Bool { abs(volume - 1) < 0.005 && !muted && output == nil }
    }

    private(set) var apps: [App] = []
    private(set) var rules: [String: Rule] = [:]
    private(set) var permission: AudioCapturePermission.State = AudioCapturePermission.state
    private(set) var peaks: [String: Float] = [:]
    private(set) var failure: String?
    private(set) var active = false

    @ObservationIgnored var onLevels: (([Float]) -> Void)?
    @ObservationIgnored private var engines: [String: TapEngine] = [:]
    @ObservationIgnored private var analysis: TapEngine?
    @ObservationIgnored private var analysisPID: pid_t = 0
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private let analyzer = SpectrumAnalyzer()
    @ObservationIgnored private var failedKeys: [String: Date] = [:]
    @ObservationIgnored var metering = false { didSet { updateMeterTimer() } }
    @ObservationIgnored private var spectrumKey = ""
    @ObservationIgnored private var sampleRate: Double = 48_000
    @ObservationIgnored var spectrumFor: pid_t = 0 {
        didSet {
            guard spectrumFor != oldValue else { return }
            spectrumKey = spectrumFor > 0 ? (RunningApps.bundlePath(pid: spectrumFor) ?? "pid:\(spectrumFor)") : ""
            sampleRate = CA.value(CA.defaultDevice(input: false), kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, Float64(48_000))
            reconcileAnalysis()
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "suite.mixerRules"),
           let saved = try? JSONDecoder().decode([String: Rule].self, from: data) {
            rules = saved
        }
    }

    func start() {
        guard !active else { return }
        active = true
        permission = AudioCapturePermission.state
        if permission == .unknown { requestPermission() }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        updateMeterTimer()
    }

    func stop() {
        active = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        engines.values.forEach { $0.teardown() }
        engines = [:]
        analysis?.teardown()
        analysis = nil
        updateMeterTimer()
    }

    func requestPermission() {
        if permission == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
            return
        }
        AudioCapturePermission.request { granted in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let mixer = Suite.shared.mixer
                    mixer.permission = granted ? .granted : AudioCapturePermission.state
                    mixer.failedKeys = [:]
                    mixer.reconcile()
                }
            }
        }
    }

    func rule(_ app: App) -> Rule { rules[app.id] ?? Rule() }

    func setVolume(_ volume: Double, for app: App) {
        update(app) { $0.volume = min(max(volume, 0), 2) }
    }

    func toggleMute(_ app: App) {
        update(app) { $0.muted.toggle() }
    }

    func setOutput(_ uid: String?, for app: App) {
        update(app) { $0.output = uid }
    }

    func reset(_ app: App) {
        rules[app.id] = nil
        save()
        reconcile()
    }

    private func update(_ app: App, _ change: (inout Rule) -> Void) {
        var rule = rules[app.id] ?? Rule()
        change(&rule)
        rules[app.id] = rule.isDefault ? nil : rule
        save()
        if let engine = engines[app.id] {
            let output = resolvedOutput(rule)
            if engine.outputUID == output, Set(engine.processes) == Set(app.objects) {
                engine.gain = rule.muted ? 0 : Float(rule.volume)
                if rule.isDefault { reconcile() }
                return
            }
        }
        failedKeys[app.id] = nil
        reconcile()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(data, forKey: "suite.mixerRules") }
    }

    /// Default output changed or a device came or went: rebuild engines whose target moved.
    func devicesChanged() {
        sampleRate = CA.value(CA.defaultDevice(input: false), kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, Float64(48_000))
        for (key, engine) in engines {
            let output = resolvedOutput(rules[key] ?? Rule())
            if engine.outputUID != output {
                engine.teardown()
                engines[key] = nil
            }
        }
        if let analysis, analysis.outputUID != CA.uid(CA.defaultDevice(input: false)) {
            analysis.teardown()
            self.analysis = nil
        }
        reconcile()
    }

    private func resolvedOutput(_ rule: Rule) -> String {
        if let uid = rule.output, CA.device(uid: uid) != nil { return uid }
        return CA.uid(CA.defaultDevice(input: false)) ?? ""
    }

    // MARK: Discovery

    func refresh() {
        let me = ProcessInfo.processInfo.processIdentifier
        let now = Date()
        var grouped: [String: App] = [:]
        for process in CA.processes() where process.pid > 0 && process.pid != me {
            let path = RunningApps.bundlePath(pid: process.pid)
            let key = path ?? process.bundle ?? "pid:\(process.pid)"
            if key.hasPrefix("pid:") && !process.output { continue }
            var app = grouped[key] ?? App(id: key, name: Self.name(path: path, bundle: process.bundle, pid: process.pid), path: path,
                                          objects: [], playing: false, lastHeard: .distantPast)
            app.objects.append(process.object)
            if process.output {
                app.playing = true
                app.lastHeard = now
            }
            grouped[key] = app
        }
        var list: [App] = []
        for (key, var app) in grouped {
            let known = apps.first { $0.id == key }
            if !app.playing { app.lastHeard = known?.lastHeard ?? .distantPast }
            let recent = now.timeIntervalSince(app.lastHeard) < 180
            if app.playing || recent || rules[key] != nil || engines[key] != nil { list.append(app) }
        }
        list.sort { lhs, rhs in
            if lhs.playing != rhs.playing { return lhs.playing }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        if list != apps { apps = list }
        reconcile()
    }

    private static func name(path: String?, bundle: String?, pid: pid_t) -> String {
        if let path { return FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "") }
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName { return name }
        return bundle?.components(separatedBy: ".").last ?? "\(pid)"
    }

    // MARK: Engines

    private func reconcile() {
        guard active else { return }
        permission = AudioCapturePermission.state == .unknown ? permission : AudioCapturePermission.state
        var wanted: Set<String> = []
        for app in apps where !app.objects.isEmpty {
            let rule = rules[app.id] ?? Rule()
            guard !rule.isDefault else { continue }
            wanted.insert(app.id)
            let output = resolvedOutput(rule)
            let gain = rule.muted ? Float(0) : Float(rule.volume)
            if let engine = engines[app.id] {
                if engine.outputUID == output && Set(engine.processes) == Set(app.objects) {
                    engine.gain = gain
                    continue
                }
                engine.teardown()
                engines[app.id] = nil
            }
            if let failed = failedKeys[app.id], Date().timeIntervalSince(failed) < 20 { continue }
            guard permission != .denied, !output.isEmpty else { continue }
            let engine = TapEngine(key: app.id, processes: app.objects, outputUID: output, gain: gain)
            do {
                try engine.start()
                engines[app.id] = engine
                failure = nil
            } catch {
                failedKeys[app.id] = Date()
                failure = "\(error)"
            }
        }
        for key in engines.keys where !wanted.contains(key) {
            engines[key]?.teardown()
            engines[key] = nil
        }
        reconcileAnalysis()
        updateMeterTimer()
    }

    /// Feeds the island equalizer from the app that is playing, without changing what you hear.
    private func reconcileAnalysis() {
        guard active, permission == .granted, spectrumFor > 0 else {
            analysis?.teardown()
            analysis = nil
            analysisPID = 0
            updateMeterTimer()
            return
        }
        let key = spectrumKey
        if engines[key] != nil {
            analysis?.teardown()
            analysis = nil
            analysisPID = spectrumFor
            updateMeterTimer()
            return
        }
        guard analysis == nil || analysisPID != spectrumFor || analysis?.key != key else { return }
        analysis?.teardown()
        analysis = nil
        guard let app = apps.first(where: { $0.id == key }), !app.objects.isEmpty,
              let output = CA.uid(CA.defaultDevice(input: false)) else { return }
        let engine = TapEngine(key: key, processes: app.objects, outputUID: output, gain: 1, plays: false)
        if (try? engine.start()) != nil {
            analysis = engine
            analysisPID = spectrumFor
        }
        updateMeterTimer()
    }

    private func updateMeterTimer() {
        let needed = active && (metering || analysis != nil || (spectrumFor > 0 && !engines.isEmpty))
        if needed, meterTimer == nil {
            meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.meter() }
            }
        } else if !needed {
            meterTimer?.invalidate()
            meterTimer = nil
        }
    }

    private func meter() {
        if metering {
            var next: [String: Float] = [:]
            for (key, engine) in engines {
                let peak = engine.takePeak()
                let previous = peaks[key] ?? 0
                next[key] = peak > previous ? peak : max(previous * 0.86, peak)
            }
            if next != peaks { peaks = next }
        }
        if spectrumFor > 0, let source = engines[spectrumKey] ?? analysis {
            onLevels?(analyzer.bands(ring: source.ring, head: source.head.pointee, sampleRate: sampleRate))
        }
    }

    var hasEngines: Bool { !engines.isEmpty }
    func isTapped(_ app: App) -> Bool { engines[app.id] != nil }
}
