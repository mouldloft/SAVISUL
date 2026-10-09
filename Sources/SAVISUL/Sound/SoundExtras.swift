import AppKit
import AudioToolbox
import CoreAudio

/// Sound shortcuts and guards: cycle the output, mute every microphone at once, turn the speakers
/// down when headphones drop, and keep a chosen microphone when AirPods try to take over.
@MainActor
final class SoundExtras {
    private unowned let suite: Suite
    private var lastOutput = AudioDeviceID(0)
    private var lastOutputHeadphones = false
    private var lastOutputs: Set<AudioDeviceID> = []
    private var listening = false
    private var watchedSources: Set<AudioDeviceID> = []
    private var enforce: Timer?
    private var cycled = false
    private var settleTask: DispatchWorkItem?
    private var volumeDevice = AudioDeviceID(0)
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var volumeAddresses: [AudioObjectPropertyAddress] = []
    private var lastLevel: (volume: Float, muted: Bool)?

    private struct Saved: Codable { var volume: Float?; var usedMute: Bool }
    private var saved: [String: Saved] = [:]

    init(suite: Suite) {
        self.suite = suite
        if let data = UserDefaults.standard.data(forKey: "suite.mutedMics"),
           let previous = try? JSONDecoder().decode([String: Saved].self, from: data), !previous.isEmpty {
            saved = previous
            restoreMics()
        }
    }

