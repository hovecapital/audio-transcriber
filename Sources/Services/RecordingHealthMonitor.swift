import AppKit
import Foundation

enum AudioSource: String {
    case microphone = "Mic"
    case systemAudio = "System"
}

@MainActor
final class RecordingHealthMonitor: ObservableObject {
    @Published private(set) var micHealthy = true
    @Published private(set) var systemHealthy = true

    private var bufferCounts: [AudioSource: Int] = [.microphone: 0, .systemAudio: 0]
    private var lastBufferTime: [AudioSource: Date] = [:]
    private var frameCounts: [AudioSource: Int64] = [.microphone: 0, .systemAudio: 0]

    private var healthTimer: Timer?
    private let starvationThreshold: TimeInterval = 5.0

    private var isMonitoring = false

    func start() {
        guard !isMonitoring else { return }

        bufferCounts = [.microphone: 0, .systemAudio: 0]
        lastBufferTime = [:]
        frameCounts = [.microphone: 0, .systemAudio: 0]
        micHealthy = true
        systemHealthy = true
        isMonitoring = true

        healthTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkHealth()
            }
        }

        Log.audio.info("RecordingHealthMonitor started")
    }

    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        isMonitoring = false
        Log.audio.info("RecordingHealthMonitor stopped")
    }

    nonisolated func recordBufferReceived(source: AudioSource, frameCount: Int) {
        Task { @MainActor in
            bufferCounts[source, default: 0] += 1
            lastBufferTime[source] = Date()
            frameCounts[source, default: 0] += Int64(frameCount)

            if source == .microphone && !micHealthy {
                micHealthy = true
                Log.audio.info("Microphone buffer flow restored")
            } else if source == .systemAudio && !systemHealthy {
                systemHealthy = true
                Log.audio.info("System audio buffer flow restored")
            }
        }
    }

    nonisolated func reportStreamDeath(source: AudioSource, error: Error) {
        Task { @MainActor in
            Log.audio.error("\(source.rawValue) stream died: \(error.localizedDescription)")

            switch source {
            case .microphone:
                micHealthy = false
            case .systemAudio:
                systemHealthy = false
            }

            fireAlert(message: "\(source.rawValue) audio recording stopped unexpectedly")
            await AppState.shared.updateStatus(.warning("\(source.rawValue) recording failed - check backup"))
        }
    }

    private func checkHealth() {
        let now = Date()

        for source in [AudioSource.microphone, AudioSource.systemAudio] {
            guard let lastTime = lastBufferTime[source] else {
                let count = bufferCounts[source, default: 0]
                if count == 0 && isMonitoring {
                    Log.audio.warning("No buffers ever received from \(source.rawValue)")
                }
                continue
            }

            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed > starvationThreshold {
                let wasHealthy = source == .microphone ? micHealthy : systemHealthy
                if wasHealthy {
                    Log.audio.error("\(source.rawValue) buffer starvation: \(String(format: "%.1f", elapsed))s since last buffer")

                    switch source {
                    case .microphone:
                        micHealthy = false
                    case .systemAudio:
                        systemHealthy = false
                    }

                    fireAlert(message: "\(source.rawValue) audio: no data for \(Int(elapsed))s")
                    Task {
                        await AppState.shared.updateStatus(.warning("\(source.rawValue) audio may not be recording"))
                    }
                }
            }
        }

        let micCount = bufferCounts[.microphone, default: 0]
        let sysCount = bufferCounts[.systemAudio, default: 0]
        Log.audio.debug("Health check - Mic buffers: \(micCount), System buffers: \(sysCount)")
    }

    private func fireAlert(message: String) {
        let notification = NSUserNotification()
        notification.title = "Recording Warning"
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
}
