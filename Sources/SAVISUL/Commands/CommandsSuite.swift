import AppKit
import Carbon.HIToolbox

/// The command bar, the radial menu and the favourites palette with their shortcuts.
@MainActor
final class CommandsSuite {
    let bar = CommandBar()
    let radial = RadialMenu()
    let quick = QuickPanel()
    private(set) var barCombo: KeyCombo = .option(kVK_Space)

    func apply(_ settings: SuiteSettings) {
        if settings.commandBar {
            if !HotKeyCenter.shared.isRegistered("command.bar") {
                barCombo = .option(kVK_Space)
                if !HotKeyCenter.shared.register("command.bar", barCombo, press: { Suite.shared.commands.bar.toggle() }) {
                    barCombo = .control(kVK_Space)
                    HotKeyCenter.shared.register("command.bar", barCombo, press: { Suite.shared.commands.bar.toggle() })
                }
            }
        } else {
            HotKeyCenter.shared.unregister("command.bar")
            bar.close()
        }

        if settings.radial {
            if !HotKeyCenter.shared.isRegistered("command.radial") {
                HotKeyCenter.shared.register("command.radial", .control(kVK_ANSI_R), press: { Suite.shared.commands.radial.press() },
                                             release: { Suite.shared.commands.radial.release() })
            }
        } else {
            HotKeyCenter.shared.unregister("command.radial")
            radial.close(run: false)
        }

        if settings.radial && settings.radialMouse {
            if !InputTap.shared.has("radial.mouse") {
                InputTap.shared.add("radial.mouse", priority: 20, types: [.otherMouseDown, .otherMouseUp]) { type, event in
                    guard event.getIntegerValueField(.mouseEventButtonNumber) == 2 else { return event }
                    if type == .otherMouseDown { Suite.shared.commands.radial.press() } else { Suite.shared.commands.radial.release() }
                    return nil
                }
            }
        } else {
            InputTap.shared.remove("radial.mouse")
        }

        if settings.quickPanel {
            if !HotKeyCenter.shared.isRegistered("command.quick") {
                HotKeyCenter.shared.register("command.quick", .control(kVK_ANSI_P), press: { Suite.shared.commands.quick.toggle() })
            }
        } else {
            HotKeyCenter.shared.unregister("command.quick")
            quick.hide()
        }
        quick.refresh()

        if settings.contextActions {
            if !HotKeyCenter.shared.isRegistered("context.actions") {
                HotKeyCenter.shared.register("context.actions", .control(kVK_ANSI_A), press: { Suite.shared.contextActions.toggle() })
            }
        } else {
            HotKeyCenter.shared.unregister("context.actions")
            Suite.shared.contextActions.close()
        }
    }
}
