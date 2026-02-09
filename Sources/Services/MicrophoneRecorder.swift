import AVFoundation
import Foundation

final class MicrophoneRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private let outputURL: URL
    private var isRecording = false

    weak var bufferDelegate: AudioBufferDelegate?

    init(outputURL: URL) {
        self.outputURL = outputURL
        Log.audio.debug("MicrophoneRecorder initialized with output: \(outputURL.lastPathComponent)")
    }

    func checkPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.audio.debug("Microphone authorization status: \(String(describing: status))")

        switch status {
        case .authorized:
            Log.audio.debug("Microphone already authorized")
            return true
        case .notDetermined:
            Log.audio.info("Requesting microphone permission...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            Log.audio.info("Microphone permission \(granted ? "granted" : "denied")")
            return granted
        case .denied, .restricted:
            Log.audio.error("Microphone permission denied or restricted")
            return false
        @unknown default:
            Log.audio.error("Unknown microphone authorization status")
            return false
        }
    }

    func start() throws {
        Log.audio.info("Starting microphone recording with AVAudioEngine...")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let inputFormat = inputNode.outputFormat(forBus: 0)
        Log.audio.debug("Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            Log.audio.error("Failed to create target audio format")
            throw RecordingError.initializationFailed
        }

        audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: targetFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            Log.audio.error("Failed to create audio converter")
            throw RecordingError.initializationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        isRecording = true
        Log.audio.info("Microphone recording started")
    }

    func stop() {
        Log.audio.info("Stopping microphone recording...")
        guard isRecording else {
            Log.audio.debug("Not recording, ignoring stop")
            return
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false
        Log.audio.info("Microphone recording stopped")
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return
        }

        var error: NSError?
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

        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        guard status != .error, outputBuffer.frameLength > 0 else {
            if let error = error {
                Log.audio.error("Audio conversion error: \(error.localizedDescription)")
            }
            return
        }

        do {
            try audioFile?.write(from: outputBuffer)
        } catch {
            Log.audio.error("Error writing audio buffer: \(error.localizedDescription)")
        }

        bufferDelegate?.audioRecorder(didReceiveBuffer: outputBuffer, speaker: .person1)
    }

    enum RecordingError: LocalizedError {
        case initializationFailed
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .initializationFailed:
                return "Failed to initialize microphone recorder"
            case .recordingFailed:
                return "Failed to start microphone recording"
            }
        }
    }
}
