import AppKit
import SwiftUI

/// Engine connection details, maintenance actions, and the app's own provenance.
struct SettingsAppView: View {

    @Environment(ConfigurationStore.self) private var store

    var body: some View {
        Form {
            Section("Engine") {
                SettingsRow(
                    title: "Endpoint",
                    description: "Read from \(CorePropsLocator.defaultPath). Discovery falls back to \(CorePropsLocator.fallbackHostAndPort) if the file is missing."
                ) {
                    Text(store.engineURL?.absoluteString ?? "Not connected")
                        .font(.callout)
                        .monospaced()
                        .foregroundColor(store.engineURL == nil ? .secondary : .primary)
                        .frame(minWidth: 150, alignment: .trailing)
                }

                SettingsRow(
                    title: "Status",
                    description: "The engine is the local SteelSeries GG core. This app never contacts SteelSeries' servers and never uses a login."
                ) {
                    statusLabel
                }

                SettingsRow(
                    title: "Devices detected",
                    description: "Reported by GET /devices on the last scan."
                ) {
                    Text("\(store.devices.count)")
                        .font(.callout)
                        .monospacedDigit()
                        .frame(minWidth: 90, alignment: .trailing)
                }

                SettingsRow(
                    title: "Rescan",
                    description: "Re-read coreProps.json and reload devices and configurations."
                ) {
                    Button("Rescan") {
                        Task { await store.bootstrap() }
                    }
                    .disabled(store.isBusy)
                }

                SettingsRow(
                    title: "SteelSeries GG",
                    description: "Launch the official app if the engine is not responding. Its own settings are untouched by doing this."
                ) {
                    Button("Open GG") {
                        store.launchEngine()
                    }
                }
            }

            Section("Backups") {
                SettingsRow(
                    title: "Backup folder",
                    description: "JSON snapshots written immediately before each save."
                ) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([BackupStore.rootURL])
                    }
                }
            }

            Section("About") {
                SettingsRow(
                    title: "SteelSeries Config",
                    description: "Unofficial, login-free configuration tool for SteelSeries peripherals. Not affiliated with SteelSeries. Writes are read-modify-write with an automatic pre-write backup; the settings schema was derived by reverse-engineering the official client."
                ) {
                    Text("0.1.0")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(minWidth: 60, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch store.phase {
        case .booting:
            Label("Searching…", systemImage: "hourglass")
                .foregroundColor(.secondary)
        case .ready:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .unavailable(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}
