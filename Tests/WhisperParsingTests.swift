import Foundation
import XCTest

@testable import MeetingRecorderCore

final class WhisperParsingTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperParsingTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func writeJSON(_ json: [String: Any]) throws -> URL {
        let url = tempDir.appendingPathComponent("\(UUID().uuidString).json")
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: url)
        return url
    }

    // MARK: - parseSegments

    func testParseSegmentsWithTranscriptionArray() throws {
        let json: [String: Any] = [
            "transcription": [
                [
                    "text": "Hello world",
                    "offsets": ["from": 0, "to": 2000]
                ],
                [
                    "text": "How are you",
                    "offsets": ["from": 2000, "to": 5000]
                ]
            ]
        ]
        let url = try writeJSON(json)
        let segments = try WhisperOutputParser.parseSegments(jsonURL: url, speaker: .person1)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "Hello world")
        XCTAssertEqual(segments[0].start, 0.0)
        XCTAssertEqual(segments[0].end, 2.0)
        XCTAssertEqual(segments[0].speaker, .person1)
        XCTAssertEqual(segments[1].text, "How are you")
        XCTAssertEqual(segments[1].start, 2.0)
        XCTAssertEqual(segments[1].end, 5.0)
    }

    func testParseSegmentsFallsBackToTextKey() throws {
        let json: [String: Any] = ["text": "Single block of text"]
        let url = try writeJSON(json)
        let segments = try WhisperOutputParser.parseSegments(jsonURL: url, speaker: .person2)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "Single block of text")
        XCTAssertEqual(segments[0].speaker, .person2)
    }

    func testParseSegmentsSkipsEmptyText() throws {
        let json: [String: Any] = [
            "transcription": [
                ["text": "Valid text", "offsets": ["from": 0, "to": 1000]],
                ["text": "   ", "offsets": ["from": 1000, "to": 2000]],
                ["text": "", "offsets": ["from": 2000, "to": 3000]]
            ]
        ]
        let url = try writeJSON(json)
        let segments = try WhisperOutputParser.parseSegments(jsonURL: url, speaker: .person1)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "Valid text")
    }

    func testParseSegmentsThrowsOnMissingFile() {
        let url = tempDir.appendingPathComponent("nonexistent.json")
        XCTAssertThrowsError(try WhisperOutputParser.parseSegments(jsonURL: url, speaker: .person1))
    }

    func testParseSegmentsThrowsOnInvalidJSON() throws {
        let url = tempDir.appendingPathComponent("invalid.json")
        try "not json".data(using: .utf8)!.write(to: url)
        XCTAssertThrowsError(try WhisperOutputParser.parseSegments(jsonURL: url, speaker: .person1))
    }

    func testParseSegmentsThrowsOnNoTranscriptionData() throws {
        let json: [String: Any] = ["other_key": "value"]
        let url = try writeJSON(json)
        XCTAssertThrowsError(try WhisperOutputParser.parseSegments(jsonURL: url, speaker: .person1))
    }

    func testParseSegmentsHandlesMissingOffsets() throws {
        let json: [String: Any] = [
            "transcription": [
                ["text": "No offsets here"]
            ]
        ]
        let url = try writeJSON(json)
        let segments = try WhisperOutputParser.parseSegments(jsonURL: url, speaker: .person1)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].start, 0.0)
        XCTAssertEqual(segments[0].end, 0.0)
    }

    // MARK: - parsePlainText

    func testParsePlainTextFromTranscriptionArray() throws {
        let json: [String: Any] = [
            "transcription": [
                ["text": "Hello"],
                ["text": "world"]
            ]
        ]
        let url = try writeJSON(json)
        let text = try WhisperOutputParser.parsePlainText(jsonURL: url)

        XCTAssertEqual(text, "Hello world")
    }

    func testParsePlainTextFromTextKey() throws {
        let json: [String: Any] = ["text": "Direct text content"]
        let url = try writeJSON(json)
        let text = try WhisperOutputParser.parsePlainText(jsonURL: url)

        XCTAssertEqual(text, "Direct text content")
    }

    func testParsePlainTextThrowsOnEmptyTranscription() throws {
        let json: [String: Any] = [
            "transcription": [[String: Any]]()
        ]
        let url = try writeJSON(json)
        XCTAssertThrowsError(try WhisperOutputParser.parsePlainText(jsonURL: url))
    }

    func testParsePlainTextTrimsWhitespace() throws {
        let json: [String: Any] = ["text": "  trimmed  "]
        let url = try writeJSON(json)
        let text = try WhisperOutputParser.parsePlainText(jsonURL: url)

        XCTAssertEqual(text, "trimmed")
    }

    func testParsePlainTextThrowsOnMissingFile() {
        let url = tempDir.appendingPathComponent("nonexistent.json")
        XCTAssertThrowsError(try WhisperOutputParser.parsePlainText(jsonURL: url))
    }
}
