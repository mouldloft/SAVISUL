import AppKit
import Carbon.HIToolbox

/// Clipboard history, plain paste, the floating shelf, Finder shortcuts and the disk image installer.
@MainActor
final class ClipboardSuite {
    let history = ClipboardHistory()
    let panel: ClipboardPanel
    let finder = FinderTweaks()
    let installer = DiskImageInstaller()
    let shelfPanel = ShelfPanel()

    init() {
        panel = ClipboardPanel(history: history)
    }

    func apply(_ settings: SuiteSettings) {
        history.limit = max(50, settings.clipboardLimit)
        if settings.clipboard {
            history.start()
            if !HotKeyCenter.shared.isRegistered("clipboard.panel") {
                HotKeyCenter.shared.register("clipboard.panel", .control(kVK_ANSI_V), press: { Suite.shared.clipboard.panel.toggle() })
            }
        } else {
            history.stop()
            HotKeyCenter.shared.unregister("clipboard.panel")
            panel.close()
        }
        if settings.plainPaste {
            if !HotKeyCenter.shared.isRegistered("clipboard.plain") {
                HotKeyCenter.shared.register("clipboard.plain", .control(kVK_ANSI_V, shift: true), press: { Suite.shared.clipboard.history.pastePlain() })
            }
        } else {
            HotKeyCenter.shared.unregister("clipboard.plain")
        }
        finder.apply(settings)
        installer.enable(settings.dmgInstaller)
        shelfPanel.enable(shake: settings.shelf && settings.shelfShake)
    }
}
