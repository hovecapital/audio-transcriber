import Foundation

final class TranscriptionService {
    private let modelSize: AppConfig.WhisperModelSize
    private let modelsDirectory: URL

    init(modelSize: AppConfig.WhisperModelSize = .base) {
        self.modelSize = modelSize
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelsDirectory = appSupport.appendingPathComponent("MeetingRecorder/models")
        Log.transcription.info("TranscriptionService initialized with model size: \(modelSize.rawValue)")
        Log.transcription.debug("Models directory: \(self.modelsDirectory.path)")
    }

    func transcribe(
        audioURL: URL,
        speaker: TranscriptSegment.Speaker,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> [TranscriptSegment] {
        Log.transcription.info("Starting transcription for: \(audioURL.lastPathComponent)")
        progressHandler(0.1, "Preparing transcription...")

        let whisperPath = findWhisperExecutable()

        guard let whisperPath = whisperPath else {
            Log.transcription.error("Whisper executable not found")
            throw TranscriptionError.whisperNotFound
        }

        Log.transcription.info("Using whisper at: \(whisperPath)")

        let modelPath = modelsDirectory.appendingPathComponent("ggml-\(modelSize.rawValue).bin")
        Log.transcription.debug("Model path: \(modelPath.path)")

        if !FileManager.default.fileExists(atPath: modelPath.path) {
            Log.transcription.info("Model not found locally, downloading...")
            progressHandler(0.2, "Downloading Whisper model...")
            try await downloadModel(modelSize: modelSize, to: modelPath)
            Log.transcription.info("Model downloaded successfully")
        } else {
            Log.transcription.debug("Model already exists locally")
        }

        progressHandler(0.3, "Running transcription...")

        let wavValidation = WAVFileValidator.validate(url: audioURL)
        Log.transcription.info("WAV validation for \(audioURL.lastPathComponent): size=\(wavValidation.fileSize), hasAudio=\(wavValidation.hasAudioData)")
        guard wavValidation.isValid else {
            Log.transcription.error("Invalid WAV file: \(wavValidation.errorMessage ?? "unknown")")
            throw TranscriptionError.transcriptionFailed(wavValidation.errorMessage ?? "Invalid audio file")
        }

        let outputPath = audioURL.deletingPathExtension().appendingPathExtension("json")
        Log.transcription.debug("Output path: \(outputPath.path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        process.arguments = [
            "-m", modelPath.path,
            "-f", audioURL.path,
            "-oj",
            "-of", outputPath.deletingPathExtension().path,
            "--no-timestamps"
        ]

        Log.transcription.debug("Whisper arguments: \(process.arguments?.joined(separator: " ") ?? "")")

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        Log.transcription.info("Launching whisper process...")
        let launchTime = Date()
        try process.run()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let elapsed = Date().timeIntervalSince(launchTime)
        let exitCode = process.terminationStatus
        let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
        Log.transcription.info("Whisper process exited with code: \(exitCode) in \(String(format: "%.1f", elapsed))s")
        Log.transcription.debug("Whisper stdout: \(stdoutString.prefix(2000))")
        if !stderrString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Log.transcription.warning("Whisper stderr: \(stderrString.prefix(2000))")
        }

        progressHandler(0.8, "Processing results...")

        guard exitCode == 0 else {
            let combinedOutput = [stdoutString, stderrString].filter { !$0.isEmpty }.joined(separator: "\n")
            Log.transcription.error("Whisper failed: \(combinedOutput)")
            throw TranscriptionError.transcriptionFailed(combinedOutput)
        }

        let segments = try WhisperOutputParser.parseSegments(jsonURL: outputPath, speaker: speaker)
        Log.transcription.info("Parsed \(segments.count) transcript segments")

        try? FileManager.default.removeItem(at: outputPath)

        progressHandler(1.0, "Transcription complete")
        Log.transcription.info("Transcription completed successfully")

        return segments
    }

    private func findWhisperExecutable() -> String? {
        Log.transcription.info("Searching for whisper executable...")

        let possiblePaths = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/opt/homebrew/bin/whisper.cpp",
            "/opt/homebrew/bin/whisper",
            "/usr/local/bin/whisper-cpp",
            "/usr/local/bin/whisper.cpp",
            "/usr/local/bin/whisper",
            "/usr/bin/whisper",
            Bundle.main.path(forResource: "whisper-cli", ofType: nil),
            Bundle.main.path(forResource: "whisper", ofType: nil),
            Bundle.main.path(forResource: "whisper-cpp", ofType: nil)
        ].compactMap { $0 }

        for path in possiblePaths {
            let exists = FileManager.default.isExecutableFile(atPath: path)
            Log.transcription.debug("Checking \(path): \(exists ? "FOUND" : "not found")")
            if exists {
                Log.transcription.info("Found whisper at: \(path)")
                return path
            }
        }

        Log.transcription.debug("Trying 'which' command for whisper variants...")

        let executableNames = ["whisper-cli", "whisper-cpp", "whisper.cpp", "whisper"]
        for name in executableNames {
            let whichProcess = Process()
            whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            whichProcess.arguments = [name]
            let pipe = Pipe()
            whichProcess.standardOutput = pipe
            whichProcess.standardError = FileHandle.nullDevice
            try? whichProcess.run()
            whichProcess.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let path = path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                Log.transcription.info("Found \(name) via which: \(path)")
                return path
            }
        }

        Log.transcription.error("No whisper executable found in any location")
        return nil
    }

    private func downloadModel(modelSize: AppConfig.WhisperModelSize, to destination: URL) async throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(modelSize.rawValue).bin")!
        Log.transcription.info("Downloading model from: \(modelURL)")

        let (tempURL, response) = try await URLSession.shared.download(from: modelURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            Log.transcription.error("Model download failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw TranscriptionError.modelDownloadFailed
        }

        try FileManager.default.moveItem(at: tempURL, to: destination)
        Log.transcription.info("Model saved to: \(destination.path)")
    }

    enum TranscriptionError: LocalizedError {
        case whisperNotFound
        case modelDownloadFailed
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .whisperNotFound:
                return "Whisper not found. Please install whisper.cpp: brew install whisper-cpp"
            case .modelDownloadFailed:
                return "Failed to download Whisper model"
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            }
        }
    }
}
