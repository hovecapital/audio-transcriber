import Foundation

struct UnprocessedSession: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let sessionDirectory: URL
    let micFilePath: URL
    let systemFilePath: URL

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    var formattedDuration: String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: startTime)
    }

    var totalFileSizeBytes: Int64 {
        let fm = FileManager.default
        let micSize = (try? fm.attributesOfItem(atPath: micFilePath.path)[.size] as? Int64) ?? 0
        let systemSize = (try? fm.attributesOfItem(atPath: systemFilePath.path)[.size] as? Int64) ?? 0
        return micSize + systemSize
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: totalFileSizeBytes, countStyle: .file)
    }

    static let metadataFilename = "unprocessed.json"
}
