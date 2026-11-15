import Foundation

/// Ücretsiz yapay zekâ desteği: serbest (çoğunlukla Türkçe) bir tarifi sitelerin anladığı
/// kısa arama etiketlerine çevirir — yabancı siteler için İngilizce, Türk siteleri için Türkçe.
///
/// İki motor desteklenir, ikisinin de ücretsiz katmanı var:
/// - **Gemini** (Google AI Studio anahtarı; kart gerekmez)
/// - **GPT** (OpenAI uyumlu herhangi bir uç nokta: GitHub Models ile ücretsiz GPT,
///   OpenRouter ":free" modelleri, Pollinations, kendi OpenAI anahtarın, yerel Ollama…)
/// Hiçbiri ayarlı değilse ya da yanıt vermezse yerleşik çevrimdışı sözlük kullanılır.
enum AIEngine: String, CaseIterable, Identifiable, Sendable {
    case auto, gemini, gpt, dictionary
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Otomatik (Gemini → GPT → sözlük)"
        case .gemini: return "Sadece Gemini"
        case .gpt: return "Sadece GPT"
        case .dictionary: return "Sadece sözlük (yapay zekâ yok)"
        }
    }
}

enum AIConfig {
    // UserDefaults / Keychain anahtarları
    static let engineKey = "aiEngine"
    static let geminiModelKey = "aiGeminiModel"
    static let gptBaseKey = "aiBaseURL"
    static let gptModelKey = "aiModel"
    static let geminiSecret = "geminiAPIKey"
    static let gptSecret = "aiAPIKey"

    /// Ücretsiz katmandaki Gemini modelleri (Kasım 2026). Liste değişirse Ayarlar'dan elle yazılabilir.
    static let geminiModels = ["gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-3.6-flash", "gemini-3.1-flash-lite"]
    static let defaultGeminiModel = geminiModels[0]

    struct Preset: Identifiable, Sendable {
        let name: String, baseURL: String, model: String, note: String
        var id: String { name }
    }
    /// OpenAI uyumlu ücretsiz seçenekler.
    static let gptPresets: [Preset] = [
        .init(name: "GitHub Models — GPT (ücretsiz)", baseURL: "https://models.github.ai/inference",
              model: "openai/gpt-4o", note: "Anahtar: GitHub → Settings → Developer settings → Personal access token (models:read izni)."),
        .init(name: "OpenRouter — ücretsiz model", baseURL: "https://openrouter.ai/api/v1",
              model: "openai/gpt-oss-20b:free", note: "Anahtar: openrouter.ai → Keys. Sonu :free ile biten modeller ücretsizdir."),
        .init(name: "Pollinations — GPT", baseURL: "https://gen.pollinations.ai/v1",
              model: "openai/gpt-5.4-nano", note: "Anahtar: pollinations.ai üzerinden ücretsiz alınır."),
        .init(name: "OpenAI (kendi anahtarın)", baseURL: "https://api.openai.com/v1",
              model: "gpt-4o-mini", note: "OpenAI API ücretlidir; ücretsiz kullanım için üstteki seçenekleri dene."),
        .init(name: "Ollama (evdeki bilgisayar)", baseURL: "http://192.168.1.10:11434/v1",
              model: "llama3.2", note: "Tamamen ücretsiz ve yerel; anahtar gerekmez. Adresi kendi bilgisayarının IP'siyle değiştir."),
    ]
    static let defaultGPTBase = gptPresets[0].baseURL
    static let defaultGPTModel = gptPresets[0].model

    static let systemPrompt = """
        You turn a user's description (often in Turkish) of the legal adult videos they want to find \
        into short search tags. All performers and characters must be adults; never output anything \
        involving minors. Reply ONLY with a JSON object: \
        {"en": ["tag", ...], "tr": ["etiket", ...]} — "en" holds 1-5 lowercase English tags as used on \
        international video sites, "tr" holds the Turkish equivalents as used on Turkish sites, \
        in the same order. No explanations.
        """
}

struct AITagResult: Equatable, Sendable {
    var terms: BilingualTerms
    /// "Gemini", "GPT" ya da "Sözlük"
    var source: String
}

struct AITagAssistant: Sendable {
    struct Settings: Sendable {
        var engine: AIEngine
        var geminiKey: String
        var geminiModel: String
        var gptBaseURL: String
        var gptModel: String
        var gptKey: String

        static func load() -> Settings {
            let d = UserDefaults.standard
            return Settings(
                engine: AIEngine(rawValue: d.string(forKey: AIConfig.engineKey) ?? "") ?? .auto,
                geminiKey: Keychain.get(AIConfig.geminiSecret) ?? "",
                geminiModel: d.string(forKey: AIConfig.geminiModelKey) ?? AIConfig.defaultGeminiModel,
                gptBaseURL: d.string(forKey: AIConfig.gptBaseKey) ?? AIConfig.defaultGPTBase,
                gptModel: d.string(forKey: AIConfig.gptModelKey) ?? AIConfig.defaultGPTModel,
                gptKey: Keychain.get(AIConfig.gptSecret) ?? ""
            )
        }

