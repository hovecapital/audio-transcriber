import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var recordingManager: AudioRecordingManager
    @State private var showSettings = false
    @State private var showQuitDialog = false
    @State private var unprocessedSessions: [UnprocessedSession] = []

    private let scanner = UnprocessedSessionScanner()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusSection

            Divider()

            recordingControls

            Divider()

            settingsAndQuit
        }
        .padding(8)
        .frame(width: 220)
        .onAppear { refreshUnprocessedSessions() }
        .alert("Recording in Progress", isPresented: $showQuitDialog) {
            Button("Process Now") { processAndQuit() }
            Button("Save for Later") { saveForLaterAndQuit() }
            Button("Discard", role: .destructive) { discardAndQuit() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have an active recording. What would you like to do?")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch appState.status {
        case .idle:
            HStack {
                Circle()
                    .fill(.gray)
                    .frame(width: 8, height: 8)
                Text("Ready to record")
                    .foregroundColor(.secondary)
            }

        case .recording:
            HStack {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Recording: \(formattedDuration)")
                    .foregroundColor(.primary)
            }

        case .processing(let progress, let message):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Processing...")
                        .foregroundColor(.primary)
                }
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }

        case .completed:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Transcript saved")
            }

        case .error(let message):
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var recordingControls: some View {
        if appState.status.isRecording {
            Button(action: stopRecording) {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop Recording")
                }
            }
            .buttonStyle(.plain)
        } else if !appState.status.isProcessing {
            Button(action: startRecording) {
                HStack {
                    Image(systemName: "record.circle")
                    Text("Start Recording")
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var settingsAndQuit: some View {
        Button(action: { showSettings = true }) {
            HStack {
                Image(systemName: "gear")
                Text("Settings...")
            }
        }
        .buttonStyle(.plain)
        .disabled(appState.status.isRecording || appState.status.isProcessing)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }

        Button(action: openTranscriptsFolder) {
            HStack {
                Image(systemName: "folder")
                Text("Open Transcripts Folder")
            }
        }
        .buttonStyle(.plain)

        if !unprocessedSessions.isEmpty {
            Menu {
                ForEach(unprocessedSessions) { session in
                    Button(action: { processSession(session) }) {
                        Text("\(session.formattedDate) (\(session.formattedDuration), \(session.formattedFileSize))")
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Process Old Recordings")
                    Text("(\(unprocessedSessions.count))")
                        .foregroundColor(.secondary)
                }
            }
            .disabled(appState.status.isRecording || appState.status.isProcessing)
        }

        Divider()

        Button(action: quitApp) {
            HStack {
                Image(systemName: "power")
                Text("Quit")
            }
        }
        .buttonStyle(.plain)
    }

    private var formattedDuration: String {
        let total = Int(recordingManager.recordingDuration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func startRecording() {
        Task {
            do {
                try await recordingManager.startRecording()
            } catch {
                await appState.updateStatus(.error(error.localizedDescription))
            }
        }
    }

    private func stopRecording() {
        Task {
            await recordingManager.stopRecording()
        }
    }

    private func openTranscriptsFolder() {
        let config = ConfigManager.shared.load()
        NSWorkspace.shared.open(config.expandedOutputDirectory)
    }

    private func quitApp() {
        if appState.status.isRecording {
            showQuitDialog = true
        } else {
            NSApplication.shared.terminate(nil)
        }
    }

    private func processAndQuit() {
        Task {
            await recordingManager.stopRecording()
            while appState.status.isProcessing {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            NSApplication.shared.terminate(nil)
        }
    }

    private func saveForLaterAndQuit() {
        Task {
            await recordingManager.saveForLater()
            NSApplication.shared.terminate(nil)
        }
    }

    private func discardAndQuit() {
        Task {
            await recordingManager.discardCurrentSession()
            NSApplication.shared.terminate(nil)
        }
    }

    private func refreshUnprocessedSessions() {
        unprocessedSessions = scanner.scan()
    }

    private func processSession(_ session: UnprocessedSession) {
        Task {
            await recordingManager.processUnprocessedSession(session)
            refreshUnprocessedSessions()
        }
    }
}
