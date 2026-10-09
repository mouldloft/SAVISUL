import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import Vision

/// Everything Context Actions can do with a selection, grouped by what it works on.
@MainActor
enum ContextCatalog {
    static var all: [ActionDefinition] { text + link + image + file }

    // MARK: Text

    private static var text: [ActionDefinition] {
        [
            ai("ai.summarize", Phrase("Summarize", ru: "Кратко пересказать", uk: "Коротко переказати", fr: "Résumer"), "text.badge.star",
               system: "Summarize the text in a few short bullet points. Reply in the same language as the text. No preamble.",
               keywords: ["summary", "tldr", "пересказ", "кратко"], when: plainText),
            ai("ai.translate", Phrase("Translate", ru: "Перевести", uk: "Перекласти", fr: "Traduire"), "character.book.closed",
               system: "Translate the text into \(AIService.languageName). If it is already in \(AIService.languageName), translate it into English. Keep formatting. Return only the translation.",
               keywords: ["translate", "перевод", "переклад"], when: plainText),
            ai("ai.rewrite", Phrase("Rewrite", ru: "Переписать лучше", uk: "Переписати краще", fr: "Réécrire"), "pencil.and.outline",
               system: "Rewrite the text so it reads clearly and naturally. Keep its meaning, tone and language. Fix grammar and spelling. Return only the rewritten text.",
               keywords: ["rewrite", "grammar", "исправить", "грамматика"], when: plainText),
            ai("ai.explain", Phrase("Explain", ru: "Объяснить", uk: "Пояснити", fr: "Expliquer"), "lightbulb",
               system: "Explain this simply and briefly, as to a smart friend who isn't an expert. Reply in \(AIService.languageName).",
               keywords: ["explain", "объяснить", "что это"], when: plainText),
            ai("ai.ask", Phrase("Ask AI…", ru: "Спросить ИИ…", uk: "Запитати ШІ…", fr: "Demander à l’IA…"), "sparkles",
               system: "Answer the person's question about the content they selected. Be concise. Reply in the language of the question.",
               keywords: ["ask", "ai", "вопрос", "спросить"], when: plainText,
               prompt: ActionPrompt(placeholder: Phrase("Your question about the selection", ru: "Ваш вопрос о выделенном", uk: "Ваше питання про виділене", fr: "Votre question sur la sélection"))),
            ActionDefinition(id: "text.shelf", title: Phrases.toShelf, symbol: "tray.and.arrow.down", accepts: [.text, .url]) { context, _, _ in
                if let url = context.url { Suite.shared.shelf.add(urls: [url]) } else { Suite.shared.shelf.add(text: context.text ?? "") }
                return .notice(Phrases.onShelf.text, symbol: "tray.full.fill")
            },
            ActionDefinition(id: "text.note", title: Phrase("Create note", ru: "Создать заметку", uk: "Створити нотатку", fr: "Créer une note"),
                             symbol: "note.text.badge.plus", tint: Palette.warning, accepts: [.text],
                             activity: Phrase("Creating note", ru: "Создаю заметку", uk: "Створюю нотатку", fr: "Création de la note"), when: plainText) { context, _, _ in
                try await Notes.create(context.text ?? "")
                return .notice(Phrase("Note created", ru: "Заметка создана", uk: "Нотатку створено", fr: "Note créée").text, symbol: "note.text")
            },
            ActionDefinition(id: "text.search", title: Phrase("Search the web", ru: "Найти в интернете", uk: "Знайти в інтернеті", fr: "Rechercher sur le web"),
                             symbol: "magnifyingglass", accepts: [.text], when: plainText) { context, _, _ in
                let query = (context.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)
                if let encoded = String(query).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
                    NSWorkspace.shared.open(url)
                }
                return .none
            },
            ActionDefinition(id: "text.qr", title: Phrase("QR code", ru: "QR-код", uk: "QR-код", fr: "Code QR"), symbol: "qrcode",
                             keywords: ["qr"], accepts: [.text, .url]) { context, _, _ in
                guard let image = QRCode.image(context.url?.absoluteString ?? context.text ?? "") else {
                    throw ActionError.message(Phrase("Too long for a QR code", ru: "Слишком длинно для QR-кода", uk: "Задовго для QR-коду", fr: "Trop long pour un code QR").text)
                }
                PinWindow.pin(image, title: "QR")
                return .none
            },
            ActionDefinition(id: "text.count", title: Phrase("Count words", ru: "Посчитать слова", uk: "Порахувати слова", fr: "Compter les mots"),
                             symbol: "number", tint: Palette.secondary, keywords: ["count", "слова", "символы"], accepts: [.text], when: plainText) { context, _, _ in
                let text = context.text ?? ""
                let words = text.split { $0.isWhitespace || $0.isNewline }.count
                let lines = text.split(whereSeparator: \.isNewline).count
                return .text(ContextPhrases.counts(Say.number(words), Say.number(text.count), Say.number(max(lines, 1))))
            }
        ]
    }

    // MARK: Links

    private static var link: [ActionDefinition] {
        [
            ActionDefinition(id: "url.open", title: Phrase("Open in browser", ru: "Открыть в браузере", uk: "Відкрити в браузері", fr: "Ouvrir dans le navigateur"),
                             symbol: "safari", accepts: [.url]) { context, _, _ in
                if let url = context.url { NSWorkspace.shared.open(url) }
                return .none
            },
            ActionDefinition(id: "url.clean", title: Phrase("Clean link", ru: "Очистить ссылку", uk: "Очистити посилання", fr: "Nettoyer le lien"),
                             symbol: "wand.and.sparkles", tint: Palette.positive, keywords: ["utm", "tracking", "метки"], accepts: [.url]) { context, _, _ in
                guard let url = context.url else { return .none }
                let clean = URLCleaner.clean(url.absoluteString)
                Clipboard.copy(clean.url)
                return .notice(clean.removed > 0 ? ContextPhrases.cleaned(clean.removed) : ContextPhrases.alreadyClean.text, symbol: "checkmark.seal.fill")
            },
            ai("ai.page", Phrase("Summarize page", ru: "Пересказать страницу", uk: "Переказати сторінку", fr: "Résumer la page"), "doc.richtext",
               accepts: [.url], system: "Summarize this web page in a few short bullet points: what it is and what matters in it. Reply in \(AIService.languageName). No preamble.",
               keywords: ["page", "article", "статья"]) { context, run in
                guard let url = context.url else { return "" }
                run.progress(nil, url.host)
                return try await WebPage.text(url)
            },
            ActionDefinition(id: "url.copy", title: Phrase("Copy link", ru: "Скопировать ссылку", uk: "Скопіювати посилання", fr: "Copier le lien"),
                             symbol: "link", accepts: [.url]) { context, _, _ in
                Clipboard.copy(context.url?.absoluteString ?? "")
                return .notice(Phrases.copy.text, symbol: "doc.on.doc.fill")
            }
        ]
    }

    // MARK: Images

    private static var image: [ActionDefinition] {
        [
            ActionDefinition(id: "image.ocr", title: Phrase("Recognize text", ru: "Распознать текст", uk: "Розпізнати текст", fr: "Reconnaître le texte"),
                             symbol: "text.viewfinder", tint: Palette.positive, keywords: ["ocr", "text", "текст", "распознать"], accepts: [.image],
                             activity: Phrase("Reading text", ru: "Читаю текст", uk: "Читаю текст", fr: "Lecture du texte")) { context, run, _ in
                .text(try await recognize(context, run: run))
            },
            ActionDefinition(id: "image.copyText", title: Phrase("Copy text from image", ru: "Скопировать текст с картинки", uk: "Скопіювати текст із зображення", fr: "Copier le texte de l’image"),
                             symbol: "doc.on.clipboard", tint: Palette.positive, keywords: ["ocr"], accepts: [.image],
                             activity: Phrase("Reading text", ru: "Читаю текст", uk: "Читаю текст", fr: "Lecture du texte")) { context, run, _ in
                let text = try await recognize(context, run: run)
                Clipboard.copy(text)
                return .notice(ContextPhrases.copiedChars(Say.number(text.count)), symbol: "doc.on.clipboard.fill")
            },
            ActionDefinition(id: "image.pin", title: Phrase("Pin to screen", ru: "Закрепить на экране", uk: "Закріпити на екрані", fr: "Épingler à l’écran"),
                             symbol: "pin.fill", tint: Palette.warning, keywords: ["pin", "float", "закрепить"], accepts: [.image]) { context, _, _ in
                guard let image = context.resolvedImage else { return .none }
                PinWindow.pin(image, title: context.files.first?.lastPathComponent)
                return .none
            },
            ai("ai.image", Phrase("Ask AI about image…", ru: "Спросить ИИ о картинке…", uk: "Запитати ШІ про зображення…", fr: "Demander à l’IA sur l’image…"), "sparkles",
               accepts: [.image], system: "Answer the person's question about the image. Be concise. Reply in the language of the question.",
               keywords: ["vision", "картинка"],
               prompt: ActionPrompt(placeholder: Phrase("What do you want to know?", ru: "Что хотите узнать?", uk: "Що хочете дізнатися?", fr: "Que voulez-vous savoir ?")),
               image: true),
            convert("png", UTType.png, "PNG"),
            convert("jpeg", UTType.jpeg, "JPEG"),
            convert("heic", UTType.heic, "HEIC"),
            ActionDefinition(id: "image.compress", title: Phrase("Compress image", ru: "Сжать картинку", uk: "Стиснути зображення", fr: "Compresser l’image"),
                             symbol: "arrow.down.right.and.arrow.up.left", keywords: ["compress", "сжать", "size"], accepts: [.image],
                             activity: Phrase("Compressing", ru: "Сжимаю", uk: "Стискаю", fr: "Compression")) { context, run, _ in
                try await images(context, run: run) { source, _ in
                    let alpha = ImageWork.hasAlpha(source)
                    return (alpha ? .heic : .jpeg, alpha ? 0.6 : 0.72, ContextPhrases.compressedSuffix.text)
                }
            },
            ActionDefinition(id: "image.shelf", title: Phrases.toShelf, symbol: "tray.and.arrow.down", accepts: [.image],
                             when: { $0.files.isEmpty }) { context, _, _ in
                if !context.files.isEmpty { Suite.shared.shelf.add(urls: context.files) } else if let image = context.image { Suite.shared.shelf.add(image: image) }
                return .notice(Phrases.onShelf.text, symbol: "tray.full.fill")
            }
        ]
    }

    // MARK: Files and folders

    private static var file: [ActionDefinition] {
        [
            ActionDefinition(id: "file.compress", title: Phrase("Compress to ZIP", ru: "Сжать в ZIP", uk: "Стиснути в ZIP", fr: "Compresser en ZIP"),
                             symbol: "doc.zipper", keywords: ["zip", "archive", "архив"], accepts: [.file, .folder],
                             activity: Phrase("Compressing", ru: "Сжимаю", uk: "Стискаю", fr: "Compression")) { context, run, _ in
                run.progress(nil, ContextPhrases.items(context.files.count))
                let files = context.files
                let archive = try await Task.detached(priority: .userInitiated) { try Archive.zip(files) }.value
                return .files([archive])
            },
            ActionDefinition(id: "file.rename", title: Phrase("Rename…", ru: "Переименовать…", uk: "Перейменувати…", fr: "Renommer…"),
                             symbol: "character.cursor.ibeam", keywords: ["rename", "переименовать"], accepts: [.file, .folder],
                             prompt: ActionPrompt(placeholder: Phrase("New name", ru: "Новое имя", uk: "Нове імʼя", fr: "Nouveau nom"),
                                                  initial: { $0.files.count == 1 ? $0.files[0].deletingPathExtension().lastPathComponent : "" })) { context, _, input in
                let renamed = try FileWork.rename(context.files, to: input ?? "")
                return .files(renamed)
            },
            ActionDefinition(id: "file.move", title: Phrase("Move to…", ru: "Переместить в…", uk: "Перемістити в…", fr: "Déplacer vers…"),
                             symbol: "folder.badge.plus", keywords: ["move", "переместить"], accepts: [.file, .folder]) { context, _, _ in
                guard let folder = FileWork.chooseFolder() else { return .none }
                return .files(try FileWork.move(context.files, to: folder))
            },
            ActionDefinition(id: "file.share", title: Phrase("Share…", ru: "Поделиться…", uk: "Поділитися…", fr: "Partager…"),
                             symbol: "square.and.arrow.up", keywords: ["share", "airdrop", "поделиться"], accepts: [.file, .folder, .url, .image]) { context, _, _ in
                let items: [Any] = !context.files.isEmpty ? context.files : (context.url.map { [$0] } ?? context.image.map { [$0] } ?? [])
                Suite.shared.contextActions.share(items)
                return .none
            },
            ai("ai.file", Phrase("Ask AI about file…", ru: "Спросить ИИ о файле…", uk: "Запитати ШІ про файл…", fr: "Demander à l’IA sur le fichier…"), "sparkles",
               accepts: [.file], system: "The person shares a file. Answer their question about it, or if there is no question, say what the file is and what matters in it. Be concise. Reply in \(AIService.languageName).",
               keywords: ["analyze", "анализ", "файл"], when: { $0.files.contains(where: ActionFiles.isText) },
               prompt: ActionPrompt(placeholder: Phrase("Question (optional)", ru: "Вопрос (можно пусто)", uk: "Питання (можна порожньо)", fr: "Question (facultative)"))) { context, _ in
                guard let url = context.files.first(where: ActionFiles.isText) else {
                    throw ActionError.message(Phrase("AI can read text files and images", ru: "ИИ читает текстовые файлы и картинки", uk: "ШІ читає текстові файли й зображення", fr: "L’IA lit les fichiers texte et les images").text)
                }
                let text = try String(contentsOf: url, encoding: .utf8)
                return "File: \(url.lastPathComponent)\n\n" + String(text.prefix(60_000))
            },
            ActionDefinition(id: "file.copyPath", title: Phrase("Copy path", ru: "Скопировать путь", uk: "Скопіювати шлях", fr: "Copier le chemin"),
                             symbol: "doc.on.doc", accepts: [.file, .folder]) { context, _, _ in
                Clipboard.copy(context.files.map(\.path).joined(separator: "\n"))
                return .notice(Phrases.copy.text, symbol: "doc.on.doc.fill")
            },
            ActionDefinition(id: "file.reveal", title: Phrases.reveal, symbol: "folder", accepts: [.file, .folder]) { context, _, _ in
                NSWorkspace.shared.activateFileViewerSelecting(context.files)
                return .none
            },
            ActionDefinition(id: "folder.terminal", title: Phrase("Open in Terminal", ru: "Открыть в Терминале", uk: "Відкрити в Терміналі", fr: "Ouvrir dans Terminal"),
                             symbol: "terminal", accepts: [.folder], when: { $0.files.count == 1 }) { context, _, _ in
                guard let folder = context.files.first else { return .none }
                let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
                return .none
            },
            ActionDefinition(id: "file.shelf", title: Phrases.toShelf, symbol: "tray.and.arrow.down", accepts: [.file, .folder]) { context, _, _ in
                Suite.shared.shelf.add(urls: context.files)
                return .notice(Phrases.onShelf.text, symbol: "tray.full.fill")
            }
        ]
    }

    // MARK: Builders

    /// Text that isn't a lone link: a link gets its own actions.
    private static let plainText: @MainActor (ActionContext) -> Bool = { $0.url == nil }

    /// An AI action on text. `source` turns the context into the text to send; by default the selected text.
    private static func ai(_ id: String, _ title: Phrase, _ symbol: String, accepts: Set<ActionInput> = [.text], system: String,
                           keywords: [String] = [], when: (@MainActor (ActionContext) -> Bool)? = nil,
                           prompt: ActionPrompt? = nil, image: Bool = false,
                           source: (@MainActor (ActionContext, ActionRun) async throws -> String)? = nil) -> ActionDefinition {
        ActionDefinition(id: id, title: title, symbol: symbol, tint: AgentKind.claude.tint, keywords: keywords + ["ai", "ии"], accepts: accepts,
                         permissions: [.ai], prompt: prompt, activity: Phrase("Asking AI", ru: "Спрашиваю ИИ", uk: "Питаю ШІ", fr: "Question à l’IA"),
                         when: when) { context, run, input in
            let content = try await source?(context, run) ?? (context.text ?? "")
            var message = content
            if let input, !input.trimmingCharacters(in: .whitespaces).isEmpty {
                message = image ? input : "Question: \(input)\n\nContent:\n\(content)"
            } else if image {
                message = "Describe this image."
            }
            let picture = image ? context.resolvedImage.flatMap { ImageWork.png($0, maxSide: 1568) } : nil
            run.progress(nil, AIService.shared.model)
            var answer = ""
            for try await piece in AIService.shared.stream(system: system, prompt: message, image: picture) {
                if run.cancelled { break }
                answer += piece
                run.stream(answer)
            }
            return .text(answer.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func convert(_ id: String, _ type: UTType, _ name: String) -> ActionDefinition {
        ActionDefinition(id: "image.to\(id)", title: Phrase("Convert to %@", ru: "Конвертировать в %@", uk: "Конвертувати в %@", fr: "Convertir en %@").formatted(name),
                         symbol: "arrow.triangle.2.circlepath", keywords: ["convert", "конвертировать", id], accepts: [.image],
                         activity: Phrase("Converting", ru: "Конвертирую", uk: "Конвертую", fr: "Conversion")) { context, run, _ in
            try await images(context, run: run) { _, _ in (type, type == .png ? nil : 0.9, nil) }
        }
    }

    /// Runs one image job over every image in the context, writing each result next to its original.
    private static func images(_ context: ActionContext, run: ActionRun,
                               plan: @escaping (CGImage, URL?) -> (UTType, Double?, String?)) async throws -> ActionOutput {
        var sources: [(CGImage, URL?)] = context.files.filter(ActionFiles.isImage).compactMap { url in ImageWork.cgImage(url).map { ($0, url) } }
        if sources.isEmpty, let image = context.image.flatMap(ImageWork.cgImage) { sources = [(image, nil)] }
        guard !sources.isEmpty else { throw ActionError.message(ContextPhrases.noImage.text) }
        var made: [URL] = []
        var before = 0
        var after = 0
        for (index, (image, url)) in sources.enumerated() {
            if run.cancelled { break }
            run.progress(Double(index) / Double(sources.count), ContextPhrases.of(index + 1, sources.count))
            let (type, quality, suffix) = plan(image, url)
            let folder = url?.deletingLastPathComponent() ?? ShelfStore.drops
            let base = url?.deletingPathExtension().lastPathComponent ?? "Image \(Int(Date().timeIntervalSince1970))"
            let name = base + (suffix.map { " (\($0))" } ?? "")
            let target = ActionFiles.free(folder.appendingPathComponent(name).appendingPathExtension(type.preferredFilenameExtension ?? "img"))
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await Task.detached(priority: .userInitiated) { try ImageWork.write(image, to: target, type: type, quality: quality) }.value
            made.append(target)
            before += url.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
            after += (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        run.progress(1)
        if context.files.isEmpty { Suite.shared.shelf.add(urls: made) }
        if before > 0, after > 0, after < before {
            run.activity?.update(progress: 1, detail: "\(ByteCountFormatter.string(fromByteCount: Int64(before), countStyle: .file)) → \(ByteCountFormatter.string(fromByteCount: Int64(after), countStyle: .file))")
        }
        return .files(made)
    }

    private static func recognize(_ context: ActionContext, run: ActionRun) async throws -> String {
        guard let image = context.resolvedImage.flatMap(ImageWork.cgImage) else { throw ActionError.message(ContextPhrases.noImage.text) }
        let text = try await TextRecognizer.text(in: image)
        guard !text.isEmpty else { throw ActionError.message(ContextPhrases.noText.text) }
        return text
    }
}

// MARK: Helpers

enum Clipboard {
    @MainActor static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// On-device text recognition: nothing leaves the Mac.
enum TextRecognizer {
    static func text(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                let wanted = ["en-US", "ru-RU", "uk-UA", "fr-FR", "de-DE", "es-ES", "it-IT", "pt-BR"]
                let supported = (try? request.supportedRecognitionLanguages()) ?? []
                request.recognitionLanguages = wanted.filter(supported.contains)
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum ImageWork {
    /// Decodes with the camera's rotation applied.
    static func cgImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 16_384]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func cgImage(_ image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double?) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ActionError.phrase(ContextPhrases.cantWrite)
        }
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ActionError.phrase(ContextPhrases.cantWrite) }
    }

    /// PNG no larger than `maxSide`, small enough to send to an AI model.
    static func png(_ image: NSImage, maxSide: CGFloat) -> Data? {
        guard let source = cgImage(image) else { return nil }
        let scale = min(1, maxSide / CGFloat(max(source.width, source.height)))
        let width = Int(CGFloat(source.width) * scale)
        let height = Int(CGFloat(source.height) * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }
}

enum Archive {
    /// Zips files next to the first one: "Name.zip" for one item, "Archive.zip" for several.
    static func zip(_ files: [URL]) throws -> URL {
        guard let first = files.first else { throw ActionError.phrase(ContextPhrases.nothing) }
        let folder = first.deletingLastPathComponent()
        let name = files.count == 1 ? first.lastPathComponent : "Archive"
        let target = ActionFiles.free(folder.appendingPathComponent(name).appendingPathExtension("zip"))
        let output: Shell.Output?
        if files.count == 1 {
            output = Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, target.path], timeout: 600)
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = folder
            let names = files.map { $0.deletingLastPathComponent() == folder ? $0.lastPathComponent : $0.path }
            process.arguments = ["-r", "-q", "-y", target.path] + names
            try process.run()
            process.waitUntilExit()
            output = Shell.Output(status: process.terminationStatus, text: "")
        }
        guard output?.status == 0, FileManager.default.fileExists(atPath: target.path) else {
            throw ActionError.phrase(ContextPhrases.cantWrite)
        }
        return target
    }
}

enum FileWork {
    /// One file takes the new name as is (keeping its extension); several become "Name 1", "Name 2"…
    static func rename(_ files: [URL], to name: String) throws -> [URL] {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !base.isEmpty else { throw ActionError.phrase(ContextPhrases.nameNeeded) }
        var renamed: [URL] = []
        for (index, url) in files.enumerated() {
            let ext = url.pathExtension
            var stem = files.count == 1 ? base : "\(base) \(index + 1)"
            if files.count == 1, !ext.isEmpty, stem.lowercased().hasSuffix("." + ext.lowercased()) { stem = String(stem.dropLast(ext.count + 1)) }
            let wanted = url.deletingLastPathComponent().appendingPathComponent(ext.isEmpty || ActionFiles.isFolder(url) ? stem : "\(stem).\(ext)")
            guard wanted.path != url.path else { renamed.append(url); continue }
            let target = ActionFiles.free(wanted)
            try FileManager.default.moveItem(at: url, to: target)
            renamed.append(target)
        }
        return renamed
    }

    static func move(_ files: [URL], to folder: URL) throws -> [URL] {
        try files.map { url in
            let target = ActionFiles.free(folder.appendingPathComponent(url.lastPathComponent))
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
    }

    @MainActor static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = Phrase("Move here", ru: "Переместить сюда", uk: "Перемістити сюди", fr: "Déplacer ici").text
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

enum QRCode {
    static func image(_ text: String) -> NSImage? {
        guard !text.isEmpty, text.utf8.count <= 2_000 else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

/// Apple Notes, through AppleScript. macOS asks once whether SAVISUL may control Notes.
enum Notes {
    static func create(_ text: String) async throws {
        let html = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .components(separatedBy: .newlines).map { "<div>\($0.isEmpty ? "<br>" : $0)</div>" }.joined()
        let literal = html.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Notes\" to make new note with properties {body:\"\(literal)\"}"
        let output = await Task.detached(priority: .userInitiated) { Shell.run("/usr/bin/osascript", ["-e", script], timeout: 30) }.value
        guard output?.status == 0 else {
            throw ActionError.phrase(Phrase("Notes didn’t answer. Allow SAVISUL to control Notes in Privacy & Security → Automation.",
                                             ru: "Заметки не ответили. Разрешите SAVISUL управлять Заметками: Конфиденциальность → Автоматизация.",
                                             uk: "Нотатки не відповіли. Дозвольте SAVISUL керувати Нотатками: Конфіденційність → Автоматизація.",
                                             fr: "Notes n’a pas répondu. Autorisez SAVISUL dans Confidentialité → Automatisation."))
        }
    }
}

/// A web page reduced to its readable text, for summaries.
enum WebPage {
    static func text(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        var html = String(decoding: data.prefix(3_000_000), as: UTF8.self)
        for tag in ["script", "style", "noscript", "svg", "nav", "footer", "header"] {
            html = html.replacingOccurrences(of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        let title = html.range(of: "<title[^>]*>([\\s\\S]*?)</title>", options: [.regularExpression, .caseInsensitive]).map { String(html[$0]) } ?? ""
        var text = html.replacingOccurrences(of: "<br\\s*/?>|</p>|</div>|</h[1-6]>|</li>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, value) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&rsquo;": "’", "&mdash;": "—"] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 80 else {
            throw ActionError.phrase(Phrase("This page has no readable text", ru: "На странице нет читаемого текста", uk: "На сторінці немає тексту", fr: "Cette page n’a pas de texte lisible"))
        }
        let cleanTitle = title.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return "Page: \(cleanTitle)\nURL: \(url.absoluteString)\n\n" + String(text.prefix(40_000))
    }
}

enum ContextPhrases {
    static let noImage = Phrase("No image here", ru: "Здесь нет картинки", uk: "Тут немає зображення", fr: "Aucune image ici")
    static let noText = Phrase("No text found in the image", ru: "На картинке нет текста", uk: "На зображенні немає тексту", fr: "Aucun texte dans l’image")
    static let cantWrite = Phrase("Couldn’t save the file", ru: "Не удалось сохранить файл", uk: "Не вдалося зберегти файл", fr: "Impossible d’enregistrer le fichier")
    static let nothing = Phrase("Nothing selected", ru: "Ничего не выделено", uk: "Нічого не виділено", fr: "Rien de sélectionné")
    static let nameNeeded = Phrase("Type a name", ru: "Введите имя", uk: "Введіть імʼя", fr: "Saisissez un nom")
    static let alreadyClean = Phrase("Link is already clean · copied", ru: "Ссылка уже чистая · скопирована", uk: "Посилання вже чисте · скопійовано", fr: "Lien déjà propre · copié")
    static let compressedSuffix = Phrase("compressed", ru: "сжато", uk: "стиснуто", fr: "compressé")

    @MainActor static func cleaned(_ count: Int) -> String {
        Phrase("Removed %d trackers · copied", ru: "Убрано меток: %d · скопировано", uk: "Прибрано міток: %d · скопійовано", fr: "%d traceurs retirés · copié")(count)
    }
    @MainActor static func copiedChars(_ count: String) -> String {
        Phrase("Copied %@ characters", ru: "Скопировано символов: %@", uk: "Скопійовано символів: %@", fr: "%@ caractères copiés")(count)
    }
    @MainActor static func counts(_ words: String, _ characters: String, _ lines: String) -> String {
        Phrase("Words: %@\nCharacters: %@\nLines: %@", ru: "Слов: %@\nСимволов: %@\nСтрок: %@", uk: "Слів: %@\nСимволів: %@\nРядків: %@",
               fr: "Mots : %@\nCaractères : %@\nLignes : %@")(words, characters, lines)
    }
    @MainActor static func of(_ index: Int, _ total: Int) -> String {
        Phrase("%d of %d", ru: "%d из %d", uk: "%d з %d", fr: "%d sur %d")(index, total)
    }
    @MainActor static func items(_ count: Int) -> String {
        Phrase("%d items", ru: "Объектов: %d", uk: "Обʼєктів: %d", fr: "%d éléments")(count)
    }
}

extension Phrases {
    static let toShelf = Phrase("Add to Shelf", ru: "Положить на полку", uk: "Покласти на полицю", fr: "Mettre sur l’étagère")
}

extension Phrase {
    /// The phrase with its %@ filled in, for every language.
    func formatted(_ value: String) -> Phrase {
        Phrase(en.replacingOccurrences(of: "%@", with: value), ru: ru.replacingOccurrences(of: "%@", with: value),
               uk: uk.replacingOccurrences(of: "%@", with: value), fr: fr.replacingOccurrences(of: "%@", with: value))
    }
}
