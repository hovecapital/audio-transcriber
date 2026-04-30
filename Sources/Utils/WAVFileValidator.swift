import Foundation

enum WAVFileValidator {
    struct ValidationResult {
        let isValid: Bool
        let fileSize: UInt64
        let hasAudioData: Bool
        let errorMessage: String?
    }

    private static let wavHeaderSize: UInt64 = 44
    private static let dataChunkOffset: UInt64 = 4088
    private static let audioDataOffset: UInt64 = 4096
    private static let riffSizeOffset: UInt64 = 4
    private static let dataSizeOffset: UInt64 = 4092
    private static let maxUInt32: UInt64 = UInt64(UInt32.max)

    struct RepairResult {
        let repaired: Bool
        let error: String?
    }

    static func repairHeaderIfNeeded(url: URL) -> RepairResult {
        let fileSize: UInt64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            fileSize = attrs[.size] as? UInt64 ?? 0
        } catch {
            return RepairResult(repaired: false, error: "Cannot read file attributes: \(error.localizedDescription)")
        }

        guard fileSize > audioDataOffset else {
            return RepairResult(repaired: false, error: "File too small to contain audio data (\(fileSize) bytes)")
        }

        guard fileSize - 8 <= maxUInt32 else {
            return RepairResult(repaired: false, error: "File exceeds 4GB WAV limit (\(fileSize) bytes)")
        }

        guard let handle = try? FileHandle(forUpdating: url) else {
            return RepairResult(repaired: false, error: "Cannot open file for updating: \(url.lastPathComponent)")
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: riffSizeOffset)
            guard let riffData = try handle.read(upToCount: 4), riffData.count == 4 else {
                return RepairResult(repaired: false, error: "Cannot read RIFF size")
            }
            let currentRIFFSize = riffData.withUnsafeBytes { $0.load(as: UInt32.self) }

            try handle.seek(toOffset: dataSizeOffset)
            guard let dataData = try handle.read(upToCount: 4), dataData.count == 4 else {
                return RepairResult(repaired: false, error: "Cannot read data chunk size")
            }
            let currentDataSize = dataData.withUnsafeBytes { $0.load(as: UInt32.self) }

            let expectedRIFFSize = UInt32(fileSize - 8)
            let expectedDataSize = UInt32(fileSize - audioDataOffset)

            if currentRIFFSize == expectedRIFFSize && currentDataSize == expectedDataSize {
                return RepairResult(repaired: false, error: nil)
            }

            guard currentDataSize == 0 || currentRIFFSize == UInt32(dataChunkOffset) else {
                return RepairResult(repaired: false, error: "Unexpected header values (RIFF=\(currentRIFFSize), data=\(currentDataSize)), skipping repair")
            }

            var riffBytes = expectedRIFFSize.littleEndian
            var dataBytes = expectedDataSize.littleEndian

            try handle.seek(toOffset: riffSizeOffset)
            try handle.write(contentsOf: Data(bytes: &riffBytes, count: 4))

            try handle.seek(toOffset: dataSizeOffset)
            try handle.write(contentsOf: Data(bytes: &dataBytes, count: 4))

            Log.transcription.info("Repaired WAV header for \(url.lastPathComponent): RIFF \(currentRIFFSize)->\(expectedRIFFSize), data \(currentDataSize)->\(expectedDataSize)")

            return RepairResult(repaired: true, error: nil)
        } catch {
            return RepairResult(repaired: false, error: "Header repair I/O error: \(error.localizedDescription)")
        }
    }

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
