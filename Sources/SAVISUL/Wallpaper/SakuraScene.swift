import AppKit
import ImageIO
import SpriteKit

/// The sakura wallpaper: a painted scene with petals simulated every frame. Nothing is a video, so nothing ever
/// loops: each petal is born on the tree or above the frame, drifts on a wind that never repeats, and lands.
final class SakuraScene: SKScene {
    enum Placement { case panel, desktop }

    /// Lights the wallpaper under the pointer and lets the petals there shy away from it.
    var glowEnabled = true

    /// The painting the petals fall in. Changing it swaps the painting and starts the petals on the new tree.
    var landscape: WallpaperLandscape {
        didSet { if landscape != oldValue && built { reload() } }
    }

    /// The person's own picture, for the custom scene.
    var customPath = "" {
        didSet { if customPath != oldValue && landscape == .custom && built { reload() } }
    }

    private let placement: Placement
    private let painting = SKSpriteNode()
    private let halo = SKSpriteNode(texture: SakuraArt.glow)
    private let light = SKSpriteNode(texture: SakuraArt.glow)
    private let layer = SKNode()
    private let grass = SakuraArt.makeGrassShader()
    private var art: LandscapeArt { landscape.art(for: placement, custom: customPath) }
    private var lastPointer: CGPoint?
    private var grassEnergy: CGFloat = 0
    private var petals: [Petal] = []
    private var paintingRect = CGRect.zero
    private var last: TimeInterval?
    private var clock = 0.0
    private var lightLevel: CGFloat = 0
    private var built = false

    init(size: CGSize, placement: Placement, landscape: WallpaperLandscape) {
        self.placement = placement
        self.landscape = landscape
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = SakuraArt.ground
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        painting.zPosition = 0
        painting.shader = grass
        addChild(painting)
        halo.blendMode = .add
        halo.color = NSColor(calibratedRed: 1, green: 0.72, blue: 0.42, alpha: 1)
        halo.colorBlendFactor = 1
        halo.zPosition = 1
        addChild(halo)
        layer.zPosition = 2
        addChild(layer)
        light.blendMode = .add
        light.alpha = 0
        light.zPosition = 3
        addChild(light)
        layout()
        for _ in 0..<petalCount { petals.append(spawn(scattered: true)) }
    }

    private func reload() {
        for petal in petals { petal.node.removeFromParent() }
        petals.removeAll()
        layout()
        for _ in 0..<petalCount { petals.append(spawn(scattered: true)) }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard built else { return }
        layout()
    }

    // MARK: Layout

    private var petalCount: Int {
        let area = size.width * size.height
        switch placement {
        case .panel: return 30
        case .desktop: return Int(min(max(area / 15_000, 50), 150))
        }
    }

    /// Petal size in points at depth 1.
    private var petalSize: CGFloat { placement == .panel ? 10 : 15 }

    private func layout() {
        let art = self.art
        let painted = SakuraArt.painting(art.resource)
        let image = painted?.size ?? size
        let scale = max(size.width / image.width, size.height / image.height)
        let drawn = CGSize(width: image.width * scale, height: image.height * scale)
        // Cropped around the landscape's focus, so a narrow panel still frames the tree.
        let focus = art.focus
        let x = min(0, max(size.width - drawn.width, size.width / 2 - focus.x * drawn.width))
        let y = min(0, max(size.height - drawn.height, size.height / 2 - (1 - focus.y) * drawn.height))
        paintingRect = CGRect(x: x, y: y, width: drawn.width, height: drawn.height)
        grass.uniformNamed("u_aspect")?.floatValue = Float(drawn.width / max(drawn.height, 1))
        grass.uniformNamed("u_grass_top")?.floatValue = Float(art.grassTop)
        let box = art.sway
        grass.uniformNamed("u_sway")?.vectorFloat4Value = vector_float4(Float(box.minX), Float(box.minY), Float(box.maxX), Float(box.maxY))
        grass.uniformNamed("u_sway_amp")?.floatValue = Float(art.swayAmount)
        if let texture = painted?.texture {
            painting.texture = texture
            painting.size = drawn
            painting.position = CGPoint(x: paintingRect.midX, y: paintingRect.midY)
            painting.isHidden = false
        } else {
            painting.isHidden = true
        }
        halo.size = CGSize(width: drawn.width * 0.42, height: drawn.width * 0.42)
        halo.position = point(art.haloCenter)
        let lightSide: CGFloat = placement == .panel ? 300 : 560
        light.size = CGSize(width: lightSide, height: lightSide)
    }

