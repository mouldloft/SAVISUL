#if MOULD_ENGINE
import Foundation
import MouldEngine
import Observation

/// What the assistant panel shows: the requests, answers, tool steps, plans and questions for consent, in order.
@MainActor
@Observable
final class MindConversation {
    struct Item: Identifiable, Equatable {
        enum Kind: Equatable { case request, answer, step, plan, consent, note, failure, photos }
        enum Status: Equatable { case running, done, failed, declined }

        let id: String
        var kind: Kind
        var text: String
        var detail: String?
        var status: Status = .done
        var request: ConfirmationRequest?
        var steps: [String] = []
        /// The pictures a photo search found.
        var photos: [PhotoHit] = []
    }

    private(set) var items: [Item] = []
    /// The task running now.
    private(set) var running: String?
    /// The model answering, and why it was chosen.
    private(set) var route: (title: String, local: Bool, reasons: [String])?
    var input = ""
    /// What the person brought along: selected text, files, a page.
    var attachments: [Attachment] = []
    /// Selected files: granted for one request.
    var selectedFiles: [URL] = []
    /// One session per panel opening, so follow-ups know what came before.
    private(set) var session = UUID().uuidString

    var lastAnswer: String? { items.last { $0.kind == .answer }.map(\.text) }
    var isEmpty: Bool { items.isEmpty }

    func newSession() {
        items.removeAll()
        attachments.removeAll()
        selectedFiles.removeAll()
        route = nil
        session = UUID().uuidString
    }

    /// The selection and page as context for the engine.
    var contextDeltas: [ContextDelta] {
        var nodes: [ContextNode] = []
        for url in selectedFiles {
            nodes.append(ContextNode(id: "file:\(url.path)", kind: .file, title: url.lastPathComponent, attributes: ["path": .string(url.path), "selected": true],
                                     sensitive: true, weight: 0.9, source: "savisul.selection"))
        }
        return [.replace(kind: .file, source: "savisul.selection", nodes: nodes)]
    }

    // MARK: Events from the engine

    func begin(_ request: MindRequest) {
        running = request.taskID
        items.append(Item(id: request.taskID, kind: .request, text: request.prompt,
                          detail: attachments.isEmpty ? nil : attachments.map(\.title).joined(separator: " · ")))
    }

    func apply(_ event: MindEvent) {
        switch event {
        case .started:
            break
        case .routed(_, let title, let local, let reasons):
            route = (title, local, reasons)
        case .text(let piece):
            if let index = items.indices.last, items[index].kind == .answer, items[index].status == .running {
                items[index].text += piece
            } else {
                items.append(Item(id: UUID().uuidString, kind: .answer, text: piece, status: .running))
            }
        case .retracted:
            // The model wrote about a tool instead of calling it; that text goes, and the real answer follows.
            if let index = items.indices.last, items[index].kind == .answer, items[index].status == .running { items.remove(at: index) }
        case .retrying(let reason):
            // A reply that looped or broke goes; one the answer limit cut off, or too large for the model's window, keeps
            // what it wrote. A quiet line says why it starts again.
            let kept = reason == ReplyFault.cutOff || reason == ReplyFault.overflow
            if !kept, let index = items.indices.last, items[index].kind == .answer, items[index].status == .running { items.remove(at: index) }
            let phrase = reason == ReplyFault.cutOff ? MindPhrases.cutOff : reason == ReplyFault.overflow ? MindPhrases.overflow : MindPhrases.retrying
            items.append(Item(id: UUID().uuidString, kind: .note, text: phrase.text))
        case .reasoning, .preparing:
            break                                               // SAVISUL shows the answer and the steps, not the thinking
        case .toolStarted(let call, let title):
            closeAnswer()
            items.append(Item(id: call.id, kind: .step, text: MindPhrases.tool(call.tool, title), status: .running))
        case .toolFinished(let call, let summary):
            // Tools sum up in English, for the model; the answer that follows says it in the person's language.
            update(call.id) { $0.status = .done; $0.detail = Suite.shared.language == .en ? summary : nil }
        case .toolFailed(let call, let error):
            update(call.id) {
                if case .declined = error { $0.status = .declined } else { $0.status = .failed }
                $0.detail = MindPhrases.error(error)
            }
        case .planned(let graph):
            closeAnswer()
            items.append(Item(id: graph.id, kind: .plan, text: graph.title, status: .running,
                              steps: graph.steps.map { $0.title ?? MindPhrases.tool($0.tool, $0.tool.rawValue) }))
        case .graphFinished(let result):
            update(result.graphID) { $0.status = result.status == .succeeded ? .done : .failed }
        case .usage:
            break                                               // SAVISUL doesn't show token counts
        case .finished(let answer):
            if let index = items.indices.last, items[index].kind == .answer, items[index].status == .running {
                items[index].status = .done
            } else if !answer.isEmpty {
                items.append(Item(id: UUID().uuidString, kind: .answer, text: answer))
            }
        }
    }

    func fail(_ error: MouldError) {
        closeAnswer()
        switch error {
        case .cancelled, .declined:
            // Stopping or saying no isn't a failure: a quiet line says what happened.
            items.append(Item(id: UUID().uuidString, kind: .note, text: MindPhrases.error(error)))
        default:
            items.append(Item(id: UUID().uuidString, kind: .failure, text: MindPhrases.error(error)))
        }
    }

    func note(_ text: String) {
        items.append(Item(id: UUID().uuidString, kind: .note, text: text))
    }

    /// Pictures a photo search found, as thumbnails under its step.
    func found(_ photos: [PhotoHit]) {
        guard !photos.isEmpty else { return }
        closeAnswer()
        items.append(Item(id: UUID().uuidString, kind: .photos, text: "", photos: photos))
    }

    func end() {
        closeAnswer()
        for index in items.indices where items[index].status == .running && items[index].kind != .consent { items[index].status = .failed }
        running = nil
    }

    func confirm(_ request: ConfirmationRequest) {
        closeAnswer()
        // A single call is titled by its tool, which SAVISUL can say in the person's language; a plan keeps its own title.
        let title = request.items.count == 1 && request.title == request.items[0].toolTitle
            ? MindPhrases.tool(request.items[0].tool, request.title) : request.title
        items.append(Item(id: request.id, kind: .consent, text: title, status: .running, request: request))
    }

    func answered(_ id: String, _ decision: ConfirmationDecision) {
        update(id) {
            $0.status = decision == .approved ? .done : .declined
            if decision == .expired { $0.detail = MindPhrases.expired.text }
        }
    }

    /// Questions still waiting for an answer.
    var pendingConsent: [ConfirmationRequest] {
        items.filter { $0.kind == .consent && $0.status == .running }.compactMap(\.request)
    }

    private func closeAnswer() {
        if let index = items.indices.last, items[index].kind == .answer, items[index].status == .running { items[index].status = .done }
    }

    private func update(_ id: String, _ change: (inout Item) -> Void) {
        guard let index = items.lastIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }
}
#endif
