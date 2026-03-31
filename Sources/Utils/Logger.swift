import Foundation
import os.log

public struct AppLogger {
    private let osLogger: Logger
    private let category: String

    init(subsystem: String, category: String) {
        self.osLogger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    public func debug(_ message: String) {
        osLogger.debug("\(message)")
        appendToStore(level: .debug, message: message)
    }

    public func info(_ message: String) {
        osLogger.info("\(message)")
        appendToStore(level: .info, message: message)
    }

    public func warning(_ message: String) {
        osLogger.warning("\(message)")
        appendToStore(level: .warning, message: message)
    }

    public func error(_ message: String) {
        osLogger.error("\(message)")
        appendToStore(level: .error, message: message)
    }

    private func appendToStore(level: LogLevel, message: String) {
        let entry = LogEntry(
            timestamp: Date(),
            category: category,
            level: level,
            message: message
        )
        Task { @MainActor in
            LogStore.shared.append(entry)
        }
    }
}

public enum Log {
    private static let subsystem = "com.meetingrecorder.app"

    public static let general = AppLogger(subsystem: subsystem, category: "general")
    static let audio = AppLogger(subsystem: subsystem, category: "audio")
    static let transcription = AppLogger(subsystem: subsystem, category: "transcription")
    static let config = AppLogger(subsystem: subsystem, category: "config")
    static let realtime = AppLogger(subsystem: subsystem, category: "realtime")
    static let autocorrect = AppLogger(subsystem: subsystem, category: "autocorrect")
    static let dictation = AppLogger(subsystem: subsystem, category: "dictation")
    static let meeting = AppLogger(subsystem: subsystem, category: "meeting")
    static let llmServer = AppLogger(subsystem: subsystem, category: "llmServer")
}
