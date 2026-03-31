import AppKit
import AVFoundation
import Foundation

@MainActor
public final class AudioRecordingManager: ObservableObject {
    public static let shared = AudioRecordingManager()

    @Published private(set) var isRecording = false
    @Published private(set) var currentSession: RecordingSession?
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var realTimeCoordinator: RealTimeRecordingCoordinator?
    @Published private(set) var healthMonitor: RecordingHealthMonitor?

    private var micRecorder: MicrophoneRecorder?
    private var systemRecorder: SystemAudioRecorder?
    private var durationTimer: Timer?

    private var config: AppConfig

    private init() {
        config = ConfigManager.shared.load()
        Log.audio.info("AudioRecordingManager initialized")
    }

    func reloadConfig() {
        config = ConfigManager.shared.load()
        realTimeCoordinator?.updateConfig(config)
    }

    func startRecording() async throws {
        Log.audio.info("Start recording requested")
        guard !isRecording else {
            Log.audio.debug("Already recording, ignoring request")
            return
        }

        config = ConfigManager.shared.load()

        if let diskError = checkDiskSpace() {
            throw diskError
        }

        Log.audio.info("Checking permissions...")
        if let permissionError = await checkPermissions() {
            Log.audio.error("Permission error: \(permissionError.localizedDescription)")
            throw permissionError
        }
        Log.audio.info("All permissions granted")

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

        let monitor = RecordingHealthMonitor()
        healthMonitor = monitor
        micRecorder?.healthMonitor = monitor
        systemRecorder?.healthMonitor = monitor
        monitor.start()

        if config.enableRealTimeTranscription {
            let coordinator = RealTimeRecordingCoordinator(config: config)
            realTimeCoordinator = coordinator
            micRecorder?.bufferDelegate = coordinator
            systemRecorder?.bufferDelegate = coordinator
            coordinator.startSession()
            Log.audio.info("Real-time transcription enabled")
        }

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
        healthMonitor?.stop()

        Log.audio.info("Stopping microphone recorder...")
        micRecorder?.stop()
        Log.audio.info("Stopping system audio recorder...")
        await systemRecorder?.stop()

        session.endTime = Date()
        currentSession = session

        isRecording = false
        Log.audio.info("Recording stopped. Duration: \(session.formattedDuration)")

        let backupService = AudioBackupService(config: config)
        let backupResult = backupService.backupSessionFiles(
            micFile: session.micFilePath,
            systemFile: session.systemFilePath,
            sessionStart: session.startTime
        )
        if !backupResult.success {
            Log.audio.warning("Backup completed with errors: \(backupResult.errors.joined(separator: ", "))")
        }

        let verificationIssues = verifyRecordingFiles(session: session)
        if !verificationIssues.isEmpty {
            let message = verificationIssues.joined(separator: "; ")
            Log.audio.error("Recording verification failed: \(message)")
            showWarningNotification(message: message)
            await AppState.shared.updateStatus(.warning(message))
        }

        let realTimeResult = await realTimeCoordinator?.stopSession()
        realTimeCoordinator = nil
        healthMonitor = nil

        await processRecording(session: session, realTimeResult: realTimeResult)
    }

