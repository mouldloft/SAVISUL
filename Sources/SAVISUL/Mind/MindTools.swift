#if MOULD_ENGINE
import AppKit
import MouldEngine
import UniformTypeIdentifiers

/// SAVISUL's own features as engine tools. Each one says what it touches and how risky it is; the Secure Runtime
/// decides when the person is asked. Nothing here reaches past SAVISUL's own stores and settings.
enum MindTools {
    @MainActor static func all(suite: Suite) -> [any Tool] {
        automations(suite.automations) + general
    }

    /// Everything but automations, which work on a store of their own.
    static let general: [any Tool] = [shelfAdd, clipboardSearch, clipboardCopy, agentsStatus, calendarUpcoming, islandNotify, feature,
                                      recognizeText, convertImages, findPhotos]

    // MARK: Automations

    static func automations(_ engine: AutomationEngine) -> [any Tool] {
        let triggerKinds = AutomationTrigger.Kind.allCases.map(\.rawValue)
        let conditionKinds = AutomationCondition.Kind.allCases.map(\.rawValue)
        let stepKinds = AutomationStep.Kind.allCases.map(\.rawValue)
        let trigger = JSONSchema.object([
            "kind": .string(oneOf: triggerKinds),
            "text": .string("Device name, folder path, app bundle id or agent name; empty for any.", maxLength: 500),
            "label": .string(maxLength: 120),
            "extensions": .string("File types for a folder, like \"pdf, jpg\".", maxLength: 200),
            "number": .integer("Battery percent, or minutes after midnight for a schedule.", minimum: 0, maximum: 1440),
            "weekdays": .array(of: .integer(minimum: 1, maximum: 7), maxItems: 7)
        ], required: ["kind"])
        let condition = JSONSchema.object([
            "kind": .string(oneOf: conditionKinds), "text": .string(maxLength: 300), "label": .string(maxLength: 120),
            "number": .integer(minimum: 0, maximum: 1440), "number2": .integer(minimum: 0, maximum: 1440),
            "weekdays": .array(of: .integer(minimum: 1, maximum: 7), maxItems: 7)
        ], required: ["kind"])
        let step = JSONSchema.object([
            "kind": .string(oneOf: stepKinds),
            "text": .string("Notice text, sound, output, bundle id, link, shortcut, feature id, action id, name pattern or folder.", maxLength: 500),
            "label": .string(maxLength: 120), "number": .integer("Volume percent or seconds to wait.", minimum: 0, maximum: 3600),
            "flag": .boolean("Feature on or off.")
        ], required: ["kind"])

        let list = FunctionTool(
            ToolSpec(name: "automations.list", title: "List automations", summary: "SAVISUL's automations: names, triggers, whether they're on.",
                     effects: [.read], risk: .low, idempotent: true)
        ) { _, _ in
            let items = await MainActor.run { engine.items }
            let value: [JSONValue] = items.map { automation in
                ["id": .string(automation.id.uuidString), "name": .string(automation.name), "enabled": .bool(automation.enabled),
                 "trigger": .string(automation.trigger.kind.rawValue), "steps": .number(Double(automation.steps.count)), "runs": .number(Double(automation.runs))]
            }
            return ToolOutput(["automations": .array(value)], summary: "\(items.count) automations")
        }

        let create = FunctionTool(
            ToolSpec(name: "automations.create", title: "Create an automation",
                     summary: "Creates a SAVISUL automation: WHEN a trigger fires, IF conditions hold, DO the steps. Paths must be inside granted folders.",
                     input: .object(["name": .string(minLength: 1, maxLength: 120), "trigger": trigger,
                                     "conditions": .array(of: condition, maxItems: 10), "steps": .array(of: step, minItems: 1, maxItems: 20)],
                                    required: ["name", "trigger", "steps"]),
                     effects: [.write, .settings], risk: .reversible),
            preview: { arguments, context in
                let automation = try await build(arguments, context)
                return ToolPreview(summary: await MainActor.run { describe(automation) }, changes: [Change(.create, automation.name)])
            },
            undo: { record, _ in
                guard let id = record.payload["id"]?.string.flatMap(UUID.init(uuidString:)) else { return }
                await MainActor.run { engine.remove(id) }
            },
            run: { arguments, context in
                let automation = try await build(arguments, context)
                let added = await MainActor.run { engine.add(automation) }
                return ToolOutput(["id": .string(added.id.uuidString)], summary: "Created the automation \(added.name)",
                                  undo: UndoRecord(tool: "automations.create", payload: ["id": .string(added.id.uuidString)], summary: "Removed \(added.name)"))
            })

        let enable = FunctionTool(
            ToolSpec(name: "automations.set_enabled", title: "Turn an automation on or off", summary: "Turns one automation on or off by its id.",
                     input: .object(["id": .string(minLength: 36, maxLength: 36), "enabled": .boolean()], required: ["id", "enabled"]),
                     effects: [.settings], risk: .reversible),
            undo: { record, _ in
                guard let id = record.payload["id"]?.string.flatMap(UUID.init(uuidString:)), let was = record.payload["was"]?.bool else { return }
                await MainActor.run { engine.setEnabled(id, was) }
            },
            run: { arguments, _ in
                guard let id = arguments["id"]?.string.flatMap(UUID.init(uuidString:)) else { throw MouldError.invalidValue("not an automation id") }
                let wanted = arguments["enabled"]?.bool ?? true
                let found = await MainActor.run { () -> (String, Bool)? in
                    guard let item = engine.items.first(where: { $0.id == id }) else { return nil }
                    let was = item.enabled
                    engine.setEnabled(id, wanted)
                    return (item.name, was)
                }
                guard let (name, was) = found else { throw MouldError.failed("no automation with that id") }
                return ToolOutput(["name": .string(name), "enabled": .bool(wanted)], summary: "\(name): \(wanted ? "on" : "off")",
                                  undo: UndoRecord(tool: "automations.set_enabled", payload: ["id": .string(id.uuidString), "was": .bool(was)],
                                                   summary: "\(name) back \(was ? "on" : "off")"))
            })

        let runNow = FunctionTool(
            ToolSpec(name: "automations.run", title: "Run an automation now", summary: "Runs one automation's steps now, by its id.",
                     input: .object(["id": .string(minLength: 36, maxLength: 36)], required: ["id"]),
                     effects: [.write, .process, .interface], risk: .sensitive),
            preview: { arguments, _ in
                let id = arguments["id"]?.string.flatMap(UUID.init(uuidString:))
                let text = await MainActor.run { engine.items.first { $0.id == id }.map(describe) } ?? "No such automation"
                return ToolPreview(summary: text)
            },
            run: { arguments, _ in
                guard let id = arguments["id"]?.string.flatMap(UUID.init(uuidString:)) else { throw MouldError.invalidValue("not an automation id") }
                let name = await MainActor.run { () -> String? in
                    guard let item = engine.items.first(where: { $0.id == id }) else { return nil }
                    engine.run(item)
                    return item.name
                }
                guard let name else { throw MouldError.failed("no automation with that id") }
                return ToolOutput(["name": .string(name)], summary: "Ran \(name)")
            })
        return [list, create, enable, runNow]
    }

