import Foundation
import Observation
import UserNotifications

final class BannerDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

struct AlertMemory {
    var cpuHighSince: Date?
    var heatSince: Date?
    var heavySince: Date?
    var calmSince: Date?
}

enum AlertSignal: Equatable {
    case cpu, memory, battery, heat, done(TimeInterval)
}

/// Which alerts a sample should raise. CPU waits 60 s, heat 30 s, “work finished” waits for a calm minute after a long load.
enum AlertRules {
    static func signals(_ snapshot: SystemSnapshot, now: Date, cpuLimit: Double, memoryLimit: Double, batteryLimit: Double,
                        heatLimit: Double, workDone: Bool, memory: inout AlertMemory) -> [AlertSignal] {
        var signals: [AlertSignal] = []
        if snapshot.cpu >= cpuLimit {
            memory.cpuHighSince = memory.cpuHighSince ?? now
            if let since = memory.cpuHighSince, now.timeIntervalSince(since) >= 60 { signals.append(.cpu) }
        } else {
            memory.cpuHighSince = nil
        }
        if snapshot.memoryFraction * 100 >= memoryLimit || snapshot.pressure == .critical { signals.append(.memory) }
        let battery = snapshot.battery
        if battery.present, !battery.onAdapter, battery.percent <= batteryLimit { signals.append(.battery) }
        if let heat = snapshot.temperature, heat >= heatLimit {
            memory.heatSince = memory.heatSince ?? now
            if let since = memory.heatSince, now.timeIntervalSince(since) >= 30 { signals.append(.heat) }
        } else {
            memory.heatSince = nil
        }
        guard workDone else { return signals }
        if snapshot.cpu >= 60 {
            memory.heavySince = memory.heavySince ?? now
            memory.calmSince = nil
        } else if let start = memory.heavySince {
            if snapshot.cpu < 25 {
                memory.calmSince = memory.calmSince ?? now
                if let calm = memory.calmSince, now.timeIntervalSince(calm) >= 45 {
                    let stretch = calm.timeIntervalSince(start)
                    memory.heavySince = nil
                    memory.calmSince = nil
                    if stretch >= 180 { signals.append(.done(stretch)) }
                }
            } else {
                memory.calmSince = nil
            }
        }
        return signals
    }
}

@MainActor
@Observable
final class AlertCenter {
    var enabled: Bool { didSet { store(enabled, "alertsEnabled") } }
    var cpuLimit: Double { didSet { store(cpuLimit, "alertCPU") } }
    var memoryLimit: Double { didSet { store(memoryLimit, "alertMemory") } }
    var batteryLimit: Double { didSet { store(batteryLimit, "alertBattery") } }
    var heatLimit: Double { didSet { store(heatLimit, "alertHeat") } }
    var workDone: Bool { didSet { store(workDone, "alertWorkDone") } }

    @ObservationIgnored private let banners = BannerDelegate()
    @ObservationIgnored private var lastSent: [String: Date] = [:]
    @ObservationIgnored private var cpuHighSince: Date?
    @ObservationIgnored private var heatSince: Date?
    @ObservationIgnored private var heavySince: Date?
    @ObservationIgnored private var calmSince: Date?
    @ObservationIgnored private var heavyStretch: TimeInterval = 0

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.bool(forKey: "alertsEnabled")
        cpuLimit = defaults.object(forKey: "alertCPU") as? Double ?? 90
        memoryLimit = defaults.object(forKey: "alertMemory") as? Double ?? 90
        batteryLimit = defaults.object(forKey: "alertBattery") as? Double ?? 15
        heatLimit = defaults.object(forKey: "alertHeat") as? Double ?? 95
        workDone = defaults.object(forKey: "alertWorkDone") as? Bool ?? true
    }

    func start() {
        UNUserNotificationCenter.current().delegate = banners
    }

    func evaluate(_ snapshot: SystemSnapshot, lidAwake: Bool, model: AppModel) {
        guard enabled, snapshot.cpuReady else { return }
        var memory = AlertMemory(cpuHighSince: cpuHighSince, heatSince: heatSince, heavySince: heavySince, calmSince: calmSince)
        let signals = AlertRules.signals(snapshot, now: Date(), cpuLimit: cpuLimit, memoryLimit: memoryLimit, batteryLimit: batteryLimit,
                                         heatLimit: heatLimit, workDone: workDone, memory: &memory)
        cpuHighSince = memory.cpuHighSince
        heatSince = memory.heatSince
        heavySince = memory.heavySince
        calmSince = memory.calmSince
        for signal in signals {
            switch signal {
            case .cpu:
                send("cpu", model.format(.nCPU, model.percent(cpuLimit)), title: model.text(.processor))
            case .memory:
                send("memory", model.format(.nMemory, model.percent(snapshot.memoryFraction * 100)), title: model.text(.memory))
            case .battery:
                let body = lidAwake ? model.format(.nBatteryLid, model.percent(snapshot.battery.percent)) : model.format(.nBattery, model.percent(snapshot.battery.percent))
                send("battery", body, title: model.text(.battery))
            case .heat:
                send("heat", model.format(.nHeat, model.celsius(snapshot.temperature ?? 0)), title: model.text(.temperature))
            case .done(let stretch):
                heavyStretch = stretch
                send("done", model.format(.nDone, model.duration(stretch)), title: "SAVISUL", cooldown: 0)
            }
        }
    }

    func sendTest(body: String) {
        send("test-\(UUID().uuidString)", body, title: "SAVISUL", cooldown: 0)
    }

    private func send(_ kind: String, _ body: String, title: String, cooldown: TimeInterval = 900) {
        let now = Date()
        if let last = lastSent[kind], now.timeIntervalSince(last) < cooldown { return }
        lastSent[kind] = now
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "savisul.\(kind).\(Int(now.timeIntervalSince1970))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func store(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
