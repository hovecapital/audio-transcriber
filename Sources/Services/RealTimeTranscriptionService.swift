import AVFoundation
import Foundation

final class RealTimeTranscriptionService {
    private let modelSize: AppConfig.WhisperModelSize
    private let chunkIntervalSeconds: Double
    private let modelsDirectory: URL

    private var accumulatedBuffers: [(buffer: AVAudioPCMBuffer, speaker: TranscriptSegment.Speaker)] = []
    private var chunkStartTime: Date?
    private var recordingStartTime: Date?
    private let bufferQueue = DispatchQueue(label: "com.meetingrecorder.transcription.buffer")

    var onSegmentsReady: (([TranscriptSegment]) -> Void)?

    init(modelSize: AppConfig.WhisperModelSize, chunkIntervalSeconds: Double) {
        self.modelSize = modelSize
        self.chunkIntervalSeconds = chunkIntervalSeconds
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelsDirectory = appSupport.appendingPathComponent("MeetingRecorder/models")
        Log.transcription.info("RealTimeTranscriptionService initialized: model=\(modelSize.rawValue), interval=\(chunkIntervalSeconds)s")
    }

    func startSession() {
        bufferQueue.sync {
            accumulatedBuffers.removeAll()
            chunkStartTime = Date()
            recordingStartTime = Date()
        }
        Log.transcription.info("Real-time transcription session started")
    }

    func addBuffer(_ buffer: AVAudioPCMBuffer, speaker: TranscriptSegment.Speaker) {
        bufferQueue.async { [weak self] in
            self?.accumulatedBuffers.append((buffer, speaker))
        }
    }

    func shouldTranscribe() -> Bool {
        guard let chunkStart = chunkStartTime else { return false }
        return Date().timeIntervalSince(chunkStart) >= chunkIntervalSeconds
    }

    func processAccumulatedBuffers() async throws -> [TranscriptSegment] {
        let (micBuffers, systemBuffers, baseTime) = bufferQueue.sync { () -> ([AVAudioPCMBuffer], [AVAudioPCMBuffer], TimeInterval) in
            let mic = accumulatedBuffers.filter { $0.speaker == .person1 }.map { $0.buffer }
            let system = accumulatedBuffers.filter { $0.speaker == .person2 }.map { $0.buffer }
            let base = recordingStartTime.map { chunkStartTime?.timeIntervalSince($0) ?? 0 } ?? 0
            accumulatedBuffers.removeAll()
            chunkStartTime = Date()
            return (mic, system, base)
        }

        var allSegments: [TranscriptSegment] = []

        if !micBuffers.isEmpty {
            let micSegments = try await transcribeBuffers(micBuffers, speaker: .person1, baseTime: baseTime)
            allSegments.append(contentsOf: micSegments)
        }

        if !systemBuffers.isEmpty {
            let systemSegments = try await transcribeBuffers(systemBuffers, speaker: .person2, baseTime: baseTime)
            allSegments.append(contentsOf: systemSegments)
        }

        allSegments.sort { $0.start < $1.start }

        if !allSegments.isEmpty {
            onSegmentsReady?(allSegments)
        }

        return allSegments
    }

    func stopSession() {
        bufferQueue.sync {
            accumulatedBuffers.removeAll()
            chunkStartTime = nil
            recordingStartTime = nil
        }
        Log.transcription.info("Real-time transcription session stopped")
    }

    private func transcribeBuffers(_ buffers: [AVAudioPCMBuffer], speaker: TranscriptSegment.Speaker, baseTime: TimeInterval) async throws -> [TranscriptSegment] {
        guard !buffers.isEmpty else { return [] }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk_\(UUID().uuidString).wav")

        try writeBuffersToWAV(buffers, url: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let segments = try await runWhisperTranscription(audioURL: tempURL, speaker: speaker)

        return segments.map { segment in
            TranscriptSegment(
                start: segment.start + baseTime,
                end: segment.end + baseTime,
                text: segment.text,
                speaker: segment.speaker
            )
        }
    }

    private func writeBuffersToWAV(_ buffers: [AVAudioPCMBuffer], url: URL) throws {
        guard let firstBuffer = buffers.first else { return }

        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: firstBuffer.format.settings,
            commonFormat: firstBuffer.format.commonFormat,
            interleaved: firstBuffer.format.isInterleaved
        )

        for buffer in buffers {
            try audioFile.write(from: buffer)
        }
    }

    private func runWhisperTranscription(audioURL: URL, speaker: TranscriptSegment.Speaker) async throws -> [TranscriptSegment] {
        let whisperPath = findWhisperExecutable()
        guard let whisperPath = whisperPath else {
            throw TranscriptionError.whisperNotFound
        }

        let modelPath = modelsDirectory.appendingPathComponent("ggml-\(modelSize.rawValue).bin")
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw TranscriptionError.modelNotFound
        }

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

        guard process.terminationStatus == 0 else {
            throw TranscriptionError.transcriptionFailed
        }

        defer { try? FileManager.default.removeItem(at: outputPath) }

        return try parseWhisperOutput(jsonURL: outputPath, speaker: speaker)
    }

    private func findWhisperExecutable() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/opt/homebrew/bin/whisper",
            "/usr/local/bin/whisper-cpp",
            "/usr/local/bin/whisper"
        ]

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func parseWhisperOutput(jsonURL: URL, speaker: TranscriptSegment.Speaker) throws -> [TranscriptSegment] {
        let data = try Data(contentsOf: jsonURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let transcription = json?["transcription"] as? [[String: Any]] else {
            if let text = json?["text"] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return [] }
                return [TranscriptSegment(start: 0, end: 0, text: trimmed, speaker: speaker)]
            }
            throw TranscriptionError.parseError
        }

        return transcription.compactMap { segment -> TranscriptSegment? in
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
    }

    enum TranscriptionError: LocalizedError {
        case whisperNotFound
        case modelNotFound
        case transcriptionFailed
        case parseError

        var errorDescription: String? {
            switch self {
            case .whisperNotFound:
                return "Whisper executable not found"
            case .modelNotFound:
                return "Whisper model not found"
            case .transcriptionFailed:
                return "Transcription failed"
            case .parseError:
                return "Failed to parse transcription output"
            }
        }
    }
}
