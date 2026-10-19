import SwiftUI

/// Shown when no device is detected at all — the engine answered, the list is empty.
struct NoDeviceView: View {

    @Environment(ConfigurationStore.self) private var store

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "computermouse")
                .font(.system(size: 34))
                .foregroundColor(.secondary)

            Text("No devices found")
                .font(.headline)

            Text("Plug in a SteelSeries peripheral, or turn it on if it is wireless.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Scan Again") {
                Task { await store.bootstrap() }
            }
            .controlSize(.small)
            .disabled(store.isBusy)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// Shown when the engine itself cannot be reached — a distinct state from "no
/// device", because the remedy is different (start GG, or fix the install).
struct EngineUnavailableView: View {

    let message: String

    @Environment(ConfigurationStore.self) private var store

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundColor(.orange)

            Text("Engine not reachable")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button("Start SteelSeries GG") {
                    store.launchEngine()
                }
                .controlSize(.small)

                Button("Retry") {
                    Task { await store.bootstrap() }
                }
                .controlSize(.small)
                .disabled(store.isBusy)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// Shown while discovery is in flight so the panel never flashes an empty state.
struct BarLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Looking for your SteelSeries devices…")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
