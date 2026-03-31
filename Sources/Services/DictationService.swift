import AVFoundation
import AppKit
import Foundation

@MainActor
public final class DictationService: ObservableObject {
    public static let shared = DictationService()

    @Published private(set) var state: DictationStatus = .idle

    private var audioEngine: AVAudioEngine?
    private var accumulatedBuffers: [AVAudioPCMBuffer] = []
    private let bufferQueue = DispatchQueue(label: "com.meetingrecorder.dictation.buffer")
    private let modelsDirectory: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelsDirectory = appSupport.appendingPathComponent("MeetingRecorder/models")
    }

    public func toggle() {
        switch state {
        case .idle:
            startListening()
        case .listening:
            stopAndTranscribe()
        case .transcribing:
            break
        }
    }

    private func startListening() {
        guard !AppState.shared.status.isRecording else {
            Log.dictation.error("Cannot start dictation while meeting recording is active")
            return
        }

        guard AccessibilityReader.isTrusted(promptIfNeeded: true) else {
            Log.dictation.error("Accessibility permission not granted")
            return
        }

        Task {
            let hasPermission = await checkMicPermission()
            guard hasPermission else {
                Log.dictation.error("Microphone permission not granted")
                return
            }

            do {
                try startAudioCapture()
                state = .listening
                AppState.shared.dictationStatus = .listening
                Log.dictation.info("Dictation listening started")
            } catch {
                Log.dictation.error("Failed to start audio capture: \(error.localizedDescription)")
            }
        }
    }

    private func checkMicPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func startAudioCapture() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw DictationError.initializationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw DictationError.initializationFailed
        }

        bufferQueue.sync { accumulatedBuffers.removeAll() }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return
        }

        var inputConsumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        guard status != .error, outputBuffer.frameLength > 0 else { return }

        bufferQueue.async { [weak self] in
            self?.accumulatedBuffers.append(outputBuffer)
        }
    }

    private func stopAndTranscribe() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        state = .transcribing
        AppState.shared.dictationStatus = .transcribing
        Log.dictation.info("Dictation stopped, starting transcription")

        let buffers = bufferQueue.sync { () -> [AVAudioPCMBuffer] in
            let result = accumulatedBuffers
            accumulatedBuffers.removeAll()
            return result
        }

        guard !buffers.isEmpty else {
            Log.dictation.info("No audio buffers captured")
            resetState()
            return
        }

        Task {
            do {
                let text = try await transcribe(buffers: buffers)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    Log.dictation.info("Transcription returned empty text")
                    resetState()
                    return
                }

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(trimmed, forType: .string)
                Log.dictation.info("Dictation text copied to clipboard")

                let inserted = AccessibilityReader.insertTextAtCursor(trimmed, preserveClipboard: false)
                if inserted {
                    Log.dictation.info("Dictation text inserted: \(trimmed.prefix(50))...")
                } else {
                    Log.dictation.info("Text available on clipboard for Cmd+V")
                }
            } catch {
                Log.dictation.error("Dictation transcription failed: \(error.localizedDescription)")
            }

            resetState()
        }
    }

    private func transcribe(buffers: [AVAudioPCMBuffer]) async throws -> String {
        let tempWAV = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation_\(UUID().uuidString).wav")

        try writeBuffersToWAV(buffers, url: tempWAV)
        defer { try? FileManager.default.removeItem(at: tempWAV) }

        let wavValidation = WAVFileValidator.validate(url: tempWAV)
        Log.dictation.info("WAV validation: size=\(wavValidation.fileSize), hasAudio=\(wavValidation.hasAudioData)")
        guard wavValidation.isValid else {
            throw DictationError.transcriptionFailed
        }

        let whisperPath = findWhisperExecutable()
        guard let whisperPath else {
            throw DictationError.whisperNotFound
        }

        let config = ConfigManager.shared.load()
        let modelPath = modelsDirectory.appendingPathComponent("ggml-\(config.whisperModelSize.rawValue).bin")
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw DictationError.modelNotFound
        }

        let outputPath = tempWAV.deletingPathExtension().appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: outputPath) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        process.arguments = [
            "-m", modelPath.path,
            "-f", tempWAV.path,
            "-oj",
            "-of", outputPath.deletingPathExtension().path,
            "--no-timestamps"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                let outputString = String(data: outputData, encoding: .utf8) ?? ""
                Log.dictation.info("Whisper exited with code: \(proc.terminationStatus)")
                Log.dictation.debug("Whisper output: \(outputString.prefix(2000))")

                guard proc.terminationStatus == 0 else {
                    continuation.resume(throwing: DictationError.transcriptionFailed)
                    return
                }

                do {
                    let text = try WhisperOutputParser.parsePlainText(jsonURL: outputPath)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
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

    private func resetState() {
        state = .idle
        AppState.shared.dictationStatus = .idle
    }

    enum DictationError: LocalizedError {
        case initializationFailed
        case whisperNotFound
        case modelNotFound
        case transcriptionFailed

        var errorDescription: String? {
            switch self {
            case .initializationFailed:
                return "Failed to initialize dictation audio capture"
            case .whisperNotFound:
                return "Whisper executable not found"
            case .modelNotFound:
                return "Whisper model not found"
            case .transcriptionFailed:
                return "Dictation transcription failed"
            }
        }
    }
}
