import AudioToolbox
import CoreAudio
import Foundation

/// Small typed readers for the Core Audio object model.
enum CA {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func has(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var address = address(selector, scope)
        return AudioObjectHasProperty(object, &address)
    }

    static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ fallback: T) -> T {
        var address = address(selector, scope)
        guard AudioObjectHasProperty(object, &address) else { return fallback }
        var result = fallback
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr ? result : fallback
    }

    static func array<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, of: T.Type) -> [T] {
        var address = address(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer) == noErr else { return [] }
        let typed = buffer.bindMemory(to: T.self, capacity: count)
        return Array(UnsafeBufferPointer(start: typed, count: Int(size) / MemoryLayout<T>.stride))
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
        var address = address(selector, scope)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    @discardableResult
    static func set<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ value: T) -> Bool {
        var address = address(selector, scope)
        guard AudioObjectHasProperty(object, &address) else { return false }
        var copy = value
        return withUnsafeMutablePointer(to: &copy) {
            AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), $0) == noErr
        }
    }

    static func defaultDevice(input: Bool) -> AudioDeviceID {
        value(system, input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, AudioDeviceID(0))
    }

    static func uid(_ device: AudioDeviceID) -> String? { string(device, kAudioDevicePropertyDeviceUID) }

    static func device(uid: String) -> AudioDeviceID? {
        devices().first { CA.uid($0) == uid }
    }

    static func devices() -> [AudioDeviceID] { array(system, kAudioHardwarePropertyDevices, of: AudioDeviceID.self) }

    static func streams(_ device: AudioDeviceID, input: Bool) -> Int {
        array(device, kAudioDevicePropertyStreams, input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput, of: AudioStreamID.self).count
    }

    static func transport(_ device: AudioDeviceID) -> UInt32 {
        value(device, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, UInt32(0))
    }

    static func name(_ device: AudioDeviceID) -> String { string(device, kAudioObjectPropertyName) ?? "Device \(device)" }

    static func isHeadphones(_ device: AudioDeviceID) -> Bool {
        let transport = transport(device)
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE { return true }
        if transport == kAudioDeviceTransportTypeBuiltIn {
            let source = value(device, kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput, UInt32(0))
            return source == 0x6864_706E
        }
        if transport == kAudioDeviceTransportTypeUSB {
            let lower = name(device).lowercased()
            return ["headset", "headphone", "earbud", "наушник", "гарнитур"].contains { lower.contains($0) }
        }
        return false
    }

    /// Process objects Core Audio knows about, with their PIDs.
    static func processes() -> [(object: AudioObjectID, pid: pid_t, output: Bool, bundle: String?)] {
        array(system, kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self).map { object in
            let pid = value(object, kAudioProcessPropertyPID, kAudioObjectPropertyScopeGlobal, pid_t(-1))
            let output = value(object, kAudioProcessPropertyIsRunningOutput, kAudioObjectPropertyScopeGlobal, UInt32(0)) != 0
            return (object, pid, output, string(object, kAudioProcessPropertyBundleID))
        }
    }

    /// Processes recording from a microphone right now.
    static func inputPIDs() -> [pid_t] {
        array(system, kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self).compactMap { object in
            guard value(object, kAudioProcessPropertyIsRunningInput, kAudioObjectPropertyScopeGlobal, UInt32(0)) != 0 else { return nil }
            let pid = value(object, kAudioProcessPropertyPID, kAudioObjectPropertyScopeGlobal, pid_t(-1))
            return pid > 0 ? pid : nil
        }
    }
}

/// The macOS privacy switch for listening to other apps' audio has no public query, so read it through TCC.
enum AudioCapturePermission {
    enum State { case unknown, granted, denied }

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    private static let service = "kTCCServiceAudioCapture" as CFString

    static var state: State {
        guard let handle, let symbol = dlsym(handle, "TCCAccessPreflight") else { return .unknown }
        let preflight = unsafeBitCast(symbol, to: Preflight.self)
        switch preflight(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .unknown
        }
    }

    static func request(_ done: @escaping @Sendable (Bool) -> Void) {
        guard let handle, let symbol = dlsym(handle, "TCCAccessRequest") else {
            done(false)
            return
        }
        let request = unsafeBitCast(symbol, to: Request.self)
        request(service, nil) { granted in done(granted) }
    }
}