    /// An automation from a model's arguments, with SAVISUL's defaults for whatever was left out. Folders it watches or
    /// moves files to must be inside what was granted.
    static func build(_ arguments: JSONValue, _ context: ToolContext) async throws -> Automation {
        guard let kind = arguments["trigger"]?["kind"]?.string.flatMap(AutomationTrigger.Kind.init(rawValue:)) else {
            throw MouldError.invalidValue("unknown trigger")
        }
        let source = arguments["trigger"] ?? [:]
        var trigger = AutomationTrigger(kind: kind)
        trigger.text = source["text"]?.string ?? ""
        trigger.label = source["label"]?.string ?? ""
        trigger.extensions = source["extensions"]?.string ?? ""
        trigger.number = source["number"]?.int ?? trigger.number
        trigger.weekdays = source["weekdays"]?.array?.compactMap(\.int) ?? []
        if kind == .fileAdded {
            trigger.text = try context.access.readable(try PathResolver.url(trigger.text)).path
        }
        let conditions = try (arguments["conditions"]?.array ?? []).map { value -> AutomationCondition in
            guard let kind = value["kind"]?.string.flatMap(AutomationCondition.Kind.init(rawValue:)) else { throw MouldError.invalidValue("unknown condition") }
            var condition = AutomationCondition(kind: kind)
            condition.text = value["text"]?.string ?? ""
            condition.label = value["label"]?.string ?? ""
            condition.number = value["number"]?.int ?? condition.number
            condition.number2 = value["number2"]?.int ?? condition.number2
            condition.weekdays = value["weekdays"]?.array?.compactMap(\.int) ?? []
            return condition
        }
        let steps = try (arguments["steps"]?.array ?? []).map { value -> AutomationStep in
            guard let kind = value["kind"]?.string.flatMap(AutomationStep.Kind.init(rawValue:)) else { throw MouldError.invalidValue("unknown step") }
            var step = AutomationStep(kind: kind)
            step.text = value["text"]?.string ?? ""
            step.label = value["label"]?.string ?? ""
            step.number = value["number"]?.int ?? step.number
            step.flag = value["flag"]?.bool ?? false
            if kind == .moveFile { step.text = try context.access.writable(try PathResolver.url(step.text)).path }
            return step
        }
        guard !steps.isEmpty else { throw MouldError.invalidValue("an automation needs at least one step") }
        let name = arguments["name"]?.string ?? "Automation"
        return Automation(name: name, trigger: trigger, conditions: conditions, steps: steps)
    }

