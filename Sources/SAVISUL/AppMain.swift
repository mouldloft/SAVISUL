import AppKit
import ApplicationServices
import CoreGraphics
import SMCBridge

@main
enum SAVISULMain {
    static func main() {
        let arguments = CommandLine.arguments
        if BridgeHost.isRequested(arguments) { BridgeHost.run() }
        if arguments.contains("--probe-screen") {
            print(CGPreflightScreenCaptureAccess() ? "1" : "0")
            return
        }
        if arguments.contains("--self-check") {
            MainActor.assumeIsolated { SelfCheck.run() }
            return
        }
        if arguments.contains("--agent-report") {
            AgentReport.print()
            return
        }
        if let index = arguments.firstIndex(of: "--render-icon"), index + 1 < arguments.count {
            MainActor.assumeIsolated { IconRenderer.writeIconset(to: URL(fileURLWithPath: arguments[index + 1])) }
            return
        }
        if let index = arguments.firstIndex(of: "--render-extension-icons"), index + 1 < arguments.count {
            MainActor.assumeIsolated { IconRenderer.writeExtensionIcons(to: URL(fileURLWithPath: arguments[index + 1])) }
            return
        }
        var dumpFolder: URL?
        if let index = arguments.firstIndex(of: "--dump-panels") {
            dumpFolder = URL(fileURLWithPath: index + 1 < arguments.count ? arguments[index + 1] : FileManager.default.currentDirectoryPath)
        }
        let background = arguments.contains("--background")
        if dumpFolder == nil, SingleInstance.handOff(present: !background) { return }
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate(dumpFolder: dumpFolder, background: background)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let dumpFolder: URL?
    private let background: Bool
    private var controller: PanelController?
    private var bridge: BridgeServer?
    private var launchedAtLogin = false
    private var terminationSource: DispatchSourceSignal?

    init(dumpFolder: URL?, background: Bool = false) {
        self.dumpFolder = dumpFolder
        self.background = background
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAtLogin = LaunchContext.isLoginLaunch()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(preview: dumpFolder != nil)
        let controller = PanelController(model: model)
        self.controller = controller
        if let dumpFolder {
            NSApp.setActivationPolicy(.accessory)
            controller.dumpPanels(to: dumpFolder)
            return
        }
        controller.start(showPanel: !launchedAtLogin && !background)
        SingleInstance.listen { [weak controller] in controller?.show() }
        let bridge = BridgeServer(model: model)
        bridge.onOpen = { [weak controller] in controller?.show() }
        bridge.start()
        self.bridge = bridge
        DispatchQueue.global(qos: .utility).async { BrowserIntegration.prepare() }
        handleTermination()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard dumpFolder == nil else { return }
        controller?.shutdown()
    }

    /// `pkill` and logout send SIGTERM; route it through NSApp so activity is saved.
    private func handleTermination() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        source.resume()
        terminationSource = source
    }
}

@MainActor
enum SelfCheck {
    static func run() {
        print("SAVISUL self-check")
        if let power = PowerProbe.read() {
            print("power: SleepDisabled=\(power.sleepDisabled) sleep=\(power.sleepMinutes.map(String.init) ?? "?") holders=\(power.holders)")
        } else {
            print("power: pmset unreadable")
        }
        let sampler = SystemSampler()
        var last = SystemSnapshot()
        var count = 0
        sampler.onSnapshot = { snapshot in
            last = snapshot
            count += 1
        }
        sampler.start()
        let deadline = Date().addingTimeInterval(5)
        while count < 3 && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        print(String(format: "cpu: %.1f%% ready=%@", last.cpu, last.cpuReady ? "yes" : "no"))
        print(String(format: "memory: %.1f of %.1f GB, pressure=%@, swap=%.2f GB", last.memoryUsed / 1_073_741_824,
                     last.memoryTotal / 1_073_741_824, "\(last.pressure)", last.swapUsed / 1_073_741_824))
        print("temperature: \(last.temperature.map { String(format: "%.1f°C", $0) } ?? "none")")
        for fan in last.fans {
            print(String(format: "fan %d: %.0f rpm (%.0f–%.0f)", fan.id, fan.actual, fan.minimum, fan.maximum))
        }
        let battery = last.battery
        print("battery: present=\(battery.present) \(Int(battery.percent))% charging=\(battery.charging) adapter=\(battery.onAdapter) health=\(battery.health.map { String(format: "%.1f%%", $0) } ?? "?") cycles=\(battery.cycles.map(String.init) ?? "?")")
        let audio = AudioService()
        audio.reload(force: true)
        for device in audio.outputs {
            print("output: \(device.name) [\(device.symbol)] volume=\(device.volume.map { String(format: "%.3f", $0) } ?? "none") muted=\(device.muted.map { "\($0)" } ?? "n/a")\(device.id == audio.defaultOutput ? " default" : "")")
        }
        for device in audio.inputs {
            print("input: \(device.name) [\(device.symbol)]\(device.id == audio.defaultInput ? " default" : "")")
        }
        print("balance: \(audio.hasBalance ? String(format: "%.3f", audio.balance) : "n/a")")
        print("accessibility: \(AXIsProcessTrusted()) screen: \(CGPreflightScreenCaptureAccess())")
        print("ip: \(UtilityStore.localIPv4() ?? "none")")
    }
}
