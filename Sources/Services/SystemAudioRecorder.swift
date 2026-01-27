import AVFoundation
import Foundation
import ScreenCaptureKit

@available(macOS 13.0, *)
final class SystemAudioRecorder: NSObject {
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private let outputURL: URL
    private var isRecording = false

    init(outputURL: URL) {
        self.outputURL = outputURL
        super.init()
    }

    func checkPermission() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return !content.displays.isEmpty
        } catch {
            return false
        }
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw RecordingError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000
        config.channelCount = 1

        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        stream = SCStream(filter: filter, configuration: config, delegate: self)

        guard let stream = stream else {
            throw RecordingError.streamCreationFailed
        }

        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        try await stream.startCapture()
        isRecording = true
    }

    func stop() async {
        guard isRecording, let stream = stream else { return }

        do {
            try await stream.stopCapture()
        } catch {
            print("Error stopping stream: \(error)")
        }

        self.stream = nil
        audioFile = nil
        isRecording = false
    }

    enum RecordingError: LocalizedError {
        case noDisplayFound
        case streamCreationFailed
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .noDisplayFound:
                return "No display found for screen capture"
            case .streamCreationFailed:
                return "Failed to create screen capture stream"
            case .permissionDenied:
                return "Screen recording permission denied"
            }
        }
    }
}

@available(macOS 13.0, *)
extension SystemAudioRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error)")
        isRecording = false
    }
}

@available(macOS 13.0, *)
extension SystemAudioRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let audioFile = audioFile else { return }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard status == kCMBlockBufferNoErr, let data = dataPointer else { return }

        let frameCount = length / Int(asbd.pointee.mBytesPerFrame)
        guard frameCount > 0 else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(asbd.pointee.mSampleRate),
                channels: AVAudioChannelCount(asbd.pointee.mChannelsPerFrame),
                interleaved: true
            )!,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return }

        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        if let int16Data = pcmBuffer.int16ChannelData {
            memcpy(int16Data[0], data, length)
        }

        do {
            try audioFile.write(from: pcmBuffer)
        } catch {
            print("Error writing audio: \(error)")
        }
    }
}