    /// A point given in the painting's normalised coordinates (origin top-left) placed in the scene.
    private func point(_ unit: CGPoint) -> CGPoint {
        CGPoint(x: paintingRect.minX + unit.x * paintingRect.width, y: paintingRect.maxY - unit.y * paintingRect.height)
    }

    // MARK: Petals

    private func spawn(scattered: Bool) -> Petal {
        let depth = CGFloat.random(in: 0.55...1.6)
        let blurred = depth > 1.38
        let node = SKSpriteNode(texture: blurred ? SakuraArt.blurredPetal : SakuraArt.petals.randomElement())
        let side = petalSize * depth
        node.size = CGSize(width: side, height: side)
        node.alpha = 0
        node.zPosition = depth
        layer.addChild(node)
        var petal = Petal(node: node, depth: depth, blurred: blurred)
        place(&petal, scattered: scattered)
        return petal
    }

    private func place(_ petal: inout Petal, scattered: Bool) {
        let art = self.art
        let fromTree = SakuraArt.painting(art.resource) != nil && Double.random(in: 0...1) < 0.55
        if fromTree, let pad = art.canopy.randomElement() {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let radius = sqrt(CGFloat.random(in: 0...1))
            let unit = CGPoint(x: pad.center.x + cos(angle) * radius * pad.radii.width,
                               y: pad.center.y + sin(angle) * radius * pad.radii.height)
            petal.base = point(unit)
            petal.fromTree = true
        } else {
            let y = scattered ? CGFloat.random(in: -20...(size.height + 20)) : size.height + CGFloat.random(in: 12...60)
            petal.base = CGPoint(x: CGFloat.random(in: -60...(size.width + 20)), y: y)
            petal.fromTree = false
        }
        petal.fall = (placement == .panel ? 28 : 40) * CGFloat.random(in: 0.75...1.25)
        petal.swayAmp = CGFloat.random(in: 10...34) * (placement == .panel ? 0.7 : 1)
        petal.swayRate = Double.random(in: 0.5...1.3)
        petal.phase = Double.random(in: 0...(2 * .pi))
        petal.flipRate = Double.random(in: 1.2...3.2) * (Bool.random() ? 1 : -1)
        petal.spinRate = CGFloat.random(in: -1.1...1.1)
        petal.node.zRotation = CGFloat.random(in: 0...(2 * .pi))
        petal.age = 0
        petal.fadeIn = petal.fromTree ? Double.random(in: 0.8...1.6) : 0.3
        petal.settled = nil
        petal.push = .zero
        petal.landing = CGFloat.random(in: 0...art.landingSpread)
        petal.maxAlpha = petal.blurred ? 0.72 : (0.55 + 0.4 * min(1, (petal.depth - 0.55) / 0.8))
    }

    // MARK: Frame

