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
        Log.audio.info("AudioRecordingManager initialized")
    }

    func startRecording() async throws {
        Log.audio.info("Start recording requested")
        guard !isRecording else {
            Log.audio.debug("Already recording, ignoring request")
            return
        }

        Log.audio.info("Checking permissions...")
        let hasPermissions = await checkPermissions()
        guard hasPermissions else {
            Log.audio.error("Permission denied for microphone or screen recording")
            throw RecordingManagerError.permissionDenied
        }
        Log.audio.info("Permissions granted")

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

        Log.audio.info("Session created: \(session.id)")
        Log.audio.debug("Mic output: \(micURL.path)")
        Log.audio.debug("System output: \(systemURL.path)")

        micRecorder = MicrophoneRecorder(outputURL: micURL)
        systemRecorder = SystemAudioRecorder(outputURL: systemURL)

        Log.audio.info("Starting microphone recorder...")
        try micRecorder?.start()
        Log.audio.info("Starting system audio recorder...")
        try await systemRecorder?.start()

        currentSession = session
        isRecording = true
        recordingDuration = 0

        startDurationTimer()

        await AppState.shared.updateStatus(.recording)
        Log.audio.info("Recording started successfully")
    }

    func stopRecording() async {
        Log.audio.info("Stop recording requested")
        guard isRecording, var session = currentSession else {
            Log.audio.debug("Not recording, ignoring stop request")
            return
        }

        stopDurationTimer()

        Log.audio.info("Stopping microphone recorder...")
        micRecorder?.stop()
        Log.audio.info("Stopping system audio recorder...")
        await systemRecorder?.stop()

        session.endTime = Date()
        currentSession = session

        isRecording = false
        Log.audio.info("Recording stopped. Duration: \(session.formattedDuration)")

        await processRecording(session: session)
    }

    private func processRecording(session: RecordingSession) async {
        Log.audio.info("Processing recording for session: \(session.id)")
        let currentConfig = ConfigManager.shared.load()

        await AppState.shared.updateStatus(.processing(progress: 0, message: "Starting transcription..."))

        let transcriptionService = TranscriptionService(modelSize: currentConfig.whisperModelSize)

        do {
            Log.audio.info("Transcribing microphone audio...")
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
            Log.audio.info("Microphone transcription complete: \(micSegments.count) segments")

            Log.audio.info("Transcribing system audio...")
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
            Log.audio.info("System audio transcription complete: \(systemSegments.count) segments")

            await AppState.shared.updateStatus(.processing(progress: 0.9, message: "Generating transcript..."))

            let generator = MarkdownGenerator(config: currentConfig)
            let markdown = generator.generate(
                micSegments: micSegments,
                systemSegments: systemSegments,
                session: session
            )

            let filename = MarkdownGenerator.generateFilename(for: session.startTime)
            let transcriptURL = currentConfig.expandedOutputDirectory.appendingPathComponent(filename)

            Log.audio.info("Saving transcript to: \(transcriptURL.path)")
            try generator.save(markdown: markdown, to: transcriptURL)

            if currentConfig.deleteAudioAfterTranscription {
                Log.audio.debug("Deleting audio files...")
                try? FileManager.default.removeItem(at: session.micFilePath)
                try? FileManager.default.removeItem(at: session.systemFilePath)
                try? FileManager.default.removeItem(at: session.micFilePath.deletingLastPathComponent())
            }

            await AppState.shared.updateStatus(.completed)
            Log.audio.info("Processing completed successfully")

            showCompletionNotification(transcriptURL: transcriptURL)

            if currentConfig.autoOpenTranscript {
                Log.audio.debug("Auto-opening transcript")
                NSWorkspace.shared.open(transcriptURL)
            }

            try await Task.sleep(nanoseconds: 2_000_000_000)
            await AppState.shared.updateStatus(.idle)

        } catch {
            Log.audio.error("Processing failed: \(error.localizedDescription)")
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

        Log.audio.debug("Mic permission: \(hasMicPermission), System permission: \(hasSystemPermission)")

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

        Log.audio.debug("Created session directory: \(sessionDir.path)")
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
