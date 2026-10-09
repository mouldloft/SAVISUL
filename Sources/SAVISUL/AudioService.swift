import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import Observation

enum AudioScope {
    case output, input

    var core: AudioObjectPropertyScope {
        self == .output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput
    }
}

struct AudioEndpoint: Identifiable, Equatable {
    let id: AudioDeviceID
    var name: String
    var symbol: String
    var volume: Double?
    var muted: Bool?
}

struct PlayingApp: Identifiable, Equatable {
    var id: String
    var name: String
    var appPath: String?
}

@MainActor
@Observable
final class AudioService {
    var outputs: [AudioEndpoint] = []
    var inputs: [AudioEndpoint] = []
    var defaultOutput: AudioDeviceID = 0
    var defaultInput: AudioDeviceID = 0
    var balance: Double = 0.5
    var hasBalance = false
    var playing: [PlayingApp] = []

    @ObservationIgnored private var holdUntil = Date.distantPast
    @ObservationIgnored private var listening = false

    var currentOutput: AudioEndpoint? { outputs.first { $0.id == defaultOutput } }
    var currentInput: AudioEndpoint? { inputs.first { $0.id == defaultInput } }
    /// True right after SAVISUL itself set a volume or mute, so the island does not echo the panel's slider.
    var changedHere: Bool { Date() < holdUntil.addingTimeInterval(0.4) }

    func start() {
        reload(force: true)
        installListeners()
    }

    /// Skips reads for a moment after a local change so the slider never jumps back.
    func reload(force: Bool = false) {
        if !force && Date() < holdUntil { return }
        let output = readDefault(kAudioHardwarePropertyDefaultOutputDevice)
        let input = readDefault(kAudioHardwarePropertyDefaultInputDevice)
        let devices = readDevices().filter { !isHidden($0) }
        let newOutputs = devices.filter { hasStreams($0, kAudioDevicePropertyScopeOutput) }.map { endpoint($0, .output) }
        let newInputs = devices.filter { hasStreams($0, kAudioDevicePropertyScopeInput) }.map { endpoint($0, .input) }
        if output != defaultOutput { defaultOutput = output }
        if input != defaultInput { defaultInput = input }
        if newOutputs != outputs { outputs = newOutputs }
        if newInputs != inputs { inputs = newInputs }
        let pan = readFloat(output, kAudioHardwareServiceDeviceProperty_VirtualMainBalance, kAudioDevicePropertyScopeOutput)
        if (pan != nil) != hasBalance { hasBalance = pan != nil }
        if let pan, abs(Double(pan) - balance) > 0.0005 { balance = Double(pan) }
        refreshPlaying()
    }

    func setVolume(_ value: Double, device: AudioDeviceID, scope: AudioScope) {
        holdUntil = Date().addingTimeInterval(0.4)
        var volume = Float32(min(max(value, 0), 1))
        writeFloat(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope.core, &volume)
        update(device, scope) { $0.volume = Double(volume) }
    }

    func nudge(device: AudioDeviceID, scope: AudioScope, by delta: Double) {
        let list = scope == .output ? outputs : inputs
        let current = list.first { $0.id == device }?.volume ?? 0
        setVolume(current + delta, device: device, scope: scope)
    }

    func setMuted(_ muted: Bool, device: AudioDeviceID, scope: AudioScope) {
        holdUntil = Date().addingTimeInterval(0.4)
        var value: UInt32 = muted ? 1 : 0
        writeUInt(device, kAudioDevicePropertyMute, scope.core, &value)
        update(device, scope) { $0.muted = muted }
    }

    func setBalance(_ value: Double) {
        holdUntil = Date().addingTimeInterval(0.4)
        balance = min(max(value, 0), 1)
        var pan = Float32(balance)
        writeFloat(defaultOutput, kAudioHardwareServiceDeviceProperty_VirtualMainBalance, kAudioDevicePropertyScopeOutput, &pan)
    }