    @MainActor static func describe(_ automation: Automation) -> String {
        let when = automation.trigger.kind.title.text + (automation.trigger.text.isEmpty ? "" : " (\(automation.trigger.label.isEmpty ? automation.trigger.text : automation.trigger.label))")
        let steps = automation.steps.map { $0.kind.title.text + ($0.text.isEmpty ? "" : ": \($0.text)") }.joined(separator: " → ")
        return "\(automation.name): \(when) → \(steps)"
    }

    // MARK: Shelf, clipboard, island

    static let shelfAdd = FunctionTool(
        ToolSpec(name: "shelf.add", title: "Put on the Shelf", summary: "Puts files (by path) or a piece of text on SAVISUL's Shelf, for dragging or sharing later.",
                 input: .object(["paths": .array(of: .path(), maxItems: 200), "text": .string(maxLength: 20_000)]),
                 effects: [.interface], risk: .low)
    ) { arguments, context in
        let urls = try (arguments["paths"]?.array ?? []).map { try context.access.readable(try PathResolver.url($0.string ?? "")) }
        let text = arguments["text"]?.string
        guard !urls.isEmpty || !(text ?? "").isEmpty else { throw MouldError.invalidValue("nothing to put on the Shelf") }
        await MainActor.run {
            if !urls.isEmpty { Suite.shared.shelf.add(urls: urls) }
            if let text, !text.isEmpty { Suite.shared.shelf.add(text: text) }
        }
        return ToolOutput(["added": .number(Double(urls.count + (text == nil ? 0 : 1)))], summary: "On the Shelf")
    }

    static let clipboardSearch = FunctionTool(
        ToolSpec(name: "clipboard.search", title: "Search clipboard history", summary: "Finds things copied earlier: text, links, files, colors.",
                 input: .object(["query": .string(maxLength: 200), "limit": .integer(minimum: 1, maximum: 50)]),
                 effects: [.read], risk: .low, idempotent: true)
    ) { arguments, _ in
        let query = arguments["query"]?.string?.lowercased() ?? ""
        let limit = arguments["limit"]?.int ?? 10
        let found = await MainActor.run { () -> [JSONValue] in
            let history = Suite.shared.clipboard.history
            return history.items.lazy.filter { query.isEmpty || history.fullText($0).lowercased().contains(query) }.prefix(limit).map { item in
                ["kind": .string(item.kind.rawValue), "text": .string(String(history.fullText(item).prefix(2000))),
                 "copied": .string(ISO8601DateFormatter().string(from: item.date))]
            }
        }
        return ToolOutput(["items": .array(found)], summary: "\(found.count) clipboard items", untrusted: true)
    }

    static let clipboardCopy = FunctionTool(
        ToolSpec(name: "clipboard.copy", title: "Copy", summary: "Puts text on the clipboard, ready to paste.",
                 input: .object(["text": .string(minLength: 1, maxLength: 100_000)], required: ["text"]), effects: [.interface], risk: .low)
    ) { arguments, _ in
        let text = arguments["text"]?.string ?? ""
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        return ToolOutput(["characters": .number(Double(text.count))], summary: "Copied")
    }