    override func update(_ currentTime: TimeInterval) {
        let dt = min(max(currentTime - (last ?? currentTime), 0), 1.0 / 20)
        last = currentTime
        clock += dt
        let t = clock
        let wind = SakuraArt.wind(at: t)
        let pointer = glowEnabled ? pointerInScene() : nil

        // The pointer's light eases in and out and trails the pointer a little.
        let lightTarget: CGFloat = pointer == nil ? 0 : 1
        lightLevel += (lightTarget - lightLevel) * CGFloat(1 - exp(-dt * 6))
        if let pointer {
            let follow = CGFloat(1 - exp(-dt * 12))
            light.position = light.alpha < 0.01 ? pointer
                : CGPoint(x: light.position.x + (pointer.x - light.position.x) * follow,
                          y: light.position.y + (pointer.y - light.position.y) * follow)
        }
        light.alpha = 0.42 * lightLevel
        halo.alpha = art.halo * (0.09 + 0.05 * CGFloat(sin(t * 0.55) * 0.5 + 0.5))

        // Grass rustles where the pointer moves through it and settles a moment after it stops.
        var energyTarget: CGFloat = 0
        if let pointer, let previous = lastPointer {
            let speed = hypot(pointer.x - previous.x, pointer.y - previous.y) / CGFloat(max(dt, 1.0 / 240))
            energyTarget = min(1, speed / 450)
        }
        lastPointer = pointer
        grassEnergy += (energyTarget - grassEnergy) * CGFloat(1 - exp(-dt * (energyTarget > grassEnergy ? 10 : 1.4)))
        grass.uniformNamed("u_energy")?.floatValue = Float(grassEnergy)
        grass.uniformNamed("u_wind")?.floatValue = Float(wind)
        if let pointer, paintingRect.width > 0 {
            grass.uniformNamed("u_pointer")?.vectorFloat2Value = vector_float2(Float((pointer.x - paintingRect.minX) / paintingRect.width),
                                                                                Float((pointer.y - paintingRect.minY) / paintingRect.height))
        }

        let reach: CGFloat = placement == .panel ? 110 : 190
        let art = self.art

        for index in petals.indices {
            var petal = petals[index]
            petal.age += dt
            let node = petal.node

            if let settled = petal.settled {
                // Resting on the stand or the floor: it lies still and fades, then a new petal is born.
                let fade = (t - settled) / 3.5
                node.alpha = petal.maxAlpha * CGFloat(max(0, 1 - fade))
                if fade >= 1 { place(&petal, scattered: false) }
                petals[index] = petal
                continue
            }

            petal.base.x += (wind * 26 * petal.depth) * CGFloat(dt)
            petal.base.y -= petal.fall * petal.depth * CGFloat(dt)
            let sway = petal.swayAmp * CGFloat(sin(petal.phase + t * petal.swayRate))
            var position = CGPoint(x: petal.base.x + sway, y: petal.base.y)

            var lit: CGFloat = 0
            if let pointer {
                let dx = position.x - pointer.x, dy = position.y - pointer.y
                let distance = max(sqrt(dx * dx + dy * dy), 1)
                if distance < reach {
                    let strength = pow(1 - distance / reach, 2)
                    petal.push.x += dx / distance * strength * 150 * CGFloat(dt)
                    petal.push.y += dy / distance * strength * 150 * CGFloat(dt)
                    lit = 1 - distance / reach
                }
            }
            // The push decays, so a petal the pointer nudged drifts back into its fall.
            let decay = CGFloat(exp(-dt * 1.4))
            petal.push = CGPoint(x: petal.push.x * decay, y: petal.push.y * decay)
            position.x += petal.push.x
            position.y += petal.push.y

            // Tumbling: the petal's width follows the cosine of its turn, and its pale back shows on the far side.
            let flip = cos(petal.phase + t * petal.flipRate)
            node.xScale = CGFloat(0.18 + 0.82 * abs(flip)) * (flip < 0 ? -1 : 1)
            node.yScale = CGFloat(0.9 + 0.1 * sin(petal.phase * 2 + t * 0.9))
            node.zRotation += petal.spinRate * CGFloat(dt)
            node.position = position
            node.color = lit > 0 ? .white : SakuraArt.backside
            node.colorBlendFactor = lit > 0 ? 0.55 * lit : (flip < 0 ? 0.28 * CGFloat(-flip) : 0)
            let fadeIn = min(1, petal.age / petal.fadeIn)
            node.alpha = petal.maxAlpha * CGFloat(fadeIn)

            let unitX = (position.x - paintingRect.minX) / max(paintingRect.width, 1)
            let landing = point(CGPoint(x: 0, y: art.groundY(atX: unitX) + petal.landing)).y
            if position.y <= landing && petal.fromTree && petal.age > 1 {
                petal.settled = t
            } else if position.y < -40 || position.x > size.width + 80 || position.x < -120 {
                place(&petal, scattered: false)
            }
            petals[index] = petal
        }
    }

    private func pointerInScene() -> CGPoint? {
        guard let view, let window = view.window else { return nil }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let inView = view.convert(inWindow, from: nil)
        guard view.bounds.contains(inView) else { return nil }
        return convertPoint(fromView: inView)
    }
}

