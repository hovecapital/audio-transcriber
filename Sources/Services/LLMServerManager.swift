import Foundation

@MainActor
public final class LLMServerManager: ObservableObject {
    public static let shared = LLMServerManager()

    @Published private(set) var isRunning = false

    private var process: Process?
    private var retryCount = 0
    private let maxRetries = 3

    private init() {}

    public func startServer() {
        guard !isRunning else { return }

        let config = ConfigManager.shared.load()
        let hasHFModel = !config.llamaServerHFModel.isEmpty
        let hasLocalModel = !config.llamaServerModelPath.isEmpty
        guard hasHFModel || hasLocalModel else {
            Log.llmServer.warning("No model configured, skipping LLM server start")
            return
        }

        guard let binaryPath = findLlamaServerExecutable() else {
            Log.llmServer.error("llama-server binary not found")
            return
        }

        let port = parsePort(from: config.autocorrectServerURL)

        var args: [String]
        if hasHFModel {
            args = ["-hf", config.llamaServerHFModel]
        } else {
            args = ["-m", config.llamaServerModelPath]
        }
        args += ["--port", String(port), "--host", "0.0.0.0"]

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRunning = false
                self.process = nil

                if terminatedProcess.terminationStatus != 0 && self.retryCount < self.maxRetries {
                    self.retryCount += 1
                    Log.llmServer.warning("llama-server crashed, restarting (attempt \(self.retryCount)/\(self.maxRetries))")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    self.startServer()
                } else if self.retryCount >= self.maxRetries {
                    Log.llmServer.error("llama-server exceeded max retries, giving up")
                }
            }
        }

        do {
            try proc.run()
            process = proc
            isRunning = true
            retryCount = 0
            Log.llmServer.info("llama-server started (pid: \(proc.processIdentifier), port: \(port))")
        } catch {
            Log.llmServer.error("Failed to start llama-server: \(error.localizedDescription)")
        }
    }

    public func stopServer() {
        guard let proc = process, proc.isRunning else {
            isRunning = false
            process = nil
            return
        }

        retryCount = maxRetries
        proc.terminate()

        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            if proc.isRunning {
                proc.interrupt()
            }
        }

        process = nil
        isRunning = false
        Log.llmServer.info("llama-server stopped")
    }

    private func findLlamaServerExecutable() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server"
        ]

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func parsePort(from urlString: String) -> Int {
        guard let url = URL(string: urlString), let port = url.port else {
            return 8080
        }
        return port
    }
}
