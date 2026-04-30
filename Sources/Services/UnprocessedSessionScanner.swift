import Foundation

struct UnprocessedSessionScanner {
    func scan() -> [UnprocessedSession] {
        let config = ConfigManager.shared.load()
        let outputDir = config.expandedOutputDirectory

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: outputDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        var sessions: [UnprocessedSession] = []

        for url in contents {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  url.lastPathComponent.hasPrefix("session_") else {
                continue
            }

            let metadataURL = url.appendingPathComponent(UnprocessedSession.metadataFilename)
            guard FileManager.default.fileExists(atPath: metadataURL.path),
                  let data = try? Data(contentsOf: metadataURL),
                  let session = try? JSONDecoder().decode(UnprocessedSession.self, from: data) else {
                continue
            }

            guard FileManager.default.fileExists(atPath: session.micFilePath.path),
                  FileManager.default.fileExists(atPath: session.systemFilePath.path) else {
                continue
            }

            sessions.append(session)
        }

        return sessions.sorted { $0.startTime > $1.startTime }
    }

    func scanOrphaned() -> [OrphanedSession] {
        let config = ConfigManager.shared.load()
        let outputDir = config.expandedOutputDirectory

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: outputDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        var orphaned: [OrphanedSession] = []

        for url in contents {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  url.lastPathComponent.hasPrefix("session_") else {
                continue
            }

            let metadataURL = url.appendingPathComponent(UnprocessedSession.metadataFilename)
            if FileManager.default.fileExists(atPath: metadataURL.path) {
                continue
            }

            let micFile = url.appendingPathComponent("microphone.wav")
            let systemFile = url.appendingPathComponent("system_audio.wav")

            let hasMic = FileManager.default.fileExists(atPath: micFile.path)
            let hasSystem = FileManager.default.fileExists(atPath: systemFile.path)

            guard hasMic || hasSystem else { continue }

            if transcriptExistsForSession(sessionDirName: url.lastPathComponent, outputDir: outputDir) {
                continue
            }

            let session = OrphanedSession(
                sessionDirectory: url,
                micFilePath: hasMic ? micFile : nil,
                systemFilePath: hasSystem ? systemFile : nil,
                estimatedDate: parseSessionDate(from: url.lastPathComponent)
            )
            orphaned.append(session)
        }

        return orphaned.sorted { ($0.estimatedDate ?? .distantPast) > ($1.estimatedDate ?? .distantPast) }
    }

    func scanAll() -> (unprocessed: [UnprocessedSession], orphaned: [OrphanedSession]) {
        return (unprocessed: scan(), orphaned: scanOrphaned())
    }

    func promoteOrphanedSession(_ orphaned: OrphanedSession) -> UnprocessedSession? {
        let sessionDir = orphaned.sessionDirectory
        let micFile = orphaned.micFilePath ?? sessionDir.appendingPathComponent("microphone.wav")
        let systemFile = orphaned.systemFilePath ?? sessionDir.appendingPathComponent("system_audio.wav")

        let startTime = orphaned.estimatedDate ?? Date()

        let session = UnprocessedSession(
            id: UUID(),
            startTime: startTime,
            endTime: startTime,
            sessionDirectory: sessionDir,
            micFilePath: micFile,
            systemFilePath: systemFile
        )

        let metadataURL = sessionDir.appendingPathComponent(UnprocessedSession.metadataFilename)
        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: metadataURL)
            Log.audio.info("Promoted orphaned session: \(sessionDir.lastPathComponent)")
            return session
        } catch {
            Log.audio.error("Failed to promote orphaned session: \(error.localizedDescription)")
            return nil
        }
    }

    func delete(_ session: UnprocessedSession) {
        try? FileManager.default.removeItem(at: session.sessionDirectory)
    }

    private func transcriptExistsForSession(sessionDirName: String, outputDir: URL) -> Bool {
        let dateString = sessionDirName.replacingOccurrences(of: "session_", with: "")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: outputDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return false
        }

        return contents.contains { url in
            url.pathExtension == "md" && url.lastPathComponent.contains(dateString)
        }
    }

    private func parseSessionDate(from dirName: String) -> Date? {
        let dateString = dirName.replacingOccurrences(of: "session_", with: "")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.date(from: dateString)
    }
}
