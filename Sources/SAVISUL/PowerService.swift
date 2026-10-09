import AppKit
import IOKit.pwr_mgt
import Observation

enum PowerMessage: Equatable {
    case cancelled
    case failed(String)
    case unverified
}

@MainActor
@Observable
final class PowerService {
    var lidAwake = false
    var known = false
    var busy = false
    var confirmBattery = false
    var message: PowerMessage?
    var restoredTimers = false
    var idleHeld = false
    var battery = BatteryInfo()
    var sleepMinutes: Int?
    var sleepHolders: [String] = []
    var awakeSince: Date?

    @ObservationIgnored var onStateChange: (() -> Void)?
    @ObservationIgnored private var assertion: IOPMAssertionID = 0
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// Keys written by the first SAVISUL build, which also zeroed the sleep timers.
    private static let legacyKeys = ["savedBatterySleep", "savedBatteryDisk", "savedAdapterSleep", "savedAdapterDisk", "savedSleepGuessed"]

    func start() {
        awakeSince = defaults.object(forKey: "awakeSince") as? Date
        if defaults.bool(forKey: "idleHeld") { setIdle(true) }
    }

    func update(from snapshot: SystemSnapshot) {
        if battery != snapshot.battery { battery = snapshot.battery }
        guard let reading = snapshot.power, !busy else { return }
        apply(reading)
    }

    private func apply(_ reading: PowerReading) {
        if sleepMinutes != reading.sleepMinutes { sleepMinutes = reading.sleepMinutes }
        let holders = reading.holders.filter { $0 != "powerd" }
        if sleepHolders != holders { sleepHolders = holders }
        let changed = !known || lidAwake != reading.sleepDisabled
        known = true
        if lidAwake != reading.sleepDisabled { lidAwake = reading.sleepDisabled }
        syncAwakeSince()
        if changed { onStateChange?() }
    }

    func toggleLid(promptOn: String, promptOff: String) {
        message = nil
        restoredTimers = false
        if lidAwake {
            confirmBattery = false
            change(to: false, prompt: promptOff)
        } else if battery.present && !battery.onAdapter && !confirmBattery {
            confirmBattery = true
        } else {
            confirmBattery = false
            change(to: true, prompt: promptOn)
        }
    }

    func confirmOnBattery(prompt: String) {
        confirmBattery = false
        change(to: true, prompt: prompt)
    }

    func cancelConfirm() {
        confirmBattery = false
    }

    private func change(to enabled: Bool, prompt: String) {
        guard !busy else { return }
        busy = true
        var command = "/usr/bin/pmset -a disablesleep \(enabled ? 1 : 0)"
        let legacy = enabled ? nil : legacyRestoreCommand()
        if let legacy { command += "; " + legacy }
        // Let SwiftUI draw the busy state before the password dialog blocks the main thread.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            MainActor.assumeIsolated {
                self?.runAdmin(command, prompt: prompt, enabled: enabled, restoresLegacy: legacy != nil)
            }
        }
    }

    private func runAdmin(_ command: String, prompt: String, enabled: Bool, restoresLegacy: Bool) {
        switch Admin.run(command, prompt: prompt) {
        case .success:
            if restoresLegacy {
                Self.legacyKeys.forEach { defaults.removeObject(forKey: $0) }
                restoredTimers = true
            }
            verify(expecting: enabled)
        case .failure(.cancelled):
            message = .cancelled
            busy = false
        case .failure(.failed(let detail)):
            message = .failed(detail)
            busy = false
        }
    }

    private func verify(expecting enabled: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            let reading = PowerProbe.read()
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.busy = false
                    if let reading {
                        self.apply(reading)
                        if reading.sleepDisabled != enabled { self.message = .unverified }
                    } else {
                        self.message = .unverified
                    }
                    self.onStateChange?()
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
            }
        }
    }

    private func legacyRestoreCommand() -> String? {
        guard defaults.object(forKey: "savedBatterySleep") != nil || defaults.object(forKey: "savedAdapterSleep") != nil else {
            return nil
        }
        func minutes(_ key: String, _ fallback: Int) -> Int {
            let value = defaults.object(forKey: key) as? Int ?? fallback
            return min(max(value, 0), 180)
        }
        let batterySleep = minutes("savedBatterySleep", 1)
        let batteryDisk = minutes("savedBatteryDisk", 10)
        let adapterSleep = minutes("savedAdapterSleep", 1)
        let adapterDisk = minutes("savedAdapterDisk", 10)
        return "/usr/bin/pmset -b sleep \(batterySleep) disksleep \(batteryDisk); /usr/bin/pmset -c sleep \(adapterSleep) disksleep \(adapterDisk)"
    }

    private func syncAwakeSince() {
        if lidAwake, awakeSince == nil {
            awakeSince = Date()
            defaults.set(awakeSince, forKey: "awakeSince")
        } else if !lidAwake, awakeSince != nil {
            awakeSince = nil
            defaults.removeObject(forKey: "awakeSince")
        }
    }

    func setIdle(_ hold: Bool) {
        if hold, assertion == 0 {
            var identifier: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "SAVISUL keeps the Mac awake" as CFString,
                &identifier)
            if result == kIOReturnSuccess { assertion = identifier }
        } else if !hold, assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
        idleHeld = assertion != 0
        defaults.set(idleHeld, forKey: "idleHeld")
    }

    func displayOff() {
        DispatchQueue.global(qos: .userInitiated).async {
            Shell.run("/usr/bin/pmset", ["displaysleepnow"], timeout: 5)
        }
    }
}
