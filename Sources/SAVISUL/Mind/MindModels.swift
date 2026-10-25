#if MOULD_ENGINE
import Foundation
import MouldEngine

/// The cloud model the person already set up in Settings → AI, as an engine backend: the same provider, address,
/// model and Keychain key Context Actions use.
enum CloudModels {
    @MainActor static func backend() -> (any ModelBackend)? {
        let ai = AIService.shared
        guard ai.ready, let base = URL(string: ai.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: " /"))) else { return nil }
        let provider = ai.provider
        let profile = Self.profile(provider: provider, model: ai.model)
        let key: @Sendable () -> String? = { AIService.storedKey(for: provider) }
        switch provider {
        case .anthropic:
            return AnthropicBackend(id: provider.rawValue, base: base, key: key, profiles: [profile])
        default:
            let features: OpenAICompatibleBackend.Features = switch provider {
            case .openai, .openrouter, .groq: .standard
            case .gemini: [.jsonSchema]
            default: []
            }
            return OpenAICompatibleBackend(id: provider.rawValue, base: base, key: key, profiles: [profile], features: features)
        }
    }

    /// What the router should assume about a provider's model: rough ability, price per million tokens, context size.
    /// Ollama runs on this Mac, so it counts as local.
    static func profile(provider: AIService.Provider, model: String) -> ModelProfile {
        let name = model.lowercased()
        var quality = 0.7, input = 1.0, output = 4.0, context = 128_000, vision = false
        switch provider {
        case .anthropic:
            context = 200_000
            vision = true
            if name.contains("opus") { (quality, input, output) = (0.95, 15, 75) }
            else if name.contains("haiku") { (quality, input, output) = (0.75, 0.8, 4) }
            else { (quality, input, output) = (0.9, 3, 15) }
        case .openai:
            vision = true
            if name.contains("mini") || name.contains("nano") { (quality, input, output) = (0.7, 0.15, 0.6) }
            else { (quality, input, output) = (0.88, 2.5, 10) }
        case .gemini:
            context = 1_000_000
            vision = true
            if name.contains("pro") { (quality, input, output) = (0.9, 1.25, 5) } else { (quality, input, output) = (0.78, 0.1, 0.4) }
        case .deepseek: (quality, input, output) = (0.82, 0.27, 1.1)
        case .groq: (quality, input, output) = (0.72, 0.59, 0.79)
        case .mistral: (quality, input, output) = (0.68, 0.2, 0.6)
        case .openrouter: (quality, input, output) = (0.8, 1, 4)
        case .ollama, .custom: (quality, input, output) = (0.55, 0, 0)
        }
        let local = provider == .ollama
        return ModelProfile(id: "\(provider.rawValue):\(model)", backend: provider.rawValue, model: model, title: model,
                            locality: local ? .local : .cloud, contextTokens: context, maxOutputTokens: 4096, tools: true, vision: vision,
                            json: true, quality: quality, inputCost: input, outputCost: output, firstToken: local ? 0.5 : 1.0,
                            tokensPerSecond: local ? 40 : 70)
    }
}

/// Open-weight models on this Mac: any GGUF file in SAVISUL's Models folder, and the recommended one when it's there.
enum LocalModels {
    /// Good with tools and with Russian and Ukrainian, light enough for Apple Silicon Macs; Apache 2.0. The checksum is
    /// the published file's. Measured on an M-series Mac: right tools and paths, a Ukrainian translation the smaller model
    /// couldn't write, 1 to 4 seconds an answer.
    static let recommended = (file: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf", title: "Qwen3 4B",
                              url: URL(string: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf")!,
                              bytes: Int64(2_497_281_120), sha256: "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597")
    /// The model recommended before 2.9, kept as the one that answers when memory is too short for the new one.
    static let earlier = (file: "qwen2.5-1.5b-instruct-q4_k_m.gguf", title: "Qwen 2.5 1.5B")
    /// Models better than their size says.
    private static let qualities: [String: Double] = ["qwen3-4b-instruct-2507-q4_k_m": 0.72]

    static var recommendedID: String { recommended.file.replacingOccurrences(of: ".gguf", with: "").lowercased() }

    static var folders: [URL] {
        [MindHost.modelsFolder,
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/Mould/Models")]
    }

    static func installed(in folders: [URL] = folders) -> [LocalModel] {
        var seen = Set<String>()
        var result: [LocalModel] = []
        for folder in folders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            for file in files where file.pathExtension.lowercased() == "gguf" {
                // A model split into parts is loaded from its first part.
                let name = file.lastPathComponent.lowercased()
                if name.range(of: #"-\d{5}-of-\d{5}\.gguf$"#, options: .regularExpression) != nil && !name.contains("-00001-of-") { continue }
                let id = file.deletingPathExtension().lastPathComponent.lowercased()
                guard seen.insert(id).inserted else { continue }
                result.append(describe(file))
            }
        }
        return result
    }

    /// Ability and memory from the file: the parameter count in its name and its size. The context is 16k tokens: SAVISUL's
    /// 34 tools alone take about 4,600 of them (134 each, measured), so 8k left too little room for what the person brings.
    static func describe(_ file: URL) -> LocalModel {
        let name = file.deletingPathExtension().lastPathComponent
        let lower = name.lowercased()
        let size = Double((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) / 1_073_741_824
        let billions = lower.range(of: #"(\d+(\.\d+)?)b"#, options: .regularExpression).flatMap { Double(lower[$0].dropLast()) } ?? 3
        let quality = qualities[lower] ?? min(0.8, 0.2 + log2(max(billions, 0.5) + 1) * 0.12)
        let speed = max(8, 220 / max(billions, 0.5))
        let title = lower == recommendedID ? recommended.title : name.lowercased() == earlier.file.replacingOccurrences(of: ".gguf", with: "") ? earlier.title : name
        return LocalModel(id: lower, title: title, file: file, contextTokens: 16_384, memoryGB: max(1, size * 1.2 + 0.6), quality: quality,
                          tokensPerSecond: speed)
    }

    static var serverInstalled: Bool { LocalModelRuntime.findServer() != nil }
}
#endif
