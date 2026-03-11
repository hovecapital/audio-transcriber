import Foundation

enum OllamaError: LocalizedError {
    case serverUnreachable
    case requestTimeout
    case modelNotFound(String)
    case invalidResponse
    case httpError(Int)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .serverUnreachable:
            return "Server is not reachable. Make sure your LLM server is running."
        case .requestTimeout:
            return "Request timed out. The server may be overloaded or the timeout is too short."
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Check that the model is available on your server."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .httpError(let code):
            return "Server returned HTTP \(code)."
        case .networkError(let message):
            return message
        }
    }
}

final class OllamaClient {
    private let backend: AppConfig.AutocorrectBackend
    private let serverURL: String
    private let model: String
    private let timeout: TimeInterval

    private let systemPrompt = """
        You are a spelling corrector. Fix only typos and spelling errors. \
        Do not change wording, punctuation, capitalisation, or meaning. \
        Return only the corrected text with no explanation.
        """

    init(backend: AppConfig.AutocorrectBackend, serverURL: String, model: String, timeout: TimeInterval) {
        self.backend = backend
        self.serverURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.model = model
        self.timeout = timeout
    }

    func checkHealth() async throws {
        switch backend {
        case .ollama:
            let url = URL(string: "\(serverURL)/api/tags")!
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            let (_, response) = try await performRequest(request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw OllamaError.serverUnreachable
            }

        case .llamaCpp:
            let url = URL(string: "\(serverURL)/health")!
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            let (data, response) = try await performRequest(request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw OllamaError.serverUnreachable
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String,
               status != "ok" {
                throw OllamaError.serverUnreachable
            }
        }
    }

    func listModels() async throws -> [String] {
        switch backend {
        case .ollama:
            let url = URL(string: "\(serverURL)/api/tags")!
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            let (data, response) = try await performRequest(request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw OllamaError.serverUnreachable
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                return []
            }
            return models.compactMap { $0["name"] as? String }

        case .llamaCpp:
            let url = URL(string: "\(serverURL)/v1/models")!
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            let (data, response) = try await performRequest(request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["data"] as? [[String: Any]] else {
                return []
            }
            return models.compactMap { $0["id"] as? String }
        }
    }

    func correct(_ text: String) async throws -> String {
        switch backend {
        case .ollama:
            return try await correctViaOllama(text)
        case .llamaCpp:
            return try await correctViaLlamaCpp(text)
        }
    }

    private func correctViaOllama(_ text: String) async throws -> String {
        let url = URL(string: "\(serverURL)/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let body: [String: Any] = [
            "model": model,
            "system": systemPrompt,
            "prompt": text,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw OllamaError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw OllamaError.invalidResponse
        }

        guard let validated = validate(responseText, original: text) else {
            throw OllamaError.invalidResponse
        }
        return validated
    }

    private func correctViaLlamaCpp(_ text: String) async throws -> String {
        let url = URL(string: "\(serverURL)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw OllamaError.httpError(http.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OllamaError.invalidResponse
        }

        guard let validated = validate(content, original: text) else {
            throw OllamaError.invalidResponse
        }
        return validated
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw OllamaError.requestTimeout
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                throw OllamaError.serverUnreachable
            default:
                throw OllamaError.networkError(error.localizedDescription)
            }
        }
    }

    private func validate(_ response: String, original: String) -> String? {
        let corrected = response.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if corrected.isEmpty { return nil }
        if corrected.count > original.count * 3 { return nil }
        if corrected.contains("\n") { return nil }
        if corrected == original { return nil }

        return corrected
    }
}
