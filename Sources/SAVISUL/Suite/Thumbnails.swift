import AppKit
import QuickLookThumbnailing

/// Quick Look thumbnails, cached per path and size.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()
    private var cache: [String: NSImage] = [:]

    func thumbnail(path: String, size: CGFloat) async -> NSImage? {
        let key = "\(path)#\(Int(size))"
        if let cached = cache[key] { return cached }
        let url = URL(fileURLWithPath: path)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: 2,
                                                   representationTypes: .thumbnail)
        let image: NSImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                nonisolated(unsafe) let result = representation?.nsImage
                continuation.resume(returning: result)
            }
        }
        if let image {
            if cache.count > 300 { cache.removeAll() }
            cache[key] = image
        }
        return image
    }
}
