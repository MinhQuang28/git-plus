import Foundation

enum AIError: LocalizedError, Equatable {
    case notConfigured(String)
    case invalidBaseURL
    case keychain(String)
    case unauthorized(String)
    case paymentRequired(String)
    case modelNotFound(String)
    case responsesAPIOnly
    case rateLimited(retryAfter: Int?)
    case server(status: Int, message: String)
    case badResponse(String)
    case diffTooLarge(bytes: Int)
    case nothingToDescribe

    var errorDescription: String? {
        switch self {
        case .notConfigured(let why): why
        case .invalidBaseURL: "The base URL must start with https:// (http:// only for localhost). Check Settings → AI."
        case .keychain(let message): "Keychain: \(message)"
        case .unauthorized(let message): "API key rejected — check Settings → AI. \(message)"
        case .paymentRequired(let message): "The AI account is out of credit. \(message)"
        case .modelNotFound(let message): "Model not found — choose another one in Settings → AI. \(message)"
        case .responsesAPIOnly: "This model only works with OpenAI's Responses API — choose a chat model in Settings → AI."
        case .rateLimited(let seconds): "Rate limited by the provider — try again\(seconds.map { " in \($0)s" } ?? " shortly")."
        case .server(let status, let message): "The AI service failed (HTTP \(status)). \(message)"
        case .badResponse(let why): "Unexpected answer from the AI service: \(why)"
        case .diffTooLarge(let bytes): "The changes are too large to send (\(bytes / 1024) KB)."
        case .nothingToDescribe: "There are no changes to describe."
        }
    }
}

/// Minimal client for the OpenAI-compatible API (DeepSeek, OpenAI, OpenRouter, Ollama, …).
/// Sends only `model` + `messages`: optional knobs (temperature, max tokens) differ between providers.
struct ChatCompletionClient: Sendable {
    let config: AIConfig
    var session: URLSession = .shared

    /// Returns the assistant's text.
    func complete(system: String, user: String) async throws -> String {
        let body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        var request = request("chat/completions", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(request)
        return try Self.messageText(from: data)
    }

    /// Model ids the key can use (`GET /models`), sorted.
    func models() async throws -> [String] {
        let data = try await send(request("models", method: "GET"))
        struct List: Decodable { struct Model: Decodable { let id: String }; let data: [Model] }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else { throw AIError.badResponse("model list is not readable") }
        return list.data.map(\.id).sorted()
    }

    private func request(_ path: String, method: String) -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingPathComponent(path), timeoutInterval: 60)
        request.httpMethod = method
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)   // throws URLError (offline, timeout, cancelled)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(status: http.statusCode, body: data, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        }
        return data
    }

    // MARK: Pure parsing (unit-tested)

    /// `choices[0].message.content`; reasoning models' `reasoning_content` is ignored.
    static func messageText(from data: Data) throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
                let finish_reason: String?
            }
            let choices: [Choice]
        }
        guard let choice = (try? JSONDecoder().decode(Response.self, from: data))?.choices.first else {
            throw AIError.badResponse("no choices in the reply")
        }
        if choice.finish_reason == "content_filter" { throw AIError.badResponse("the provider's content filter blocked the reply") }
        let text = (choice.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AIError.badResponse(choice.finish_reason == "length" ? "the reply was cut off" : "the reply was empty")
        }
        return text
    }

    /// Maps an error status + body (`{"error": {"message": …}}` or `{"message": …}`) to `AIError`.
    static func error(status: Int, body: Data, retryAfter: String?) -> AIError {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let nested = json?["error"] as? [String: Any]
        let raw = (nested?["message"] as? String) ?? (json?["error"] as? String) ?? (json?["message"] as? String)
            ?? String(decoding: body.prefix(300), as: UTF8.self)
        let message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.contains("v1/responses") { return .responsesAPIOnly }
        // DeepSeek answers an unknown model with 400 "Model Not Exist".
        let lower = message.lowercased()
        if lower.contains("model"), ["not exist", "does not exist", "not found"].contains(where: lower.contains) {
            return .modelNotFound(message)
        }
        switch status {
        case 401, 403: return .unauthorized(message)
        case 402: return .paymentRequired(message)
        case 404: return .modelNotFound(message)
        case 429:
            // Some providers report an empty balance as 429 "insufficient_quota".
            if (nested?["code"] as? String) == "insufficient_quota" { return .paymentRequired(message) }
            return .rateLimited(retryAfter: retryAfter.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) })
        default: return .server(status: status, message: message)
        }
    }
}
