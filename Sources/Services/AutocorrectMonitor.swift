import Cocoa
import Combine

enum OllamaConnectionState: Equatable {
    case unknown
    case checking
    case connected
    case error(String)
}

struct OllamaConnectionStatus: Equatable {
    var serverState: OllamaConnectionState = .unknown
    var modelAvailable: Bool?
    var availableModels: [String] = []
    var lastChecked: Date?
}

@MainActor
final class AutocorrectMonitor: ObservableObject {
    static let shared = AutocorrectMonitor()

    @Published var isRunning = false
    @Published var connectionStatus = OllamaConnectionStatus()
    @Published var correctionCount = 0
    @Published var lastCorrectionTime: Date?

    private var hotkeyMonitor: Any?
    private var ollamaClient: OllamaClient?
    private var isProcessing = false

    private static let abbreviations: Set<String> = [
        "Dr", "Mr", "Mrs", "Ms", "Jr", "Sr", "Prof", "St",
        "vs", "etc", "Inc", "Ltd", "i.e", "e.g"
    ]

    private init() {}

    func checkConnection() async {
        connectionStatus.serverState = .checking

        let config = ConfigManager.shared.load()
        let client = OllamaClient(
            backend: config.autocorrectBackend,
            serverURL: config.autocorrectServerURL,
            model: config.autocorrectModel,
            timeout: config.autocorrectTimeout
        )

        do {
            try await client.checkHealth()
            let models = try await client.listModels()
            connectionStatus.availableModels = models

            let modelFound = models.contains(where: { $0.contains(config.autocorrectModel) })
            connectionStatus.modelAvailable = config.autocorrectBackend == .llamaCpp
                ? !models.isEmpty
                : modelFound
            connectionStatus.serverState = .connected
        } catch {
            connectionStatus.serverState = .error(error.localizedDescription)
            connectionStatus.modelAvailable = nil
            connectionStatus.availableModels = []
        }

        connectionStatus.lastChecked = Date()
    }

    func start() {
        guard !isRunning else { return }

        guard AccessibilityReader.isTrusted(promptIfNeeded: true) else {
            Log.autocorrect.warning("Accessibility permission not granted")
            return
        }

        let config = ConfigManager.shared.load()
        ollamaClient = OllamaClient(
            backend: config.autocorrectBackend,
            serverURL: config.autocorrectServerURL,
            model: config.autocorrectModel,
            timeout: config.autocorrectTimeout
        )

        let combo = config.autocorrectHotkey
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard combo.matches(event) else { return }
            Task { @MainActor in
                await self?.handleSentenceEnd()
            }
        }

        isRunning = true
        correctionCount = 0
        lastCorrectionTime = nil
        Log.autocorrect.info("Autocorrect monitor started (hotkey: \(combo.displayString))")

        Task {
            await checkConnection()
        }
    }

    func stop() {
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        hotkeyMonitor = nil
        ollamaClient = nil
        isRunning = false
        correctionCount = 0
        lastCorrectionTime = nil
        Log.autocorrect.info("Autocorrect monitor stopped")
    }

    func reregisterHotkey() {
        guard isRunning else { return }
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        let config = ConfigManager.shared.load()
        let combo = config.autocorrectHotkey
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard combo.matches(event) else { return }
            Task { @MainActor in
                await self?.handleSentenceEnd()
            }
        }
        Log.autocorrect.info("Autocorrect hotkey re-registered (\(combo.displayString))")
    }

    private func handleSentenceEnd() async {
        guard !isProcessing else { return }
        guard let client = ollamaClient else { return }

        isProcessing = true
        defer { isProcessing = false }

        guard let focused = AccessibilityReader.readFocusedElementText() else { return }

        let cursorPosition = focused.selectedRange.location
        guard cursorPosition > 0 else { return }

        guard let (sentence, sentenceRange) = extractLastSentence(from: focused.text, cursorPosition: cursorPosition) else {
            return
        }

        guard sentence.count >= 3 else { return }

        Log.autocorrect.debug("Correcting: \(sentence)")

        do {
            let corrected = try await client.correct(sentence)
            Log.autocorrect.info("Correction: \"\(sentence)\" -> \"\(corrected)\"")
            correctionCount += 1
            lastCorrectionTime = Date()

            let cfRange = CFRange(location: sentenceRange.lowerBound, length: sentenceRange.count)
            let success = AccessibilityReader.replaceText(in: focused.element, range: cfRange, with: corrected)
            if !success {
                Log.autocorrect.debug("Failed to apply correction")
            }
        } catch {
            Log.autocorrect.debug("Correction failed: \(error.localizedDescription)")
            if case OllamaError.serverUnreachable = error {
                connectionStatus.serverState = .error(error.localizedDescription)
            } else if case OllamaError.requestTimeout = error {
                connectionStatus.serverState = .error(error.localizedDescription)
            }
        }
    }

    private func extractLastSentence(from text: String, cursorPosition: Int) -> (String, Range<Int>)? {
        let endIndex = cursorPosition
        guard endIndex <= text.count else { return nil }

        let prefix = String(text.prefix(endIndex))

        var startIndex = endIndex - 1
        while startIndex > 0 {
            let charIndex = prefix.index(prefix.startIndex, offsetBy: startIndex - 1)
            let char = prefix[charIndex]

            if char == "\n" {
                break
            }

            if char == "." || char == "!" || char == "?" {
                if char == "." && isAbbreviationOrDecimal(text: prefix, dotPosition: startIndex - 1) {
                    startIndex -= 1
                    continue
                }

                if char == "." && isEllipsis(text: prefix, dotPosition: startIndex - 1) {
                    startIndex -= 1
                    continue
                }

                break
            }

            startIndex -= 1
        }

        let rawStart = prefix.index(prefix.startIndex, offsetBy: startIndex)
        let rawEnd = prefix.index(prefix.startIndex, offsetBy: endIndex)
        let rawSubstring = String(prefix[rawStart..<rawEnd])
        let leadingSpaces = rawSubstring.prefix(while: { $0 == " " || $0 == "\t" }).count
        let adjustedStart = startIndex + leadingSpaces
        let sentence = rawSubstring.trimmingCharacters(in: .whitespaces)

        guard !sentence.isEmpty else { return nil }

        return (sentence, adjustedStart..<endIndex)
    }

    private func isAbbreviationOrDecimal(text: String, dotPosition: Int) -> Bool {
        if dotPosition > 0 && dotPosition < text.count - 1 {
            let beforeIndex = text.index(text.startIndex, offsetBy: dotPosition - 1)
            let afterIndex = text.index(text.startIndex, offsetBy: dotPosition + 1)
            if text[beforeIndex].isNumber && text[afterIndex].isNumber {
                return true
            }
        }

        var wordStart = dotPosition - 1
        while wordStart >= 0 {
            let idx = text.index(text.startIndex, offsetBy: wordStart)
            if !text[idx].isLetter && text[idx] != "." {
                wordStart += 1
                break
            }
            wordStart -= 1
        }
        if wordStart < 0 { wordStart = 0 }

        let word = String(text[text.index(text.startIndex, offsetBy: wordStart)..<text.index(text.startIndex, offsetBy: dotPosition)])

        return Self.abbreviations.contains(word)
    }

    private func isEllipsis(text: String, dotPosition: Int) -> Bool {
        guard dotPosition >= 2 else { return false }
        let idx1 = text.index(text.startIndex, offsetBy: dotPosition - 1)
        let idx2 = text.index(text.startIndex, offsetBy: dotPosition - 2)
        return text[idx1] == "." && text[idx2] == "."
    }
}
