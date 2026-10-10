import CoreVideo
import Foundation
import Vision

/// What one camera frame says about the face in it.
struct FaceFrame: Sendable {
    /// Vision's faceprint scaled to unit length, so a dot product of two prints is how alike the faces are.
    /// Nil on the frames read only for the eyes, which are most of them: a blink is over in a few frames.
    var print: [Float]?
    /// How open the eyes are: their height over their width, both eyes averaged; nil when the eyes weren't found.
    var eyes: Double?
    /// The face's width as a share of the frame's.
    var size: Double
}

/// Apple's face recognizer, the one Photos uses to tell people apart. It has no public API, so it is found by name;
/// on a system without it Face Unlock can't be turned on.
enum FaceEngine {
    private static let requestType: VNImageBasedRequest.Type? = {
        // Vision loads lazily; touching a public request first makes its private classes visible.
        _ = VNDetectFaceRectanglesRequest()
        return NSClassFromString("VNCreateFaceprintRequest") as? VNImageBasedRequest.Type
    }()

    static var available: Bool { requestType != nil }

    /// Faces narrower than this share of the frame are too far away to read.
    static let smallestFace: CGFloat = 0.05
    /// Under this share of the frame a face counts as far: the eyes are a few pixels and measured loosely.
    static let farFace = 0.1

    /// The recognizer's version. Prints from different versions don't compare, so a new one means a new scan.
    static var revision: Int? { requestType.map { $0.init().revision } }

    /// Reads the biggest face in a frame, or nil when there is none big enough to recognize. The eyes are read every time;
    /// the faceprint, which takes longer, only when `print` asks for it.
    static func read(_ buffer: CVPixelBuffer, print wantsPrint: Bool) -> FaceFrame? {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        let landmarks = VNDetectFaceLandmarksRequest()
        do { try handler.perform([landmarks]) } catch { return nil }
        // A twentieth of a 720p frame is still about 64 pixels of face, enough for Apple's recognizer.
        guard let face = landmarks.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
              face.boundingBox.width >= Self.smallestFace else { return nil }
        let eyes = FaceMath.eyeOpenness([face.landmarks?.leftEye?.normalizedPoints, face.landmarks?.rightEye?.normalizedPoints])
        var frame = FaceFrame(print: nil, eyes: eyes, size: Double(face.boundingBox.width))
        guard wantsPrint, let requestType else { return frame }
        let request = requestType.init()
        request.setValue([face], forKey: "inputFaceObservations")
        // Float32 elements; anything else is a recognizer this code doesn't know.
        guard (try? handler.perform([request])) != nil,
              let observation = (request.results as? [VNFaceObservation])?.first,
              let faceprint = observation.value(forKey: "faceprint") as? NSObject,
              (faceprint.value(forKey: "elementType") as? Int) == 1,
              let data = faceprint.value(forKey: "descriptorData") as? Data, data.count >= 256
        else { return frame }
        frame.print = FaceMath.unit(data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) })
        return frame
    }
}

enum FaceMath {
    static func unit(_ vector: [Float]) -> [Float]? {
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard length > 0, length.isFinite else { return nil }
        return vector.map { $0 / length }
    }

    /// Cosine similarity of two unit prints: about 0.9 and up for one person, under 0.7 for two in Apple's recognizer.
    static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return -1 }
        var sum: Float = 0
        for index in a.indices { sum += a[index] * b[index] }
        return sum
    }

    static func best(_ print: [Float], among prints: [[Float]]) -> Float {
        prints.map { similarity(print, $0) }.max() ?? -1
    }

    /// Each eye's height over its width, averaged over the eyes found.
    static func eyeOpenness(_ eyes: [[CGPoint]?]) -> Double? {
        let ratios = eyes.compactMap { points -> Double? in
            guard let points, points.count >= 4,
                  let left = points.map(\.x).min(), let right = points.map(\.x).max(),
                  let bottom = points.map(\.y).min(), let top = points.map(\.y).max(), right > left
            else { return nil }
            return Double((top - bottom) / (right - left))
        }
        return ratios.isEmpty ? nil : ratios.reduce(0, +) / Double(ratios.count)
    }
}

/// Watches the eyes across frames for a blink: open, then clearly closed for a moment, then open again,
/// the way a living face does and a photo can't.
struct BlinkTracker {
    private(set) var blinked = false
    private var open: Double = 0
    private var openFrames = 0
    private var closedRun = 0

    /// A blink keeps the eyes shut for a tenth to a third of a second, up to about ten frames; longer is eyes simply closed.
    static let longestBlink = 12

    mutating func add(_ eyes: Double?) {
        guard let eyes, eyes > 0 else { return }
        // Vision draws a shut eye as a thin one rather than a line, so "shut" is two thirds of the open height.
        if openFrames >= 3, eyes < open * 0.65 {
            closedRun += 1
            return
        }
        guard openFrames < 3 || eyes >= open * 0.8 else { return }
        if (1...Self.longestBlink).contains(closedRun) { blinked = true }
        closedRun = 0
        open = openFrames == 0 ? eyes : open * 0.8 + eyes * 0.2
        openFrames += 1
    }
}

