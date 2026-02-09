import Foundation

struct MeetingAnalysis: Codable, Equatable {
    var summary: String
    var clarificationQuestions: [ClarificationQuestion]
    var goalsAndTasks: [GoalOrTask]
    var softwareEngineeringSpecs: SoftwareEngineeringSpecs
    var lastUpdated: Date

    init(
        summary: String = "",
        clarificationQuestions: [ClarificationQuestion] = [],
        goalsAndTasks: [GoalOrTask] = [],
        softwareEngineeringSpecs: SoftwareEngineeringSpecs = .empty,
        lastUpdated: Date = Date()
    ) {
        self.summary = summary
        self.clarificationQuestions = clarificationQuestions
        self.goalsAndTasks = goalsAndTasks
        self.softwareEngineeringSpecs = softwareEngineeringSpecs
        self.lastUpdated = lastUpdated
    }

    static let empty = MeetingAnalysis()
}

struct ClarificationQuestion: Codable, Equatable, Identifiable {
    var id: UUID
    var question: String
    var context: String
    var priority: Priority

    enum Priority: String, Codable, CaseIterable {
        case high
        case medium
        case low
    }

    init(id: UUID = UUID(), question: String, context: String, priority: Priority) {
        self.id = id
        self.question = question
        self.context = context
        self.priority = priority
    }
}

struct GoalOrTask: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var description: String
    var assignee: String?
    var isCompleted: Bool

    init(id: UUID = UUID(), title: String, description: String, assignee: String? = nil, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.description = description
        self.assignee = assignee
        self.isCompleted = isCompleted
    }
}

struct SoftwareEngineeringSpecs: Codable, Equatable {
    var featureRequirements: [FeatureRequirement]
    var technicalDecisions: [TechnicalDecision]
    var apiContracts: [APIContract]
    var dataModels: [DataModelSpec]
    var openQuestions: [String]

    init(
        featureRequirements: [FeatureRequirement] = [],
        technicalDecisions: [TechnicalDecision] = [],
        apiContracts: [APIContract] = [],
        dataModels: [DataModelSpec] = [],
        openQuestions: [String] = []
    ) {
        self.featureRequirements = featureRequirements
        self.technicalDecisions = technicalDecisions
        self.apiContracts = apiContracts
        self.dataModels = dataModels
        self.openQuestions = openQuestions
    }

    static let empty = SoftwareEngineeringSpecs()
}

struct FeatureRequirement: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var description: String
    var acceptanceCriteria: [String]
    var priority: String?

    init(id: UUID = UUID(), name: String, description: String, acceptanceCriteria: [String] = [], priority: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.acceptanceCriteria = acceptanceCriteria
        self.priority = priority
    }
}

struct TechnicalDecision: Codable, Equatable, Identifiable {
    var id: UUID
    var decision: String
    var rationale: String
    var alternatives: [String]

    init(id: UUID = UUID(), decision: String, rationale: String, alternatives: [String] = []) {
        self.id = id
        self.decision = decision
        self.rationale = rationale
        self.alternatives = alternatives
    }
}

struct APIContract: Codable, Equatable, Identifiable {
    var id: UUID
    var endpoint: String
    var method: String
    var description: String
    var requestSchema: String?
    var responseSchema: String?

    init(id: UUID = UUID(), endpoint: String, method: String, description: String, requestSchema: String? = nil, responseSchema: String? = nil) {
        self.id = id
        self.endpoint = endpoint
        self.method = method
        self.description = description
        self.requestSchema = requestSchema
        self.responseSchema = responseSchema
    }
}

struct DataModelSpec: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var description: String
    var fields: [DataField]

    init(id: UUID = UUID(), name: String, description: String, fields: [DataField] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.fields = fields
    }
}

struct DataField: Codable, Equatable {
    var name: String
    var type: String
    var isRequired: Bool
    var description: String?
}

struct RealTimeSessionState {
    var segments: [TranscriptSegment]
    var analysis: MeetingAnalysis
    var isAnalyzing: Bool
    var lastTranscriptionTime: Date?
    var lastAnalysisTime: Date?

    init(
        segments: [TranscriptSegment] = [],
        analysis: MeetingAnalysis = .empty,
        isAnalyzing: Bool = false,
        lastTranscriptionTime: Date? = nil,
        lastAnalysisTime: Date? = nil
    ) {
        self.segments = segments
        self.analysis = analysis
        self.isAnalyzing = isAnalyzing
        self.lastTranscriptionTime = lastTranscriptionTime
        self.lastAnalysisTime = lastAnalysisTime
    }
}
