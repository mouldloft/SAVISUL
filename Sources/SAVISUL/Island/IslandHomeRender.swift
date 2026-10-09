import AppKit
import SwiftUI

/// Panel renders (--dump-panels): the island's Home tab playing a sample track, as panels-island-home.png.
/// The track, its lyrics and its cover are the site's fictional "Low Tide Hours", so renders never show someone else's music.
/// The size is the tab's content area in an expanded island (640 x 232), so the render drops into a capture 1:1.
@MainActor
enum IslandHomeRender {
    private static let gold = Color(red: 0.906, green: 0.769, blue: 0.561)

    static func dump(to folder: URL, completion: @escaping () -> Void) {
        let suite = Suite.shared
        let length = 214.0
        let lines = ["We left the porch light on for no one", "the tide came in and kept the time", "low tide hours, slow and golden",
                     "nothing to fix and nothing to find", "stay a while, the night is open", "the water knows the way back home"]
        suite.nowPlaying.preview(NowPlayingItem(title: "Low Tide Hours", artist: "Maren Vale", album: "", duration: length, elapsed: 84,
                                                rate: 0, stamp: Date(), playing: true, pid: 0),
                                 artwork: cover(), tint: gold, appPath: "/System/Applications/Music.app")
        suite.lyrics.preview(lines.enumerated().map { Lyrics.Line(time: Double($0.offset) * length / Double(lines.count), text: $0.element) })
        suite.calendar.preview([])
        let size = NSSize(width: 640, height: 232)
        let content = IslandHome(suite: suite)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated {
                if let view = window.contentView {
                    view.layoutSubtreeIfNeeded()
                    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("panels-island-home.png"))
                    }
                }
                window.orderOut(nil)
                completion()
            }
        }
    }

    /// The site's cover for the track: a low sun over dark water.
    private static func cover() -> NSImage? {
        let renderer = ImageRenderer(content: SampleCover(light: gold).frame(width: 104, height: 104))
        renderer.scale = 2
        return renderer.nsImage
    }
}

private struct SampleCover: View {
    let light: Color
    private let mid = Color(red: 0.541, green: 0.310, blue: 0.165)
    private let dark = Color(red: 0.114, green: 0.078, blue: 0.063)

    var body: some View {
        Canvas { context, size in
            let unit = size.width / 100
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [mid, dark]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            context.fill(Path(ellipseIn: CGRect(x: 47 * unit, y: 23 * unit, width: 34 * unit, height: 34 * unit)), with: .color(light))
            for index in 0..<4 {
                let y = Double(70 + index * 8) * unit
                var wave = Path()
                wave.move(to: CGPoint(x: 0, y: y))
                wave.addQuadCurve(to: CGPoint(x: 50 * unit, y: y), control: CGPoint(x: 25 * unit, y: y - 8 * unit))
                wave.addQuadCurve(to: CGPoint(x: 100 * unit, y: y), control: CGPoint(x: 75 * unit, y: y + 8 * unit))
                wave.addLine(to: CGPoint(x: size.width, y: size.height))
                wave.addLine(to: CGPoint(x: 0, y: size.height))
                wave.closeSubpath()
                context.fill(wave, with: .color(dark.opacity(0.45 + Double(index) * 0.15)))
            }
        }
    }
}
