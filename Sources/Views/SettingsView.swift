import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var config: AppConfig
    @State private var launchAtLogin: Bool
    @Environment(\.dismiss) private var dismiss

    init() {
        _config = State(initialValue: ConfigManager.shared.load())
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("General") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            setLaunchAtLogin(newValue)
                        }
                }
                .padding(8)
            }

            GroupBox("Output") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Save Location:")
                            .frame(width: 100, alignment: .leading)
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

            GroupBox("Transcription") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Whisper Model:")
                            .frame(width: 100, alignment: .leading)
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

            GroupBox("Speaker Labels") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Microphone:")
                            .frame(width: 100, alignment: .leading)
                        TextField("Person 1", text: $config.person1Label)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("System Audio:")
                            .frame(width: 100, alignment: .leading)
                        TextField("Person 2", text: $config.person2Label)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(8)
            }

            Spacer()

            HStack {
                Button("Reset to Defaults") {
                    config = .default
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    ConfigManager.shared.save(config)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480, height: 520)
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
}
