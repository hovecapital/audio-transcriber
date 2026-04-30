import Foundation

enum WhisperOutputParser {
    enum ParseError: LocalizedError {
        case fileNotFound(String)
        case invalidJSON
        case noTranscriptionData

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "Whisper output file not found: \(path)"
            case .invalidJSON:
                return "Failed to parse whisper JSON output"
            case .noTranscriptionData:
                return "No transcription data found in whisper output"
            }
        }
    }

    static func parseSegments(jsonURL: URL, speaker: TranscriptSegment.Speaker) throws -> [TranscriptSegment] {
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw ParseError.fileNotFound(jsonURL.lastPathComponent)
        }

        let data = try Data(contentsOf: jsonURL)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }

        let keys = Array(json.keys)
        Log.transcription.debug("Whisper JSON keys: \(keys.joined(separator: ", "))")

        if let transcription = json["transcription"] as? [[String: Any]] {
            Log.transcription.info("Transcription array has \(transcription.count) entries")

            let segments = transcription.compactMap { segment -> TranscriptSegment? in
                guard let text = segment["text"] as? String else { return nil }

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }

                let start = (segment["offsets"] as? [String: Any])?["from"] as? Int ?? 0
                let end = (segment["offsets"] as? [String: Any])?["to"] as? Int ?? 0

                return TranscriptSegment(
                    start: TimeInterval(start) / 1000.0,
                    end: TimeInterval(end) / 1000.0,
                    text: trimmed,
                    speaker: speaker
                )
            }

            Log.transcription.info("After filtering empty segments: \(segments.count) of \(transcription.count) entries retained")
            return segments
        }

        if let text = json["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                Log.transcription.warning("Whisper JSON 'text' field was empty")
                return []
            }
            Log.transcription.info("Parsed single text block from whisper output")
            return [TranscriptSegment(start: 0, end: 0, text: trimmed, speaker: speaker)]
        }

        throw ParseError.noTranscriptionData
    }

    static func parsePlainText(jsonURL: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw ParseError.fileNotFound(jsonURL.lastPathComponent)
        }

        let data = try Data(contentsOf: jsonURL)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }

        if let transcription = json["transcription"] as? [[String: Any]] {
            let text = transcription
                .compactMap { $0["text"] as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            guard !text.isEmpty else {
                throw ParseError.noTranscriptionData
            }
            return text
        }

        if let text = json["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ParseError.noTranscriptionData
            }
            return trimmed
        }

        throw ParseError.noTranscriptionData
    }
}
