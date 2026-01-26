import Foundation

struct MarkdownGenerator {
    private let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func generate(
        micSegments: [TranscriptSegment],
        systemSegments: [TranscriptSegment],
        session: RecordingSession
    ) -> String {
        var allSegments = micSegments + systemSegments
        allSegments.sort { $0.start < $1.start }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy 'at' h:mm a"

        var markdown = """
        # Meeting Transcript

        **Date:** \(dateFormatter.string(from: session.startTime))
        **Duration:** \(session.formattedDuration)

        ---

        """

        for segment in allSegments {
            let speakerLabel = segment.speaker == .person1 ? config.person1Label : config.person2Label
            let timestamp = formatTimestamp(segment.start)

            markdown += "\n\(timestamp) **\(speakerLabel):** \(segment.text)\n"
        }

        return markdown
    }

    func save(markdown: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "[%02d:%02d]", minutes, secs)
    }

    static func generateFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "meeting_\(formatter.string(from: date)).md"
    }
}
