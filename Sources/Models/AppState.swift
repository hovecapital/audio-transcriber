import Foundation
import SwiftUI

enum DictationStatus: Equatable {
    case idle
    case listening
    case transcribing
}

enum RecordingStatus: Equatable {
    case idle
    case recording
    case processing(progress: Double, message: String)
    case completed
    case error(String)
    case warning(String)

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isProcessing: Bool {
        if case .processing = self { return true }
        return false
    }

    var isWarning: Bool {
        if case .warning = self { return true }
        return false
    }
}

struct RecordingSession {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    let micFilePath: URL
    let systemFilePath: URL
    var transcriptPath: URL?
    var status: RecordingStatus

    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    var formattedDuration: String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct TranscriptSegment: Identifiable {
    let id = UUID()
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    let speaker: Speaker

    enum Speaker: String {
        case person1 = "Person 1"
        case person2 = "Person 2"
    }

    var formattedTimestamp: String {
        let minutes = Int(start) / 60
        let seconds = Int(start) % 60
        return String(format: "[%02d:%02d]", minutes, seconds)
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var status: RecordingStatus = .idle
    @Published var dictationStatus: DictationStatus = .idle
    @Published var currentSession: RecordingSession?
    @Published var showSettings = false

    private init() {}

    func updateStatus(_ newStatus: RecordingStatus) {
        status = newStatus
    }
}
