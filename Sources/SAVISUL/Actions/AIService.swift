import Foundation
import Observation
import Security

/// AI for Context Actions, on the person's own API key. SAVISUL ships no key and no account: nothing is sent
/// anywhere until someone adds a key in Settings, and the key lives in the macOS Keychain.
@MainActor
@Observable
final class AIService {
    enum Provider: String, CaseIterable, Identifiable {
        /// Claude, through Anthropic's Messages API. The address can still be a proxy.
        case anthropic
        case openai, openrouter, groq, deepseek, gemini, mistral, ollama
        /// Any other server that speaks the OpenAI chat API.
        case custom

        var id: String { rawValue }

        /// Anthropic's own message format. Everything else uses chat completions.
        var anthropicWire: Bool { self == .anthropic }

        @MainActor var title: String {
            switch self {
            case .anthropic: "Anthropic"
            case .openai: "OpenAI"
            case .openrouter: "OpenRouter"
            case .groq: "Groq"
            case .deepseek: "DeepSeek"
            case .gemini: "Gemini"
            case .mistral: "Mistral"
            case .ollama: "Ollama"
            case .custom: AIPhrases.custom.text
            }
        }

        var defaultModel: String {
            switch self {
            case .anthropic: "claude-opus-5-5"
            case .openai: "gpt-4o-mini"
            case .openrouter: "openai/gpt-4o-mini"
            case .groq: "llama-3.3-70b-versatile"
            case .deepseek: "deepseek-chat"
            case .gemini: "gemini-2.0-flash"
            case .mistral: "mistral-small-latest"
            case .ollama: "llama3.1"
            case .custom: ""
            }
        }

        var defaultBase: String {
            switch self {
            case .anthropic: "https://api.anthropic.com"
            case .openai: "https://api.openai.com/v1"
            case .openrouter: "https://openrouter.ai/api/v1"
            case .groq: "https://api.groq.com/openai/v1"
            case .deepseek: "https://api.deepseek.com"
            case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
            case .mistral: "https://api.mistral.ai/v1"
            case .ollama: "http://127.0.0.1:11434/v1"
            case .custom: ""
            }
        }
    }

    static let shared = AIService()

    var provider: Provider { didSet { defaults.set(provider.rawValue, forKey: "ai.provider"); refreshKey() } }
    var model: String { didSet { defaults.set(model, forKey: "ai.model.\(provider.rawValue)") } }
    var baseURL: String { didSet { defaults.set(baseURL, forKey: "ai.base.\(provider.rawValue)") } }
    private(set) var hasKey = false

    /// Ready when there's a key and a model to ask.
    var ready: Bool { hasKey && !model.trimmingCharacters(in: .whitespaces).isEmpty }

    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let service = "com.savisul.ai"
    static let openAIBase = "https://api.openai.com/v1"

    private init() {
        let saved = Provider(rawValue: UserDefaults.standard.string(forKey: "ai.provider") ?? "") ?? .anthropic
        provider = saved
        model = UserDefaults.standard.string(forKey: "ai.model.\(saved.rawValue)") ?? saved.defaultModel
        let legacy = saved == .openai ? UserDefaults.standard.string(forKey: "ai.baseURL") : nil
        baseURL = UserDefaults.standard.string(forKey: "ai.base.\(saved.rawValue)") ?? legacy ?? saved.defaultBase
        refreshKey()
    }

    /// Switching provider brings back that provider's own model and address.
    func select(_ next: Provider) {
        provider = next
        model = defaults.string(forKey: "ai.model.\(next.rawValue)") ?? next.defaultModel
        baseURL = defaults.string(forKey: "ai.base.\(next.rawValue)") ?? next.defaultBase
    }

    // MARK: Keychain

