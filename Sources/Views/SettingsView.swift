import AVFoundation
import ScreenCaptureKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var config: AppConfig
    @State private var launchAtLogin: Bool
    @State private var apiKey: String
    @State private var showAPIKeyField = false
    @State private var micPermissionStatus: AVAuthorizationStatus = .notDetermined
    @State private var screenRecordingGranted = false
    @Environment(\.dismiss) private var dismiss

    init() {
        _config = State(initialValue: ConfigManager.shared.load())
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
        _apiKey = State(initialValue: KeychainHelper.getLLMAPIKey() ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    generalSection
                    permissionsSection
                    outputSection
                    transcriptionSection
                    realTimeSection
                    speakerLabelsSection
                }
            }
            .onAppear {
                checkPermissions()
            }

            Spacer()

            buttonRow
        }
        .padding(24)
        .frame(width: 520, height: 700)
    }

    @ViewBuilder
    private var generalSection: some View {
        GroupBox("General") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var permissionsSection: some View {
        GroupBox("Permissions") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Microphone:")
                        .frame(width: 120, alignment: .leading)
                    permissionStatusView(for: micPermissionStatus)
                    Spacer()
                    if micPermissionStatus != .authorized {
                        Button("Open Settings") {
                            SystemSettingsHelper.openMicrophoneSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                HStack {
                    Text("Screen Recording:")
                        .frame(width: 120, alignment: .leading)
                    if screenRecordingGranted {
                        Text("Granted")
                            .foregroundColor(.green)
                    } else {
                        Text("Not Granted")
                            .foregroundColor(.red)
                    }
                    Spacer()
                    if !screenRecordingGranted {
                        Button("Open Settings") {
                            SystemSettingsHelper.openScreenRecordingSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Button("Refresh Status") {
                    checkPermissions()
                }
                .buttonStyle(.bordered)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func permissionStatusView(for status: AVAuthorizationStatus) -> some View {
        switch status {
        case .authorized:
            Text("Granted")
                .foregroundColor(.green)
        case .denied:
            Text("Denied")
                .foregroundColor(.red)
        case .restricted:
            Text("Restricted")
                .foregroundColor(.orange)
        case .notDetermined:
            Text("Not Determined")
                .foregroundColor(.secondary)
        @unknown default:
            Text("Unknown")
                .foregroundColor(.secondary)
        }
    }

    private func checkPermissions() {
        micPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        if #available(macOS 13.0, *) {
            Task {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                    await MainActor.run {
                        screenRecordingGranted = !content.displays.isEmpty
                    }
                } catch {
                    await MainActor.run {
                        screenRecordingGranted = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var outputSection: some View {
        GroupBox("Output") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Save Location:")
                        .frame(width: 120, alignment: .leading)
                    TextField("", text: $config.outputDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        selectOutputDirectory()
                    }
                }

                Toggle("Open transcript after processing", isOn: $config.autoOpenTranscript)

                Toggle("Delete audio files after transcription", isOn: $config.deleteAudioAfterTranscription)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var transcriptionSection: some View {
        GroupBox("Transcription") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Whisper Model:")
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: $config.whisperModelSize) {
                        ForEach(AppConfig.WhisperModelSize.allCases, id: \.self) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .labelsHidden()
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var realTimeSection: some View {
        GroupBox("Real-Time Transcription") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable real-time transcription", isOn: $config.enableRealTimeTranscription)

                if config.enableRealTimeTranscription {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Chunk Interval:")
                                .frame(width: 120, alignment: .leading)
                            Slider(
                                value: $config.transcriptionChunkIntervalSeconds,
                                in: 10...60,
                                step: 5
                            )
                            Text("\(Int(config.transcriptionChunkIntervalSeconds))s")
                                .frame(width: 40)
                        }

                        Divider()

                        HStack {
                            Text("LLM Provider:")
                                .frame(width: 120, alignment: .leading)
                            Picker("", selection: $config.llmProvider) {
                                ForEach(AppConfig.LLMProvider.allCases, id: \.self) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: config.llmProvider) { newValue in
                                config.llmModel = newValue.defaultModel
                            }
                        }

                        HStack {
                            Text("Model:")
                                .frame(width: 120, alignment: .leading)
                            TextField("Model name", text: $config.llmModel)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("API Key:")
                                .frame(width: 120, alignment: .leading)
                            if showAPIKeyField {
                                SecureField("Enter API key", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                if apiKey.isEmpty {
                                    Text("Not configured")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Configured")
                                        .foregroundColor(.green)
                                }
                            }
                            Button(showAPIKeyField ? "Hide" : "Edit") {
                                showAPIKeyField.toggle()
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack {
                            Text("Analysis Interval:")
                                .frame(width: 120, alignment: .leading)
                            Slider(
                                value: $config.llmAnalysisIntervalSeconds,
                                in: 60...600,
                                step: 30
                            )
                            Text("\(Int(config.llmAnalysisIntervalSeconds / 60))min")
                                .frame(width: 50)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var speakerLabelsSection: some View {
        GroupBox("Speaker Labels") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Microphone:")
                        .frame(width: 120, alignment: .leading)
                    TextField("Person 1", text: $config.person1Label)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("System Audio:")
                        .frame(width: 120, alignment: .leading)
                    TextField("Person 2", text: $config.person2Label)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var buttonRow: some View {
        HStack {
            Button("Reset to Defaults") {
                config = .default
                apiKey = ""
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)

            Button("Save") {
                saveSettings()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            config.outputDirectory = url.path
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                Log.config.info("Launch at login enabled")
            } else {
                try SMAppService.mainApp.unregister()
                Log.config.info("Launch at login disabled")
            }
        } catch {
            Log.config.error("Failed to set launch at login: \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func saveSettings() {
        ConfigManager.shared.save(config)

        if !apiKey.isEmpty {
            do {
                try KeychainHelper.saveLLMAPIKey(apiKey)
                Log.config.info("API key saved to keychain")
            } catch {
                Log.config.error("Failed to save API key: \(error.localizedDescription)")
            }
        } else if KeychainHelper.getLLMAPIKey() != nil {
            do {
                try KeychainHelper.deleteLLMAPIKey()
                Log.config.info("API key removed from keychain")
            } catch {
                Log.config.error("Failed to delete API key: \(error.localizedDescription)")
            }
        }

        AudioRecordingManager.shared.reloadConfig()
    }
}