    func start() {
        lastOutput = CA.defaultDevice(input: false)
        lastOutputHeadphones = CA.isHeadphones(lastOutput)
        lastOutputs = Set(outputDevices())
        guard !listening else { return }
        listening = true
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = CA.address(selector)
            AudioObjectAddPropertyListenerBlock(CA.system, &address, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.hardwareChanged(selector) }
            }
        }
        watchDataSources()
        watchVolume(lastOutput)
    }

    // MARK: Output

    private func outputDevices() -> [AudioDeviceID] {
        CA.devices().filter { device in
            CA.streams(device, input: false) > 0
                && CA.value(device, kAudioDevicePropertyIsHidden, kAudioObjectPropertyScopeGlobal, UInt32(0)) == 0
                && CA.transport(device) != kAudioDeviceTransportTypeAggregate
        }
    }

    func cycleOutput() {
        let outputs = outputDevices()
        guard outputs.count > 1 else {
            suite.notify(IslandNotice(symbol: "speaker.wave.2.fill", tint: Palette.accent, title: SoundPhrases.oneOutput.text, detail: nil, duration: 2))
            return
        }
        let current = CA.defaultDevice(input: false)
        let index = outputs.firstIndex(of: current) ?? -1
        let next = outputs[(index + 1) % outputs.count]
        cycled = true
        suite.app?.audio.select(next, scope: .output)
    }

    private func announceOutput(_ device: AudioDeviceID) {
        let asked = cycled
        cycled = false
        guard asked || suite.settings.islandDevices,
              let endpoint = suite.app?.audio.outputs.first(where: { $0.id == device }) else { return }
        suite.notify(IslandNotice(symbol: endpoint.symbol, tint: Palette.accent, title: endpoint.name,
                                  detail: SoundPhrases.output.text, level: endpoint.volume, duration: 2.2))
    }

    private func hardwareChanged(_ selector: AudioObjectPropertySelector) {
        suite.app?.audio.reload(force: true)
        switch selector {
        case kAudioHardwarePropertyDefaultOutputDevice:
            let current = CA.defaultDevice(input: false)
            // Speakers taking over from headphones get turned down at once, before anything plays out loud.
            if current != lastOutput, !Set(outputDevices()).contains(lastOutput), lastOutputHeadphones, !CA.isHeadphones(current) {
                headphonesGone(speaker: current)
                lastOutput = current
                lastOutputHeadphones = false
            }
            settleSoon()
        case kAudioHardwarePropertyDefaultInputDevice:
            keepPinnedInput()
            if suite.micMuted { muteAll() }
        case kAudioHardwarePropertyDevices:
            if suite.micMuted { muteAll() }
            keepPinnedInput()
            settleSoon()
        default:
            break
        }
    }

    /// A device arriving fires several hardware changes in an order that varies; the island speaks once they settle.
    private func settleSoon() {
        settleTask?.cancel()
        let task = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.settle() } }
        settleTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    private func settle() {
        suite.app?.audio.reload(force: true)
        let devices = Set(outputDevices())
        let current = CA.defaultDevice(input: false)
        let added = devices.subtracting(lastOutputs)
        if current != lastOutput {
            if added.contains(current) { announceConnected(current, playing: true) } else { announceOutput(current) }
        }
        for device in added where device != current { announceConnected(device, playing: false) }
        if current != lastOutput || !added.isEmpty || devices != lastOutputs { suite.mixer.devicesChanged() }
        lastOutputs = devices
        lastOutput = current
        lastOutputHeadphones = CA.isHeadphones(current)
        watchDataSources()
        watchVolume(current)
    }

    private func announceConnected(_ device: AudioDeviceID, playing: Bool) {
        guard suite.settings.islandDevices else { return }
        let endpoint = suite.app?.audio.outputs.first { $0.id == device }
        suite.notify(IslandNotice(symbol: endpoint?.symbol ?? (CA.isHeadphones(device) ? "headphones" : "hifispeaker.fill"), tint: Palette.positive,
                                  title: endpoint?.name ?? CA.name(device),
                                  detail: playing ? SoundPhrases.connectedPlaying.text : SoundPhrases.connected.text,
                                  style: .success, level: playing ? endpoint?.volume : nil, duration: 2.8))
    }

    // MARK: Volume

    /// Follows the volume and mute of the current output, so the island can show the level as it moves.
    private func watchVolume(_ device: AudioDeviceID) {
        guard device != volumeDevice else { return }
        if let volumeListener {
            for var address in volumeAddresses { AudioObjectRemovePropertyListenerBlock(volumeDevice, &address, .main, volumeListener) }
        }
        volumeDevice = device
        volumeAddresses = []
        lastLevel = level(device)
        guard device != 0 else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.volumeChanged() }
        }
        volumeListener = listener
        let scope = kAudioDevicePropertyScopeOutput
        var wanted = [CA.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope), CA.address(kAudioDevicePropertyMute, scope)]
        for element: UInt32 in [1, 2] {
            wanted.append(AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element))
        }
        for var address in wanted where AudioObjectHasProperty(device, &address) {
            if AudioObjectAddPropertyListenerBlock(device, &address, .main, listener) == noErr { volumeAddresses.append(address) }
        }
    }

    private func level(_ device: AudioDeviceID) -> (volume: Float, muted: Bool) {
        let scope = kAudioDevicePropertyScopeOutput
        return (CA.value(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope, Float32(0)),
                CA.value(device, kAudioDevicePropertyMute, scope, UInt32(0)) != 0)
    }

    private func volumeChanged() {
        let now = level(volumeDevice)
        defer { lastLevel = now }
        guard let last = lastLevel, abs(now.volume - last.volume) > 0.004 || now.muted != last.muted else { return }
        guard suite.settings.island, suite.settings.islandVolume, suite.app?.audio.changedHere != true else { return }
        suite.app?.audio.reload(force: true)
        let endpoint = suite.app?.audio.outputs.first { $0.id == volumeDevice }
        let silent = now.muted || now.volume < 0.005
        suite.island.show(hud: IslandHUD(symbol: Self.volumeSymbol(silent: silent, volume: now.volume, device: endpoint?.symbol),
                                         title: endpoint?.name ?? CA.name(volumeDevice), level: Double(now.volume), muted: now.muted))
    }

    /// Headphones keep their own picture; speakers show how loud they are.
    static func volumeSymbol(silent: Bool, volume: Float, device: String?) -> String {
        if silent { return "speaker.slash.fill" }
        if let device, ["airpods", "airpodspro", "airpodsmax", "beats.headphones", "headphones"].contains(device) { return device }
        switch volume {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    /// The built-in output switches between speakers and the headphone jack without changing device.
    private func watchDataSources() {
        for device in outputDevices() where CA.transport(device) == kAudioDeviceTransportTypeBuiltIn && !watchedSources.contains(device) {
            guard CA.has(device, kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput) else { continue }
            watchedSources.insert(device)
            var address = CA.address(kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput)
            AudioObjectAddPropertyListenerBlock(device, &address, .main) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let headphones = CA.isHeadphones(device)
                    if device == CA.defaultDevice(input: false) {
                        if self.lastOutputHeadphones && !headphones { self.headphonesGone(speaker: device) }
                        self.lastOutputHeadphones = headphones
                    }
                    self.suite.app?.audio.reload(force: true)
                }
            }
        }
    }

    private func headphonesGone(speaker: AudioDeviceID) {
        guard suite.settings.headphoneGuard else {
            announceOutput(speaker)
            return
        }
        let level = Float(suite.settings.headphoneLevel)
        let current = CA.value(speaker, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput, Float32(0))
        if current > level {
            suite.app?.audio.setVolume(Double(level), device: speaker, scope: .output)
        }
        suite.notify(IslandNotice(symbol: "headphones", tint: Palette.warning, title: SoundPhrases.headphonesGone.text,
                                  detail: SoundPhrases.turnedDown(Int((min(current, level) * 100).rounded())),
                                  style: .warning, level: Double(min(current, level)), duration: 3.4))
    }

    // MARK: Microphones

    private func inputDevices() -> [AudioDeviceID] {
        CA.devices().filter { CA.streams($0, input: true) > 0 && CA.transport($0) != kAudioDeviceTransportTypeAggregate }
    }

    func toggleMics() {
        if suite.micMuted {
            restoreMics()
            suite.micMuted = false
            enforce?.invalidate()
            enforce = nil
            suite.notify(IslandNotice(symbol: "mic.fill", tint: Palette.positive, title: SoundPhrases.micsOn.text, detail: nil, style: .success, duration: 2))
        } else {
            muteAll()
            suite.micMuted = true
            enforce = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.muteAll() }
            }
            suite.notify(IslandNotice(symbol: "mic.slash.fill", tint: Palette.danger, title: SoundPhrases.micsOff.text,
                                      detail: SoundPhrases.micsCount(inputDevices().count), style: .warning, duration: 2.6))
        }
    }

    /// Mutes each microphone the way it supports: a mute switch, or input gain at zero.
    private func muteAll() {
        let scope = kAudioDevicePropertyScopeInput
        for device in inputDevices() {
            guard let uid = CA.uid(device) else { continue }
            if CA.set(device, kAudioDevicePropertyMute, scope, UInt32(1)) {
                if saved[uid] == nil { saved[uid] = Saved(volume: nil, usedMute: true) }
            } else {
                let volume = CA.value(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope, Float32(-1))
                if saved[uid] == nil { saved[uid] = Saved(volume: volume >= 0 ? volume : nil, usedMute: false) }
                if volume > 0 { CA.set(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope, Float32(0)) }
            }
        }
        persist()
    }

    private func restoreMics() {
        let scope = kAudioDevicePropertyScopeInput
        for (uid, state) in saved {
            guard let device = CA.device(uid: uid) else { continue }
            if state.usedMute {
                CA.set(device, kAudioDevicePropertyMute, scope, UInt32(0))
            } else if let volume = state.volume {
                CA.set(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope, Float32(max(volume, 0.05)))
            }
        }
        saved = [:]
        persist()
    }

    private func persist() {
        if saved.isEmpty {
            UserDefaults.standard.removeObject(forKey: "suite.mutedMics")
        } else if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "suite.mutedMics")
        }
    }

    func shutdown() {
        if suite.micMuted { restoreMics() }
    }

    /// AirPods switch the Mac to their own microphone, which drops music to call quality.
    private func keepPinnedInput() {
        let pinned = suite.settings.pinnedInput
        guard !pinned.isEmpty, let device = CA.device(uid: pinned), CA.defaultDevice(input: true) != device else { return }
        suite.app?.audio.select(device, scope: .input)
    }
}