    func setKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        removeKey()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
            kSecAttrAccount as String: provider.rawValue, kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
        refreshKey()
    }

    func removeKey() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
                                    kSecAttrAccount as String: provider.rawValue]
        SecItemDelete(query as CFDictionary)
        refreshKey()
    }

    private func key() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
                                    kSecAttrAccount as String: provider.rawValue, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func refreshKey() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
                                    kSecAttrAccount as String: provider.rawValue]
        hasKey = SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: Asking

    /// Streams the answer as it's written. `image` is PNG data for questions about a picture.
    func stream(system: String, prompt: String, image: Data? = nil) -> AsyncThrowingStream<String, Error> {
        let request: URLRequest
        do {
            request = try makeRequest(system: system, prompt: prompt, image: image)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let provider = self.provider
        let language = Suite.shared.language
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status != 200 {
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 4000 { break } }
                        throw ActionError.message(Self.failure(status: status, body: body, language: language))
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let piece = Self.piece(object, provider: provider) { continuation.yield(piece) }
                        if let error = object["error"] as? [String: Any] {
                            throw ActionError.message(error["message"] as? String ?? AIPhrases.failed.text(language))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole answer at once, for "Test" in Settings.
    func ask(system: String, prompt: String) async throws -> String {
        var text = ""
        for try await piece in stream(system: system, prompt: prompt) { text += piece }
        return text
    }

    private func makeRequest(system: String, prompt: String, image: Data?) throws -> URLRequest {
        guard let key = key() else { throw ActionError.message(AIPhrases.needsKey.text) }
        let model = self.model.trimmingCharacters(in: .whitespaces)
        guard !model.isEmpty else { throw ActionError.message(AIPhrases.needsModel.text) }
        var request: URLRequest
        var body: [String: Any]
        if provider.anthropicWire {
            guard let url = Self.endpoint(baseURL, fallback: Provider.anthropic.defaultBase, suffix: "/v1/messages", already: "/messages") else {
                throw ActionError.message(AIPhrases.badAddress.text)
            }
            request = URLRequest(url: url)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var content: [[String: Any]] = []
            if let image {
                content.append(["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": image.base64EncodedString()]])
            }
            content.append(["type": "text", "text": prompt])
            // Current Claude models always think, and thinking shares this budget with the answer.
            body = ["model": model, "max_tokens": 16000, "stream": true, "system": system,
                    "messages": [["role": "user", "content": content]]]
        } else {
            guard let url = Self.endpoint(baseURL, fallback: Provider.openai.defaultBase, suffix: "/chat/completions", already: "/chat/completions") else {
                throw ActionError.message(AIPhrases.badAddress.text)
            }
            request = URLRequest(url: url)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let user: Any = image.map { data in
                [["type": "text", "text": prompt],
                 ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(data.base64EncodedString())"]]] as [[String: Any]]
            } ?? prompt
            body = ["model": model, "stream": true,
                    "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
        }
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Joins a server address with the API path. A full path already ending in `already` is used as typed.
    nonisolated static func endpoint(_ raw: String, fallback: String, suffix: String, already: String) -> URL? {
        var base = raw.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        if base.isEmpty { base = fallback }
        if base.lowercased().hasSuffix(already) { return URL(string: base) }
        return URL(string: base + suffix)
    }

    /// The next bit of text in one streamed event.
    nonisolated private static func piece(_ object: [String: Any], provider: Provider) -> String? {
        if provider.anthropicWire {
            guard object["type"] as? String == "content_block_delta", let delta = object["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta" else { return nil }
            return delta["text"] as? String
        }
        guard let choices = object["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any] else { return nil }
        return delta["content"] as? String
    }

    /// A readable reason from an error reply: "Invalid API key", "Model not found".
    nonisolated private static func failure(status: Int, body: String, language: Language) -> String {
        if let data = body.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return "\(status): \(message)"
        }
        switch status {
        case 401, 403: return AIPhrases.badKey.text(language)
        case 404: return AIPhrases.badModel.text(language)
        case 429: return AIPhrases.limited.text(language)
        default: return "\(AIPhrases.failed.text(language)) (\(status))"
        }
    }

    /// The app's language spelled out for a prompt.
    static var languageName: String {
        switch Suite.shared.language {
        case .en: "English"
        case .ru: "Russian"
        case .uk: "Ukrainian"
        case .fr: "French"
        }
    }
}

enum AIPhrases {
    static let title = Phrase("AI for actions", ru: "ИИ для действий", uk: "ШІ для дій", fr: "IA pour les actions")
    static let detail = Phrase("Summarize, translate, rewrite and ask about what you select. Uses your own API key; nothing is sent until you add one.",
                               ru: "Пересказ, перевод, правка и вопросы о выделенном. Работает на вашем API-ключе: без ключа ничего никуда не отправляется.",
                               uk: "Переказ, переклад, правка й питання про виділене. Працює на вашому API-ключі: без ключа нічого нікуди не надсилається.",
                               fr: "Résumer, traduire, réécrire et interroger la sélection. Avec votre propre clé API : rien n’est envoyé sans clé.")
    static let service = Phrase("Service", ru: "Сервис", uk: "Сервіс", fr: "Service")
    static let custom = Phrase("Custom address", ru: "Свой адрес", uk: "Своя адреса", fr: "Adresse perso")
    static let compatible = Phrase("OpenAI-compatible", ru: "OpenAI-совместимый", uk: "OpenAI-сумісний", fr: "Compatible OpenAI")
    static let addressHint = Phrase("Any server: OpenAI, Claude, Gemini, Groq, Ollama…",
                                    ru: "Любой сервер: OpenAI, Claude, Gemini, Groq, Ollama…",
                                    uk: "Будь-який сервер: OpenAI, Claude, Gemini, Groq, Ollama…",
                                    fr: "N’importe quel serveur : OpenAI, Claude, Gemini, Groq, Ollama…")
    static let key = Phrase("API key", ru: "API-ключ", uk: "API-ключ", fr: "Clé API")
    static let keyPlaceholder = Phrase("Paste your key", ru: "Вставьте ключ", uk: "Вставте ключ", fr: "Collez votre clé")
    static let keySaved = Phrase("Key saved in Keychain", ru: "Ключ сохранён в Связке ключей", uk: "Ключ збережено у Звʼязці ключів", fr: "Clé enregistrée dans le trousseau")
    static let save = Phrase("Save", ru: "Сохранить", uk: "Зберегти", fr: "Enregistrer")
    static let remove = Phrase("Remove key", ru: "Удалить ключ", uk: "Видалити ключ", fr: "Supprimer la clé")
    static let model = Phrase("Model", ru: "Модель", uk: "Модель", fr: "Modèle")
    static let modelPlaceholder = Phrase("gpt-…, llama3.1, mistral…", ru: "gpt-…, llama3.1, mistral…", uk: "gpt-…, llama3.1, mistral…", fr: "gpt-…, llama3.1, mistral…")
    static let address = Phrase("Server address", ru: "Адрес сервера", uk: "Адреса сервера", fr: "Adresse du serveur")
    static let test = Phrase("Test", ru: "Проверить", uk: "Перевірити", fr: "Tester")
    static let works = Phrase("Works", ru: "Работает", uk: "Працює", fr: "Ça marche")
    static let needsKey = Phrase("Add your AI key in Settings → AI for actions.", ru: "Добавьте ключ ИИ: Настройки → ИИ для действий.",
                                 uk: "Додайте ключ ШІ: Налаштування → ШІ для дій.", fr: "Ajoutez votre clé IA : Réglages → IA pour les actions.")
    static let needsModel = Phrase("Choose a model in Settings → AI for actions.", ru: "Укажите модель: Настройки → ИИ для действий.",
                                   uk: "Вкажіть модель: Налаштування → ШІ для дій.", fr: "Choisissez un modèle : Réglages → IA pour les actions.")
    static let badKey = Phrase("The API key was refused.", ru: "API-ключ не принят.", uk: "API-ключ не прийнято.", fr: "La clé API a été refusée.")
    static let badModel = Phrase("This model or address wasn’t found.", ru: "Модель или адрес не найдены.", uk: "Модель або адресу не знайдено.", fr: "Modèle ou adresse introuvable.")
    static let badAddress = Phrase("The server address isn’t valid.", ru: "Неверный адрес сервера.", uk: "Неправильна адреса сервера.", fr: "Adresse du serveur invalide.")
    static let limited = Phrase("Rate limit reached. Try again shortly.", ru: "Достигнут лимит запросов. Попробуйте чуть позже.",
                                uk: "Досягнуто ліміту запитів. Спробуйте трохи згодом.", fr: "Limite atteinte. Réessayez bientôt.")
    static let failed = Phrase("The AI request failed", ru: "Запрос к ИИ не удался", uk: "Запит до ШІ не вдався", fr: "La requête IA a échoué")
    static let openSettings = Phrase("Open AI settings", ru: "Открыть настройки ИИ", uk: "Відкрити налаштування ШІ", fr: "Ouvrir les réglages IA")
}
