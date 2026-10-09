import AppKit
import SwiftUI

// The action core: every SAVISUL action is one definition that says what it accepts, what it needs and how it runs,
// so the same action can start from the command bar, the radial menu, the favourites panel, Context Actions or the Shelf.

/// What an action can work on.
enum ActionInput: String, CaseIterable, Sendable {
    /// Needs nothing: "Mute sound", "Timer 5 min".
    case none
    case text, url, image, file, folder
}

/// Where an action was started from. Results show differently in a panel than from a shortcut.
enum ActionSource: Sendable {
    case commandBar, radial, quickPanel, contextActions, shelf, island
}

/// What an action needs before it can run.
enum ActionPermission: Sendable {
    /// Reads or controls other apps.
    case accessibility
    /// An AI provider with the person's own API key (Settings → AI).
    case ai
}

/// The thing an action works on: the selection, the clipboard, a Shelf item.
struct ActionContext {
    var text: String?
    var url: URL?
    var image: NSImage?
    var files: [URL] = []
    var source: ActionSource = .contextActions
    /// True when nothing was selected and the clipboard stood in.
    var fromClipboard = false

    static let empty = ActionContext()

    /// A Shelf item as something to act on.
    init(shelf item: ShelfItem) {
        source = .shelf
        switch item.kind {
        case .file: files = item.url.map { [$0] } ?? []
        case .link: text = item.text; url = item.url
        case .text: text = item.text
        }
    }

    init(text: String? = nil, url: URL? = nil, image: NSImage? = nil, files: [URL] = []) {
        self.text = text
        self.url = url
        self.image = image
        self.files = files
    }

    /// Every input this context can feed. An image file is both a file and an image.
    var inputs: Set<ActionInput> {
        var set: Set<ActionInput> = [.none]
        if let text, !text.isEmpty { set.insert(.text) }
        if url != nil { set.insert(.url) }
        if image != nil || (!files.isEmpty && files.allSatisfy(ActionFiles.isImage)) { set.insert(.image) }
        if !files.isEmpty {
            if files.allSatisfy(ActionFiles.isFolder) { set.insert(.folder) } else { set.insert(.file) }
        }
        return set
    }

    /// The most specific kind, for the panel header.
    var primary: ActionInput {
        let set = inputs
        for kind in [ActionInput.image, .folder, .file, .url, .text] where set.contains(kind) { return kind }
        return .none
    }

    /// The image itself: the one in the context, or the first image file.
    var resolvedImage: NSImage? {
        image ?? files.first(where: ActionFiles.isImage).flatMap(NSImage.init(contentsOf:))
    }
}

/// What a finished action hands back.
enum ActionOutput {
    case none
    /// Text to show and copy: OCR, an AI answer, a word count.
    case text(String)
    /// A short confirmation for the island: "Copied", "3 files compressed".
    case notice(String, symbol: String)
    /// Files the action made, shown with Reveal and Shelf.
    case files([URL])
}

enum ActionError: LocalizedError {
    case message(String)
    /// For work that runs off the main thread: the text is picked in the app's language when it's shown.
    case phrase(Phrase)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        case .phrase(let phrase): phrase.text(Language(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .en)
        }
    }
}

/// Lets a running action report progress to the island and stream partial text into the panel.
@MainActor
final class ActionRun {
    let activity: LiveActivity?
    var onText: ((String) -> Void)?
    /// Set when the person closes the panel or presses Esc: long actions check it between steps.
    private(set) var cancelled = false

    init(activity: LiveActivity?) { self.activity = activity }

    func progress(_ fraction: Double?, _ detail: String? = nil) {
        activity?.update(progress: fraction, detail: detail)
    }

    func stream(_ text: String) {
        onText?(text)
    }

    func cancel() {
        cancelled = true
        activity?.finish(nil)
    }
}

/// Asks the person for one line before running: the question for "Ask AI", the new name for "Rename".
struct ActionPrompt {
    var placeholder: Phrase
    /// Pre-filled text, like the current file name.
    var initial: (@MainActor (ActionContext) -> String)?
}

/// One thing SAVISUL can do.
struct ActionDefinition: Identifiable {
    enum Body {
        /// Runs at once and returns nothing: switches, timers, panels.
        case instant(@MainActor () -> Void)
        /// Works on a context, may take a while and may hand back a result.
        case task(@MainActor (ActionContext, ActionRun, String?) async throws -> ActionOutput)
    }