private struct Petal {
    let node: SKSpriteNode
    let depth: CGFloat
    let blurred: Bool
    var base = CGPoint.zero
    var fall: CGFloat = 40
    var swayAmp: CGFloat = 20
    var swayRate = 1.0
    var phase = 0.0
    var flipRate = 2.0
    var spinRate: CGFloat = 0
    var age = 0.0
    var fadeIn = 1.0
    var maxAlpha: CGFloat = 1
    var fromTree = false
    var settled: Double?
    var push = CGPoint.zero
    /// How far in front of the ground line this petal comes to rest, in the painting's height.
    var landing: CGFloat = 0

    init(node: SKSpriteNode, depth: CGFloat, blurred: Bool) {
        self.node = node
        self.depth = depth
        self.blurred = blurred
    }
}

/// The painting, its landmarks and the drawn textures, shared by every scene.
enum SakuraArt {
    static let ground = NSColor(calibratedRed: 0.05, green: 0.04, blue: 0.03, alpha: 1)
    static let backside = NSColor(calibratedRed: 0.72, green: 0.42, blue: 0.5, alpha: 1)

    /// A breeze made of incommensurate waves, so its pattern never comes round again.
    static func wind(at t: Double) -> CGFloat {
        CGFloat(0.12 + 0.5 * sin(t * 0.11) + 0.28 * sin(t * 0.29 + 1.7) + 0.15 * sin(t * 0.73 + 0.4))
    }

    /// Moves the painting's own grass: a slow breeze over the whole meadow, and blades shivering and leaning away
    /// where the pointer brushes through. Only green pixels below the grass line move; tree, stone and sky stay put.
    @MainActor static func makeGrassShader() -> SKShader {
        SKShader(source: grassSource, uniforms: [
            SKUniform(name: "u_pointer", vectorFloat2: vector_float2(-1, -1)),
            SKUniform(name: "u_energy", float: 0),
            SKUniform(name: "u_grass_top", float: 2),
            SKUniform(name: "u_aspect", float: 1.6),
            SKUniform(name: "u_wind", float: 0),
            SKUniform(name: "u_sway", vectorFloat4: vector_float4(0, 0, 0, 0)),
            SKUniform(name: "u_sway_amp", float: 0)
        ])
    }

    private static let grassSource = """
    float treeLike(vec4 c) { return 1.0 - smoothstep(0.0, 0.06, max(c.g - c.r, c.b - c.r)); }

    void main() {
        vec2 uv = v_tex_coord;
        float fromTop = 1.0 - uv.y;
        vec4 base = texture2D(u_texture, uv);

        // The tree sways: most at the top of the crown, not at all at the trunk, harder in the gusts that carry the
        // petals. Only blossom and bark move, so the sky and mountains behind it stay still.
        float inX = smoothstep(u_sway.x, u_sway.x + 0.05, uv.x) * (1.0 - smoothstep(u_sway.z - 0.05, u_sway.z, uv.x));
        float height = clamp((u_sway.w - fromTop) / max(u_sway.w - u_sway.y, 0.001), 0.0, 1.0);
        float lift = height * height * (3.0 - 2.0 * height) * inX;
        float sway = sin(u_time * 0.85 + fromTop * 5.0) * 0.5 + sin(u_time * 1.6 + uv.x * 7.0 + 1.3) * 0.25 + u_wind * 0.55;
        vec2 bend = vec2(sway, sin(u_time * 1.2 + uv.x * 6.0) * 0.22) * u_sway_amp * lift;
        vec4 bent = texture2D(u_texture, uv - bend);
        float tree = max(treeLike(base), treeLike(bent)) * step(0.0001, lift);
        vec4 color = mix(base, bent, tree);

        // Grass: gusts run across the meadow, and blades shiver and lean away where the pointer brushes through.
        float grass = smoothstep(0.012, 0.07, color.g - max(color.r, color.b)) * smoothstep(u_grass_top, u_grass_top + 0.05, fromTop);
        float wave = sin(u_time * 2.1 - uv.x * 22.0 + fromTop * 9.0) * 0.0012 + sin(u_time * 3.3 + uv.x * 140.0) * 0.00035;
        float breeze = wave * (0.7 + 0.5 * u_wind);
        vec2 d = (uv - u_pointer) * vec2(u_aspect, 1.0);
        float near = exp(-dot(d, d) / 0.005);
        float rustle = near * u_energy * (sin(u_time * 16.0 + uv.x * 170.0 + fromTop * 40.0) * 0.003 + clamp(d.x * 8.0, -1.0, 1.0) * 0.003);
        float shift = (breeze + rustle) * grass * (0.4 + 0.6 * smoothstep(u_grass_top, 1.0, fromTop));
        vec4 blown = texture2D(u_texture, uv + vec2(shift, 0.0));
        gl_FragColor = mix(color, blown, grass);
    }
    """