    static let islandNotify = FunctionTool(
        ToolSpec(name: "island.notify", title: "Show in the island", summary: "Shows a short notice around the notch.",
                 input: .object(["title": .string(minLength: 1, maxLength: 80), "detail": .string(maxLength: 160)], required: ["title"]),
                 effects: [.interface], risk: .low)
    ) { arguments, _ in
        let title = arguments["title"]?.string ?? "", detail = arguments["detail"]?.string
        await MainActor.run {
            Suite.shared.notify(IslandNotice(symbol: "sparkles", tint: Palette.accent, title: title, detail: detail, style: .info, duration: 5))
        }
        return ToolOutput(summary: "Shown")
    }

    // MARK: Agents and calendar

    static let agentsStatus = FunctionTool(
        ToolSpec(name: "agents.status", title: "AI agents", summary: "What the person's coding agents (Claude Code, Codex, Cursor…) are doing: who works on which project, since when.",
                 effects: [.read], risk: .low, idempotent: true)
    ) { _, _ in
        let agents = await MainActor.run { () -> [JSONValue] in
            Suite.shared.agents.agents.filter(\.installed).map { status in
                ["agent": .string(status.kind.short), "working": .bool(status.working), "project": status.project.map(JSONValue.string) ?? .null,
                 "model": status.model.map(JSONValue.string) ?? .null,
                 "minutes": status.since.map { .number((Date().timeIntervalSince($0) / 60).rounded()) } ?? .null]
            }
        }
        return ToolOutput(["agents": .array(agents)], summary: "\(agents.count) agents")
    }

    static let calendarUpcoming = FunctionTool(
        ToolSpec(name: "calendar.upcoming", title: "Upcoming meetings", summary: "The next events in the person's calendars.",
                 input: .object(["limit": .integer(minimum: 1, maximum: 20)]), effects: [.read], risk: .low, idempotent: true)
    ) { arguments, _ in
        let limit = arguments["limit"]?.int ?? 5
        let events = await MainActor.run { () -> [JSONValue] in
            let formatter = ISO8601DateFormatter()
            return Suite.shared.calendar.events.filter { $0.end > Date() }.prefix(limit).map { event in
                ["title": .string(event.title), "start": .string(formatter.string(from: event.start)), "end": .string(formatter.string(from: event.end)),
                 "calendar": .string(event.calendar), "location": event.location.map(JSONValue.string) ?? .null, "online": .bool(event.meeting != nil)]
            }
        }
        return ToolOutput(["events": .array(events)], summary: "\(events.count) events", untrusted: true)
    }

    // MARK: Settings

    static let feature = FunctionTool(
        ToolSpec(name: "savisul.feature", title: "Turn a SAVISUL feature on or off",
                 summary: "Turns one of SAVISUL's own features on or off by its id (from the Features tab), e.g. to save battery.",
                 input: .object(["id": .string(minLength: 2, maxLength: 60), "on": .boolean()], required: ["id", "on"]),
                 effects: [.settings], risk: .reversible),
        preview: { arguments, _ in
            ToolPreview(summary: "\(arguments["id"]?.string ?? ""): \(arguments["on"]?.bool == true ? "on" : "off")",
                        changes: [Change(.setting, arguments["id"]?.string ?? "", arguments["on"]?.bool == true ? "on" : "off")])
        },
        undo: { record, _ in
            guard let id = record.payload["id"]?.string, let was = record.payload["was"]?.bool else { return }
            await MainActor.run {
                if let key = AutomationEngine.featureKey(id) { Suite.shared.settings[keyPath: key] = was }
            }
        },
        run: { arguments, _ in
            let id = arguments["id"]?.string ?? "", on = arguments["on"]?.bool ?? false
            // The assistant can't switch itself off, or the switches that keep the person in control.
            guard !["assistant", "assistantHotkey", "agentApprovals", "faceUnlock"].contains(id) else { throw MouldError.denied("\(id) is changed only by the person") }
            let was = await MainActor.run { () -> Bool? in
                guard let key = AutomationEngine.featureKey(id) else { return nil }
                let was = Suite.shared.settings[keyPath: key]
                Suite.shared.settings[keyPath: key] = on
                return was
            }
            guard let was else { throw MouldError.invalidValue("there is no feature \(id)") }
            return ToolOutput(["id": .string(id), "on": .bool(on)], summary: "\(id) \(on ? "on" : "off")",
                              undo: UndoRecord(tool: "savisul.feature", payload: ["id": .string(id), "was": .bool(was)], summary: "\(id) back \(was ? "on" : "off")"))
        })

