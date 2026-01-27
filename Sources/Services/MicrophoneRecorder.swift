import AVFoundation
import Foundation

final class MicrophoneRecorder {
    private var audioRecorder: AVAudioRecorder?
    private let outputURL: URL

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
        Log.audio.info("Starting microphone recording...")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        audioRecorder = try AVAudioRecorder(url: outputURL, settings: settings)

        guard let recorder = audioRecorder else {
            Log.audio.error("Failed to create AVAudioRecorder")
            throw RecordingError.initializationFailed
        }

        recorder.prepareToRecord()
        Log.audio.debug("Microphone recorder prepared")

        guard recorder.record() else {
            Log.audio.error("Failed to start recording")
            throw RecordingError.recordingFailed
        }

        Log.audio.info("Microphone recording started")
    }

    func stop() {
        Log.audio.info("Stopping microphone recording...")
        audioRecorder?.stop()
        audioRecorder = nil
        Log.audio.info("Microphone recording stopped")
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