    /// A bundled painting by name, or the person's own picture by its full path.
    static func location(_ name: String) -> URL? {
        guard !name.isEmpty else { return nil }
        return name.hasPrefix("/") ? URL(fileURLWithPath: name) : Bundle.main.url(forResource: name, withExtension: "heic")
    }

    @MainActor private static var thumbnails: [String: NSImage] = [:]

    /// A small preview for the gallery in Settings, decoded straight at that size.
    @MainActor static func thumbnail(_ name: String) -> NSImage? {
        if let cached = thumbnails[name] { return cached }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 420,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let url = location(name), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        thumbnails[name] = preview
        return preview
    }

    @MainActor private static var loaded: (name: String, texture: SKTexture, size: CGSize)?

    /// The painting for a landscape, from the app's resources. Only the one in use stays in memory.
    @MainActor static func painting(_ name: String) -> (texture: SKTexture, size: CGSize)? {
        if let loaded, loaded.name == name { return (loaded.texture, loaded.size) }
        guard let url = location(name), let image = NSImage(contentsOf: url) else { return nil }
        let texture = SKTexture(image: image)
        loaded = (name, texture, image.size)
        return (texture, image.size)
    }

    @MainActor static let petals: [SKTexture] = [
        petalTexture(light: NSColor(calibratedRed: 1, green: 0.93, blue: 0.95, alpha: 1), deep: NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.72, alpha: 1)),
        petalTexture(light: NSColor(calibratedRed: 1, green: 0.9, blue: 0.93, alpha: 1), deep: NSColor(calibratedRed: 0.93, green: 0.55, blue: 0.67, alpha: 1)),
        petalTexture(light: NSColor(calibratedRed: 1, green: 0.96, blue: 0.97, alpha: 1), deep: NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.79, alpha: 1))
    ]

    @MainActor static let blurredPetal: SKTexture = petalTexture(light: NSColor(calibratedRed: 1, green: 0.92, blue: 0.94, alpha: 1),
                                                                deep: NSColor(calibratedRed: 0.95, green: 0.6, blue: 0.7, alpha: 1), blur: 5)

    @MainActor static let glow: SKTexture = {
        let side = 256
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let colors = [NSColor(calibratedRed: 1, green: 0.9, blue: 0.86, alpha: 0.9).cgColor,
                          NSColor(calibratedRed: 1, green: 0.75, blue: 0.7, alpha: 0.28).cgColor,
                          NSColor(calibratedRed: 1, green: 0.7, blue: 0.6, alpha: 0).cgColor] as CFArray
            guard let context = NSGraphicsContext.current?.cgContext,
                  let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1]) else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: rect.width / 2, options: [])
            return true
        }
        return SKTexture(image: image)
    }()

    /// A five-petal sakura petal seen flat: a rounded blade with the notch at its tip, pale at the edge, deeper at the base.
    @MainActor private static func petalTexture(light: NSColor, deep: NSColor, blur: CGFloat = 0) -> SKTexture {
        let side: CGFloat = 64
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 32, y: 6))
            path.addCurve(to: CGPoint(x: 12, y: 42), control1: CGPoint(x: 18, y: 14), control2: CGPoint(x: 8, y: 30))
            path.addCurve(to: CGPoint(x: 29, y: 57), control1: CGPoint(x: 15, y: 52), control2: CGPoint(x: 22, y: 58))
            path.addLine(to: CGPoint(x: 32, y: 51))
            path.addLine(to: CGPoint(x: 35, y: 57))
            path.addCurve(to: CGPoint(x: 52, y: 42), control1: CGPoint(x: 42, y: 58), control2: CGPoint(x: 49, y: 52))
            path.addCurve(to: CGPoint(x: 32, y: 6), control1: CGPoint(x: 56, y: 30), control2: CGPoint(x: 46, y: 14))
            path.closeSubpath()
            if blur > 0 { context.setShadow(offset: .zero, blur: blur, color: light.cgColor) }
            context.saveGState()
            context.addPath(path)
            context.clip()
            let colors = [light.cgColor, deep.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.15, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 32, y: 54), end: CGPoint(x: 32, y: 4), options: [.drawsAfterEndLocation])
            }
            context.restoreGState()
            if blur > 0 {
                context.addPath(path)
                context.setFillColor(light.withAlphaComponent(0.55).cgColor)
                context.fillPath()
            }
            context.addPath(path)
            context.setStrokeColor(deep.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(0.8)
            context.strokePath()
            return true
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }
}

