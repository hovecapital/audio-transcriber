import Foundation
import XCTest

@testable import MeetingRecorderCore

final class AppStateTests: XCTestCase {
    // MARK: - RecordingStatus

    func testRecordingStatusIsRecording() {
        XCTAssertTrue(RecordingStatus.recording.isRecording)
        XCTAssertFalse(RecordingStatus.idle.isRecording)
        XCTAssertFalse(RecordingStatus.processing(progress: 0.5, message: "test").isRecording)
        XCTAssertFalse(RecordingStatus.completed.isRecording)
        XCTAssertFalse(RecordingStatus.error("err").isRecording)
        XCTAssertFalse(RecordingStatus.warning("warn").isRecording)
    }

    func testRecordingStatusIsProcessing() {
        XCTAssertTrue(RecordingStatus.processing(progress: 0.5, message: "test").isProcessing)
        XCTAssertFalse(RecordingStatus.idle.isProcessing)
        XCTAssertFalse(RecordingStatus.recording.isProcessing)
    }

    func testRecordingStatusIsWarning() {
        XCTAssertTrue(RecordingStatus.warning("warn").isWarning)
        XCTAssertFalse(RecordingStatus.idle.isWarning)
        XCTAssertFalse(RecordingStatus.recording.isWarning)
    }

    func testRecordingStatusEquality() {
        XCTAssertEqual(RecordingStatus.idle, RecordingStatus.idle)
        XCTAssertEqual(RecordingStatus.recording, RecordingStatus.recording)
        XCTAssertNotEqual(RecordingStatus.idle, RecordingStatus.recording)
    }

    // MARK: - RecordingSession

    func testRecordingSessionFormattedDurationMinutesSeconds() {
        let session = RecordingSession(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 125),
            micFilePath: URL(fileURLWithPath: "/tmp/mic.wav"),
            systemFilePath: URL(fileURLWithPath: "/tmp/sys.wav"),
            status: .idle
        )
        XCTAssertEqual(session.formattedDuration, "02:05")
    }

    func testRecordingSessionFormattedDurationWithHours() {
        let session = RecordingSession(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 3661),
            micFilePath: URL(fileURLWithPath: "/tmp/mic.wav"),
            systemFilePath: URL(fileURLWithPath: "/tmp/sys.wav"),
            status: .idle
        )
        XCTAssertEqual(session.formattedDuration, "1:01:01")
    }

    func testRecordingSessionDurationCalculation() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1060)
        let session = RecordingSession(
            id: UUID(),
            startTime: start,
            endTime: end,
            micFilePath: URL(fileURLWithPath: "/tmp/mic.wav"),
            systemFilePath: URL(fileURLWithPath: "/tmp/sys.wav"),
            status: .idle
        )
        XCTAssertEqual(session.duration, 60.0, accuracy: 0.1)
    }

    // MARK: - TranscriptSegment

    func testTranscriptSegmentFormattedTimestamp() {
        let segment = TranscriptSegment(start: 125.0, end: 130.0, text: "Test", speaker: .person1)
        XCTAssertEqual(segment.formattedTimestamp, "[02:05]")
    }

    func testTranscriptSegmentFormattedTimestampZero() {
        let segment = TranscriptSegment(start: 0, end: 5.0, text: "Test", speaker: .person2)
        XCTAssertEqual(segment.formattedTimestamp, "[00:00]")
    }

    func testTranscriptSegmentSpeakerRawValues() {
        XCTAssertEqual(TranscriptSegment.Speaker.person1.rawValue, "Person 1")
        XCTAssertEqual(TranscriptSegment.Speaker.person2.rawValue, "Person 2")
    }
}