    // MARK: Images

    static let recognizeText = FunctionTool(
        ToolSpec(name: "images.recognize_text", title: "Read text in an image", summary: "Recognizes the text in an image or screenshot, on this Mac.",
                 input: .object(["path": .path()], required: ["path"]), effects: [.read], risk: .low, timeout: .seconds(60), idempotent: true)
    ) { arguments, context in
        let url = try context.access.readable(try PathResolver.url(arguments["path"]?.string ?? ""))
        guard let image = ImageWork.cgImage(url) else { throw MouldError.failed("\(url.lastPathComponent) isn't an image") }
        let text = try await TextRecognizer.text(in: image)
        return ToolOutput(["text": .string(text)], summary: "Read \(text.count) characters", untrusted: true)
    }

    static let convertImages = FunctionTool(
        ToolSpec(name: "images.convert", title: "Convert images", summary: "Saves copies of images as PNG, JPEG or HEIC next to the originals.",
                 input: .object(["paths": .array(of: .path(), minItems: 1, maxItems: 300), "format": .string(oneOf: ["png", "jpeg", "heic"])],
                                required: ["paths", "format"]),
                 effects: [.write], risk: .reversible, timeout: .seconds(300)),
        preview: { arguments, _ in
            ToolPreview(summary: "Save \(arguments["paths"]?.array?.count ?? 0) images as \(arguments["format"]?.string?.uppercased() ?? "")")
        },
        undo: { record, context in
            for path in record.payload["made"]?.array?.compactMap(\.string) ?? [] {
                try? FileManager.default.removeItem(at: try context.access.restorable(URL(fileURLWithPath: path)))
            }
        },
        run: { arguments, context in
            let format = arguments["format"]?.string ?? "png"
            let type: UTType = format == "jpeg" ? .jpeg : (format == "heic" ? .heic : .png)
            var made: [URL] = []
            let paths = arguments["paths"]?.array ?? []
            for (index, value) in paths.enumerated() {
                try Task.checkCancellation()
                let url = try context.access.readable(try PathResolver.url(value.string ?? ""))
                guard let image = ImageWork.cgImage(url) else { continue }
                let target = try context.access.writable(ActionFiles.free(url.deletingPathExtension().appendingPathExtension(format == "jpeg" ? "jpg" : format)))
                try ImageWork.write(image, to: target, type: type, quality: type == .png ? nil : 0.85)
                made.append(target)
                context.progress(Double(index + 1) / Double(paths.count), target.lastPathComponent)
            }
            return ToolOutput(["made": .array(made.map { .string($0.path) })], summary: "Saved \(made.count) images",
                              undo: UndoRecord(tool: "images.convert", payload: ["made": .array(made.map { .string($0.path) })], summary: "Removed \(made.count) converted images"))
        })
}

/// SAVISUL's state as context: agents at work, the next meeting, what's playing.
struct SuiteContextSource: ContextSource {
    let name = "savisul.suite"

    func refresh() async -> [ContextDelta] {
        await MainActor.run {
            let suite = Suite.shared
            var nodes: [ContextNode] = []
            for agent in suite.agents.working {
                nodes.append(ContextNode(id: "agent:\(agent.kind.rawValue)", kind: .agent, title: agent.kind.short,
                                         attributes: ["project": agent.project.map(JSONValue.string) ?? .null, "working": true],
                                         weight: 0.6, source: name))
            }
            var deltas: [ContextDelta] = [.replace(kind: .agent, source: name, nodes: nodes)]
            // Meetings stay out of every request: they would make each one private, keep it from the person's own AI,
            // and SAVISUL answers questions about them itself.
            deltas.append(.replace(kind: .calendar, source: name, nodes: []))
            if suite.nowPlaying.playing, let item = suite.nowPlaying.item {
                deltas.append(.replace(kind: .media, source: name, nodes: [ContextNode(id: "media:now", kind: .media, title: item.title,
                                                                                      attributes: ["artist": .string(item.artist)], weight: 0.2, source: name)]))
            } else {
                deltas.append(.replace(kind: .media, source: name, nodes: []))
            }
            return deltas
        }
    }
}
#endif