        var geminiReady: Bool { !geminiKey.isEmpty }
        /// Yerel sunucular (Ollama) anahtarsız çalışır.
        var gptReady: Bool { !gptKey.isEmpty || gptBaseURL.hasPrefix("http://") }
    }

    var settings: Settings = .load()

    func tags(for text: String) async -> AITagResult {
        let s = settings
        if (s.engine == .auto || s.engine == .gemini), s.geminiReady,
           let reply = try? await Self.askGemini(text, key: s.geminiKey, model: s.geminiModel),
           let terms = Self.parse(reply) {
            return AITagResult(terms: terms, source: "Gemini")
        }
        if (s.engine == .auto || s.engine == .gpt), s.gptReady,
           let reply = try? await Self.askOpenAICompatible(text, baseURL: s.gptBaseURL, model: s.gptModel, key: s.gptKey),
           let terms = Self.parse(reply) {
            return AITagResult(terms: terms, source: "GPT")
        }
        let t = TagTranslator.bilingual(text)
        return AITagResult(terms: BilingualTerms(en: SafetyFilter.sanitize(t.en), tr: SafetyFilter.sanitize(t.tr)),
                           source: "Sözlük")
    }

    // MARK: Gemini (yerel API)

    private struct GeminiRequest: Encodable {
        struct Part: Encodable { let text: String }
        struct Content: Encodable { var role: String? = nil; let parts: [Part] }
        struct Config: Encodable { let temperature: Double; let responseMimeType: String }
        struct Safety: Encodable { let category: String; let threshold: String }
        let systemInstruction: Content
        let contents: [Content]
        let generationConfig: Config
        let safetySettings: [Safety]
    }
    private struct GeminiResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable { struct Part: Decodable { let text: String? }; let parts: [Part]? }
            let content: Content?
        }
        let candidates: [Candidate]?
    }

    static func askGemini(_ text: String, key: String, model: String) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw HTTPError.empty
        }
        let body = GeminiRequest(
            systemInstruction: .init(parts: [.init(text: AIConfig.systemPrompt)]),
            contents: [.init(role: "user", parts: [.init(text: text)])],
            generationConfig: .init(temperature: 0, responseMimeType: "application/json"),
            // Yetişkin arama terimleri varsayılan filtreye takılmasın. Çocuk güvenliği filtreleri
            // Google tarafında her zaman açıktır ve kapatılamaz.
            safetySettings: [.init(category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE")]
        )
        let r = try await HTTP.postJSON(url, body: body, headers: ["x-goog-api-key": key], as: GeminiResponse.self)
        let reply = r.candidates?.first?.content?.parts?.compactMap(\.text).joined() ?? ""
        guard !reply.isEmpty else { throw HTTPError.empty }
        return reply
    }

    // MARK: GPT / OpenAI uyumlu

    private struct ChatRequest: Encodable {
        struct Msg: Encodable { let role: String; let content: String }
        let model: String
        let messages: [Msg]
    }
    private struct ChatResponse: Decodable {
        struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
        let choices: [Choice]
    }

    static func askOpenAICompatible(_ text: String, baseURL: String, model: String, key: String) async throws -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") { base.removeLast("/chat/completions".count) }
        guard let url = URL(string: base + "/chat/completions") else { throw HTTPError.empty }
        let body = ChatRequest(model: model, messages: [
            .init(role: "system", content: AIConfig.systemPrompt),
            .init(role: "user", content: text),
        ])
        var headers: [String: String] = [:]
        if !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }
        let r = try await HTTP.postJSON(url, body: body, headers: headers, as: ChatResponse.self)
        guard let reply = r.choices.first?.message.content, !reply.isEmpty else { throw HTTPError.empty }
        return reply
    }

    // MARK: Yanıt ayrıştırma

    /// Modelin yanıtından {"en":[…],"tr":[…]} nesnesini (ya da düz bir diziyi) çıkarır; güvenlik filtresinden geçirir.
    static func parse(_ reply: String) -> BilingualTerms? {
        func clean(_ list: [String]) -> [String] {
            SafetyFilter.sanitize(list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty && $0.count <= 40 }).prefix(6).map { $0 }
        }
        struct Both: Decodable { let en: [String]?; let tr: [String]? }
        if let a = reply.firstIndex(of: "{"), let b = reply.lastIndex(of: "}"), a < b,
           let both = try? JSONDecoder().decode(Both.self, from: Data(reply[a...b].utf8)) {
            let en = clean(both.en ?? []), tr = clean(both.tr ?? [])
            if !en.isEmpty || !tr.isEmpty {
                return BilingualTerms(en: en.isEmpty ? tr : en, tr: tr.isEmpty ? en : tr)
            }
        }
        if let a = reply.firstIndex(of: "["), let b = reply.lastIndex(of: "]"), a < b,
           let list = try? JSONDecoder().decode([String].self, from: Data(reply[a...b].utf8)) {
            let en = clean(list)
            if !en.isEmpty {
                // Sadece İngilizce geldiyse Türkçesini sözlükten türet.
                return BilingualTerms(en: en, tr: en.map { TagTranslator.bilingual($0).tr.joined(separator: " ") })
            }
        }
        return nil
    }
}
