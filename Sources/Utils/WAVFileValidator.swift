import Foundation

enum WAVFileValidator {
    struct ValidationResult {
        let isValid: Bool
        let fileSize: UInt64
        let hasAudioData: Bool
        let errorMessage: String?
    }

    private static let wavHeaderSize: UInt64 = 44

    static func validate(url: URL) -> ValidationResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ValidationResult(
                isValid: false,
                fileSize: 0,
                hasAudioData: false,
                errorMessage: "File does not exist: \(url.lastPathComponent)"
            )
        }

        let fileSize: UInt64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            fileSize = attrs[.size] as? UInt64 ?? 0
        } catch {
            return ValidationResult(
                isValid: false,
                fileSize: 0,
                hasAudioData: false,
                errorMessage: "Cannot read file attributes: \(error.localizedDescription)"
            )
        }

        guard fileSize > 0 else {
            return ValidationResult(
                isValid: false,
                fileSize: 0,
                hasAudioData: false,
                errorMessage: "File is empty (0 bytes)"
            )
        }

        let hasAudioData = fileSize > wavHeaderSize

        guard hasAudioData else {
            return ValidationResult(
                isValid: false,
                fileSize: fileSize,
                hasAudioData: false,
                errorMessage: "File is header-only (\(fileSize) bytes, no audio data)"
            )
        }

        return ValidationResult(
            isValid: true,
            fileSize: fileSize,
            hasAudioData: true,
            errorMessage: nil
        )
    }
}
