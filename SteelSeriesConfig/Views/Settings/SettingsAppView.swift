import AppKit
import SwiftUI

/// Engine connection details, maintenance actions, and the app's own provenance.
struct SettingsAppView: View {

    @Environment(ConfigurationStore.self) private var store
    private let updates = UpdateChecker.shared

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

            Section("Updates") {
                SettingsRow(
                    title: "Status",
                    description: "Checked against GitHub every six hours and downloaded in the background. Nothing is replaced until you install."
                ) {
                    updateStatusLabel
                }

                SettingsRow(
                    title: "Check for updates",
                    description: "Installed: \(UpdateChecker.installedDescription)."
                ) {
                    Button("Check Now") {
                        Task { await updates.checkForUpdates() }
                    }
                    .disabled(updates.isWorking)
                }

                if let build = updates.readyBuild {
                    SettingsRow(
                        title: "Build \(build) is ready",
                        description: updates.installBlockReason ?? "Replaces this app and relaunches it."
                    ) {
                        Button("Install & Relaunch") {
                            updates.install()
                        }
                        .disabled(updates.installBlockReason != nil)
                    }
                }
            }

            Section("About") {
                SettingsRow(
                    title: "SteelSeries Config",
                    description: "Unofficial, login-free configuration tool for SteelSeries peripherals. Not affiliated with SteelSeries. Writes are read-modify-write with an automatic pre-write backup; the settings schema was derived by reverse-engineering the official client."
                ) {
                    Text(UpdateChecker.installedDescription)
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
    private var updateStatusLabel: some View {
        switch updates.state {
        case .idle:
            Text("Not checked yet")
                .foregroundColor(.secondary)
        case .checking:
            Label("Checking…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundColor(.secondary)
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .downloading(let build):
            Label("Downloading build \(build)…", systemImage: "arrow.down.circle")
                .foregroundColor(.secondary)
        case .ready(let build):
            Label("Build \(build) ready", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
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
