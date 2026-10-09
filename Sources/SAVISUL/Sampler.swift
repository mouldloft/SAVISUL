import Darwin
import Foundation
import IOKit
import IOKit.ps
import SMCBridge

enum MemoryPressure: Equatable {
    case normal, warning, critical
}

struct FanReading: Equatable, Identifiable {
    var id: Int
    var actual: Double
    var minimum: Double
    var maximum: Double
}

struct BatteryInfo: Equatable {
    var present = false
    var percent: Double = 0
    var charging = false
    var onAdapter = true
    var minutesToEmpty: Int?
    var minutesToFull: Int?
    var health: Double?
    var cycles: Int?
}

struct PowerReading: Equatable {
    var sleepDisabled = false
    var sleepMinutes: Int?
    var holders: [String] = []
}

struct SystemSnapshot: Equatable {
    var cpu: Double = 0
    var cpuReady = false
    var memoryUsed: Double = 0
    var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    var pressure: MemoryPressure = .normal
    var swapUsed: Double = 0
    var temperature: Double?
    var fans: [FanReading] = []
    var fansRead = false
    var battery = BatteryInfo()
    var power: PowerReading?

    var memoryFraction: Double { memoryTotal > 0 ? min(memoryUsed / memoryTotal, 1) : 0 }
}

struct BusyApp: Equatable, Identifiable {
    var id: String
    var name: String
    var appPath: String?
    var cpu: Double
}

enum PowerProbe {
    /// `pmset -g` prints the closed-lid switch as "SleepDisabled", not as the `disablesleep` argument name.
    static func read() -> PowerReading? {
        guard let output = Shell.run("/usr/bin/pmset", ["-g"], timeout: 5), output.status == 0 else { return nil }
        var reading = PowerReading()
        for raw in output.text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let key = parts.first, parts.count > 1 else { continue }
            if key == "SleepDisabled" {
                reading.sleepDisabled = parts[1] == "1"
            } else if key == "sleep" {
                reading.sleepMinutes = Int(parts[1])
                if let open = line.range(of: "sleep prevented by "),
                   let close = line.range(of: ")", range: open.upperBound..<line.endIndex) {
                    reading.holders = line[open.upperBound..<close.lowerBound]
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            }
        }
        return reading
    }
}

/// Samples hardware on a utility queue and hands immutable snapshots to the main actor.
final class SystemSampler: @unchecked Sendable {
    var onSnapshot: (@MainActor (SystemSnapshot) -> Void)?
    var onProcesses: (@MainActor ([BusyApp]) -> Void)?

    private let queue = DispatchQueue(label: "com.savisul.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var snapshot = SystemSnapshot()
    private var previousTicks: [UInt64]?
    private var count = 0
    private var wantsProcesses = false
    private var processTimes: [pid_t: UInt64] = [:]
    private var lastProcessSample: UInt64 = 0
    private var identities: [pid_t: (key: String, name: String, path: String?)] = [:]
    private let cores = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
    private let timebase: (numer: UInt64, denom: UInt64)

    init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        timebase = (UInt64(max(info.numer, 1)), UInt64(max(info.denom, 1)))
    }

