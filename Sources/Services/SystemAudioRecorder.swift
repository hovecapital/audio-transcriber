import AVFoundation
import Foundation
import ScreenCaptureKit

@available(macOS 13.0, *)
final class SystemAudioRecorder: NSObject {
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private let outputURL: URL
    private var isRecording = false
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    init(outputURL: URL) {
        self.outputURL = outputURL
        super.init()
        Log.audio.debug("SystemAudioRecorder initialized with output: \(outputURL.lastPathComponent)")
    }

    func checkPermission() async -> Bool {
        Log.audio.debug("Checking screen recording permission...")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let hasPermission = !content.displays.isEmpty
            Log.audio.debug("Screen recording permission: \(hasPermission ? "granted" : "denied")")
            return hasPermission
        } catch {
            Log.audio.error("Screen recording permission check failed: \(error.localizedDescription)")
            return false
        }
    }

    func start() async throws {
        Log.audio.info("Starting system audio recording...")

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        Log.audio.debug("Found \(content.displays.count) displays")

        guard let display = content.displays.first else {
            Log.audio.error("No display found for screen capture")
            throw RecordingError.noDisplayFound
        }

        Log.audio.debug("Using display: \(display.displayID)")

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

        Log.audio.debug("Stream config: sampleRate=16000, channels=1, excludesSelf=true")

        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!
        targetFormat = format

        audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        Log.audio.debug("Audio file created for writing")

        stream = SCStream(filter: filter, configuration: config, delegate: self)

        guard let stream = stream else {
            Log.audio.error("Failed to create SCStream")
            throw RecordingError.streamCreationFailed
        }

        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        Log.audio.debug("Stream output handler added")

        try await stream.startCapture()
        isRecording = true
        Log.audio.info("System audio recording started")
    }

    func stop() async {
        Log.audio.info("Stopping system audio recording...")
        guard isRecording, let stream = stream else {
            Log.audio.debug("Not recording, ignoring stop")
            return
        }

        do {
            try await stream.stopCapture()
            Log.audio.info("System audio recording stopped")
        } catch {
            Log.audio.error("Error stopping stream: \(error.localizedDescription)")
        }

        self.stream = nil
        audioFile = nil
        converter = nil
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
        Log.audio.error("Stream stopped with error: \(error.localizedDescription)")
        isRecording = false
    }
}

@available(macOS 13.0, *)
extension SystemAudioRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let audioFile = audioFile, let targetFormat = targetFormat else { return }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard status == kCMBlockBufferNoErr, let data = dataPointer, length > 0 else { return }

        let incomingSampleRate = asbd.pointee.mSampleRate
        let incomingChannels = asbd.pointee.mChannelsPerFrame
        let bytesPerFrame = asbd.pointee.mBytesPerFrame
        let isFloat = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        let frameCount = length / Int(bytesPerFrame)
        guard frameCount > 0 else { return }

        let commonFormat: AVAudioCommonFormat = isFloat ? .pcmFormatFloat32 : .pcmFormatInt16

        guard let incomingFormat = AVAudioFormat(
            commonFormat: commonFormat,
            sampleRate: incomingSampleRate,
            channels: AVAudioChannelCount(incomingChannels),
            interleaved: !isNonInterleaved
        ) else { return }

        if converter == nil {
            Log.audio.debug("Incoming audio: \(incomingSampleRate)Hz, \(incomingChannels)ch, float=\(isFloat), nonInterleaved=\(isNonInterleaved), bytesPerFrame=\(bytesPerFrame)")
            converter = AVAudioConverter(from: incomingFormat, to: targetFormat)
            if converter == nil {
                Log.audio.error("Failed to create audio converter from \(incomingFormat) to \(targetFormat)")
                return
            }
        }

        guard let converter = converter else { return }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: incomingFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }
        inputBuffer.frameLength = AVAudioFrameCount(frameCount)

        if isFloat {
            if let floatData = inputBuffer.floatChannelData {
                memcpy(floatData[0], data, length)
            }
        } else {
            if let int16Data = inputBuffer.int16ChannelData {
                memcpy(int16Data[0], data, length)
            }
        }

        let ratio = targetFormat.sampleRate / incomingFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return
        }

        var convError: NSError?
        var inputConsumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        let convStatus = converter.convert(to: outputBuffer, error: &convError, withInputFrom: inputBlock)

        if convStatus == .error {
            Log.audio.error("Audio conversion failed: \(convError?.localizedDescription ?? "unknown")")
            return
        }

        guard outputBuffer.frameLength > 0 else { return }

        do {
            try audioFile.write(from: outputBuffer)
        } catch {
            Log.audio.error("Error writing audio buffer: \(error.localizedDescription)")
        }
    }
}
