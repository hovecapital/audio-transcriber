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
        llmModel: "claude-sonnet-4-20250514"
    )

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
