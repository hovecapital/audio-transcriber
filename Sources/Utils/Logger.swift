import Foundation
import os.log

enum Log {
    private static let subsystem = "com.meetingrecorder.app"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let realtime = Logger(subsystem: subsystem, category: "realtime")
}
