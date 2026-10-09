import AppKit

/// The window and Dock features, switched together from the suite settings.
@MainActor
final class WindowsSuite {
    let switcher = Switcher()
    let snapper = Snapper()
    let dragSnap = DragSnap()
    let dock = DockPreview()
    let tweaks = WindowTweaks()

    func apply(_ settings: SuiteSettings) {
        WindowCatalog.shared.start()
        if settings.switcher { switcher.enable(commandTab: settings.switcherCommandTab) } else { switcher.disable() }
        snapper.enable(settings.snapping)
        dragSnap.enable(modifier: settings.modifierDrag, edges: settings.edgeSnap)
        dock.enable(settings.dockPreview)
        tweaks.apply(settings)
        InputTap.shared.start()
    }

    /// Gives ⌘Tab back to macOS.
    func shutdown() {
        switcher.disable()
    }
}
