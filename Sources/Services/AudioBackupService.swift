import Foundation

final class AudioBackupService {
    private let backupBaseDirectory: URL

    init(config: AppConfig) {
        backupBaseDirectory = config.expandedBackupDirectory
    }

    func backupSessionFiles(micFile: URL, systemFile: URL, sessionStart: Date) -> BackupResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let sessionName = "session_\(formatter.string(from: sessionStart))"
        let sessionBackupDir = backupBaseDirectory.appendingPathComponent(sessionName)

        do {
            try FileManager.default.createDirectory(at: sessionBackupDir, withIntermediateDirectories: true)
        } catch {
            Log.audio.error("Failed to create backup directory: \(error.localizedDescription)")
            return BackupResult(success: false, backupDirectory: nil, errors: ["Failed to create backup directory: \(error.localizedDescription)"])
        }

        var errors: [String] = []
        let micBackup = sessionBackupDir.appendingPathComponent(micFile.lastPathComponent)
        let systemBackup = sessionBackupDir.appendingPathComponent(systemFile.lastPathComponent)

        if FileManager.default.fileExists(atPath: micFile.path) {
            do {
                try FileManager.default.copyItem(at: micFile, to: micBackup)
                let sourceSize = fileSize(at: micFile)
                let backupSize = fileSize(at: micBackup)
                if sourceSize != backupSize {
                    errors.append("Mic backup size mismatch: source=\(sourceSize), backup=\(backupSize)")
                }
                Log.audio.info("Mic audio backed up to: \(micBackup.path) (\(backupSize) bytes)")
            } catch {
                errors.append("Failed to backup mic file: \(error.localizedDescription)")
                Log.audio.error("Failed to backup mic file: \(error.localizedDescription)")
            }
        } else {
            errors.append("Mic file does not exist: \(micFile.path)")
            Log.audio.warning("Mic file does not exist for backup: \(micFile.path)")
        }

        if FileManager.default.fileExists(atPath: systemFile.path) {
            do {
                try FileManager.default.copyItem(at: systemFile, to: systemBackup)
                let sourceSize = fileSize(at: systemFile)
                let backupSize = fileSize(at: systemBackup)
                if sourceSize != backupSize {
                    errors.append("System backup size mismatch: source=\(sourceSize), backup=\(backupSize)")
                }
                Log.audio.info("System audio backed up to: \(systemBackup.path) (\(backupSize) bytes)")
            } catch {
                errors.append("Failed to backup system file: \(error.localizedDescription)")
                Log.audio.error("Failed to backup system file: \(error.localizedDescription)")
            }
        } else {
            errors.append("System file does not exist: \(systemFile.path)")
            Log.audio.warning("System file does not exist for backup: \(systemFile.path)")
        }

        let success = errors.isEmpty
        Log.audio.info("Backup \(success ? "completed successfully" : "completed with errors") to: \(sessionBackupDir.path)")
        return BackupResult(success: success, backupDirectory: sessionBackupDir, errors: errors)
    }

    private func fileSize(at url: URL) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else {
            return 0
        }
        return size
    }

    struct BackupResult {
        let success: Bool
        let backupDirectory: URL?
        let errors: [String]
    }
}