    func select(_ id: AudioDeviceID, scope: AudioScope) {
        var device = id
        let selector = scope == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &device)
        reload(force: true)
    }

    private func update(_ device: AudioDeviceID, _ scope: AudioScope, _ change: (inout AudioEndpoint) -> Void) {
        if scope == .output, let index = outputs.firstIndex(where: { $0.id == device }) {
            change(&outputs[index])
        } else if scope == .input, let index = inputs.firstIndex(where: { $0.id == device }) {
            change(&inputs[index])
        }
    }

    // MARK: Apps that are playing

    func refreshPlaying() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var rows: [PlayingApp] = []
        if AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 {
            var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            if AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr {
                let me = getpid()
                for object in objects {
                    guard (readUInt(object, kAudioProcessPropertyIsRunningOutput, kAudioObjectPropertyScopeGlobal) ?? 0) != 0,
                          let pid = readPID(object), pid > 0, pid != me else { continue }
                    let app = Self.describe(pid: pid)
                    if rows.contains(where: { $0.id == app.id }) { continue }
                    rows.append(app)
                    if rows.count == 5 { break }
                }
            }
        }
        if rows != playing { playing = rows }
    }

    private static func describe(pid: pid_t) -> PlayingApp {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            let path = String(cString: buffer)
            if let range = path.range(of: ".app/") {
                let appPath = String(path[..<range.lowerBound]) + ".app"
                let name = FileManager.default.displayName(atPath: appPath)
                return PlayingApp(id: appPath, name: (name as NSString).deletingPathExtension, appPath: appPath)
            }
            let name = (path as NSString).lastPathComponent
            return PlayingApp(id: path, name: name, appPath: nil)
        }
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "\(pid)"
        return PlayingApp(id: "pid:\(pid)", name: name, appPath: nil)
    }

    private func readPID(_ object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr else { return nil }
        return pid
    }

    // MARK: Devices

    private func installListeners() {
        guard !listening else { return }
        listening = true
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(system, &address, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reload(force: true) }
            }
        }
    }

    private func endpoint(_ id: AudioDeviceID, _ scope: AudioScope) -> AudioEndpoint {
        let name = deviceName(id)
        let volume = readFloat(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope.core).map(Double.init)
        let muted = readUInt(id, kAudioDevicePropertyMute, scope.core).map { $0 == 1 }
        return AudioEndpoint(id: id, name: name, symbol: symbol(id, name: name, scope: scope), volume: volume, muted: muted)
    }

    private func symbol(_ id: AudioDeviceID, name: String, scope: AudioScope) -> String {
        let transport = readUInt(id, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal) ?? 0
        let lower = name.lowercased()
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return scope == .output ? "laptopcomputer" : "mic"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            if lower.contains("airpods max") { return "airpodsmax" }
            if lower.contains("airpods pro") { return "airpodspro" }
            if lower.contains("airpods") { return "airpods" }
            if lower.contains("beats") { return "beats.headphones" }
            return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeThunderbolt:
            return "display"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeUSB:
            return scope == .output ? "hifispeaker" : "mic"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless:
            return "iphone"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return "waveform"
        default:
            return scope == .output ? "speaker.wave.2" : "mic"
        }
    }

    private func deviceName(_ id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name {
            return name.takeRetainedValue() as String
        }
        return "Device \(id)"
    }

    private func readDevices() -> [AudioDeviceID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func isHidden(_ id: AudioDeviceID) -> Bool {
        (readUInt(id, kAudioDevicePropertyIsHidden, kAudioObjectPropertyScopeGlobal) ?? 0) != 0
    }

    private func hasStreams(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private func readDefault(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private func readFloat(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> Float32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func readUInt(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func writeFloat(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope,
                            _ value: inout Float32) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return }
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    private func writeUInt(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope,
                           _ value: inout UInt32) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return }
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}
