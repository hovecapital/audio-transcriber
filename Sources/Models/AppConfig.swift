import AppKit
import Foundation

public struct HotkeyCombo: Codable, Equatable {
    public var keyCode: UInt16
    public var modifiers: UInt

    public static let dictationDefault = HotkeyCombo(keyCode: 0x02, modifiers: NSEvent.ModifierFlags([.control, .command]).rawValue)
    public static let autocorrectDefault = HotkeyCombo(keyCode: 0x00, modifiers: NSEvent.ModifierFlags([.control, .command]).rawValue)

    public init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public func matches(_ event: NSEvent) -> Bool {
        let mask: NSEvent.ModifierFlags = [.control, .command, .option, .shift]
        return event.keyCode == keyCode && event.modifierFlags.intersection(mask) == NSEvent.ModifierFlags(rawValue: modifiers).intersection(mask)
    }

    public var displayString: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var symbols = ""
        if flags.contains(.control) { symbols += "^" }
        if flags.contains(.option) { symbols += "\u{2325}" }
        if flags.contains(.shift) { symbols += "\u{21E7}" }
        if flags.contains(.command) { symbols += "\u{2318}" }
        return symbols + Self.keyName(for: keyCode)
    }

    public static func keyName(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x28: "K", 0x2C: "/", 0x2D: "N",
            0x2E: "M", 0x2F: ".", 0x31: " ", 0x32: "`",
            0x24: "\u{21A9}", 0x30: "\u{21E5}", 0x33: "\u{232B}",
            0x35: "\u{238B}", 0x7A: "F1", 0x78: "F2", 0x63: "F3",
            0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7",
            0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11",
            0x6F: "F12", 0x7B: "\u{2190}", 0x7C: "\u{2192}",
            0x7D: "\u{2193}", 0x7E: "\u{2191}",
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }
}

public struct AppConfig: Codable {
    public var outputDirectory: String
    public var autoOpenTranscript: Bool
    public var whisperModelSize: WhisperModelSize
    public var person1Label: String
    public var person2Label: String
    public var deleteAudioAfterTranscription: Bool

    public var enableRealTimeTranscription: Bool
    public var transcriptionChunkIntervalSeconds: Double
    public var llmAnalysisIntervalSeconds: Double
    public var llmProvider: LLMProvider
    public var llmModel: String

    public var autocorrectEnabled: Bool
    public var autocorrectBackend: AutocorrectBackend
    public var autocorrectServerURL: String
    public var autocorrectModel: String
    public var autocorrectTimeout: Double
    public var backupDirectory: String
    public var dictationEnabled: Bool
    public var llamaServerModelPath: String
    public var llamaServerHFModel: String
    public var autoStartLLMServer: Bool
    public var autoRecordMeetings: Bool
    public var autocorrectHotkey: HotkeyCombo
    public var dictationHotkey: HotkeyCombo

    public enum AutocorrectBackend: String, Codable, CaseIterable {
        case ollama
        case llamaCpp

        public var displayName: String {
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

    public enum WhisperModelSize: String, Codable, CaseIterable {
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

    public enum LLMProvider: String, Codable, CaseIterable {
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

    public static let `default` = AppConfig(
        outputDirectory: "~/Documents/Transcripts",
        autoOpenTranscript: true,
        whisperModelSize: .base,
        person1Label: "Person 1",
        person2Label: "Person 2",
        deleteAudioAfterTranscription: false,
        enableRealTimeTranscription: false,
        transcriptionChunkIntervalSeconds: 15.0,
        llmAnalysisIntervalSeconds: 120.0,
        llmProvider: .anthropic,
        llmModel: "claude-sonnet-4-20250514",
        autocorrectEnabled: false,
        autocorrectBackend: .llamaCpp,
        autocorrectServerURL: "http://localhost:8080",
        autocorrectModel: "llama3.2:3b",
        autocorrectTimeout: 3.0,
        backupDirectory: "~/Documents/MeetingRecorder-Backups",
        dictationEnabled: false,
        llamaServerModelPath: "",
        llamaServerHFModel: "",
        autoStartLLMServer: true,
        autoRecordMeetings: false,
        autocorrectHotkey: .autocorrectDefault,
        dictationHotkey: .dictationDefault
    )

    public init(
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
        autocorrectTimeout: Double,
        backupDirectory: String = "~/Documents/MeetingRecorder-Backups",
        dictationEnabled: Bool = false,
        llamaServerModelPath: String = "",
        llamaServerHFModel: String = "",
        autoStartLLMServer: Bool = true,
        autoRecordMeetings: Bool = false,
        autocorrectHotkey: HotkeyCombo = .autocorrectDefault,
        dictationHotkey: HotkeyCombo = .dictationDefault
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
        self.backupDirectory = backupDirectory
        self.dictationEnabled = dictationEnabled
        self.llamaServerModelPath = llamaServerModelPath
        self.llamaServerHFModel = llamaServerHFModel
        self.autoStartLLMServer = autoStartLLMServer
        self.autoRecordMeetings = autoRecordMeetings
        self.autocorrectHotkey = autocorrectHotkey
        self.dictationHotkey = dictationHotkey
    }

    public init(from decoder: Decoder) throws {
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
        backupDirectory = try container.decodeIfPresent(String.self, forKey: .backupDirectory) ?? "~/Documents/MeetingRecorder-Backups"
        dictationEnabled = try container.decodeIfPresent(Bool.self, forKey: .dictationEnabled) ?? false
        llamaServerModelPath = try container.decodeIfPresent(String.self, forKey: .llamaServerModelPath) ?? ""
        llamaServerHFModel = try container.decodeIfPresent(String.self, forKey: .llamaServerHFModel) ?? ""
        autoStartLLMServer = try container.decodeIfPresent(Bool.self, forKey: .autoStartLLMServer) ?? true
        autoRecordMeetings = try container.decodeIfPresent(Bool.self, forKey: .autoRecordMeetings) ?? false
        autocorrectHotkey = try container.decodeIfPresent(HotkeyCombo.self, forKey: .autocorrectHotkey) ?? .autocorrectDefault
        dictationHotkey = try container.decodeIfPresent(HotkeyCombo.self, forKey: .dictationHotkey) ?? .dictationDefault
    }

    public var expandedOutputDirectory: URL {
        let expanded = NSString(string: outputDirectory).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    var expandedBackupDirectory: URL {
        let expanded = NSString(string: backupDirectory).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }
}

public final class ConfigManager {
    public static let shared = ConfigManager()

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

    public func load() -> AppConfig {
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

    public func save(_ config: AppConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL)
            Log.config.info("Config saved: model=\(config.whisperModelSize.rawValue), output=\(config.outputDirectory)")
        } catch {
            Log.config.error("Failed to save config: \(error.localizedDescription)")
        }
    }
}

public extension Notification.Name {
    static let dictationHotkeyChanged = Notification.Name("com.meetingrecorder.dictationHotkeyChanged")
}