/// The paintings the live wallpaper can play. Each scene has a tall painting for SAVISUL's panel and a wide one for
/// the desktop, so neither is a crop of the other.
enum WallpaperLandscape: String, CaseIterable, Identifiable {
    case bonsai, hill, bonsaiHill, custom

    var id: String { rawValue }

    var copy: Copy {
        switch self {
        case .bonsai: .wpBonsai
        case .hill: .wpHill
        case .bonsaiHill: .wpBonsaiHill
        case .custom: .wpCustom
        }
    }

    func art(for placement: SakuraScene.Placement, custom: String = "") -> LandscapeArt {
        let tall = placement == .panel
        switch self {
        case .custom:
            // A picture of the person's own: petals drift down from above and fall through, nothing else moves.
            return LandscapeArt(resource: custom, canopy: [], ground: [CGPoint(x: 0, y: 1.05), CGPoint(x: 1, y: 1.05)], landingSpread: 0)
        case .bonsai:
            return tall
                ? LandscapeArt(resource: "sakura-bonsai-tall", sway: CGRect(x: 0.02, y: 0.3, width: 0.97, height: 0.42), swayAmount: 0.007,
                               canopy: [(CGPoint(x: 0.5, y: 0.42), CGSize(width: 0.32, height: 0.09)),
                                        (CGPoint(x: 0.25, y: 0.55), CGSize(width: 0.18, height: 0.06)),
                                        (CGPoint(x: 0.75, y: 0.55), CGSize(width: 0.18, height: 0.06))],
                               ground: Self.stand(from: 0.05, to: 0.88, top: 0.84, floor: 0.96), landingSpread: 0.01,
                               halo: 1, haloCenter: CGPoint(x: 0.5, y: 0.45))
                : LandscapeArt(resource: "sakura-bonsai-wide", sway: CGRect(x: 0.22, y: 0.04, width: 0.58, height: 0.62), swayAmount: 0.0035,
                               canopy: [(CGPoint(x: 0.5, y: 0.28), CGSize(width: 0.18, height: 0.15)),
                                        (CGPoint(x: 0.38, y: 0.5), CGSize(width: 0.1, height: 0.08)),
                                        (CGPoint(x: 0.66, y: 0.48), CGSize(width: 0.09, height: 0.08))],
                               ground: Self.stand(from: 0.3, to: 0.7, top: 0.86, floor: 0.97), landingSpread: 0.01,
                               halo: 1, haloCenter: CGPoint(x: 0.5, y: 0.35))
        case .hill:
            return tall
                ? LandscapeArt(resource: "sakura-hill-tall", sway: CGRect(x: 0.04, y: 0.15, width: 0.92, height: 0.41), swayAmount: 0.007,
                               canopy: [(CGPoint(x: 0.5, y: 0.3), CGSize(width: 0.36, height: 0.1)),
                                        (CGPoint(x: 0.25, y: 0.42), CGSize(width: 0.15, height: 0.07)),
                                        (CGPoint(x: 0.75, y: 0.42), CGSize(width: 0.15, height: 0.07))],
                               ground: [CGPoint(x: 0, y: 0.64), CGPoint(x: 0.3, y: 0.61), CGPoint(x: 0.52, y: 0.6),
                                        CGPoint(x: 0.75, y: 0.61), CGPoint(x: 1, y: 0.64)],
                               landingSpread: 0.32, grassTop: 0.6)
                : LandscapeArt(resource: "sakura-hill-wide", sway: CGRect(x: 0.3, y: 0.06, width: 0.64, height: 0.54), swayAmount: 0.0035, focus: CGPoint(x: 0.6, y: 0.5),
                               canopy: [(CGPoint(x: 0.62, y: 0.3), CGSize(width: 0.25, height: 0.17)),
                                        (CGPoint(x: 0.45, y: 0.42), CGSize(width: 0.1, height: 0.08)),
                                        (CGPoint(x: 0.8, y: 0.42), CGSize(width: 0.1, height: 0.07))],
                               ground: [CGPoint(x: 0, y: 0.75), CGPoint(x: 0.3, y: 0.73), CGPoint(x: 0.62, y: 0.71),
                                        CGPoint(x: 0.85, y: 0.73), CGPoint(x: 1, y: 0.75)],
                               landingSpread: 0.2, grassTop: 0.7)
        case .bonsaiHill:
            return tall
                ? LandscapeArt(resource: "sakura-bonsai-hill-tall", sway: CGRect(x: 0.2, y: 0.38, width: 0.64, height: 0.3), swayAmount: 0.006,
                               canopy: [(CGPoint(x: 0.5, y: 0.48), CGSize(width: 0.25, height: 0.07)),
                                        (CGPoint(x: 0.38, y: 0.57), CGSize(width: 0.12, height: 0.05)),
                                        (CGPoint(x: 0.65, y: 0.57), CGSize(width: 0.12, height: 0.05))],
                               ground: Self.stand(from: 0.15, to: 0.85, top: 0.72, floor: 0.86), landingSpread: 0.1, grassTop: 0.62)
                : LandscapeArt(resource: "sakura-bonsai-hill-wide", sway: CGRect(x: 0.27, y: 0.3, width: 0.46, height: 0.36), swayAmount: 0.003,
                               canopy: [(CGPoint(x: 0.5, y: 0.42), CGSize(width: 0.17, height: 0.08)),
                                        (CGPoint(x: 0.42, y: 0.55), CGSize(width: 0.09, height: 0.05)),
                                        (CGPoint(x: 0.6, y: 0.54), CGSize(width: 0.08, height: 0.05))],
                               ground: Self.stand(from: 0.31, to: 0.72, top: 0.8, floor: 0.9), landingSpread: 0.08, grassTop: 0.64)
        }
    }

