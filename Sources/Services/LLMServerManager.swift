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
        killExistingLlamaServers(port: port)

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

    private func killExistingLlamaServers(port: Int) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-ti", "tcp:\(port)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !output.isEmpty else { return }

            let pids = output.components(separatedBy: .newlines).compactMap { Int32($0) }
            for pid in pids {
                Log.llmServer.info("Killing existing process on port \(port) (pid: \(pid))")
                kill(pid, SIGTERM)
            }

            if !pids.isEmpty {
                Thread.sleep(forTimeInterval: 0.5)
            }
        } catch {
            Log.llmServer.warning("Failed to check for existing llama-server: \(error.localizedDescription)")
        }
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
