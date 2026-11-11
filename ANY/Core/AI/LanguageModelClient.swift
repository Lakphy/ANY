import Foundation

/// The wire protocols a model endpoint can speak. Most third-party gateways implement one of them.
nonisolated enum LanguageModelAPI: String, CaseIterable, Identifiable, Codable, Sendable {
    case chatCompletions
    case responses
    case messages

    var id: String { rawValue }

    var name: String {
        switch self {
        case .chatCompletions: "Chat Completions"
        case .responses: "Responses"
        case .messages: "Messages"
        }
    }

    var vendor: String {
        switch self {
        case .chatCompletions, .responses: "OpenAI 兼容"
        case .messages: "Anthropic 兼容"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .chatCompletions, .responses: "https://api.openai.com/v1"
        case .messages: "https://api.anthropic.com/v1"
        }
    }

    var path: String {
        switch self {
        case .chatCompletions: "/chat/completions"
        case .responses: "/responses"
        case .messages: "/messages"
        }
    }
}

nonisolated struct LanguageModelConfiguration: Equatable, Sendable {
    var api: LanguageModelAPI
    var baseURL: String
    var apiKey: String
    var model: String

    var isComplete: Bool { !apiKey.isEmpty && !model.isEmpty }

    /// Accepts a bare host, a versioned base ("…/v1") or the full endpoint.
    var endpoint: URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = api.defaultBaseURL }
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix(api.path) { return URL(string: base) }
        return URL(string: base + api.path)
    }
}

nonisolated struct LanguageModelMessage: Sendable {
    enum Role: String, Sendable { case user, assistant }
    var role: Role
    var content: String
}

nonisolated enum LanguageModelError: LocalizedError {
    case invalidEndpoint
    case rejected(status: Int, message: String?)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Base URL 无效"
        case .rejected(401, _), .rejected(403, _): "API Key 无效或无权访问该模型"
        case .rejected(404, let message): message ?? "接口地址或模型不存在（404）"
        case .rejected(429, let message): message ?? "请求过于频繁或额度不足（429）"
        case .rejected(let status, let message): message ?? "模型服务返回错误（\(status)）"
        case .emptyResponse: "模型没有返回内容"
        }
    }

    var isConfigurationProblem: Bool {
        switch self {
        case .invalidEndpoint: true
        case .rejected(let status, _): [400, 401, 403, 404].contains(status)
        case .emptyResponse: false
        }
    }
}

/// Streams text from a model over server-sent events.
nonisolated enum LanguageModelClient {
    static func stream(
        _ configuration: LanguageModelConfiguration,
        system: String,
        messages: [LanguageModelMessage],
        maxTokens: Int = 4096
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(configuration, system: system, messages: messages, maxTokens: maxTokens)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw LanguageModelError.rejected(status: status, message: errorMessage(in: body))
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        if let message = streamError(in: event) {
                            throw LanguageModelError.rejected(status: status, message: message)
                        }
                        if let delta = textDelta(in: event, api: configuration.api), !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole reply as one string.
    static func complete(
        _ configuration: LanguageModelConfiguration,
        system: String,
        messages: [LanguageModelMessage],
        maxTokens: Int = 4096
    ) async throws -> String {
        var text = ""
        for try await delta in stream(configuration, system: system, messages: messages, maxTokens: maxTokens) {
            text += delta
        }
        guard !text.isEmpty else { throw LanguageModelError.emptyResponse }
        return text
    }

    private static func makeRequest(
        _ configuration: LanguageModelConfiguration,
        system: String,
        messages: [LanguageModelMessage],
        maxTokens: Int
    ) throws -> URLRequest {
        guard let url = configuration.endpoint else { throw LanguageModelError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let turns = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let body: [String: Any]
        switch configuration.api {
        case .chatCompletions:
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": configuration.model,
                "stream": true,
                "messages": [["role": "system", "content": system]] + turns,
            ]
        case .responses:
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": configuration.model,
                "stream": true,
                "instructions": system,
                "input": turns,
                "max_output_tokens": maxTokens,
            ]
        case .messages:
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": configuration.model,
                "stream": true,
                "system": system,
                "messages": turns,
                "max_tokens": maxTokens,
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func textDelta(in event: [String: Any], api: LanguageModelAPI) -> String? {
        switch api {
        case .chatCompletions:
            let choice = (event["choices"] as? [[String: Any]])?.first
            return (choice?["delta"] as? [String: Any])?["content"] as? String
        case .responses:
            guard event["type"] as? String == "response.output_text.delta" else { return nil }
            return event["delta"] as? String
        case .messages:
            guard event["type"] as? String == "content_block_delta" else { return nil }
            return (event["delta"] as? [String: Any])?["text"] as? String
        }
    }

    private static func streamError(in event: [String: Any]) -> String? {
        if let error = event["error"] as? [String: Any] { return error["message"] as? String ?? "模型服务返回错误" }
        if event["type"] as? String == "response.failed" {
            let error = (event["response"] as? [String: Any])?["error"] as? [String: Any]
            return error?["message"] as? String ?? "模型生成失败"
        }
        return nil
    }

    private static func errorMessage(in body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.flatMap { $0.isEmpty ? nil : String($0.prefix(160)) }
        }
        if let error = json["error"] as? [String: Any] { return error["message"] as? String }
        if let error = json["error"] as? String { return error }
        return json["message"] as? String
    }
}
