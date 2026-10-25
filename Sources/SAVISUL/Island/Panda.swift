import SwiftUI

/// What the panda is doing: running in to say something is done, raising a paw when an answer is needed, slumping
/// after a limit, typing on a little laptop while an agent works, saying hello, ringing an alarm, dozing off when the
/// battery runs low or late at night, and dancing while music plays.
enum PandaMood: Equatable {
    case done, ask, limit, working, hello, alarm, sleepy, dance
}

private struct MotionPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Views kept while their window is hidden hold still: a SwiftUI clock in an ordered-out panel goes on drawing.
    var motionPaused: Bool {
        get { self[MotionPausedKey.self] }
        set { self[MotionPausedKey.self] = newValue }
    }
}

/// SAVISUL's panda, drawn in code and moved by the clock, so it costs nothing until it is on screen.
/// Everything is laid out on a 100 × 100 grid and scaled to the view.
struct PandaView: View {
    let mood: PandaMood
    var size: CGFloat = 44
    /// The agent's colour, for the glow of the laptop screen while it works.
    var tint = Color(red: 0.85, green: 0.47, blue: 0.34)
    /// A still frame at this many seconds in, for renders of the panda; nil plays it live.
    var frozen: Double? = nil
    @State private var start = Date()
    @Environment(\.motionPaused) private var motionPaused

    private static let furLight = Color.white
    private static let furShade = Color(red: 0.89, green: 0.86, blue: 0.81)
    private static let inkLight = Color(red: 0.29, green: 0.26, blue: 0.24)
    private static let ink = Color(red: 0.09, green: 0.08, blue: 0.075)
    /// A light edge on the dark parts, so ears and paws read against the black island.
    private static let rim = Color.white.opacity(0.24)
    private static let blush = Color(red: 1, green: 0.55, blue: 0.62)
    private static let champagne = Color(red: 0.9, green: 0.81, blue: 0.64)

