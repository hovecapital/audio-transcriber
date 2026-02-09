import Foundation

final class LLMAnalysisService {
    private let provider: AppConfig.LLMProvider
    private let model: String

    init(provider: AppConfig.LLMProvider, model: String) {
        self.provider = provider
        self.model = model
        Log.transcription.info("LLMAnalysisService initialized: provider=\(provider.rawValue), model=\(model)")
    }

    func analyze(segments: [TranscriptSegment], config: AppConfig) async throws -> MeetingAnalysis {
        guard let apiKey = KeychainHelper.getLLMAPIKey() else {
            throw LLMError.noAPIKey
        }

        let transcript = formatTranscriptForAnalysis(segments: segments, config: config)
        let prompt = buildAnalysisPrompt(transcript: transcript)

        let response: String
        switch provider {
        case .anthropic:
            response = try await callAnthropicAPI(prompt: prompt, apiKey: apiKey)
        case .openai:
            response = try await callOpenAIAPI(prompt: prompt, apiKey: apiKey)
        }

        return try parseAnalysisResponse(response)
    }

    private func formatTranscriptForAnalysis(segments: [TranscriptSegment], config: AppConfig) -> String {
        var transcript = ""
        for segment in segments {
            let speaker = segment.speaker == .person1 ? config.person1Label : config.person2Label
            transcript += "[\(segment.formattedTimestamp)] \(speaker): \(segment.text)\n"
        }
        return transcript
    }

    private func buildAnalysisPrompt(transcript: String) -> String {
        return """
        Analyze this meeting transcript and extract structured information. Return a JSON object with the following structure:

        {
          "summary": "A concise 2-3 sentence summary of the meeting",
          "clarificationQuestions": [
            {
              "question": "What needs clarification",
              "context": "Why this is unclear from the transcript",
              "priority": "high|medium|low"
            }
          ],
          "goalsAndTasks": [
            {
              "title": "Task title",
              "description": "Task description",
              "assignee": "Person name or null"
            }
          ],
          "softwareEngineeringSpecs": {
            "featureRequirements": [
              {
                "name": "Feature name",
                "description": "Feature description",
                "acceptanceCriteria": ["Criterion 1", "Criterion 2"],
                "priority": "high|medium|low or null"
              }
            ],
            "technicalDecisions": [
              {
                "decision": "What was decided",
                "rationale": "Why it was decided",
                "alternatives": ["Alternative 1", "Alternative 2"]
              }
            ],
            "apiContracts": [
              {
                "endpoint": "/api/example",
                "method": "POST",
                "description": "What this endpoint does",
                "requestSchema": "JSON schema or null",
                "responseSchema": "JSON schema or null"
              }
            ],
            "dataModels": [
              {
                "name": "ModelName",
                "description": "Model description",
                "fields": [
                  {
                    "name": "fieldName",
                    "type": "string|number|boolean|etc",
                    "isRequired": true,
                    "description": "Field description or null"
                  }
                ]
              }
            ],
            "openQuestions": ["Question 1", "Question 2"]
          }
        }

        Focus on extracting:
        1. Unclear items that need follow-up questions
        2. Action items and goals with assignees when mentioned
        3. Software engineering specifications: feature requirements with acceptance criteria, technical decisions with rationale, API contracts if discussed, data models if mentioned

        Return ONLY the JSON object, no additional text.

        Transcript:
        \(transcript)
        """
    }

    private func callAnthropicAPI(prompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Log.transcription.error("Anthropic API error (\(httpResponse.statusCode)): \(errorBody)")
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw LLMError.parseError
        }

        return text
    }

    private func callOpenAIAPI(prompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 4096
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            Log.transcription.error("OpenAI API error (\(httpResponse.statusCode)): \(errorBody)")
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parseError
        }

        return content
    }

    private func parseAnalysisResponse(_ response: String) throws -> MeetingAnalysis {
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        }
        if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8) else {
            throw LLMError.parseError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let json = json else {
            throw LLMError.parseError
        }

        let summary = json["summary"] as? String ?? ""

        var clarificationQuestions: [ClarificationQuestion] = []
        if let questionsArray = json["clarificationQuestions"] as? [[String: Any]] {
            for q in questionsArray {
                let question = q["question"] as? String ?? ""
                let context = q["context"] as? String ?? ""
                let priorityString = q["priority"] as? String ?? "medium"
                let priority = ClarificationQuestion.Priority(rawValue: priorityString) ?? .medium
                clarificationQuestions.append(ClarificationQuestion(
                    question: question,
                    context: context,
                    priority: priority
                ))
            }
        }

        var goalsAndTasks: [GoalOrTask] = []
        if let tasksArray = json["goalsAndTasks"] as? [[String: Any]] {
            for t in tasksArray {
                let title = t["title"] as? String ?? ""
                let description = t["description"] as? String ?? ""
                let assignee = t["assignee"] as? String
                goalsAndTasks.append(GoalOrTask(
                    title: title,
                    description: description,
                    assignee: assignee
                ))
            }
        }

        var specs = SoftwareEngineeringSpecs()
        if let specsDict = json["softwareEngineeringSpecs"] as? [String: Any] {
            if let features = specsDict["featureRequirements"] as? [[String: Any]] {
                specs.featureRequirements = features.map { f in
                    FeatureRequirement(
                        name: f["name"] as? String ?? "",
                        description: f["description"] as? String ?? "",
                        acceptanceCriteria: f["acceptanceCriteria"] as? [String] ?? [],
                        priority: f["priority"] as? String
                    )
                }
            }

            if let decisions = specsDict["technicalDecisions"] as? [[String: Any]] {
                specs.technicalDecisions = decisions.map { d in
                    TechnicalDecision(
                        decision: d["decision"] as? String ?? "",
                        rationale: d["rationale"] as? String ?? "",
                        alternatives: d["alternatives"] as? [String] ?? []
                    )
                }
            }

            if let apis = specsDict["apiContracts"] as? [[String: Any]] {
                specs.apiContracts = apis.map { a in
                    APIContract(
                        endpoint: a["endpoint"] as? String ?? "",
                        method: a["method"] as? String ?? "",
                        description: a["description"] as? String ?? "",
                        requestSchema: a["requestSchema"] as? String,
                        responseSchema: a["responseSchema"] as? String
                    )
                }
            }

            if let models = specsDict["dataModels"] as? [[String: Any]] {
                specs.dataModels = models.map { m in
                    let fields = (m["fields"] as? [[String: Any]] ?? []).map { f in
                        DataField(
                            name: f["name"] as? String ?? "",
                            type: f["type"] as? String ?? "",
                            isRequired: f["isRequired"] as? Bool ?? false,
                            description: f["description"] as? String
                        )
                    }
                    return DataModelSpec(
                        name: m["name"] as? String ?? "",
                        description: m["description"] as? String ?? "",
                        fields: fields
                    )
                }
            }

            specs.openQuestions = specsDict["openQuestions"] as? [String] ?? []
        }

        return MeetingAnalysis(
            summary: summary,
            clarificationQuestions: clarificationQuestions,
            goalsAndTasks: goalsAndTasks,
            softwareEngineeringSpecs: specs,
            lastUpdated: Date()
        )
    }

    enum LLMError: LocalizedError {
        case noAPIKey
        case invalidResponse
        case apiError(statusCode: Int, message: String)
        case parseError

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No API key configured. Please add your API key in Settings."
            case .invalidResponse:
                return "Invalid response from LLM API"
            case .apiError(let statusCode, let message):
                return "API error (\(statusCode)): \(message)"
            case .parseError:
                return "Failed to parse LLM response"
            }
        }
    }
}
