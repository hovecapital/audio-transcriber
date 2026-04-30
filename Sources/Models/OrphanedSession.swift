import Foundation

struct OrphanedSession: Identifiable {
    let id = UUID()
    let sessionDirectory: URL
    let micFilePath: URL?
    let systemFilePath: URL?
    let estimatedDate: Date?

    var formattedDate: String {
        guard let date = estimatedDate else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    var totalFileSizeBytes: Int64 {
        let fm = FileManager.default
        let micSize = micFilePath.flatMap { try? fm.attributesOfItem(atPath: $0.path)[.size] as? Int64 } ?? 0
        let systemSize = systemFilePath.flatMap { try? fm.attributesOfItem(atPath: $0.path)[.size] as? Int64 } ?? 0
        return micSize + systemSize
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: totalFileSizeBytes, countStyle: .file)
    }
}
