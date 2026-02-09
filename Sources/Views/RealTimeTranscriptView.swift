import SwiftUI

struct RealTimeTranscriptView: View {
    @ObservedObject var coordinator: RealTimeRecordingCoordinator
    let config: AppConfig

    var body: some View {
        HSplitView {
            transcriptPane
            analysisPane
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    @ViewBuilder
    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Live Transcript")
                    .font(.headline)
                Spacer()
                Text("\(coordinator.state.segments.count) segments")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(Color(.windowBackgroundColor))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(coordinator.state.segments) { segment in
                            TranscriptSegmentRow(segment: segment, config: config)
                                .id(segment.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: coordinator.state.segments.count) { _ in
                    if let lastSegment = coordinator.state.segments.last {
                        withAnimation {
                            proxy.scrollTo(lastSegment.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 300)
    }

    @ViewBuilder
    private var analysisPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Analysis")
                    .font(.headline)
                Spacer()
                if coordinator.state.isAnalyzing {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Analyzing...")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else if let lastUpdate = coordinator.state.lastAnalysisTime {
                    Text("Updated \(lastUpdate.formatted(date: .omitted, time: .shortened))")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !coordinator.state.analysis.summary.isEmpty {
                        AnalysisSectionView(title: "Summary") {
                            Text(coordinator.state.analysis.summary)
                        }
                    }

                    if !coordinator.state.analysis.clarificationQuestions.isEmpty {
                        AnalysisSectionView(title: "Clarification Questions") {
                            ForEach(coordinator.state.analysis.clarificationQuestions) { question in
                                ClarificationQuestionRow(question: question)
                            }
                        }
                    }

                    if !coordinator.state.analysis.goalsAndTasks.isEmpty {
                        AnalysisSectionView(title: "Goals & Tasks") {
                            ForEach(coordinator.state.analysis.goalsAndTasks) { task in
                                TaskRow(task: task)
                            }
                        }
                    }

                    if hasSpecs(coordinator.state.analysis.softwareEngineeringSpecs) {
                        specsSection
                    }

                    if coordinator.state.segments.isEmpty && coordinator.state.analysis.summary.isEmpty {
                        VStack {
                            Spacer()
                            Text("Analysis will appear here after transcription begins")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 300)
    }

    @ViewBuilder
    private var specsSection: some View {
        AnalysisSectionView(title: "Software Engineering Specs") {
            let specs = coordinator.state.analysis.softwareEngineeringSpecs

            if !specs.featureRequirements.isEmpty {
                Text("Feature Requirements")
                    .font(.subheadline)
                    .fontWeight(.medium)
                ForEach(specs.featureRequirements) { feature in
                    FeatureRequirementRow(feature: feature)
                }
            }

            if !specs.technicalDecisions.isEmpty {
                Text("Technical Decisions")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.top, 8)
                ForEach(specs.technicalDecisions) { decision in
                    TechnicalDecisionRow(decision: decision)
                }
            }

            if !specs.openQuestions.isEmpty {
                Text("Open Questions")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.top, 8)
                ForEach(specs.openQuestions, id: \.self) { question in
                    Text("- \(question)")
                        .font(.caption)
                }
            }
        }
    }

    private func hasSpecs(_ specs: SoftwareEngineeringSpecs) -> Bool {
        return !specs.featureRequirements.isEmpty ||
               !specs.technicalDecisions.isEmpty ||
               !specs.apiContracts.isEmpty ||
               !specs.dataModels.isEmpty ||
               !specs.openQuestions.isEmpty
    }
}

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let config: AppConfig

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(segment.formattedTimestamp)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(speakerLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(speakerColor)
                Text(segment.text)
                    .font(.body)
            }
        }
        .padding(.vertical, 4)
    }

    private var speakerLabel: String {
        segment.speaker == .person1 ? config.person1Label : config.person2Label
    }

    private var speakerColor: Color {
        segment.speaker == .person1 ? .blue : .green
    }
}

struct AnalysisSectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .background(Color(.textBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

struct ClarificationQuestionRow: View {
    let question: ClarificationQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                priorityBadge
                Text(question.question)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            Text(question.context)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var priorityBadge: some View {
        Text(question.priority.rawValue.uppercased())
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor.opacity(0.2))
            .foregroundColor(priorityColor)
            .cornerRadius(4)
    }

    private var priorityColor: Color {
        switch question.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}

struct TaskRow: View {
    let task: GoalOrTask

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                .foregroundColor(task.isCompleted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(task.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let assignee = task.assignee {
                        Text("@\(assignee)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                Text(task.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FeatureRequirementRow: View {
    let feature: FeatureRequirement

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(feature.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let priority = feature.priority {
                    Text(priority)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            Text(feature.description)
                .font(.caption)
                .foregroundColor(.secondary)
            if !feature.acceptanceCriteria.isEmpty {
                Text("Acceptance Criteria:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.top, 2)
                ForEach(feature.acceptanceCriteria, id: \.self) { criterion in
                    Text("- \(criterion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct TechnicalDecisionRow: View {
    let decision: TechnicalDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(decision.decision)
                .font(.subheadline)
                .fontWeight(.medium)
            Text("Rationale: \(decision.rationale)")
                .font(.caption)
                .foregroundColor(.secondary)
            if !decision.alternatives.isEmpty {
                Text("Alternatives: \(decision.alternatives.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
