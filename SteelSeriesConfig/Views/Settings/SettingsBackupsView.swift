import AppKit
import SwiftUI

/// Local backups taken immediately before each write, newest first.
///
/// Nothing here talks to SteelSeries: these are plain JSON files under Application
/// Support, so they survive a GG uninstall and can be read without this app.
struct SettingsBackupsView: View {

    @Environment(ConfigurationStore.self) private var store

    @State private var selectedBackup: URL?
    @State private var confirmRestore = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .onAppear { store.refreshBackups() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Backups")
                    .font(.title3.weight(.semibold))
                Text("A snapshot is saved automatically before every write to the engine.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Show Folder") {
                NSWorkspace.shared.activateFileViewerSelecting([BackupStore.rootURL])
            }
            Button("Refresh") {
                store.refreshBackups()
            }
        }
        .padding(20)
    }

    private var list: some View {
        Group {
            if store.backups.isEmpty {
                emptyState
            } else {
                List(store.backups, id: \.self, selection: $selectedBackup) { url in
                    row(url)
                        .tag(url)
                }
                .listStyle(.inset)
            }
        }
    }

    private func row(_ url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.formattedDate(url))
                    .font(.body)
                Text("\(ByteCountFormatter.string(fromByteCount: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), countStyle: .file)) · \(url.lastPathComponent)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button("Load") {
                selectedBackup = url
                confirmRestore = true
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
        .alert("Load this backup?", isPresented: $confirmRestore) {
            Button("Load", role: .destructive) {
                if let selectedBackup { store.stageBackup(selectedBackup) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The backup replaces the editor's current values. It is written to the device only when you press Save.")
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Delete", role: .destructive) {
                selectedBackup = url
                confirmDelete = true
            }
        }
        .alert("Delete this backup?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let selectedBackup {
                    try? FileManager.default.removeItem(at: selectedBackup)
                    store.refreshBackups()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text("No backups yet")
                .font(.headline)
            Text("Save a change to this configuration and one will appear here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    static func formattedDate(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        guard let date = formatter.date(from: name) else { return name }

        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .medium
        return display.string(from: date)
    }
}
