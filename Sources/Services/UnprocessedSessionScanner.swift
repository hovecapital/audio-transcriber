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

    func delete(_ session: UnprocessedSession) {
        try? FileManager.default.removeItem(at: session.sessionDirectory)
    }
}
