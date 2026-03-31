import Foundation
import XCTest

@testable import MeetingRecorderCore

final class MarkdownGeneratorTests: XCTestCase {
    private func makeConfig() -> AppConfig {
        var config = AppConfig.default
        config.person1Label = "Alice"
        config.person2Label = "Bob"
        return config
    }

    private func makeSession(
        start: Date = Date(timeIntervalSince1970: 1_000_000),
        duration: TimeInterval = 300
    ) -> RecordingSession {
        return RecordingSession(
            id: UUID(),
            startTime: start,
            endTime: start.addingTimeInterval(duration),
            micFilePath: URL(fileURLWithPath: "/tmp/mic.wav"),
            systemFilePath: URL(fileURLWithPath: "/tmp/sys.wav"),
            status: .idle
        )
    }

    func testBasicTranscriptGeneration() {
        let generator = MarkdownGenerator(config: makeConfig())
        let session = makeSession()

        let micSegments = [
            TranscriptSegment(start: 0, end: 5, text: "Hello from Alice", speaker: .person1),
            TranscriptSegment(start: 10, end: 15, text: "Another Alice line", speaker: .person1)
        ]
        let systemSegments = [
            TranscriptSegment(start: 5, end: 10, text: "Hello from Bob", speaker: .person2)
        ]

        let markdown = generator.generate(
            micSegments: micSegments,
            systemSegments: systemSegments,
            session: session
        )

        XCTAssertTrue(markdown.contains("Meeting Transcript"))
        XCTAssertTrue(markdown.contains("Alice"))
        XCTAssertTrue(markdown.contains("Bob"))
        XCTAssertTrue(markdown.contains("Hello from Alice"))
        XCTAssertTrue(markdown.contains("Hello from Bob"))
        XCTAssertTrue(markdown.contains("Another Alice line"))
    }

    func testSegmentsAreSortedByTimestamp() {
        let generator = MarkdownGenerator(config: makeConfig())
        let session = makeSession()

        let micSegments = [
            TranscriptSegment(start: 10, end: 15, text: "Second", speaker: .person1)
        ]
        let systemSegments = [
            TranscriptSegment(start: 0, end: 5, text: "First", speaker: .person2)
        ]

        let markdown = generator.generate(
            micSegments: micSegments,
            systemSegments: systemSegments,
            session: session
        )

        let firstIndex = markdown.range(of: "First")!.lowerBound
        let secondIndex = markdown.range(of: "Second")!.lowerBound
        XCTAssertTrue(firstIndex < secondIndex)
    }

    func testTimestampFormatting() {
        let generator = MarkdownGenerator(config: makeConfig())
        let session = makeSession()

        let micSegments = [
            TranscriptSegment(start: 125, end: 130, text: "Test", speaker: .person1)
        ]

        let markdown = generator.generate(
            micSegments: micSegments,
            systemSegments: [],
            session: session
        )

        XCTAssertTrue(markdown.contains("[02:05]"))
    }

    func testFilenameGeneration() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let filename = MarkdownGenerator.generateFilename(for: date)

        XCTAssertTrue(filename.hasPrefix("meeting_"))
        XCTAssertTrue(filename.hasSuffix(".md"))
    }

    func testEmptySegments() {
        let generator = MarkdownGenerator(config: makeConfig())
        let session = makeSession()

        let markdown = generator.generate(
            micSegments: [],
            systemSegments: [],
            session: session
        )

        XCTAssertTrue(markdown.contains("Meeting Transcript"))
        XCTAssertFalse(markdown.contains("Alice:"))
        XCTAssertFalse(markdown.contains("Bob:"))
    }

    func testSaveCreatesFile() throws {
        let generator = MarkdownGenerator(config: makeConfig())
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputURL = tempDir.appendingPathComponent("test_transcript.md")
        try generator.save(markdown: "# Test", to: outputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let contents = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertEqual(contents, "# Test")
    }
}
