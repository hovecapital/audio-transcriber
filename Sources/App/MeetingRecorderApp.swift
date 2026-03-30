import SwiftUI

@main
struct MeetingRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hotkeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.general.info("MeetingRecorder app launched")
        NSApp.setActivationPolicy(.accessory)

        setupMenuBar()
        ensureOutputDirectoryExists()
        restoreAutocorrectState()
        setupDictationHotkey()
        Log.general.info("App initialization complete")
    }

    private func setupMenuBar() {
        Log.general.debug("Setting up menu bar...")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Meeting Recorder")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 220, height: 280)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                appState: AppState.shared,
                recordingManager: AudioRecordingManager.shared,
                autocorrectMonitor: AutocorrectMonitor.shared,
                dictationService: DictationService.shared
            )
        )
        self.popover = popover

        setupStatusObserver()
        Log.general.debug("Menu bar setup complete")
    }

    private func setupStatusObserver() {
        Task { @MainActor in
            for await _ in AppState.shared.$status.values {
                updateMenuBarIcon()
            }
        }
        Task { @MainActor in
            for await _ in AppState.shared.$dictationStatus.values {
                updateMenuBarIcon()
            }
        }
    }

    @MainActor
    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        let color: NSColor

        if AppState.shared.dictationStatus != .idle {
            switch AppState.shared.dictationStatus {
            case .listening:
                symbolName = "mic.fill"
                color = .systemBlue
            case .transcribing:
                symbolName = "ellipsis.circle.fill"
                color = .systemBlue
            case .idle:
                symbolName = "waveform"
                color = .labelColor
            }
        } else {
            switch AppState.shared.status {
            case .idle:
                symbolName = "waveform"
                color = .labelColor
            case .recording:
                symbolName = "record.circle.fill"
                color = .systemRed
            case .processing:
                symbolName = "gear"
                color = .systemOrange
            case .completed:
                symbolName = "checkmark.circle.fill"
                color = .systemGreen
            case .error:
                symbolName = "exclamationmark.circle.fill"
                color = .systemRed
            case .warning:
                symbolName = "exclamationmark.triangle.fill"
                color = .systemOrange
            }
        }

        let isDefaultState = AppState.shared.status == .idle && AppState.shared.dictationStatus == .idle
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        var image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image = image?.withSymbolConfiguration(config)
        image?.isTemplate = isDefaultState

        if !isDefaultState {
            if let tintedImage = image?.copy() as? NSImage {
                tintedImage.lockFocus()
                color.set()
                let rect = NSRect(origin: .zero, size: tintedImage.size)
                rect.fill(using: .sourceAtop)
                tintedImage.unlockFocus()
                button.image = tintedImage
                return
            }
        }

        button.image = image
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func setupDictationHotkey() {
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains(.option),
                  event.keyCode == 0x02 else { return }
            Task { @MainActor in
                DictationService.shared.toggle()
            }
        }
        Log.general.info("Dictation hotkey registered (Option+D)")
    }

    private func restoreAutocorrectState() {
        let config = ConfigManager.shared.load()
        if config.autocorrectEnabled {
            Task { @MainActor in
                AutocorrectMonitor.shared.start()
            }
        }
    }

    private func ensureOutputDirectoryExists() {
        let config = ConfigManager.shared.load()
        let outputDir = config.expandedOutputDirectory
        Log.general.debug("Ensuring output directory exists: \(outputDir.path)")
        try? FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true
        )
    }
}
