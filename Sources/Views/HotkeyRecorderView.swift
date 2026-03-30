import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var hotkey: HotkeyCombo
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: { startRecording() }) {
            Text(isRecording ? "Press shortcut..." : hotkey.displayString)
                .frame(minWidth: 120)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mask: NSEvent.ModifierFlags = [.control, .command, .option, .shift]
            let pressed = event.modifierFlags.intersection(mask)

            if event.keyCode == 0x35 && pressed.isEmpty {
                stopRecording()
                return nil
            }

            guard !pressed.isEmpty else { return nil }

            hotkey = HotkeyCombo(keyCode: event.keyCode, modifiers: pressed.rawValue)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }
}
