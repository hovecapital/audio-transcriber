import AppKit
import Foundation

@MainActor
final class AudioRecordingManager: ObservableObject {
    static let shared = AudioRecordingManager()

    @Published private(set) var isRecording = false
    @Published private(set) var currentSession: RecordingSession?
    @Published private(set) var recordingDuration: TimeInterval = 0

    private var micRecorder: MicrophoneRecorder?
    private var systemRecorder: SystemAudioRecorder?
    private var durationTimer: Timer?

    private let config: AppConfig

    private init() {
        config = ConfigManager.shared.load()
    }

    func startRecording() async throws {
        guard !isRecording else { return }

        let hasPermissions = await checkPermissions()
        guard hasPermissions else {
            throw RecordingManagerError.permissionDenied
        }

        let sessionDir = createSessionDirectory()
        let micURL = sessionDir.appendingPathComponent("microphone.wav")
        let systemURL = sessionDir.appendingPathComponent("system_audio.wav")

        let session = RecordingSession(
            id: UUID(),
            startTime: Date(),
            micFilePath: micURL,
            systemFilePath: systemURL,
            status: .recording
        )

        micRecorder = MicrophoneRecorder(outputURL: micURL)
        systemRecorder = SystemAudioRecorder(outputURL: systemURL)

        try micRecorder?.start()
        try await systemRecorder?.start()

        currentSession = session
        isRecording = true
        recordingDuration = 0

        startDurationTimer()

        await AppState.shared.updateStatus(.recording)
    }

    func stopRecording() async {
        guard isRecording, var session = currentSession else { return }

        stopDurationTimer()

        micRecorder?.stop()
        await systemRecorder?.stop()

        session.endTime = Date()
        currentSession = session

        isRecording = false

        await processRecording(session: session)
    }

    private func processRecording(session: RecordingSession) async {
        let currentConfig = ConfigManager.shared.load()

        await AppState.shared.updateStatus(.processing(progress: 0, message: "Starting transcription..."))

        let transcriptionService = TranscriptionService(modelSize: currentConfig.whisperModelSize)

        do {
            await AppState.shared.updateStatus(.processing(progress: 0.1, message: "Transcribing microphone audio..."))

            let micSegments = try await transcriptionService.transcribe(
                audioURL: session.micFilePath,
                speaker: .person1
            ) { progress, message in
                Task { @MainActor in
                    let overallProgress = 0.1 + (progress * 0.35)
                    AppState.shared.updateStatus(.processing(progress: overallProgress, message: message))
                }
            }

            await AppState.shared.updateStatus(.processing(progress: 0.5, message: "Transcribing system audio..."))

            let systemSegments = try await transcriptionService.transcribe(
                audioURL: session.systemFilePath,
                speaker: .person2
            ) { progress, message in
                Task { @MainActor in
                    let overallProgress = 0.5 + (progress * 0.35)
                    AppState.shared.updateStatus(.processing(progress: overallProgress, message: message))
                }
            }

            await AppState.shared.updateStatus(.processing(progress: 0.9, message: "Generating transcript..."))

            let generator = MarkdownGenerator(config: currentConfig)
            let markdown = generator.generate(
                micSegments: micSegments,
                systemSegments: systemSegments,
                session: session
            )

            let filename = MarkdownGenerator.generateFilename(for: session.startTime)
            let transcriptURL = currentConfig.expandedOutputDirectory.appendingPathComponent(filename)

            try generator.save(markdown: markdown, to: transcriptURL)

            if currentConfig.deleteAudioAfterTranscription {
                try? FileManager.default.removeItem(at: session.micFilePath)
                try? FileManager.default.removeItem(at: session.systemFilePath)
                try? FileManager.default.removeItem(at: session.micFilePath.deletingLastPathComponent())
            }

            await AppState.shared.updateStatus(.completed)

            showCompletionNotification(transcriptURL: transcriptURL)

            if currentConfig.autoOpenTranscript {
                NSWorkspace.shared.open(transcriptURL)
            }

            try await Task.sleep(nanoseconds: 2_000_000_000)
            await AppState.shared.updateStatus(.idle)

        } catch {
            await AppState.shared.updateStatus(.error(error.localizedDescription))
            showErrorNotification(message: error.localizedDescription)

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await AppState.shared.updateStatus(.idle)
        }

        currentSession = nil
    }

    private func checkPermissions() async -> Bool {
        let tempDir = FileManager.default.temporaryDirectory
        let tempMicURL = tempDir.appendingPathComponent("permission_check_mic.wav")
        let tempSystemURL = tempDir.appendingPathComponent("permission_check_system.wav")

        let micRecorder = MicrophoneRecorder(outputURL: tempMicURL)
        let systemRecorder = SystemAudioRecorder(outputURL: tempSystemURL)

        let hasMicPermission = await micRecorder.checkPermission()
        let hasSystemPermission = await systemRecorder.checkPermission()

        return hasMicPermission && hasSystemPermission
    }

    private func createSessionDirectory() -> URL {
        let config = ConfigManager.shared.load()
        let baseDir = config.expandedOutputDirectory

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let sessionName = "session_\(formatter.string(from: Date()))"

        let sessionDir = baseDir.appendingPathComponent(sessionName)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        return sessionDir
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordingDuration += 1
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func showCompletionNotification(transcriptURL: URL) {
        let notification = NSUserNotification()
        notification.title = "Meeting Transcript Ready"
        notification.informativeText = "Saved to \(transcriptURL.lastPathComponent)"
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func showErrorNotification(message: String) {
        let notification = NSUserNotification()
        notification.title = "Transcription Failed"
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    enum RecordingManagerError: LocalizedError {
        case permissionDenied
        case alreadyRecording

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone or screen recording permission denied. Please grant permissions in System Preferences."
            case .alreadyRecording:
                return "Recording is already in progress"
            }
        }
    }
}