    let id: String
    let title: Phrase
    let symbol: String
    let tint: Color
    var keywords: [String] = []
    var accepts: Set<ActionInput> = [.none]
    var permissions: Set<ActionPermission> = []
    var prompt: ActionPrompt?
    /// Shown in the island while it runs ("Converting", "Reading text").
    var activity: Phrase?
    /// A finer check than the input kind: "only plain text, not a link", "only text files".
    var when: (@MainActor (ActionContext) -> Bool)?
    let body: Body

    /// The original shape, used by every instant action and the tests.
    init(id: String, title: Phrase, symbol: String, tint: Color, keywords: [String] = [], run: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.keywords = keywords
        self.body = .instant(run)
    }

    init(id: String, title: Phrase, symbol: String, tint: Color = Palette.accent, keywords: [String] = [], accepts: Set<ActionInput>,
         permissions: Set<ActionPermission> = [], prompt: ActionPrompt? = nil, activity: Phrase? = nil,
         when: (@MainActor (ActionContext) -> Bool)? = nil,
         run: @escaping @MainActor (ActionContext, ActionRun, String?) async throws -> ActionOutput) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.keywords = keywords
        self.accepts = accepts
        self.permissions = permissions
        self.prompt = prompt
        self.activity = activity
        self.when = when
        self.body = .task(run)
    }

    /// Runs an action that needs no context, the way the command bar and the radial menu always have.
    @MainActor func run() {
        switch body {
        case .instant(let action):
            action()
        case .task:
            Task { @MainActor in _ = await ActionEngine.execute(self, context: .empty) }
        }
    }

    /// Whether this action can work on what's in the context.
    @MainActor func fits(_ context: ActionContext) -> Bool {
        !accepts.isDisjoint(with: context.inputs.subtracting([.none])) && (when?(context) ?? true)
    }
}

/// The original name, kept for the catalogue and its callers.
typealias SuiteAction = ActionDefinition

/// Runs actions: instantly for switches, as tracked tasks for everything that works on a context.
enum ActionEngine {
    /// Runs one catalogued action. An unknown id does not run anything.
    @MainActor @discardableResult
    static func perform(_ id: String, in catalog: [SuiteAction]) -> Bool {
        guard let action = catalog.first(where: { $0.id == id }) else { return false }
        action.run()
        return true
    }

    /// Runs a task action with a live activity in the island; errors come back as text for the panel.
    @MainActor
    static func execute(_ action: ActionDefinition, context: ActionContext, input: String? = nil,
                        run: ActionRun? = nil) async -> Result<ActionOutput, Error> {
        switch action.body {
        case .instant(let body):
            body()
            return .success(.none)
        case .task(let body):
            // A caller with its own run shows errors itself; without one, the island says what went wrong.
            let owned = run == nil
            if action.permissions.contains(.ai), !AIService.shared.ready {
                run?.activity?.finish(nil)
                return .failure(ActionError.message(AIPhrases.needsKey.text))
            }
            let handle = run ?? ActionRun(activity: action.activity.map {
                Suite.shared.live.start(symbol: action.symbol, tint: action.tint, title: $0.text)
            })
            do {
                let output = try await body(context, handle, input)
                handle.activity?.finish(nil)
                return .success(output)
            } catch {
                if owned { handle.activity?.fail(error.localizedDescription) } else { handle.activity?.finish(nil) }
                return .failure(error)
            }
        }
    }
}

/// Every action SAVISUL has, in one list.
@MainActor
enum ActionRegistry {
    static var all: [ActionDefinition] { SuiteActions.all + ContextCatalog.all }

    /// What fits a context: actions made for its main kind first (a link's own actions before generic text ones),
    /// the narrowest before the broadest, catalogue order otherwise.
    static func actions(for context: ActionContext) -> [ActionDefinition] {
        let primary = context.primary
        return ContextCatalog.all.filter { $0.fits(context) }.enumerated().sorted { lhs, rhs in
            let left = (lhs.element.accepts.contains(primary) ? 0 : 1, lhs.element.accepts.count, lhs.offset)
            let right = (rhs.element.accepts.contains(primary) ? 0 : 1, rhs.element.accepts.count, rhs.offset)
            return left < right
        }.map(\.element)
    }

    static func action(_ id: String) -> ActionDefinition? { all.first { $0.id == id } }
}

/// File facts the core and the catalogue share.
enum ActionFiles {
    static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])).map { $0.isDirectory == true && $0.isPackage != true } ?? false
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType else { return false }
        return type.conforms(to: .image)
    }

    static func isText(_ url: URL) -> Bool {
        guard let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType else { return false }
        return type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) || type.conforms(to: .xml)
    }

    /// "name.ext" → "name 2.ext" until nothing is in the way.
    static func free(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for index in 2...999 {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return folder.appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)"))
    }
}
