#if MOULD_ENGINE
import CoreGraphics
import CoreML
import Foundation

/// What a picture shows and what a description says, as vectors of one kind, so the two can be compared: CLIP
/// (ViT-B/32, trained by LAION on DataComp-1B, MIT licence), run with Core ML on this Mac. A picture whose vector lies
/// close to a description's shows what the description says, whatever words it uses. Nothing leaves the Mac.
final class PhotoMeaning: @unchecked Sendable {
    static let length = 512

    private let image: MLModel
    private let text: MLModel
    private let tokens: CLIPTokens
    /// One prediction at a time per model: the index looks at three pictures at once.
    private let lock = NSLock()

    /// The model as installed in `folder`: PhotoImage.mlmodelc, PhotoText.mlmodelc, vocab.json and merges.txt.
    init(folder: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        image = try MLModel(contentsOf: folder.appendingPathComponent("PhotoImage.mlmodelc"), configuration: configuration)
        text = try MLModel(contentsOf: folder.appendingPathComponent("PhotoText.mlmodelc"), configuration: configuration)
        tokens = try CLIPTokens(vocabulary: folder.appendingPathComponent("vocab.json"), merges: folder.appendingPathComponent("merges.txt"))
    }

    /// A picture's vector, from its middle square at 224 pixels a side, as CLIP was taught to look.
    func vector(of picture: CGImage) -> [Float]? {
        guard let square = Self.square(picture, side: 224),
              let constraint = image.modelDescription.inputDescriptionsByName["image"]?.imageConstraint,
              let value = try? MLFeatureValue(cgImage: square, constraint: constraint, options: nil),
              let input = try? MLDictionaryFeatureProvider(dictionary: ["image": value]) else { return nil }
        let output = lock.withLock { try? image.prediction(from: input) }
        return output?.featureValue(for: "embedding")?.multiArrayValue.map(Self.floats)
    }

    /// A description's vector. English: CLIP learned from English captions.
    func vector(of words: String) -> [Float]? {
        guard let array = try? MLMultiArray(shape: [1, NSNumber(value: CLIPTokens.length)], dataType: .int32) else { return nil }
        for (index, id) in tokens.encode(words).enumerated() { array[index] = NSNumber(value: id) }
        guard let input = try? MLDictionaryFeatureProvider(dictionary: ["tokens": array]) else { return nil }
        let output = lock.withLock { try? text.prediction(from: input) }
        return output?.featureValue(for: "embedding")?.multiArrayValue.map(Self.floats)
    }

    private static func floats(_ array: MLMultiArray) -> [Float] {
        (0..<array.count).map { array[$0].floatValue }
    }

    /// The shorter side scaled to `side` and the middle cut out, as CLIP's own preparation does.
    static func square(_ picture: CGImage, side: Int) -> CGImage? {
        guard picture.width > 0, picture.height > 0,
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let scale = CGFloat(side) / CGFloat(min(picture.width, picture.height))
        let width = CGFloat(picture.width) * scale, height = CGFloat(picture.height) * scale
        context.interpolationQuality = .high
        context.draw(picture, in: CGRect(x: (CGFloat(side) - width) / 2, y: (CGFloat(side) - height) / 2, width: width, height: height))
        return context.makeImage()
    }

    /// How alike two vectors are: both are of length one, so this is the cosine, about 0.1 for unrelated and 0.3 for a
    /// good match.
    static func likeness(_ a: [Float], _ b: [Float]) -> Float {
        var sum: Float = 0
        for index in 0..<min(a.count, b.count) { sum += a[index] * b[index] }
        return sum
    }

    /// The same, against a vector as the index keeps it, without unpacking it first.
    static func likeness(_ a: [Float], _ packed: Data) -> Float {
        packed.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: Float16.self)
            var sum: Float = 0
            for index in 0..<min(a.count, b.count) { sum += a[index] * Float(b[index]) }
            return sum
        }
    }

    /// A vector kept in the index: half precision, a kilobyte a picture.
    static func pack(_ vector: [Float]) -> Data {
        var halves = vector.map(Float16.init)
        return Data(bytes: &halves, count: halves.count * MemoryLayout<Float16>.size)
    }

    static func unpack(_ data: Data) -> [Float] {
        data.withUnsafeBytes { raw in raw.bindMemory(to: Float16.self).map(Float.init) }
    }
}

/// The meaning's model as SAVISUL downloads it: Core ML's two encoders, CLIP's vocabulary and their MIT licence, 138 MB
/// once, kept in Application Support beside the assistant's other models.
enum PhotoModel {
    enum State: Equatable, Sendable {
        case missing, downloading(Double), ready, failed(String)
    }

