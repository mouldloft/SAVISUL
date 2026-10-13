import Foundation
import Testing
@testable import SAVISUL

@MainActor
struct WallpaperTests {
    @Test func targetsSayWhereTheWallpaperPlays() {
        #expect(!WallpaperTarget.off.inApp && !WallpaperTarget.off.onDesktop)
        #expect(WallpaperTarget.app.inApp && !WallpaperTarget.app.onDesktop)
        #expect(!WallpaperTarget.desktop.inApp && WallpaperTarget.desktop.onDesktop)
        #expect(WallpaperTarget.both.inApp && WallpaperTarget.both.onDesktop)
    }

    @Test func everyLanguageNamesTheWallpaperSettings() {
        let keys: [Copy] = [.wallpaper, .wallpaperDetail, .wallpaperGlow, .wallpaperGlowDetail, .wpScene, .wpWhere, .wpAdd]
            + WallpaperTarget.allCases.map(\.copy) + WallpaperLandscape.allCases.map(\.copy)
        for language in Language.allCases {
            for key in keys { #expect(L10n.text(key, language) != key.rawValue, "\(language) \(key)") }
        }
    }

    @Test func petalsComeToRestOnEachLandscapesGround() {
        // The studio bonsai's stand, and the floor beyond it.
        let bonsai = WallpaperLandscape.bonsai.art(for: .desktop)
        #expect(abs(bonsai.groundY(atX: 0.5) - 0.86) < 0.001)
        #expect(abs(bonsai.groundY(atX: 0.1) - 0.97) < 0.001)
        for landscape in WallpaperLandscape.allCases where landscape != .custom {
            for placement in [SakuraScene.Placement.panel, .desktop] {
                let art = landscape.art(for: placement)
                #expect(art.resource.hasPrefix("sakura"))
                for x in stride(from: 0.0, through: 1.0, by: 0.05) {
                    let y = art.groundY(atX: CGFloat(x))
                    #expect(y > 0.5 && y < 1, "\(landscape) \(placement) at \(x)")
                }
            }
        }
    }

    @Test func theBreezeDoesNotComeRoundAgain() {
        // Petals drift on a sum of incommensurate waves; no shift up to an hour reproduces the first minute.
        let minute = stride(from: 0.0, to: 60, by: 0.5).map { SakuraArt.wind(at: $0) }
        for shift in stride(from: 5.0, through: 3600, by: 5) {
            let shifted = stride(from: 0.0, to: 60, by: 0.5).map { SakuraArt.wind(at: $0 + shift) }
            let error = zip(minute, shifted).map { abs($0 - $1) }.max() ?? 0
            #expect(error > 0.01, "the wind repeats after \(shift) s")
        }
    }
}
