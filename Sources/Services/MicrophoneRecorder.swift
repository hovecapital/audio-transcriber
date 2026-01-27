import AVFoundation
import Foundation

final class MicrophoneRecorder {
    private var audioRecorder: AVAudioRecorder?
    private let outputURL: URL

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func checkPermission() async -> Bool {
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

    func start() throws {
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
            throw RecordingError.initializationFailed
        }

        recorder.prepareToRecord()

        guard recorder.record() else {
            throw RecordingError.recordingFailed
        }
    }

    func stop() {
        audioRecorder?.stop()
        audioRecorder = nil
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