    func saveForLater() async {
        Log.audio.info("Save for later requested")
        guard isRecording, var session = currentSession else {
            Log.audio.debug("Not recording, ignoring save for later request")
            return
        }

        stopDurationTimer()
        healthMonitor?.stop()
        healthMonitor = nil

        Log.audio.info("Stopping recorders for save...")
        micRecorder?.stop()
        await systemRecorder?.stop()

        _ = await realTimeCoordinator?.stopSession()
        realTimeCoordinator = nil

        session.endTime = Date()

        let sessionDir = session.micFilePath.deletingLastPathComponent()
        let metadata = UnprocessedSession(
            id: session.id,
            startTime: session.startTime,
            endTime: session.endTime!,
            sessionDirectory: sessionDir,
            micFilePath: session.micFilePath,
            systemFilePath: session.systemFilePath
        )

        let metadataURL = sessionDir.appendingPathComponent(UnprocessedSession.metadataFilename)
        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL)
            Log.audio.info("Saved session metadata to: \(metadataURL.path)")
        } catch {
            Log.audio.error("Failed to save metadata: \(error.localizedDescription)")
        }

        isRecording = false
        currentSession = nil
        await AppState.shared.updateStatus(.idle)
    }

    func discardCurrentSession() async {
        Log.audio.info("Discard session requested")
        guard isRecording, let session = currentSession else {
            Log.audio.debug("Not recording, ignoring discard request")
            return
        }

        stopDurationTimer()
        healthMonitor?.stop()
        healthMonitor = nil

        Log.audio.info("Stopping recorders for discard...")
        micRecorder?.stop()
        await systemRecorder?.stop()

        _ = await realTimeCoordinator?.stopSession()
        realTimeCoordinator = nil

        let sessionDir = session.micFilePath.deletingLastPathComponent()
        do {
            try FileManager.default.removeItem(at: sessionDir)
            Log.audio.info("Deleted session directory: \(sessionDir.path)")
        } catch {
            Log.audio.error("Failed to delete session: \(error.localizedDescription)")
        }

        isRecording = false
        currentSession = nil
        await AppState.shared.updateStatus(.idle)
    }

    func processUnprocessedSession(_ unprocessed: UnprocessedSession) async {
        Log.audio.info("Processing unprocessed session: \(unprocessed.id)")

        let session = RecordingSession(
            id: unprocessed.id,
            startTime: unprocessed.startTime,
            endTime: unprocessed.endTime,
            micFilePath: unprocessed.micFilePath,
            systemFilePath: unprocessed.systemFilePath,
            status: .processing(progress: 0, message: "")
        )

        await processRecording(session: session, realTimeResult: nil)

        let metadataURL = unprocessed.sessionDirectory.appendingPathComponent(UnprocessedSession.metadataFilename)
        try? FileManager.default.removeItem(at: metadataURL)
        Log.audio.debug("Removed metadata file: \(metadataURL.path)")
    }

    func processRecording(
        session: RecordingSession,
        realTimeResult: (segments: [TranscriptSegment], analysis: MeetingAnalysis)?
    ) async {
        Log.audio.info("Processing recording for session: \(session.id)")
        let currentConfig = ConfigManager.shared.load()

        await AppState.shared.updateStatus(.processing(progress: 0, message: "Starting transcription..."))

        do {
            let allSegments: [TranscriptSegment]
            var analysis = MeetingAnalysis.empty

            if let result = realTimeResult, !result.segments.isEmpty {
                Log.audio.info("Using real-time transcription results: \(result.segments.count) segments")
                allSegments = result.segments
                analysis = result.analysis
                await AppState.shared.updateStatus(.processing(progress: 0.8, message: "Using real-time transcription..."))
            } else {
                let transcriptionService = TranscriptionService(modelSize: currentConfig.whisperModelSize)

                var micSegments: [TranscriptSegment] = []
                var systemSegments: [TranscriptSegment] = []

                let micValidation = WAVFileValidator.validate(url: session.micFilePath)
                Log.audio.info("Mic WAV validation: size=\(micValidation.fileSize), hasAudio=\(micValidation.hasAudioData), valid=\(micValidation.isValid)")

                if micValidation.isValid {
                    Log.audio.info("Transcribing microphone audio...")
                    await AppState.shared.updateStatus(.processing(progress: 0.1, message: "Transcribing microphone audio..."))

                    micSegments = try await transcriptionService.transcribe(
                        audioURL: session.micFilePath,
                        speaker: .person1
                    ) { progress, message in
                        Task { @MainActor in
                            let overallProgress = 0.1 + (progress * 0.35)
                            AppState.shared.updateStatus(.processing(progress: overallProgress, message: message))
                        }
                    }
                    Log.audio.info("Microphone transcription complete: \(micSegments.count) segments")
                } else {
                    Log.audio.error("Skipping mic transcription: \(micValidation.errorMessage ?? "invalid file")")
                }

                let sysValidation = WAVFileValidator.validate(url: session.systemFilePath)
                Log.audio.info("System WAV validation: size=\(sysValidation.fileSize), hasAudio=\(sysValidation.hasAudioData), valid=\(sysValidation.isValid)")

                if sysValidation.isValid {
                    Log.audio.info("Transcribing system audio...")
                    await AppState.shared.updateStatus(.processing(progress: 0.5, message: "Transcribing system audio..."))

                    systemSegments = try await transcriptionService.transcribe(
                        audioURL: session.systemFilePath,
                        speaker: .person2
                    ) { progress, message in
                        Task { @MainActor in
                            let overallProgress = 0.5 + (progress * 0.35)
                            AppState.shared.updateStatus(.processing(progress: overallProgress, message: message))
                        }
                    }
                    Log.audio.info("System audio transcription complete: \(systemSegments.count) segments")
                } else {
                    Log.audio.error("Skipping system transcription: \(sysValidation.errorMessage ?? "invalid file")")
                }

                allSegments = (micSegments + systemSegments).sorted { $0.start < $1.start }
            }

            await AppState.shared.updateStatus(.processing(progress: 0.9, message: "Generating transcript..."))

            let markdown: String
            let transcriptURL: URL

            if realTimeResult != nil {
                let generator = EnhancedMarkdownGenerator(config: currentConfig)
                markdown = generator.generate(
                    segments: allSegments,
                    analysis: analysis,
                    session: session
                )
                let filename = MarkdownGenerator.generateFilename(for: session.startTime)
                transcriptURL = currentConfig.expandedOutputDirectory.appendingPathComponent(filename)
                try generator.save(markdown: markdown, to: transcriptURL)
            } else {
                let generator = MarkdownGenerator(config: currentConfig)
                let micSegments = allSegments.filter { $0.speaker == .person1 }
                let systemSegments = allSegments.filter { $0.speaker == .person2 }
                markdown = generator.generate(
                    micSegments: micSegments,
                    systemSegments: systemSegments,
                    session: session
                )
                let filename = MarkdownGenerator.generateFilename(for: session.startTime)
                transcriptURL = currentConfig.expandedOutputDirectory.appendingPathComponent(filename)
                try generator.save(markdown: markdown, to: transcriptURL)
            }

            Log.audio.info("Saving transcript to: \(transcriptURL.path)")

            if currentConfig.deleteAudioAfterTranscription {
                let issues = verifyRecordingFiles(session: session)
                if issues.isEmpty {
                    Log.audio.debug("Deleting audio files...")
                    try? FileManager.default.removeItem(at: session.micFilePath)
                    try? FileManager.default.removeItem(at: session.systemFilePath)
                    try? FileManager.default.removeItem(at: session.micFilePath.deletingLastPathComponent())
                } else {
                    Log.audio.warning("Skipping audio deletion due to verification issues: \(issues.joined(separator: ", "))")
                }
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

    private func checkPermissions() async -> RecordingManagerError? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempMicURL = tempDir.appendingPathComponent("permission_check_mic.wav")
        let tempSystemURL = tempDir.appendingPathComponent("permission_check_system.wav")

        let micRecorder = MicrophoneRecorder(outputURL: tempMicURL)
        let systemRecorder = SystemAudioRecorder(outputURL: tempSystemURL)

        let hasMicPermission = await micRecorder.checkPermission()
        let hasSystemPermission = await systemRecorder.checkPermission()

        Log.audio.info("Permission check - Microphone: \(hasMicPermission ? "GRANTED" : "DENIED"), Screen Recording: \(hasSystemPermission ? "GRANTED" : "DENIED")")

        if !hasMicPermission && !hasSystemPermission {
            return .bothPermissionsDenied
        } else if !hasMicPermission {
            return .microphonePermissionDenied
        } else if !hasSystemPermission {
            return .screenRecordingPermissionDenied
        }
        return nil
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

    private func showWarningNotification(message: String) {
        let notification = NSUserNotification()
        notification.title = "Recording Warning"
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func checkDiskSpace() -> RecordingManagerError? {
        let outputDir = config.expandedOutputDirectory
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: outputDir.path)
            guard let freeSpace = attrs[.systemFreeSize] as? Int64 else {
                return nil
            }

            let freeMB = freeSpace / (1024 * 1024)
            Log.audio.debug("Available disk space: \(freeMB)MB")

            if freeMB < 100 {
                Log.audio.error("Insufficient disk space: \(freeMB)MB free")
                return .insufficientDiskSpace(freeMB: freeMB)
            }

            if freeMB < 500 {
                Log.audio.warning("Low disk space warning: \(freeMB)MB free")
                showWarningNotification(message: "Low disk space: \(freeMB)MB free. Recording may fail if space runs out.")
            }
        } catch {
            Log.audio.warning("Could not check disk space: \(error.localizedDescription)")
        }
        return nil
    }

    private func verifyRecordingFiles(session: RecordingSession) -> [String] {
        var issues: [String] = []
        let minValidSize: UInt64 = 4096

        for (label, url) in [("Microphone", session.micFilePath), ("System audio", session.systemFilePath)] {
            guard FileManager.default.fileExists(atPath: url.path) else {
                issues.append("\(label) file missing")
                continue
            }

            let size = fileSize(at: url)
            if size <= minValidSize {
                issues.append("\(label) recording appears empty (\(size) bytes)")
                continue
            }

            do {
                let audioFile = try AVAudioFile(forReading: url)
                if audioFile.length == 0 {
                    issues.append("\(label) recording has zero audio frames")
                }
            } catch {
                issues.append("\(label) file is not a valid audio file: \(error.localizedDescription)")
            }
        }

        return issues
    }

    private func fileSize(at url: URL) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else {
            return 0
        }
        return size
    }

    enum RecordingManagerError: LocalizedError {
        case microphonePermissionDenied
        case screenRecordingPermissionDenied
        case bothPermissionsDenied
        case alreadyRecording
        case insufficientDiskSpace(freeMB: Int64)

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone permission denied. Open System Settings > Privacy & Security > Microphone and enable Meeting Recorder."
            case .screenRecordingPermissionDenied:
                return "Screen Recording permission denied. Open System Settings > Privacy & Security > Screen Recording and enable Meeting Recorder."
            case .bothPermissionsDenied:
                return "Both Microphone and Screen Recording permissions denied. Open System Settings > Privacy & Security and enable Meeting Recorder for both."
            case .alreadyRecording:
                return "Recording is already in progress"
            case .insufficientDiskSpace(let freeMB):
                return "Insufficient disk space: only \(freeMB)MB free. Need at least 100MB to start recording."
            }
        }
    }
}
