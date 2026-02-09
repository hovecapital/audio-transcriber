import AVFoundation
import Combine
import Foundation

@MainActor
final class RealTimeRecordingCoordinator: ObservableObject {
    @Published private(set) var state = RealTimeSessionState()
    @Published private(set) var isEnabled = false

    private var transcriptionService: RealTimeTranscriptionService?
    private var analysisService: LLMAnalysisService?
    private var transcriptionTimer: Timer?
    private var analysisTimer: Timer?
    private var config: AppConfig

    init(config: AppConfig) {
        self.config = config
        self.isEnabled = config.enableRealTimeTranscription
        Log.audio.info("RealTimeRecordingCoordinator initialized: enabled=\(config.enableRealTimeTranscription)")
    }

    func startSession() {
        guard isEnabled else { return }

        state = RealTimeSessionState()

        transcriptionService = RealTimeTranscriptionService(
            modelSize: config.whisperModelSize,
            chunkIntervalSeconds: config.transcriptionChunkIntervalSeconds
        )
        transcriptionService?.onSegmentsReady = { [weak self] segments in
            Task { @MainActor [weak self] in
                self?.appendSegments(segments)
            }
        }
        transcriptionService?.startSession()

        analysisService = LLMAnalysisService(
            provider: config.llmProvider,
            model: config.llmModel
        )

        startTimers()

        Log.audio.info("Real-time session started")
    }

    func stopSession() async -> (segments: [TranscriptSegment], analysis: MeetingAnalysis)? {
        guard isEnabled else { return nil }

        stopTimers()

        if let service = transcriptionService, service.shouldTranscribe() {
            do {
                let finalSegments = try await service.processAccumulatedBuffers()
                appendSegments(finalSegments)
            } catch {
                Log.audio.error("Final transcription failed: \(error.localizedDescription)")
            }
        }

        transcriptionService?.stopSession()
        transcriptionService = nil
        analysisService = nil

        let result = (segments: state.segments, analysis: state.analysis)

        Log.audio.info("Real-time session stopped: \(self.state.segments.count) segments")

        return result
    }

    func updateConfig(_ newConfig: AppConfig) {
        config = newConfig
        isEnabled = newConfig.enableRealTimeTranscription
    }

    private func startTimers() {
        transcriptionTimer = Timer.scheduledTimer(
            withTimeInterval: config.transcriptionChunkIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.runTranscription()
            }
        }

        analysisTimer = Timer.scheduledTimer(
            withTimeInterval: config.llmAnalysisIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.runAnalysis()
            }
        }
    }

    private func stopTimers() {
        transcriptionTimer?.invalidate()
        transcriptionTimer = nil
        analysisTimer?.invalidate()
        analysisTimer = nil
    }

    private func runTranscription() async {
        guard let service = transcriptionService else { return }

        do {
            let segments = try await service.processAccumulatedBuffers()
            if !segments.isEmpty {
                state.lastTranscriptionTime = Date()
            }
        } catch {
            Log.audio.error("Real-time transcription failed: \(error.localizedDescription)")
        }
    }

    private func runAnalysis() async {
        guard let service = analysisService, !state.segments.isEmpty else { return }

        state.isAnalyzing = true

        do {
            let analysis = try await service.analyze(segments: state.segments, config: config)
            state.analysis = analysis
            state.lastAnalysisTime = Date()
            Log.audio.info("Real-time analysis complete")
        } catch {
            Log.audio.error("Real-time analysis failed: \(error.localizedDescription)")
        }

        state.isAnalyzing = false
    }

    private func appendSegments(_ newSegments: [TranscriptSegment]) {
        state.segments.append(contentsOf: newSegments)
        state.segments.sort { $0.start < $1.start }
    }
}

extension RealTimeRecordingCoordinator: AudioBufferDelegate {
    nonisolated func audioRecorder(didReceiveBuffer buffer: AVAudioPCMBuffer, speaker: TranscriptSegment.Speaker) {
        Task { @MainActor in
            transcriptionService?.addBuffer(buffer, speaker: speaker)
        }
    }
}
