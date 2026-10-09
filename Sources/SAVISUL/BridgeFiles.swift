import AppKit
import Foundation

/// Screenshot files written by the native messaging host, which can run without the main app.
/// The saved-note name matches `BridgeNote.saved`.
enum BridgeFiles {
    static let savedNote = Notification.Name("com.savisul.bridge.saved")
    /// Posted when the browser put a file on the Shelf; the app adds the path to `ShelfStore`.
    static let shelfNote = Notification.Name("com.savisul.bridge.shelf")
    private static let shelfTypes: Set<String> = ["md", "txt", "html", "mhtml", "pdf", "png", "jpg", "jpeg", "gif", "webp", "svg", "avif",
                                                  "csv", "tsv", "json", "zip", "mp3", "mp4", "m4a", "webm", "mov"]

    static var folder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVISUL", isDirectory: true)
    }

    static func save(_ message: [String: Any]) -> [String: Any] {
        let token = (message["token"] as? String ?? "").filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        guard !token.isEmpty, token.count <= 64,
              let index = integer(message["index"]), let total = integer(message["total"]),
              total > 0, (0..<total).contains(index),
              let encoded = message["data"] as? String, let data = Data(base64Encoded: encoded) else {
            return ["error": "chunk"]
        }
        let manager = FileManager.default
        let temp = manager.temporaryDirectory.appendingPathComponent("savisul-\(token).part")
        do {
            if index == 0 {
                try data.write(to: temp)
            } else {
                let handle = try FileHandle(forWritingTo: temp)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            }
            guard index == total - 1 else { return ["ok": true] }
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = uniqueURL(in: folder, name: fileName(message["name"] as? String))
            try manager.moveItem(at: temp, to: target)
            DistributedNotificationCenter.default().postNotificationName(savedNote, object: nil,
                                                                        userInfo: ["path": target.path],
                                                                        deliverImmediately: true)
            return ["ok": true, "path": target.path]
        } catch {
            try? manager.removeItem(at: temp)
            return ["error": "write"]
        }
    }

    /// Same chunked protocol as `save`, but the file lands in the Shelf's own folder under any allowed type.
    static func shelf(_ message: [String: Any]) -> [String: Any] {
        let token = (message["token"] as? String ?? "").filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        guard !token.isEmpty, token.count <= 64,
              let index = integer(message["index"]), let total = integer(message["total"]),
              total > 0, total <= 4096, (0..<total).contains(index),
              let encoded = message["data"] as? String, let data = Data(base64Encoded: encoded) else {
            return ["error": "chunk"]
        }
        let manager = FileManager.default
        let temp = manager.temporaryDirectory.appendingPathComponent("savisul-shelf-\(token).part")
        do {
            if index == 0 {
                try data.write(to: temp)
            } else {
                let handle = try FileHandle(forWritingTo: temp)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            }
            guard index == total - 1 else { return ["ok": true] }
            let folder = ShelfStore.drops
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = uniqueURL(in: folder, name: shelfName(message["name"] as? String))
            try manager.moveItem(at: temp, to: target)
            DistributedNotificationCenter.default().postNotificationName(shelfNote, object: nil,
                                                                        userInfo: ["path": target.path],
                                                                        deliverImmediately: true)
            return ["ok": true, "path": target.path]
        } catch {
            try? manager.removeItem(at: temp)
            return ["error": "write"]
        }
    }

    static func shelfName(_ raw: String?) -> String {
        var name = (raw ?? "").components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator: " ")
        name = name.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if name.isEmpty { name = "SAVISUL.txt" }
        var ext = (name as NSString).pathExtension.lowercased()
        if !shelfTypes.contains(ext) {
            name += ".txt"
            ext = "txt"
        }
        if name.count > 150 { name = String((name as NSString).deletingPathExtension.prefix(140)) + "." + ext }
        return name
    }

    static func reveal(_ message: [String: Any]) -> [String: Any] {
        let root = folder.standardizedFileURL.path
        guard let path = message["path"] as? String,
              URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(root + "/"),
              FileManager.default.fileExists(atPath: path) else {
            return ["error": "path"]
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        return ["ok": true]
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, double >= Double(Int.min), double <= Double(Int.max) else { return nil }
        return number.intValue
    }

    static func fileName(_ raw: String?) -> String {
        var name = (raw ?? "").components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator: " ")
        name = name.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if name.isEmpty { name = "SAVISUL.png" }
        if name.count > 150 { name = String(name.prefix(146)) + ".png" }
        let ext = (name as NSString).pathExtension.lowercased()
        if !["png", "jpg", "jpeg"].contains(ext) { name += ".png" }
        return name
    }

    private static func uniqueURL(in folder: URL, name: String) -> URL {
        var url = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(number).\(ext)")
            number += 1
        }
        return url
    }
}
