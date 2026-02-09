import Foundation

struct EnhancedMarkdownGenerator {
    private let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func generate(
        segments: [TranscriptSegment],
        analysis: MeetingAnalysis,
        session: RecordingSession
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy 'at' h:mm a"

        var markdown = """
        # Meeting Transcript

        **Date:** \(dateFormatter.string(from: session.startTime))
        **Duration:** \(session.formattedDuration)

        ---

        """

        if !analysis.summary.isEmpty {
            markdown += generateSummarySection(analysis.summary)
        }

        if !analysis.clarificationQuestions.isEmpty {
            markdown += generateClarificationSection(analysis.clarificationQuestions)
        }

        if !analysis.goalsAndTasks.isEmpty {
            markdown += generateTasksSection(analysis.goalsAndTasks)
        }

        if hasSpecs(analysis.softwareEngineeringSpecs) {
            markdown += generateSpecsSection(analysis.softwareEngineeringSpecs)
        }

        markdown += generateTranscriptSection(segments)

        return markdown
    }

    private func generateSummarySection(_ summary: String) -> String {
        return """

        ## Summary

        \(summary)

        """
    }

    private func generateClarificationSection(_ questions: [ClarificationQuestion]) -> String {
        var section = """

        ## Clarification Questions

        """

        let sortedQuestions = questions.sorted { q1, q2 in
            let order: [ClarificationQuestion.Priority] = [.high, .medium, .low]
            let i1 = order.firstIndex(of: q1.priority) ?? 1
            let i2 = order.firstIndex(of: q2.priority) ?? 1
            return i1 < i2
        }

        for question in sortedQuestions {
            let priorityEmoji = switch question.priority {
            case .high: "[HIGH]"
            case .medium: "[MEDIUM]"
            case .low: "[LOW]"
            }

            section += """

            - \(priorityEmoji) **\(question.question)**
              - Context: \(question.context)
            """
        }

        section += "\n"
        return section
    }

    private func generateTasksSection(_ tasks: [GoalOrTask]) -> String {
        var section = """

        ## Goals and Tasks

        """

        for task in tasks {
            let checkbox = task.isCompleted ? "[x]" : "[ ]"
            let assignee = task.assignee.map { " (@\($0))" } ?? ""
            section += """

            - \(checkbox) **\(task.title)**\(assignee)
              - \(task.description)
            """
        }

        section += "\n"
        return section
    }

    private func generateSpecsSection(_ specs: SoftwareEngineeringSpecs) -> String {
        var section = """

        ## Software Engineering Specs

        """

        if !specs.featureRequirements.isEmpty {
            section += """

            ### Feature Requirements

            """
            for feature in specs.featureRequirements {
                let priority = feature.priority.map { " (\($0) priority)" } ?? ""
                section += """

                #### \(feature.name)\(priority)

                \(feature.description)

                """
                if !feature.acceptanceCriteria.isEmpty {
                    section += "**Acceptance Criteria:**\n"
                    for criterion in feature.acceptanceCriteria {
                        section += "- [ ] \(criterion)\n"
                    }
                }
            }
        }

        if !specs.technicalDecisions.isEmpty {
            section += """

            ### Technical Decisions

            """
            for decision in specs.technicalDecisions {
                section += """

                #### \(decision.decision)

                **Rationale:** \(decision.rationale)

                """
                if !decision.alternatives.isEmpty {
                    section += "**Alternatives Considered:**\n"
                    for alt in decision.alternatives {
                        section += "- \(alt)\n"
                    }
                }
            }
        }

        if !specs.apiContracts.isEmpty {
            section += """

            ### API Contracts

            """
            for api in specs.apiContracts {
                section += """

                #### `\(api.method) \(api.endpoint)`

                \(api.description)

                """
                if let request = api.requestSchema {
                    section += """
                    **Request:**
                    ```json
                    \(request)
                    ```

                    """
                }
                if let response = api.responseSchema {
                    section += """
                    **Response:**
                    ```json
                    \(response)
                    ```

                    """
                }
            }
        }

        if !specs.dataModels.isEmpty {
            section += """

            ### Data Models

            """
            for model in specs.dataModels {
                section += """

                #### \(model.name)

                \(model.description)

                | Field | Type | Required | Description |
                |-------|------|----------|-------------|
                """
                for field in model.fields {
                    let required = field.isRequired ? "Yes" : "No"
                    let desc = field.description ?? "-"
                    section += "| \(field.name) | \(field.type) | \(required) | \(desc) |\n"
                }
            }
        }

        if !specs.openQuestions.isEmpty {
            section += """

            ### Open Questions

            """
            for question in specs.openQuestions {
                section += "- \(question)\n"
            }
        }

        return section
    }

    private func generateTranscriptSection(_ segments: [TranscriptSegment]) -> String {
        var section = """

        ---

        ## Full Transcript

        """

        let sortedSegments = segments.sorted { $0.start < $1.start }

        for segment in sortedSegments {
            let speakerLabel = segment.speaker == .person1 ? config.person1Label : config.person2Label
            let timestamp = formatTimestamp(segment.start)
            section += "\n\(timestamp) **\(speakerLabel):** \(segment.text)\n"
        }

        return section
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "[%02d:%02d]", minutes, secs)
    }

    private func hasSpecs(_ specs: SoftwareEngineeringSpecs) -> Bool {
        return !specs.featureRequirements.isEmpty ||
               !specs.technicalDecisions.isEmpty ||
               !specs.apiContracts.isEmpty ||
               !specs.dataModels.isEmpty ||
               !specs.openQuestions.isEmpty
    }

    func save(markdown: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }
}
