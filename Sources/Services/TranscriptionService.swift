import Foundation

final class TranscriptionService {
    private let modelSize: AppConfig.WhisperModelSize
    private let modelsDirectory: URL

    init(modelSize: AppConfig.WhisperModelSize = .base) {
        self.modelSize = modelSize
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelsDirectory = appSupport.appendingPathComponent("MeetingRecorder/models")
    }

    func transcribe(
        audioURL: URL,
        speaker: TranscriptSegment.Speaker,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> [TranscriptSegment] {
        progressHandler(0.1, "Preparing transcription...")

        let whisperPath = findWhisperExecutable()

        guard let whisperPath = whisperPath else {
            throw TranscriptionError.whisperNotFound
        }

        let modelPath = modelsDirectory.appendingPathComponent("ggml-\(modelSize.rawValue).bin")

        if !FileManager.default.fileExists(atPath: modelPath.path) {
            progressHandler(0.2, "Downloading Whisper model...")
            try await downloadModel(modelSize: modelSize, to: modelPath)
        }

        progressHandler(0.3, "Running transcription...")

        let outputPath = audioURL.deletingPathExtension().appendingPathExtension("json")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        process.arguments = [
            "-m", modelPath.path,
            "-f", audioURL.path,
            "-oj",
            "-of", outputPath.deletingPathExtension().path,
            "--no-timestamps"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        progressHandler(0.8, "Processing results...")

        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.transcriptionFailed(errorString)
        }

        let segments = try parseWhisperOutput(jsonURL: outputPath, speaker: speaker)

        try? FileManager.default.removeItem(at: outputPath)

        progressHandler(1.0, "Transcription complete")

        return segments
    }

    private func findWhisperExecutable() -> String? {
        let possiblePaths = [
            "/usr/local/bin/whisper",
            "/opt/homebrew/bin/whisper",
            "/usr/bin/whisper",
            Bundle.main.path(forResource: "whisper", ofType: nil)
        ].compactMap { $0 }

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["whisper"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        try? whichProcess.run()
        whichProcess.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let path = path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }

    private func downloadModel(modelSize: AppConfig.WhisperModelSize, to destination: URL) async throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(modelSize.rawValue).bin")!

        let (tempURL, response) = try await URLSession.shared.download(from: modelURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TranscriptionError.modelDownloadFailed
        }

        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    private func parseWhisperOutput(jsonURL: URL, speaker: TranscriptSegment.Speaker) throws -> [TranscriptSegment] {
        let data = try Data(contentsOf: jsonURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let transcription = json?["transcription"] as? [[String: Any]] else {
            if let text = json?["text"] as? String {
                return [TranscriptSegment(start: 0, end: 0, text: text.trimmingCharacters(in: .whitespacesAndNewlines), speaker: speaker)]
            }
            throw TranscriptionError.parseError
        }

        return transcription.compactMap { segment -> TranscriptSegment? in
            guard let text = segment["text"] as? String else { return nil }

            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return nil }

            let start = (segment["offsets"] as? [String: Any])?["from"] as? Int ?? 0
            let end = (segment["offsets"] as? [String: Any])?["to"] as? Int ?? 0

            return TranscriptSegment(
                start: TimeInterval(start) / 1000.0,
                end: TimeInterval(end) / 1000.0,
                text: trimmedText,
                speaker: speaker
            )
        }
    }

    enum TranscriptionError: LocalizedError {
        case whisperNotFound
        case modelDownloadFailed
        case transcriptionFailed(String)
        case parseError

        var errorDescription: String? {
            switch self {
            case .whisperNotFound:
                return "Whisper not found. Please install whisper.cpp: brew install whisper-cpp"
            case .modelDownloadFailed:
                return "Failed to download Whisper model"
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            case .parseError:
                return "Failed to parse transcription output"
            }
        }
    }
}
