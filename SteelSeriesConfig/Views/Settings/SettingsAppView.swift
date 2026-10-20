import AppKit
import SwiftUI

/// Device connection details, maintenance actions, and the app's own provenance.
struct SettingsAppView: View {

    @Environment(ConfigurationStore.self) private var store
    private let updates = UpdateChecker.shared

    var body: some View {
        Form {
            Section("Device") {
                SettingsRow(
                    title: "Connection",
                    description: "Talks to the mouse directly over HID — cable, 2.4 GHz receiver or Bluetooth. SteelSeries GG is not needed, and nothing is sent to SteelSeries' servers."
                ) {
                    statusLabel
                }

                SettingsRow(
                    title: "Devices detected",
                    description: "Supported mice found on the HID bus on the last scan."
                ) {
                    Text("\(store.devices.count)")
                        .font(.callout)
                        .monospacedDigit()
                        .frame(minWidth: 90, alignment: .trailing)
                }

                SettingsRow(
                    title: "Profile",
                    description: "The mouse cannot report its settings, so the app keeps them here and re-applies them when the mouse reconnects."
                ) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([LocalProfileStore.fileURL])
                    }
                }

                SettingsRow(
                    title: "Rescan",
                    description: "Reload the profile and look for the mouse again."
                ) {
                    Button("Rescan") {
                        Task { await store.bootstrap() }
                    }
                    .disabled(store.isBusy)
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
                    description: "Unofficial, login-free configuration tool for SteelSeries peripherals. Not affiliated with SteelSeries. Every save is preceded by an automatic backup; the HID protocol follows the open-source rivalcfg project."
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
