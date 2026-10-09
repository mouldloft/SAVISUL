import CoreGraphics
import Testing
@testable import SAVISUL

let layoutScreen = CGRect(x: 0, y: 0, width: 1200, height: 800)
let layoutWindow = CGRect(x: 100, y: 100, width: 400, height: 300)

@Test func halvesCycle() {
    let half = SnapAction.frame(.left, visible: layoutScreen, current: layoutWindow, cycle: 0)
    #expect(abs(half.width - 600) < 0.1)
    #expect(abs(half.minX) < 0.1)
    #expect(abs(SnapAction.frame(.left, visible: layoutScreen, current: layoutWindow, cycle: 1).width - 800) < 0.1)
    #expect(abs(SnapAction.frame(.left, visible: layoutScreen, current: layoutWindow, cycle: 2).width - 400) < 0.1)
    #expect(abs(SnapAction.frame(.right, visible: layoutScreen, current: layoutWindow, cycle: 0).maxX - 1200) < 0.1)
}

@Test func cornersThirdsAndCenter() {
    let corner = SnapAction.frame(.topLeft, visible: layoutScreen, current: layoutWindow, cycle: 0)
    #expect(abs(corner.width - 600) < 0.1)
    #expect(abs(corner.height - 400) < 0.1)
    let third = SnapAction.frame(.centerThird, visible: layoutScreen, current: layoutWindow, cycle: 0)
    #expect(abs(third.minX - 400) < 0.1)
    #expect(abs(third.width - 400) < 0.1)
    #expect(SnapAction.frame(.maximize, visible: layoutScreen, current: layoutWindow, cycle: 0) == layoutScreen)
    #expect(SnapAction.frame(.almostMaximize, visible: layoutScreen, current: layoutWindow, cycle: 0).width < layoutScreen.width)
    #expect(abs(SnapAction.frame(.center, visible: layoutScreen, current: layoutWindow, cycle: 0).midX - layoutScreen.midX) < 0.1)
}

@Test func smallerStaysInsideTheScreen() {
    let smaller = SnapAction.frame(.smaller, visible: layoutScreen, current: layoutWindow, cycle: 0)
    #expect(smaller.width < layoutWindow.width)
    #expect(smaller.minX >= layoutScreen.minX)
    #expect(smaller.maxX <= layoutScreen.maxX)
}

@Test func shortcutGlyphs() {
    #expect(SnapAction.left.combo.glyphs.contains("⌃"))
    #expect(SnapAction.left.combo.glyphs.contains("⌥"))
    #expect(SnapAction.nextDisplay.combo.glyphs.contains("⌘"))
    #expect(KeyCombo.option(49).glyphs.first == "⌥")
}