/// Decides a scan at the lock screen from its frames: several that look like the owner with their eyes open, and a blink
/// when one is asked for.
struct FaceMatch {
    /// One person's frames score about 0.9 and up against their enrollment; Apple's recognizer puts strangers under 0.7.
    static let threshold: Float = 0.86
    static let framesNeeded = 3
    /// Eyes at least this open count as looking, Face ID's attention: closed eyes or a sleeping face don't unlock.
    static let openEyes = 0.12

    /// The setup scan's prints first, then the ones learned since.
    let prints: [[Float]]
    /// How many of `prints` come from the setup scan.
    let enrolled: Int
    let needsBlink: Bool
    /// Matching frames needed: `framesNeeded` after a touch; more when nobody asked, so it takes a steady look.
    let needed: Int
    private(set) var seen = 0
    private(set) var matched = 0
    private(set) var best: Float = -1
    private(set) var blink = BlinkTracker()
    /// This scan's prints that matched the setup scan itself, the only ones Face Unlock may learn from.
    private(set) var strong: [[Float]] = []
    /// Frames with a face that didn't count, by reason, and the faces' sizes, for the log.
    private(set) var unlike = 0
    private(set) var notLooking = 0
    private(set) var sizes: [Double] = []
    private var widestEyes = 0.0

    init(prints: [[Float]], enrolled: Int? = nil, needsBlink: Bool, needed: Int = FaceMatch.framesNeeded) {
        self.prints = prints
        self.enrolled = min(enrolled ?? prints.count, prints.count)
        self.needsBlink = needsBlink
        self.needed = max(needed, 1)
    }

    mutating func add(_ frame: FaceFrame) {
        blink.add(frame.eyes)
        if let eyes = frame.eyes { widestEyes = max(widestEyes, eyes) }
        guard let print = frame.print else { return }
        seen += 1
        sizes.append(frame.size)
        let score = FaceMath.best(print, among: prints)
        best = max(best, score)
        guard score >= Self.threshold else {
            unlike += 1
            return
        }
        guard looking(frame.eyes, far: frame.size < FaceEngine.farFace) else {
            notLooking += 1
            return
        }
        matched += 1
        if FaceMath.best(print, among: Array(prints.prefix(enrolled))) >= Self.threshold {
            strong = Array((strong + [print]).suffix(6))
        }
    }

    /// Eyes open, both as such and next to how wide they opened during this scan. A far face's eyes are a few pixels
    /// and measured loosely, so they are judged more gently.
    private func looking(_ eyes: Double?, far: Bool) -> Bool {
        guard let eyes else { return true }
        return eyes >= (far ? 0.08 : Self.openEyes) && eyes >= widestEyes * (far ? 0.45 : 0.6)
    }

    /// The usual face size in this scan, as a share of the frame.
    var typicalSize: Double {
        guard !sizes.isEmpty else { return 0 }
        return sizes.sorted()[sizes.count / 2]
    }

    var accepted: Bool { matched >= needed && (!needsBlink || blink.blinked) }

    /// The face is the owner's and only the blink is missing.
    var waitingForBlink: Bool { needsBlink && matched >= needed && !blink.blinked }

    /// A face was in front of the camera long enough and never once looked like the owner's.
    var stranger: Bool { seen >= 5 && best < Self.threshold }
}

/// How Face Unlock keeps up with a face, as Face ID does: after an unlock by face it keeps a print that shows the owner
/// in a light or look the gallery hadn't seen. Only prints that matched the setup scan itself qualify, so the gallery
/// can't drift toward someone else.
enum FaceLearning {
    static let cap = 16

    /// The newest two strong prints that are new enough join the learned ones; the oldest go past `cap`.
    static func learn(_ learned: [[Float]], from strong: [[Float]], enrolled: [[Float]]) -> [[Float]] {
        var result = learned
        for print in strong.reversed().prefix(2) where FaceMath.best(print, among: enrolled + result) < 0.95 {
            result.append(print)
        }
        return Array(result.suffix(cap))
    }
}

/// The face scan when Face Unlock is set up: prints of one person from as many angles as they show up close, then a few
/// from farther back, so the lock screen recognizes them turned a little, lit differently or across the desk.
struct FaceEnrollment {
    static let nearTarget = 12
    static let farTarget = 4
    static var target: Int { nearTarget + farTarget }

    private(set) var prints: [[Float]] = []
    private(set) var far = 0
    var near: Int { prints.count - far }

    /// Up close is done; the scan now wants the face from farther back.
    var nearDone: Bool { near >= Self.nearTarget }

    /// Takes a frame's print when it is the same person as the first and looks new enough; tells whether it was taken.
    /// Far views wait until the close ones are done, and a far face is a little less like the close first view.
    @discardableResult
    mutating func add(_ print: [Float], far isFar: Bool = false) -> Bool {
        guard isFar ? nearDone && far < Self.farTarget : !nearDone else { return false }
        if let first = prints.first {
            guard FaceMath.similarity(print, first) >= (isFar ? 0.75 : 0.8), FaceMath.best(print, among: prints) < 0.97 else { return false }
        }
        prints.append(print)
        if isFar { far += 1 }
        return true
    }

    var progress: Double { min(1, Double(prints.count) / Double(Self.target)) }
    var complete: Bool { nearDone && far >= Self.farTarget }
}
