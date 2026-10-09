import Foundation
import IOKit.ps

/// Charger plugged and pulled, battery full, and the 20/10/5 % marks, straight from IOKit.
@MainActor
final class PowerEvents {
    struct State: Equatable {
        var adapter: Bool
        var percent: Int
        var charging: Bool
        var present: Bool
    }

    enum Event {
        case plugged(percent: Int, charging: Bool)
        case unplugged(percent: Int)
        case full
        case low(Int)
    }

    var onEvent: ((Event) -> Void)?
    private(set) var state: State?
    private var source: CFRunLoopSource?
    private var warned: Set<Int> = []

    func start() {
        guard source == nil else { return }
        state = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let loop = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let events = Unmanaged<PowerEvents>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { events.changed() }
        }, context)?.takeRetainedValue() else { return }
        source = loop
        CFRunLoopAddSource(CFRunLoopGetMain(), loop, .commonModes)
    }

    private func changed() {
        guard let next = Self.read(), next.present else { return }
        defer { state = next }
        guard let previous = state else { return }
        for event in Self.transitions(from: previous, to: next, warned: &warned) { onEvent?(event) }
    }

    /// Plugged, unplugged, full, and the 20 / 10 / 5 % marks. Each low mark fires once until the charger returns.
    nonisolated static func transitions(from previous: State, to next: State, warned: inout Set<Int>) -> [Event] {
        guard next.present, previous.present else { return [] }
        var events: [Event] = []
        if next.adapter && !previous.adapter {
            warned = []
            events.append(.plugged(percent: next.percent, charging: next.charging))
        } else if !next.adapter && previous.adapter {
            events.append(.unplugged(percent: next.percent))
        }
        if next.adapter, next.percent >= 100, previous.percent < 100 { events.append(.full) }
        if !next.adapter {
            for level in [20, 10, 5] where next.percent <= level && previous.percent > level && !warned.contains(level) {
                warned.insert(level)
                events.append(.low(level))
            }
        }
        return events
    }

    static func read() -> State? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let adapter = type == kIOPSACPowerValue
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            return State(adapter: adapter, percent: Int((Double(current) / Double(maximum) * 100).rounded()), charging: charging, present: true)
        }
        return State(adapter: adapter, percent: 100, charging: false, present: false)
    }
}