    /// A flat top (a stand or a stone) between two x positions, with the floor or grass on either side.
    private static func stand(from left: CGFloat, to right: CGFloat, top: CGFloat, floor: CGFloat) -> [CGPoint] {
        [CGPoint(x: 0, y: floor), CGPoint(x: left - 0.001, y: floor), CGPoint(x: left, y: top),
         CGPoint(x: right, y: top), CGPoint(x: right + 0.001, y: floor), CGPoint(x: 1, y: floor)]
    }
}

/// One painting and its landmarks, in coordinates normalised to the painting, origin top-left.
struct LandscapeArt {
    var resource: String
    /// The crown's box, normalised, origin top-left: the tree sways inside it, most at the top, not at all at the
    /// bottom edge, where the trunk is.
    var sway = CGRect.zero
    /// How far the top of the crown travels, as a share of the painting's width.
    var swayAmount: CGFloat = 0
    /// The point a view narrower or wider than the painting is cropped around.
    var focus = CGPoint(x: 0.5, y: 0.5)
    /// Where blossoms hang: the ellipses petals are born in.
    var canopy: [(center: CGPoint, radii: CGSize)]
    /// The line petals from the tree come to rest on, left to right.
    var ground: [CGPoint]
    /// How far in front of the ground line petals may land: in a meadow some come to rest nearer the viewer.
    var landingSpread: CGFloat
    /// Where the moving grass begins, measured from the top; past 1 there is no grass.
    var grassTop: CGFloat = 2
    /// The warm light behind a studio bonsai; outdoor scenes have the sky instead.
    var halo: CGFloat = 0
    var haloCenter = CGPoint(x: 0.5, y: 0.45)

    func groundY(atX x: CGFloat) -> CGFloat {
        guard let first = ground.first, let last = ground.last else { return 1 }
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }
        for (a, b) in zip(ground, ground.dropFirst()) where x >= a.x && x <= b.x {
            return a.y + (b.y - a.y) * (x - a.x) / max(b.x - a.x, 0.0001)
        }
        return last.y
    }
}