    /// Mould Loft's own host for the official app's models (ModelHost/ in the private repository), apart from GitHub.
    static let url = URL(string: "https://savisul-models-production.up.railway.app/PhotoMeaning-1.zip")!
    static let bytes: Int64 = 137_544_070
    static let sha256 = "e50e7205a399e7739f4d794ddf208abb41da69e9fa85fd4877230e4be8c8e0c9"
    private static let files = ["PhotoImage.mlmodelc", "PhotoText.mlmodelc", "vocab.json", "merges.txt"]

    static var folder: URL { MindHost.modelsFolder.appendingPathComponent("PhotoMeaning-1", isDirectory: true) }
    static var installed: Bool { isInstalled(in: folder) }

    static func isInstalled(in folder: URL) -> Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    /// Unzips the download beside `folder` and puts it in its place only once all of it is there.
    static func unpack(_ archive: URL, into folder: URL) -> Bool {
        let manager = FileManager.default
        let staging = folder.deletingLastPathComponent().appendingPathComponent(".unpacking-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: staging) }
        do {
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", archive.path, staging.path]
            try ditto.run()
            ditto.waitUntilExit()
            let unpacked = staging.appendingPathComponent("PhotoMeaning-1", isDirectory: true)
            guard ditto.terminationStatus == 0, isInstalled(in: unpacked) else { return false }
            if manager.fileExists(atPath: folder.path) { try manager.removeItem(at: folder) }
            try manager.moveItem(at: unpacked, to: folder)
            return true
        } catch {
            return false
        }
    }
}

/// CLIP's byte-pair tokens, as open_clip's SimpleTokenizer makes them: lower case, single spaces, the UTF-8 bytes mapped
/// to letters, then the merges learned with the model, each word ending in "</w>". 77 tokens, padded with zeros.
struct CLIPTokens: Sendable {
    static let start: Int32 = 49406
    static let end: Int32 = 49407
    static let length = 77

    private let vocabulary: [String: Int32]
    private let ranks: [String: Int]
    private let letters: [Character]
    private let pattern: NSRegularExpression

    init(vocabulary: URL, merges: URL) throws {
        let data = try Data(contentsOf: vocabulary)
        guard let table = try JSONSerialization.jsonObject(with: data) as? [String: Int] else { throw CocoaError(.fileReadCorruptFile) }
        self.vocabulary = table.mapValues { Int32($0) }
        var ranks: [String: Int] = [:]
        let lines = try String(contentsOf: merges, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: true)
        for (rank, line) in lines.dropFirst().enumerated() where line.contains(" ") && ranks[String(line)] == nil { ranks[String(line)] = rank }
        self.ranks = ranks
        // GPT-2's map of bytes to printable characters, which CLIP's vocabulary is written in.
        var bytes = Array(33...126) + Array(161...172) + Array(174...255)
        var codes = bytes
        var next = 0
        for byte in 0..<256 where !bytes.contains(byte) {
            bytes.append(byte)
            codes.append(256 + next)
            next += 1
        }
        var letters = [Character](repeating: " ", count: 256)
        for (byte, code) in zip(bytes, codes) { letters[byte] = Character(UnicodeScalar(code)!) }
        self.letters = letters
        pattern = try NSRegularExpression(pattern: #"'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+"#, options: [.caseInsensitive])
    }

    func encode(_ text: String) -> [Int32] {
        let clean = text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var ids: [Int32] = [Self.start]
        for match in pattern.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)) {
            guard let range = Range(match.range, in: clean) else { continue }
            let mapped = String(clean[range].utf8.map { letters[Int($0)] })
            for piece in merged(mapped) {
                if let id = vocabulary[piece] { ids.append(id) }
            }
            if ids.count >= Self.length { break }
        }
        ids = Array(ids.prefix(Self.length - 1)) + [Self.end]
        return ids + Array(repeating: 0, count: Self.length - ids.count)
    }

    /// One word's letters joined pair by pair, the earliest-learned pair first, until no learned pair is left.
    private func merged(_ word: String) -> [String] {
        var parts = word.unicodeScalars.map { String($0) }
        guard !parts.isEmpty else { return [] }
        parts[parts.count - 1] += "</w>"
        while parts.count > 1 {
            var best: (rank: Int, first: String, second: String)?
            for index in 0..<(parts.count - 1) {
                if let rank = ranks[parts[index] + " " + parts[index + 1]], rank < (best?.rank ?? .max) {
                    best = (rank, parts[index], parts[index + 1])
                }
            }
            guard let best else { break }
            var joined: [String] = []
            var index = 0
            while index < parts.count {
                if index < parts.count - 1, parts[index] == best.first, parts[index + 1] == best.second {
                    joined.append(best.first + best.second)
                    index += 2
                } else {
                    joined.append(parts[index])
                    index += 1
                }
            }
            parts = joined
        }
        return parts
    }
}
#endif