enum SoundPhrases {
    static let output = Phrase("Sound output", ru: "Вывод звука", uk: "Вивід звуку", fr: "Sortie audio")
    static let oneOutput = Phrase("Only one output is connected", ru: "Подключён только один выход", uk: "Підключено лише один вихід", fr: "Une seule sortie est connectée")
    static let connected = Phrase("Connected", ru: "Подключено", uk: "Підключено", fr: "Connecté")
    static let connectedPlaying = Phrase("Connected · sound plays here", ru: "Подключено · звук идёт сюда", uk: "Підключено · звук іде сюди", fr: "Connecté · le son passe ici")
    static let headphonesGone = Phrase("Headphones disconnected", ru: "Наушники отключились", uk: "Навушники відключилися", fr: "Écouteurs déconnectés")
    static let micsOff = Phrase("Microphones off", ru: "Микрофоны выключены", uk: "Мікрофони вимкнено", fr: "Micros coupés")
    static let micsOn = Phrase("Microphones on", ru: "Микрофоны включены", uk: "Мікрофони увімкнено", fr: "Micros activés")
    @MainActor static func turnedDown(_ percent: Int) -> String {
        Phrase("Speakers at %d%%", ru: "Динамики на %d%%", uk: "Динаміки на %d%%", fr: "Haut-parleurs à %d %%")(percent)
    }
    @MainActor static func micsCount(_ count: Int) -> String {
        Phrase("All %d muted", ru: "Заглушено: %d", uk: "Заглушено: %d", fr: "%d coupés")(count)
    }
}
