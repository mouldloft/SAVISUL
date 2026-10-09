import Foundation
import Testing
@testable import SAVISUL

@Test func bridgeRoutes() {
    #expect(BridgeRoute.classify("hello") == .state)
    #expect(BridgeRoute.classify("state") == .state)
    #expect(BridgeRoute.classify("set") == .command)
    #expect(BridgeRoute.classify("lidConfirm") == .command)
    #expect(BridgeRoute.classify("lidCancel") == .command)
    #expect(BridgeRoute.classify("displayOff") == .command)
    #expect(BridgeRoute.classify("open") == .command)
    #expect(BridgeRoute.classify("launch") == .launch)
    #expect(BridgeRoute.classify("saveChunk") == .saveChunk)
    #expect(BridgeRoute.classify("shelfChunk") == .shelfChunk)
    #expect(BridgeRoute.classify("shelfAdd") == .shelfAdd)
    #expect(BridgeRoute.classify("reveal") == .reveal)
    #expect(BridgeRoute.classify("nope") == .unknown)
    #expect(BridgeRoute.classify("") == .unknown)
}

@Test func bridgeJSONRoundTripAndDamage() {
    let encoded = BridgeJSON.encode(["type": "hello", "id": 3])
    #expect(BridgeJSON.decode(encoded)?["type"] as? String == "hello")
    #expect(BridgeJSON.decode(nil) == nil)
    #expect(BridgeJSON.decode("{") == nil)
    #expect(BridgeJSON.decode("[]") == nil)
    #expect(BridgeJSON.encode(["bad": Date()]) == nil)
}

@Test func badChunksAreRejected() {
    #expect(BridgeFiles.save(["token": "", "index": 0, "total": 1, "data": "QQ=="])["error"] as? String == "chunk")
    #expect(BridgeFiles.save(["token": "ok", "index": 3, "total": 2, "data": "QQ=="])["error"] as? String == "chunk")
    #expect(BridgeFiles.save(["token": "ok", "index": 0, "total": 1, "data": "!!!!"])["error"] as? String == "chunk")
    #expect(BridgeFiles.shelf(["token": "ok", "index": 0, "total": 0, "data": "QQ=="])["error"] as? String == "chunk")
}

@Test func namesCannotEscapeTheFolder() {
    #expect(!BridgeFiles.fileName("../../etc/passwd").contains("/"))
    #expect(!BridgeFiles.fileName("..\\windows").contains("\\"))
    #expect(BridgeFiles.fileName("shot").hasSuffix(".png"))
    #expect(BridgeFiles.fileName(nil) == "SAVISUL.png")
    #expect(BridgeFiles.fileName("") == "SAVISUL.png")
    #expect(BridgeFiles.shelfName("notes.md").hasSuffix(".md"))
    #expect(BridgeFiles.shelfName("virus.exe").hasSuffix(".txt"))
    #expect(BridgeFiles.shelfName(nil) == "SAVISUL.txt")
    #expect(!BridgeFiles.shelfName("a/b.json").contains("/"))
}

@Test func revealRefusesPathsOutsidePictures() {
    #expect(BridgeFiles.reveal(["path": "/etc/hosts"])["error"] as? String == "path")
    #expect(BridgeFiles.reveal([:])["error"] as? String == "path")
    #expect(BridgeFiles.reveal(["path": "/no/such/SAVISUL/file.png"])["error"] as? String == "path")
}

@Test func agentLogRejectsDamagedLines() {
    #expect(AgentLog.object(Data("not json".utf8)) == nil)
    #expect(AgentLog.object(Data("{".utf8)) == nil)
    #expect(AgentLog.object(Data("[]".utf8)) == nil)
    #expect(AgentLog.object(Data()) == nil)
    let line = Data(#"{"type":"session_meta","payload":{"cwd":"/Users/me/SAVISUL","id":"abc"}}"#.utf8)
    let object = AgentLog.object(line)
    #expect(object?["type"] as? String == "session_meta")
    #expect((object?["payload"] as? [String: Any])?["cwd"] as? String == "/Users/me/SAVISUL")
}
