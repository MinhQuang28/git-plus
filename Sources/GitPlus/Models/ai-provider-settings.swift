import Foundation

/// AI service for commit messages. All presets speak the OpenAI-compatible Chat Completions API.
enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case deepseek, openai, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepseek: "DeepSeek"
        case .openai: "OpenAI"
        case .custom: "Custom (OpenAI-compatible)"
        }
    }

    /// Empty for `.custom`: the user enters it.
    var defaultBaseURL: String {
        switch self {
        case .deepseek: "https://api.deepseek.com"
        case .openai: "https://api.openai.com/v1"
        case .custom: ""
        }
    }

    var defaultModel: String { self == .deepseek ? "deepseek-chat" : "" }

    /// Where to create an API key.
    var keysPage: URL? {
        switch self {
        case .deepseek: URL(string: "https://platform.deepseek.com/api_keys")
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .custom: nil
        }
    }
}

enum AIMessageLanguage: String, CaseIterable, Identifiable, Sendable {
    case english, vietnamese, matchHistory

    var id: String { rawValue }
    var title: String {
        switch self {
        case .english: "English"
        case .vietnamese: "Vietnamese"
        case .matchHistory: "Match repository history"
        }
    }
}

/// Everything needed for one request; the key comes from the Keychain, never from UserDefaults.
struct AIConfig: Sendable {
    let baseURL: URL
    let model: String
    let apiKey: String
}

/// UserDefaults keys and helpers for Settings → AI.
enum AISettings {
    static let enabledKey = "aiEnabled"
    static let providerKey = "aiProvider"
    static let baseURLKey = "aiBaseURL"
    static let modelKey = "aiModel"
    static let languageKey = "aiMessageLanguage"
    static let includeBodyKey = "aiIncludeBody"
    private static let disabledReposKey = "aiDisabledRepos"

    private static var defaults: UserDefaults { .standard }

    static var isEnabled: Bool { defaults.bool(forKey: enabledKey) }
    static var provider: AIProvider { AIProvider(rawValue: defaults.string(forKey: providerKey) ?? "") ?? .deepseek }
    static var language: AIMessageLanguage { AIMessageLanguage(rawValue: defaults.string(forKey: languageKey) ?? "") ?? .english }
    static var includeBody: Bool { defaults.object(forKey: includeBodyKey) as? Bool ?? true }

    /// Presets use their fixed URL; Custom uses the stored one.
    static func baseURLString(for provider: AIProvider) -> String {
        provider == .custom ? (defaults.string(forKey: baseURLKey) ?? "") : provider.defaultBaseURL
    }

    static var model: String {
        let stored = (defaults.string(forKey: modelKey) ?? "").trimmingCharacters(in: .whitespaces)
        return stored.isEmpty ? provider.defaultModel : stored
    }

    /// `https://` only, except plain `http://` to this machine (Ollama, LM Studio). No credentials in the URL.
    static func validatedBaseURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed),
              let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased(), !host.isEmpty,
              url.user() == nil, url.password() == nil, url.query() == nil else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host) { return url }
        return nil
    }

    /// The configuration to use now, or a reason why AI can't run.
    static func current() throws -> AIConfig {
        guard isEnabled else { throw AIError.notConfigured("Turn on AI commit messages in Settings → AI.") }
        let provider = provider
        guard let url = validatedBaseURL(baseURLString(for: provider)) else { throw AIError.invalidBaseURL }
        let model = model
        guard !model.isEmpty else { throw AIError.notConfigured("Choose a model in Settings → AI.") }
        guard let key = KeychainStore.apiKey(for: provider), !key.isEmpty else {
            throw AIError.notConfigured("Add your \(provider.title) API key in Settings → AI.")
        }
        return AIConfig(baseURL: url, model: model, apiKey: key)
    }

    // MARK: Per-repository opt-out (code that must not leave the machine)

    static func isDisabled(repoPath: String) -> Bool {
        (defaults.stringArray(forKey: disabledReposKey) ?? []).contains(repoPath)
    }

    static func setDisabled(_ disabled: Bool, repoPath: String) {
        var paths = Set(defaults.stringArray(forKey: disabledReposKey) ?? [])
        if disabled { paths.insert(repoPath) } else { paths.remove(repoPath) }
        defaults.set(paths.sorted(), forKey: disabledReposKey)
    }
}