    func start() {
        queue.async { [self] in
            sav_smc_open()
            sampleCPU()
            sampleMemory()
            sampleSMC()
            sampleBattery()
            readPower()
            emit()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(150))
            source.setEventHandler { [weak self] in self?.step() }
            source.resume()
            timer = source
        }
    }

    func setWantsProcesses(_ wanted: Bool) {
        queue.async { [self] in
            guard wantsProcesses != wanted else { return }
            wantsProcesses = wanted
            processTimes = [:]
            lastProcessSample = 0
            if wanted { sampleProcesses() }
        }
    }

    func refreshPower() {
        queue.async { [self] in
            readPower()
            emit()
        }
    }

    private func step() {
        count += 1
        sampleCPU()
        sampleMemory()
        if count % 2 == 0 { sampleSMC() }
        if count % 5 == 0 { sampleBattery() }
        if count % 10 == 0 { readPower() }
        if wantsProcesses && count % 2 == 0 { sampleProcesses() }
        if count % 120 == 0 { identities = [:] }
        emit()
    }

    private func emit() {
        let copy = snapshot
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onSnapshot?(copy) }
        }
    }

    // MARK: Processor and memory

    private func sampleCPU() {
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var totals = [UInt64](repeating: 0, count: 4)
        for cpu in 0..<Int(processorCount) {
            let base = cpu * Int(CPU_STATE_MAX)
            totals[0] += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            totals[1] += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            totals[2] += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            totals[3] += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
        }
        if let previous = previousTicks {
            let delta = zip(totals, previous).map { $0 >= $1 ? $0 - $1 : 0 }
            let busy = Double(delta[0] + delta[1] + delta[3])
            let all = busy + Double(delta[2])
            if all > 0 {
                snapshot.cpu = min(max(busy / all * 100, 0), 100)
                snapshot.cpuReady = true
            }
        }
        previousTicks = totals
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        if result == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            let used = Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)
            snapshot.memoryUsed = used * page
        }
        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0 {
            snapshot.pressure = level >= 4 ? .critical : level >= 2 ? .warning : .normal
        }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            snapshot.swapUsed = Double(swap.xsu_used)
        }
    }

    // MARK: SMC

    private func sampleSMC() {
        var buffer = [SAVFanReading](repeating: SAVFanReading(actual: 0, minimum: 0, maximum: 0, target: 0), count: 6)
        let found = buffer.withUnsafeMutableBufferPointer { sav_smc_read_fans($0.baseAddress, Int32($0.count)) }
        snapshot.fans = found > 0
            ? (0..<Int(found)).map {
                FanReading(id: $0, actual: Double(buffer[$0].actual), minimum: Double(buffer[$0].minimum),
                           maximum: Double(buffer[$0].maximum))
            }
            : []
        snapshot.fansRead = true
        var celsius: Float = 0
        snapshot.temperature = sav_smc_read_temperature(&celsius) == 0 && celsius > 5 && celsius < 130
            ? Double(celsius) : nil
    }

    // MARK: Battery

    private func sampleBattery() {
        var info = BatteryInfo()
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                      (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
                info.present = true
                let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
                let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
                info.percent = maximum > 0 ? min(current / maximum * 100, 100) : 0
                info.charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
                info.onAdapter = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                if let empty = (description[kIOPSTimeToEmptyKey] as? NSNumber)?.intValue, empty > 0 {
                    info.minutesToEmpty = empty
                }
                if let full = (description[kIOPSTimeToFullChargeKey] as? NSNumber)?.intValue, full > 0 {
                    info.minutesToFull = full
                }
            }
        }
        if info.present {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                if let nominal = registryNumber(service, "NominalChargeCapacity"),
                   let design = registryNumber(service, "DesignCapacity"), design > 0 {
                    info.health = min(nominal / design * 100, 100)
                }
                if let cycles = registryNumber(service, "CycleCount") { info.cycles = Int(cycles) }
                IOObjectRelease(service)
            }
        }
        snapshot.battery = info
    }

    private func registryNumber(_ service: io_service_t, _ key: String) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        return (value as? NSNumber)?.doubleValue
    }

    private func readPower() {
        if let reading = PowerProbe.read() { snapshot.power = reading }
    }

    // MARK: Processes

    private func sampleProcesses() {
        let now = mach_absolute_time()
        let capacity = 4096
        var pids = [pid_t](repeating: 0, count: capacity)
        let found = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        guard found > 0 else { return }
        let me = getpid()
        var nextTimes: [pid_t: UInt64] = [:]
        var totals: [String: (name: String, path: String?, nanos: UInt64)] = [:]
        for pid in pids.prefix(min(found, capacity)) where pid > 0 && pid != me {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.stride)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            let nanos = (info.pti_total_user + info.pti_total_system) * timebase.numer / timebase.denom
            nextTimes[pid] = nanos
            guard let previous = processTimes[pid], nanos > previous else { continue }
            let identity = identity(of: pid)
            totals[identity.key, default: (identity.name, identity.path, 0)].nanos += nanos - previous
        }
        let elapsed = lastProcessSample == 0 ? 0 : (now - lastProcessSample) * timebase.numer / timebase.denom
        processTimes = nextTimes
        lastProcessSample = now
        guard elapsed > 0 else { return }
        let rows = totals
            .map { BusyApp(id: $0.key, name: $0.value.name, appPath: $0.value.path,
                           cpu: Double($0.value.nanos) / Double(elapsed) / cores * 100) }
            .filter { $0.cpu >= 0.3 }
            .sorted { $0.cpu > $1.cpu }
        let top = Array(rows.prefix(5))
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onProcesses?(top) }
        }
    }

    private func identity(of pid: pid_t) -> (key: String, name: String, path: String?) {
        if let cached = identities[pid] { return cached }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let result: (key: String, name: String, path: String?)
        if length > 0 {
            let path = String(cString: buffer)
            if let range = path.range(of: ".app/") {
                let appPath = String(path[..<range.lowerBound]) + ".app"
                let name = ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
                result = (appPath, name, appPath)
            } else {
                result = (path, (path as NSString).lastPathComponent, nil)
            }
        } else {
            var name = [CChar](repeating: 0, count: 256)
            proc_name(pid, &name, 256)
            let text = String(cString: name)
            result = ("name:\(text)", text.isEmpty ? "\(pid)" : text, nil)
        }
        identities[pid] = result
        return result
    }
}