    var body: some View {
        Group {
            if let frozen {
                frame(at: frozen)
            } else {
                // Thirty frames a second: each one is drawn afresh, and the display's own rate (up to 120 on a ProMotion
                // Mac) kept SAVISUL at half a core whenever a panda was on, or kept in a hidden panel.
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: motionPaused)) { timeline in
                    frame(at: timeline.date.timeIntervalSince(start))
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { start = Date() }
        .accessibilityHidden(true)
    }

    private func frame(at t: Double) -> some View {
        Canvas { context, canvas in
            context.scaleBy(x: canvas.width / 100, y: canvas.height / 100)
            if mood == .working { drawWorking(&context, t) } else { drawWhole(&context, t) }
        }
    }

    // MARK: The whole panda

    private func drawWhole(_ c: inout GraphicsContext, _ t: Double) {
        // It runs in from the left, skids to a stop in a puff of dust, lands with a squash, then does what its mood says.
        // Hello pops up where it stands instead.
        let runs = [.done, .ask, .limit, .alarm].contains(mood)
        let arrival = runs ? min(max(t / 0.7, 0), 1) : 1
        let running = arrival < 1
        let x = runs ? -(pow(1 - arrival, 3)) * 125 : 0
        let settled = runs ? max(t - 0.7, 0) : t
        // Hello pops up with a small overshoot.
        let pop = runs ? 1 : (t < 0.45 ? 0.55 + sin(t / 0.45 * .pi * 0.62) * 0.53 : 1)
        let landing = runs && settled < 0.28 ? sin(settled / 0.28 * .pi) : 0
        let cheering = mood == .done && !running && settled < 1.9
        let hop: CGFloat = cheering ? max(0, sin(settled * 7.2)) * 12 : 0
        var lift: CGFloat = running ? abs(sin(t * 15)) * 4 : hop
        if mood == .hello { lift = max(0, sin(min(t, 0.5) * .pi * 2)) * 6 }
        if mood == .dance { lift = abs(sin(t * 4.2)) * 4 }
        var lean: Double = running ? 9 : 0
        if mood == .ask && !running { lean = sin(settled * 2.1) * 2.5 }
        if mood == .limit && !running { lean = -6 }
        if mood == .dance { lean = sin(t * 4.2) * 9 }
        if mood == .sleepy { lean = sin(t * 0.9) * 3 }
        // An alarm shakes for a moment when it lands.
        if mood == .alarm && !running && settled < 1.4 { lean += sin(settled * 38) * 3.5 }
        let stride = running ? sin(t * 30) * 32 : 0
        let breath = 1 + 0.018 * sin(t * 2.6)
        let squashY = (1 - 0.11 * landing) * breath
        let squashX = 1 + 0.08 * landing

        // Shadow, smaller while it's in the air.
        let air = lift / 14
        shade(&c, x: 50 + x, y: 95, width: 46 * (1 - air * 0.35), height: 7, .radialGradient(
            Gradient(colors: [Color.black.opacity(0.5 - air * 0.2), .clear]), center: .zero, startRadius: 0, endRadius: 24))

        // Dust where it stopped.
        if runs && settled > 0 && settled < 0.5 {
            for index in 0..<3 {
                let k = settled / 0.5
                let spread = CGFloat(index) * 7 + CGFloat(k) * 10
                shade(&c, x: 30 - spread, y: 91 - CGFloat(index) * 3 - CGFloat(k) * 4, width: 7 + CGFloat(k) * 8, height: 6 + CGFloat(k) * 6,
                      .color(Color.white.opacity(0.32 * (1 - k))))
            }
        }

        var body = c
        body.translateBy(x: 50 + x, y: 95 - lift)
        body.scaleBy(x: squashX * pop, y: squashY * pop)
        body.rotate(by: .degrees(lean))
        body.translateBy(x: -50, y: -95)

        // Legs, then the round body over them.
        limb(&body, from: CGPoint(x: 41, y: 79), length: 15, width: 12, angle: stride)
        limb(&body, from: CGPoint(x: 59, y: 79), length: 15, width: 12, angle: -stride)
        shade(&body, x: 50, y: 73, width: 44, height: 34, fur(width: 44, height: 34))
        shade(&body, x: 50, y: 77, width: 24, height: 17, .color(Color.white.opacity(0.55)))

        // Arms: up when it cheers, one waving when it asks or says hello, swinging when it runs.
        // A raised arm is drawn over the head, out to the side, so the paw shows beside the face.
        // Hello waves for a couple of seconds, then rests; asking and alarms keep waving, alarms faster.
        let waving = !running && (mood == .ask || mood == .alarm || (mood == .hello && settled < 2.6))
        let waveSpeed = mood == .alarm ? 16.0 : 9.5
        var leftArm: Double = cheering ? 128 + sin(settled * 14) * 10 : (running ? 34 - stride : 36)
        var rightArm: Double = waving ? -122 + sin(settled * waveSpeed) * 18 : (cheering ? -128 - sin(settled * 14) * 10 : (running ? -34 - stride : -36))
        if mood == .dance {
            leftArm = 70 + sin(t * 8.4) * 62
            rightArm = -70 + sin(t * 8.4) * 62
        }
        if mood == .sleepy {
            leftArm = 24
            rightArm = -24
        }
        let arms = [(CGPoint(x: 31, y: 64), leftArm), (CGPoint(x: 69, y: 64), rightArm)]
        for (shoulder, angle) in arms where abs(angle) <= 90 {
            limb(&body, from: shoulder, length: 16, width: 11, angle: angle)
        }

        // The head tilts toward the buttons when it asks, and droops after a limit.
        var head = body
        let tilt: Double = mood == .ask && !running ? 7 : (mood == .limit && !running ? -9 : (running ? -4 : 0))
        head.translateBy(x: 50, y: 58)
        head.rotate(by: .degrees(tilt))
        head.translateBy(x: -50, y: -58)
        let flop: Double = running ? sin(t * 30) * 7 : sin(t * 1.3) * 1.5
        ear(&head, x: 28.5, y: 21, angle: -flop)
        ear(&head, x: 71.5, y: 21, angle: flop)
        shade(&head, x: 50, y: 40, width: 56, height: 48, fur(width: 56, height: 48))
        head.stroke(Path(ellipseIn: CGRect(x: 22, y: 16, width: 56, height: 48)), with: .color(Color.black.opacity(0.12)), lineWidth: 0.8)

        // Eye patches, then the eyes: glossy when open, closed arcs when it blinks or beams.
        patch(&head, x: 38.5, y: 41, angle: 34)
        patch(&head, x: 61.5, y: 41, angle: -34)
        let blink = t.truncatingRemainder(dividingBy: 3.6) > 3.47
        let beaming = (cheering && hop > 4) || (mood == .dance && sin(t * 2.1) > 0.3)
        let asleep = mood == .sleepy
        let glance: CGFloat = mood == .ask && !running ? 1.5 : 0
        let tired = mood == .limit && !running
        for side in [-1.0, 1.0] as [CGFloat] {
            let center = CGPoint(x: 50 + side * 10.5, y: 40.5)
            if beaming {
                arc(&head, center: CGPoint(x: center.x, y: center.y + 1.2), width: 7.5, up: true)
            } else if blink || asleep {
                arc(&head, center: CGPoint(x: center.x, y: center.y + 0.6), width: 7, up: false)
            } else {
                eye(&head, center: center, look: glance, tired: tired)
            }
        }

        // Muzzle, nose and mouth.
        shade(&head, x: 50, y: 50.5, width: 19, height: 12.5, .color(Color.white.opacity(0.85)))
        nose(&head, at: CGPoint(x: 50, y: 47.6))
        mouth(&head, open: cheering, sad: tired)
        for side in [-1.0, 1.0] as [CGFloat] {
            shade(&head, x: 50 + side * 16.5, y: 50.5, width: 9, height: 6, .radialGradient(
                Gradient(colors: [Self.blush.opacity(0.75), Self.blush.opacity(0)]), center: .zero, startRadius: 0, endRadius: 5))
        }

        for (shoulder, angle) in arms where abs(angle) > 90 {
            limb(&body, from: shoulder, length: 19, width: 11, angle: angle)
        }

        // What goes with the mood.
        if mood == .done && !running { confetti(&c, settled, x: x) }
        if (mood == .ask || mood == .alarm) && !running {
            bubble(&c, at: CGPoint(x: 86 + x, y: 13 + sin(settled * 3) * 1.5), scale: min(settled / 0.22, 1), text: mood == .alarm ? "!" : "?")
        }
        if tired { drop(&c, settled, x: x) }
        if mood == .sleepy { float(&c, "z", t: t, from: CGPoint(x: 78, y: 26), rise: 22, size: 12) }
        if mood == .dance { float(&c, "♪", t: t, from: CGPoint(x: 84, y: 34), rise: 26, size: 13) }
    }

    // MARK: Typing in the wing

    private func drawWorking(_ c: inout GraphicsContext, _ t: Double) {
        var head = c
        head.translateBy(x: 0, y: sin(t * 4) * 1.4 - 6)
        ear(&head, x: 25, y: 20, angle: 0, scale: 1.25)
        ear(&head, x: 75, y: 20, angle: 0, scale: 1.25)
        shade(&head, x: 50, y: 46, width: 74, height: 60, fur(width: 74, height: 60))
        patch(&head, x: 35.5, y: 48, angle: 30, scale: 1.3)
        patch(&head, x: 64.5, y: 48, angle: -30, scale: 1.3)
        let blink = t.truncatingRemainder(dividingBy: 4) > 3.86
        for side in [-1.0, 1.0] as [CGFloat] {
            let center = CGPoint(x: 50 + side * 14, y: 49)
            if blink {
                arc(&head, center: center, width: 9, up: false)
            } else {
                // Eyes down on the screen.
                eye(&head, center: center, look: 0, tired: false, scale: 1.3, down: 1.4)
            }
        }
        nose(&head, at: CGPoint(x: 50, y: 60), scale: 1.25)

        // The little laptop, its screen in the agent's colour, and two paws on the keys.
        let screen = Path(roundedRect: CGRect(x: 22, y: 70, width: 56, height: 22), cornerRadius: 3)
        c.fill(screen, with: .color(Color(red: 0.55, green: 0.56, blue: 0.6)))
        c.fill(Path(roundedRect: CGRect(x: 25.5, y: 73, width: 49, height: 17), cornerRadius: 2), with: .linearGradient(
            Gradient(colors: [tint.opacity(0.95), tint.opacity(0.45)]), startPoint: CGPoint(x: 50, y: 73), endPoint: CGPoint(x: 50, y: 90)))
        c.fill(Path(roundedRect: CGRect(x: 14, y: 91, width: 72, height: 6), cornerRadius: 3), with: .color(Color(red: 0.72, green: 0.73, blue: 0.76)))
        let tap = sin(t * 15)
        shade(&c, x: 33, y: 91 - max(tap, 0) * 5, width: 17, height: 11, dark(width: 17, height: 11), rim: true)
        shade(&c, x: 67, y: 91 - max(-tap, 0) * 5, width: 17, height: 11, dark(width: 17, height: 11), rim: true)
    }

    // MARK: Parts

    private func fur(width: CGFloat, height: CGFloat) -> GraphicsContext.Shading {
        .radialGradient(Gradient(colors: [Self.furLight, Self.furShade]), center: CGPoint(x: -width * 0.16, y: -height * 0.22),
                        startRadius: 0, endRadius: max(width, height) * 0.72)
    }

    private func dark(width: CGFloat, height: CGFloat) -> GraphicsContext.Shading {
        .radialGradient(Gradient(colors: [Self.inkLight, Self.ink]), center: CGPoint(x: -width * 0.2, y: -height * 0.25),
                        startRadius: 0, endRadius: max(width, height) * 0.75)
    }

    /// An ellipse centred on x, y, filled with `shading` drawn around its own centre.
    private func shade(_ c: inout GraphicsContext, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                       _ shading: GraphicsContext.Shading, rotation: Double = 0, rim: Bool = false) {
        var local = c
        local.translateBy(x: x, y: y)
        if rotation != 0 { local.rotate(by: .degrees(rotation)) }
        let path = Path(ellipseIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        local.fill(path, with: shading)
        if rim { local.stroke(path, with: .color(Self.rim), lineWidth: 1.1) }
    }

    private func ear(_ c: inout GraphicsContext, x: CGFloat, y: CGFloat, angle: Double, scale: CGFloat = 1) {
        var local = c
        local.translateBy(x: x, y: y)
        local.rotate(by: .degrees(angle))
        local.scaleBy(x: scale, y: scale)
        shade(&local, x: 0, y: 0, width: 19, height: 18, dark(width: 19, height: 18), rim: true)
        shade(&local, x: x < 50 ? 1.5 : -1.5, y: 1.5, width: 9, height: 8.5, .color(Self.inkLight.opacity(0.9)))
    }

    /// A teardrop of dark fur around an eye, leaning outward and down like a real panda's.
    private func patch(_ c: inout GraphicsContext, x: CGFloat, y: CGFloat, angle: Double, scale: CGFloat = 1) {
        var local = c
        local.translateBy(x: x, y: y)
        local.rotate(by: .degrees(angle))
        local.scaleBy(x: scale, y: scale)
        var drop = Path()
        drop.move(to: CGPoint(x: 0, y: -10))
        drop.addCurve(to: CGPoint(x: 0, y: 10), control1: CGPoint(x: 9.5, y: -10), control2: CGPoint(x: 8.5, y: 10))
        drop.addCurve(to: CGPoint(x: 0, y: -10), control1: CGPoint(x: -8.5, y: 10), control2: CGPoint(x: -9.5, y: -10))
        local.fill(drop, with: dark(width: 18, height: 20))
    }

    /// A glossy eye: a dark pupil with two catchlights, looking `look` to the right and `down` lower.
    private func eye(_ c: inout GraphicsContext, center: CGPoint, look: CGFloat, tired: Bool, scale: CGFloat = 1, down: CGFloat = 0) {
        var local = c
        local.translateBy(x: center.x, y: center.y)
        local.scaleBy(x: scale, y: scale)
        local.fill(Path(ellipseIn: CGRect(x: -4.6, y: -4.8, width: 9.2, height: 9.6)), with: .color(.white))
        let pupil = CGPoint(x: look, y: 0.4 + down)
        local.fill(Path(ellipseIn: CGRect(x: pupil.x - 3.4, y: pupil.y - 3.6, width: 6.8, height: 7.2)), with: .color(Self.ink))
        local.fill(Path(ellipseIn: CGRect(x: pupil.x + 0.4, y: pupil.y - 2.9, width: 2.6, height: 2.6)), with: .color(.white))
        local.fill(Path(ellipseIn: CGRect(x: pupil.x - 2.2, y: pupil.y + 1.1, width: 1.3, height: 1.3)), with: .color(.white.opacity(0.85)))
        if tired {
            // Heavy lids after a limit.
            local.fill(Path(CGRect(x: -5, y: -5.2, width: 10, height: 5.4)), with: .color(Self.ink))
            var lid = Path()
            lid.move(to: CGPoint(x: -4.6, y: 0.2))
            lid.addQuadCurve(to: CGPoint(x: 4.6, y: 0.2), control: CGPoint(x: 0, y: 1.6))
            local.stroke(lid, with: .color(.white.opacity(0.6)), lineWidth: 0.8)
        }
    }

    /// A closed eye: down for a blink, up like ^ when it beams.
    private func arc(_ c: inout GraphicsContext, center: CGPoint, width: CGFloat, up: Bool) {
        var path = Path()
        path.move(to: CGPoint(x: center.x - width / 2, y: center.y))
        path.addQuadCurve(to: CGPoint(x: center.x + width / 2, y: center.y), control: CGPoint(x: center.x, y: center.y + (up ? -width * 0.75 : width * 0.55)))
        c.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
    }

    private func nose(_ c: inout GraphicsContext, at point: CGPoint, scale: CGFloat = 1) {
        var local = c
        local.translateBy(x: point.x, y: point.y)
        local.scaleBy(x: scale, y: scale)
        var path = Path()
        path.move(to: CGPoint(x: -3.6, y: -1.8))
        path.addQuadCurve(to: CGPoint(x: 3.6, y: -1.8), control: CGPoint(x: 0, y: -3))
        path.addQuadCurve(to: CGPoint(x: 0, y: 2.6), control: CGPoint(x: 3.4, y: 0.6))
        path.addQuadCurve(to: CGPoint(x: -3.6, y: -1.8), control: CGPoint(x: -3.4, y: 0.6))
        local.fill(path, with: .color(Self.ink))
        local.fill(Path(ellipseIn: CGRect(x: -1.6, y: -2, width: 2, height: 1.2)), with: .color(.white.opacity(0.7)))
    }

    private func mouth(_ c: inout GraphicsContext, open: Bool, sad: Bool) {
        if open {
            c.fill(Path(ellipseIn: CGRect(x: 46.3, y: 51, width: 7.4, height: 6.2)), with: .color(Color(red: 0.42, green: 0.12, blue: 0.16)))
            c.fill(Path(ellipseIn: CGRect(x: 47.6, y: 53.6, width: 4.8, height: 3)), with: .color(Color(red: 0.98, green: 0.5, blue: 0.56)))
            return
        }
        var path = Path()
        if sad {
            path.move(to: CGPoint(x: 46, y: 55))
            path.addQuadCurve(to: CGPoint(x: 50, y: 53.2), control: CGPoint(x: 48, y: 53))
            path.addQuadCurve(to: CGPoint(x: 54, y: 55), control: CGPoint(x: 52, y: 53))
        } else {
            path.move(to: CGPoint(x: 50, y: 50.2))
            path.addLine(to: CGPoint(x: 50, y: 51.6))
            path.move(to: CGPoint(x: 46.4, y: 51.4))
            path.addQuadCurve(to: CGPoint(x: 50, y: 51.6), control: CGPoint(x: 48, y: 54))
            path.addQuadCurve(to: CGPoint(x: 53.6, y: 51.4), control: CGPoint(x: 52, y: 54))
        }
        c.stroke(path, with: .color(Self.ink), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
    }

    private func limb(_ c: inout GraphicsContext, from top: CGPoint, length: CGFloat, width: CGFloat, angle: Double) {
        var local = c
        local.translateBy(x: top.x, y: top.y)
        local.rotate(by: .degrees(angle))
        let path = Path(roundedRect: CGRect(x: -width / 2, y: 0, width: width, height: length), cornerRadius: width / 2)
        local.fill(path, with: .linearGradient(Gradient(colors: [Self.inkLight, Self.ink]), startPoint: CGPoint(x: -width / 2, y: 0),
                                               endPoint: CGPoint(x: width / 2, y: length)))
        local.stroke(path, with: .color(Self.rim), lineWidth: 1)
    }

    /// Bits of colour falling around a panda that's pleased with the news.
    private func confetti(_ c: inout GraphicsContext, _ settled: Double, x: CGFloat) {
        guard settled < 2.6 else { return }
        let colours = [Self.champagne, Self.blush, Color(red: 0.55, green: 0.84, blue: 0.69), Color(red: 0.62, green: 0.8, blue: 0.98)]
        for index in 0..<7 {
            let i = Double(index)
            let fall = settled * (20 + i * 3)
            let px = CGFloat(12 + (i * 13).truncatingRemainder(dividingBy: 76)) + x + CGFloat(sin(settled * 3 + i)) * 4
            let py = CGFloat(-6 + fall - (i * 5).truncatingRemainder(dividingBy: 14))
            guard py > -4, py < 70 else { continue }
            var piece = c
            piece.translateBy(x: px, y: py)
            piece.rotate(by: .degrees(settled * 220 + i * 40))
            piece.opacity = max(0, 1 - settled / 2.6)
            piece.fill(Path(roundedRect: CGRect(x: -2.2, y: -1.2, width: 4.4, height: 2.4), cornerRadius: 0.8), with: .color(colours[index % colours.count]))
        }
    }

    /// Letters or notes drifting up from the panda: z's while it dozes, notes while it dances.
    private func float(_ c: inout GraphicsContext, _ glyph: String, t: Double, from origin: CGPoint, rise: CGFloat, size: CGFloat) {
        for index in 0..<3 {
            let progress = (t * 0.55 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            var local = c
            local.opacity = sin(progress * .pi)
            let point = CGPoint(x: origin.x + CGFloat(index) * 4 + CGFloat(sin(progress * 6)) * 2, y: origin.y - CGFloat(progress) * rise)
            local.draw(Text(glyph).font(.system(size: size * (0.7 + CGFloat(progress) * 0.5), weight: .bold, design: .rounded))
                .foregroundColor(Self.champagne), at: point)
        }
    }

    /// The bubble above a panda that needs an answer, or that rings an alarm.
    private func bubble(_ c: inout GraphicsContext, at point: CGPoint, scale: Double, text: String) {
        guard scale > 0 else { return }
        var local = c
        local.translateBy(x: point.x, y: point.y)
        local.scaleBy(x: scale, y: scale)
        local.fill(Path(ellipseIn: CGRect(x: -10.5, y: -10.5, width: 21, height: 21)), with: .linearGradient(
            Gradient(colors: [Self.champagne, Color(red: 0.8, green: 0.66, blue: 0.45)]), startPoint: CGPoint(x: 0, y: -10), endPoint: CGPoint(x: 0, y: 10)))
        local.draw(Text(text).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundColor(Self.ink), at: CGPoint(x: 0, y: 0.5))
    }

    /// A drop of sweat sliding down after a limit.
    private func drop(_ c: inout GraphicsContext, _ settled: Double, x: CGFloat) {
        let slide = CGFloat((settled * 0.6).truncatingRemainder(dividingBy: 1))
        var local = c
        local.translateBy(x: 24 + x, y: 24 + slide * 14)
        local.opacity = Double(1 - slide)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -5))
        path.addQuadCurve(to: CGPoint(x: 0, y: 4), control: CGPoint(x: 5, y: 2))
        path.addQuadCurve(to: CGPoint(x: 0, y: -5), control: CGPoint(x: -5, y: 2))
        local.fill(path, with: .color(Color(red: 0.62, green: 0.82, blue: 1)))
    }
}
