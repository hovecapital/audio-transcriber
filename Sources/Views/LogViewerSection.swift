import SwiftUI

struct LogViewerSection: View {
    @ObservedObject private var store = LogStore.shared
    @State private var enabledLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @State private var selectedCategory: String?
    @State private var autoScroll = true

    private var categories: [String] {
        Array(Set(store.entries.map(\.category))).sorted()
    }

    private var filteredEntries: [LogEntry] {
        store.entries.filter { entry in
            enabledLevels.contains(entry.level)
                && (selectedCategory == nil || entry.category == selectedCategory)
        }
    }

    var body: some View {
        GroupBox("Log Viewer") {
            VStack(alignment: .leading, spacing: 8) {
                filterBar
                logList
                controlBar
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(LogLevel.allCases, id: \.self) { level in
                Toggle(isOn: Binding(
                    get: { enabledLevels.contains(level) },
                    set: { enabled in
                        if enabled {
                            enabledLevels.insert(level)
                        } else {
                            enabledLevels.remove(level)
                        }
                    }
                )) {
                    Text(level.rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(level.color)
                }
                .toggleStyle(.button)
                .controlSize(.small)
            }

            Spacer()

            Menu {
                Button("All Categories") {
                    selectedCategory = nil
                }
                Divider()
                ForEach(categories, id: \.self) { category in
                    Button(category) {
                        selectedCategory = category
                    }
                }
            } label: {
                Text(selectedCategory ?? "All Categories")
                    .font(.caption)
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredEntries) { entry in
                        logRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(4)
            }
            .frame(height: 200)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onChange(of: filteredEntries.count) { _ in
                if autoScroll, let last = filteredEntries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    @ViewBuilder
    private func logRow(_ entry: LogEntry) -> some View {
        Text("\(Self.timeFormatter.string(from: entry.timestamp)) | \(entry.level.rawValue) | \(entry.category) | \(entry.message)")
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(entry.level.color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var controlBar: some View {
        HStack {
            Toggle("Auto-scroll", isOn: $autoScroll)
                .controlSize(.small)
            Spacer()
            Text("\(filteredEntries.count) entries")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Clear") {
                store.clear()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
