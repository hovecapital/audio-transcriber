import AppKit
import ApplicationServices
import Foundation

@MainActor
final class MeetingDetectionService: ObservableObject {
    static let shared = MeetingDetectionService()

    @Published private(set) var isMonitoring = false
    @Published private(set) var detectedMeeting: String?

    private var pollTimer: Timer?
    private var autoStartedRecording = false

    private static let browserBundleIDs = [
        "com.google.Chrome",
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.brave.Browser"
    ]

    private static let slackBundleID = "com.tinyspeck.slackmacgap"

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForMeetings()
            }
        }
        Log.meeting.info("Meeting detection started")
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        isMonitoring = false
        detectedMeeting = nil
        Log.meeting.info("Meeting detection stopped")
    }

    private func checkForMeetings() {
        guard AppState.shared.dictationStatus == .idle else { return }

        let meetingName = detectActiveMeeting()

        if let name = meetingName {
            detectedMeeting = name
            if !AppState.shared.status.isRecording {
                autoStartRecording()
            }
        } else {
            detectedMeeting = nil
            if autoStartedRecording && AppState.shared.status.isRecording {
                autoStopRecording()
            }
        }
    }

    private func detectActiveMeeting() -> String? {
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }

            if Self.browserBundleIDs.contains(bundleID) {
                if let meeting = detectBrowserMeeting(pid: app.processIdentifier) {
                    return meeting
                }
            }

            if bundleID == Self.slackBundleID {
                if let meeting = detectSlackHuddle(pid: app.processIdentifier) {
                    return meeting
                }
            }
        }

        return nil
    }

    private func detectBrowserMeeting(pid: pid_t) -> String? {
        let titles = readWindowTitles(pid: pid)

        for title in titles {
            if title.contains("Meet -") || title.contains("meet.google.com") {
                return "Google Meet"
            }
            if title.contains("Microsoft Teams") && (title.contains("Meeting") || title.contains("| Chat")) {
                return "MS Teams"
            }
        }

        return nil
    }

    private func detectSlackHuddle(pid: pid_t) -> String? {
        let titles = readWindowTitles(pid: pid)

        for title in titles {
            if title.contains("Huddle") || title.contains("huddle") {
                return "Slack Huddle"
            }
        }

        return nil
    }

    private func readWindowTitles(pid: pid_t) -> [String] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: AnyObject?

        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return []
        }

        var titles: [String] = []
        for window in windows {
            var titleValue: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String, !title.isEmpty {
                titles.append(title)
            }
        }

        return titles
    }

    private func autoStartRecording() {
        autoStartedRecording = true
        Log.meeting.info("Auto-starting recording for: \(self.detectedMeeting ?? "unknown")")
        Task {
            do {
                try await AudioRecordingManager.shared.startRecording()
            } catch {
                Log.meeting.error("Failed to auto-start recording: \(error.localizedDescription)")
                autoStartedRecording = false
            }
        }
    }

    private func autoStopRecording() {
        Log.meeting.info("Auto-stopping recording (meeting ended)")
        autoStartedRecording = false
        Task {
            await AudioRecordingManager.shared.stopRecording()
        }
    }
}
