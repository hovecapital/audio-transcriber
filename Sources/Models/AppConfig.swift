import Foundation

struct AppConfig: Codable {
    var outputDirectory: String
    var autoOpenTranscript: Bool
    var whisperModelSize: WhisperModelSize
    var person1Label: String
    var person2Label: String
    var deleteAudioAfterTranscription: Bool

    var enableRealTimeTranscription: Bool
    var transcriptionChunkIntervalSeconds: Double
    var llmAnalysisIntervalSeconds: Double
    var llmProvider: LLMProvider
    var llmModel: String

    var autocorrectEnabled: Bool
    var autocorrectBackend: AutocorrectBackend
    var autocorrectServerURL: String
    var autocorrectModel: String
    var autocorrectTimeout: Double

    enum AutocorrectBackend: String, Codable, CaseIterable {
        case ollama
        case llamaCpp

        var displayName: String {
            switch self {
            case .ollama: return "Ollama"
            case .llamaCpp: return "llama.cpp"
            }
        }

        var defaultURL: String {
            switch self {
            case .ollama: return "http://localhost:11434"
            case .llamaCpp: return "http://localhost:8080"
            }
        }
    }

    enum WhisperModelSize: String, Codable, CaseIterable {
        case tiny = "tiny"
        case base = "base"
        case small = "small"

        var displayName: String {
            switch self {
            case .tiny: return "Tiny (fastest)"
            case .base: return "Base (balanced)"
            case .small: return "Small (most accurate)"
            }
        }
    }

    enum LLMProvider: String, Codable, CaseIterable {
        case anthropic
        case openai

        var displayName: String {
            switch self {
            case .anthropic: return "Anthropic (Claude)"
            case .openai: return "OpenAI (GPT)"
            }
        }

        var defaultModel: String {
            switch self {
            case .anthropic: return "claude-sonnet-4-20250514"
            case .openai: return "gpt-4o"
            }
        }
    }

    static let `default` = AppConfig(
        outputDirectory: "~/Documents/Transcripts",
        autoOpenTranscript: true,
        whisperModelSize: .base,
        person1Label: "Person 1",
        person2Label: "Person 2",
        deleteAudioAfterTranscription: true,
        enableRealTimeTranscription: false,
        transcriptionChunkIntervalSeconds: 15.0,
        llmAnalysisIntervalSeconds: 120.0,
        llmProvider: .anthropic,
        llmModel: "claude-sonnet-4-20250514",
        autocorrectEnabled: false,
        autocorrectBackend: .llamaCpp,
        autocorrectServerURL: "http://localhost:8080",
        autocorrectModel: "llama3.2:3b",
        autocorrectTimeout: 3.0
    )

    init(
        outputDirectory: String,
        autoOpenTranscript: Bool,
        whisperModelSize: WhisperModelSize,
        person1Label: String,
        person2Label: String,
        deleteAudioAfterTranscription: Bool,
        enableRealTimeTranscription: Bool,
        transcriptionChunkIntervalSeconds: Double,
        llmAnalysisIntervalSeconds: Double,
        llmProvider: LLMProvider,
        llmModel: String,
        autocorrectEnabled: Bool,
        autocorrectBackend: AutocorrectBackend,
        autocorrectServerURL: String,
        autocorrectModel: String,
        autocorrectTimeout: Double
    ) {
        self.outputDirectory = outputDirectory
        self.autoOpenTranscript = autoOpenTranscript
        self.whisperModelSize = whisperModelSize
        self.person1Label = person1Label
        self.person2Label = person2Label
        self.deleteAudioAfterTranscription = deleteAudioAfterTranscription
        self.enableRealTimeTranscription = enableRealTimeTranscription
        self.transcriptionChunkIntervalSeconds = transcriptionChunkIntervalSeconds
        self.llmAnalysisIntervalSeconds = llmAnalysisIntervalSeconds
        self.llmProvider = llmProvider
        self.llmModel = llmModel
        self.autocorrectEnabled = autocorrectEnabled
        self.autocorrectBackend = autocorrectBackend
        self.autocorrectServerURL = autocorrectServerURL
        self.autocorrectModel = autocorrectModel
        self.autocorrectTimeout = autocorrectTimeout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputDirectory = try container.decode(String.self, forKey: .outputDirectory)
        autoOpenTranscript = try container.decode(Bool.self, forKey: .autoOpenTranscript)
        whisperModelSize = try container.decode(WhisperModelSize.self, forKey: .whisperModelSize)
        person1Label = try container.decode(String.self, forKey: .person1Label)
        person2Label = try container.decode(String.self, forKey: .person2Label)
        deleteAudioAfterTranscription = try container.decode(Bool.self, forKey: .deleteAudioAfterTranscription)
        enableRealTimeTranscription = try container.decode(Bool.self, forKey: .enableRealTimeTranscription)
        transcriptionChunkIntervalSeconds = try container.decode(Double.self, forKey: .transcriptionChunkIntervalSeconds)
        llmAnalysisIntervalSeconds = try container.decode(Double.self, forKey: .llmAnalysisIntervalSeconds)
        llmProvider = try container.decode(LLMProvider.self, forKey: .llmProvider)
        llmModel = try container.decode(String.self, forKey: .llmModel)
        autocorrectEnabled = try container.decodeIfPresent(Bool.self, forKey: .autocorrectEnabled) ?? false
        autocorrectBackend = try container.decodeIfPresent(AutocorrectBackend.self, forKey: .autocorrectBackend) ?? .llamaCpp
        autocorrectServerURL = try container.decodeIfPresent(String.self, forKey: .autocorrectServerURL) ?? AutocorrectBackend.llamaCpp.defaultURL
        autocorrectModel = try container.decodeIfPresent(String.self, forKey: .autocorrectModel) ?? "llama3.2:3b"
        autocorrectTimeout = try container.decodeIfPresent(Double.self, forKey: .autocorrectTimeout) ?? 3.0
    }

    var expandedOutputDirectory: URL {
        let expanded = NSString(string: outputDirectory).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }
}

final class ConfigManager {
    static let shared = ConfigManager()

    private let configFileName = "config.json"
    private var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MeetingRecorder")
        return appFolder.appendingPathComponent(configFileName)
    }

    private init() {
        ensureAppSupportDirectoryExists()
        Log.config.debug("ConfigManager initialized")
        Log.config.debug("Config path: \(self.configURL.path)")
    }

    private func ensureAppSupportDirectoryExists() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MeetingRecorder")
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
    }

    func load() -> AppConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            Log.config.info("No config file found, using defaults")
            return .default
        }

        do {
            let data = try Data(contentsOf: configURL)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            Log.config.info("Config loaded: model=\(config.whisperModelSize.rawValue), output=\(config.outputDirectory)")
            return config
        } catch {
            Log.config.error("Failed to load config: \(error.localizedDescription)")
            return .default
        }
    }

    func save(_ config: AppConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL)
            Log.config.info("Config saved: model=\(config.whisperModelSize.rawValue), output=\(config.outputDirectory)")
        } catch {
            Log.config.error("Failed to save config: \(error.localizedDescription)")
        }
    }
}
