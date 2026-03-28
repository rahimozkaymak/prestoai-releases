import SwiftUI
import AppKit

struct HistoryView: View {
    @State private var entries: [HistoryEntry] = []
    @State private var searchText = ""
    @State private var selectedMode: String? = nil
    @State private var showClearConfirm = false
    @Environment(\.colorScheme) var colorScheme

    var onSelectEntry: ((HistoryEntry) -> Void)?

    private let modes = ["capture", "study", "quick_prompt", "autosolve"]

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text4(colorScheme))
                TextField("Search history…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text1(colorScheme))
                    .onChange(of: searchText) { _ in reload() }
            }
            .padding(10)
            .background(Theme.inputBg(colorScheme))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Mode filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterPill("All", isSelected: selectedMode == nil) {
                        selectedMode = nil
                        reload()
                    }
                    ForEach(modes, id: \.self) { mode in
                        filterPill(displayName(for: mode), isSelected: selectedMode == mode) {
                            selectedMode = mode
                            reload()
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)

            // Entries list
            if entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Theme.text4(colorScheme))
                    Text(searchText.isEmpty ? "No history yet" : "No results")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.text3(colorScheme))
                    if searchText.isEmpty {
                        Text("Your past analyses will appear here.")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text4(colorScheme))
                    }
                }
                Spacer()
            } else {
                List {
                    ForEach(entries, id: \.id) { entry in
                        HistoryRowView(entry: entry, colorScheme: colorScheme)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectEntry?(entry) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            HistoryManager.shared.delete(id: entries[i].id)
                        }
                        entries.remove(atOffsets: offsets)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            // Footer
            HStack {
                Text("\(entries.count) entries")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text4(colorScheme))
                Spacer()
                Button(action: { showClearConfirm = true }) {
                    Text("Clear History")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(entries.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Theme.bg(colorScheme))
        .onAppear { reload() }
        .alert("Clear History", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                HistoryManager.shared.clearAll()
                entries = []
            }
        } message: {
            Text("This will permanently delete all history entries.")
        }
    }

    private func reload() {
        if searchText.isEmpty {
            entries = HistoryManager.shared.fetch(limit: 100, mode: selectedMode)
        } else {
            entries = HistoryManager.shared.search(query: searchText, limit: 100)
        }
    }

    private func filterPill(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Theme.text1(colorScheme) : Theme.text3(colorScheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Theme.subtleBg(colorScheme) : Color.clear)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.clear : Theme.border(colorScheme), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func displayName(for mode: String) -> String {
        switch mode {
        case "capture": return "Capture"
        case "study": return "Study"
        case "quick_prompt": return "Quick Prompt"
        case "autosolve": return "AutoSolve"
        default: return mode.capitalized
        }
    }
}

// MARK: - History Row

struct HistoryRowView: View {
    let entry: HistoryEntry
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let data = entry.thumbnailData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.subtleBg(colorScheme))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: iconForMode(entry.mode))
                            .font(.system(size: 16))
                            .foregroundColor(Theme.text4(colorScheme))
                    )
            }

            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.firstLine)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text1(colorScheme))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(displayName(for: entry.mode))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.text3(colorScheme))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.subtleBg(colorScheme))
                        .cornerRadius(4)

                    Text(relativeTime(entry.timestamp))
                        .font(.system(size: 11))
                        .foregroundColor(Theme.text4(colorScheme))
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private func iconForMode(_ mode: String) -> String {
        switch mode {
        case "capture": return "camera"
        case "study": return "book"
        case "quick_prompt": return "text.bubble"
        case "autosolve": return "wand.and.stars"
        default: return "doc"
        }
    }

    private func displayName(for mode: String) -> String {
        switch mode {
        case "capture": return "Capture"
        case "study": return "Study"
        case "quick_prompt": return "Prompt"
        case "autosolve": return "AutoSolve"
        default: return mode.capitalized
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 172800 { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
