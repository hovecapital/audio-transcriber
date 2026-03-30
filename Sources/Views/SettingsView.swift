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
    @State private var accessibilityGranted = false
    @State private var useHuggingFace: Bool
    @ObservedObject private var autocorrectMonitor = AutocorrectMonitor.shared
    @Environment(\.dismiss) private var dismiss

    init() {
        let loadedConfig = ConfigManager.shared.load()
        _config = State(initialValue: loadedConfig)
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
        _apiKey = State(initialValue: KeychainHelper.getLLMAPIKey() ?? "")
        _useHuggingFace = State(initialValue: !loadedConfig.llamaServerHFModel.isEmpty)
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
                    autocorrectSection
                    speakerLabelsSection
                }
            }
            .onAppear {
                checkPermissions()
                Task { await autocorrectMonitor.checkConnection() }
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

                HStack {
                    Text("Accessibility:")
                        .frame(width: 120, alignment: .leading)
                    if accessibilityGranted {
                        Text("Granted")
                            .foregroundColor(.green)
                    } else {
                        Text("Not Granted")
                            .foregroundColor(.red)
                    }
                    Spacer()
                    if !accessibilityGranted {
                        Button("Open Settings") {
                            SystemSettingsHelper.openAccessibilitySettings()
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
        accessibilityGranted = AccessibilityReader.isTrusted()

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
    private var autocorrectSection: some View {
        GroupBox("Autocorrect") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Backend:")
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: $config.autocorrectBackend) {
                        ForEach(AppConfig.AutocorrectBackend.allCases, id: \.self) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: config.autocorrectBackend) { newValue in
                        config.autocorrectServerURL = newValue.defaultURL
                    }
                }

                HStack {
                    Text("Server URL:")
                        .frame(width: 120, alignment: .leading)
                    TextField("http://localhost:8080", text: $config.autocorrectServerURL)
                        .textFieldStyle(.roundedBorder)
                }

                if config.autocorrectBackend == .llamaCpp {
                    HStack {
                        Text("Model Source:")
                            .frame(width: 120, alignment: .leading)
                        Picker("", selection: $useHuggingFace) {
                            Text("Local File").tag(false)
                            Text("HuggingFace").tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .onChange(of: useHuggingFace) { isHF in
                            if isHF {
                                config.llamaServerModelPath = ""
                            } else {
                                config.llamaServerHFModel = ""
                            }
                        }
                    }

                    if useHuggingFace {
                        HStack {
                            Text("HF Model:")
                                .frame(width: 120, alignment: .leading)
                            TextField("bartowski/Llama-3.2-3B-Instruct-GGUF", text: $config.llamaServerHFModel)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        HStack {
                            Text("Model File:")
                                .frame(width: 120, alignment: .leading)
                            TextField("/path/to/model.gguf", text: $config.llamaServerModelPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                selectModelFile()
                            }
                        }
                    }

                    Toggle("Auto-start server", isOn: $config.autoStartLLMServer)
                }

                Divider()

                connectionStatusRow

                modelStatusRow

                if case .error(let message) = autocorrectMonitor.connectionStatus.serverState {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.red)
                        setupInstructions
                    }
                }

                Divider()

                HStack {
                    Text("Model:")
                        .frame(width: 120, alignment: .leading)
                    TextField("Model name", text: $config.autocorrectModel)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Timeout:")
                        .frame(width: 120, alignment: .leading)
                    Slider(
                        value: $config.autocorrectTimeout,
                        in: 1...10,
                        step: 0.5
                    )
                    Text("\(config.autocorrectTimeout, specifier: "%.1f")s")
                        .frame(width: 40)
                }

                if autocorrectMonitor.isRunning {
                    Divider()
                    statsRow
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var connectionStatusRow: some View {
        HStack {
            Text("Connection:")
                .frame(width: 120, alignment: .leading)
            Circle()
                .fill(connectionDotColor)
                .frame(width: 8, height: 8)
            Text(connectionStatusText)
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
            Button("Test Connection") {
                Task { await autocorrectMonitor.checkConnection() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(autocorrectMonitor.connectionStatus.serverState == .checking)
        }
    }

    private var connectionDotColor: Color {
        switch autocorrectMonitor.connectionStatus.serverState {
        case .unknown: return .gray
        case .checking: return .yellow
        case .connected: return .green
        case .error: return .red
        }
    }

    private var connectionStatusText: String {
        switch autocorrectMonitor.connectionStatus.serverState {
        case .unknown: return "Not checked"
        case .checking: return "Checking..."
        case .connected: return "Connected"
        case .error: return "Disconnected"
        }
    }

    @ViewBuilder
    private var modelStatusRow: some View {
        if case .connected = autocorrectMonitor.connectionStatus.serverState {
            HStack {
                Text("Model Status:")
                    .frame(width: 120, alignment: .leading)
                if autocorrectMonitor.connectionStatus.modelAvailable == true {
                    if !autocorrectMonitor.connectionStatus.availableModels.isEmpty {
                        Text(autocorrectMonitor.connectionStatus.availableModels.joined(separator: ", "))
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Text("Available")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Model '\(config.autocorrectModel)' not found")
                            .foregroundColor(.orange)
                            .font(.caption)
                        if !autocorrectMonitor.connectionStatus.availableModels.isEmpty {
                            Text("Available: \(autocorrectMonitor.connectionStatus.availableModels.joined(separator: ", "))")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var setupInstructions: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text("Setup:")
                    .font(.caption)
                    .fontWeight(.medium)
                if config.autocorrectBackend == .llamaCpp {
                    Text("llama-server -m /path/to/model.gguf --port 8080")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Text("ollama serve")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text("ollama pull \(config.autocorrectModel)")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    @ViewBuilder
    private var statsRow: some View {
        HStack {
            Text("Stats:")
                .frame(width: 120, alignment: .leading)
            Text("\(autocorrectMonitor.correctionCount) corrections")
                .font(.caption)
                .foregroundColor(.secondary)
            if let lastTime = autocorrectMonitor.lastCorrectionTime {
                Text("-- last: \(lastTime, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
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

    private func selectModelFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data]
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            config.llamaServerModelPath = url.path
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
