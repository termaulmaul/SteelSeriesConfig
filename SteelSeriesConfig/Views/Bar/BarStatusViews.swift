import SwiftUI

/// Shown when no device is detected at all — nothing supported is on the HID bus.
struct NoDeviceView: View {

    @Environment(ConfigurationStore.self) private var store

    var body: some View {
        VStack(spacing: BarMetrics.s) {
            Image(systemName: "computermouse")
                .font(.system(size: 34))
                .foregroundColor(.secondary)

            Text("No devices found")
                .font(.headline)

            Text("Connect the mouse by cable, its 2.4 GHz receiver, or Bluetooth.")
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
        .padding(.vertical, BarMetrics.s)
    }
}

/// Shown when the app cannot start talking to devices at all — a distinct state from
/// "no device".
struct EngineUnavailableView: View {

    let message: String

    @Environment(ConfigurationStore.self) private var store

    var body: some View {
        VStack(spacing: BarMetrics.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundColor(.orange)

            Text("Mouse not reachable")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: BarMetrics.s) {

                Button("Retry") {
                    Task { await store.bootstrap() }
                }
                .controlSize(.small)
                .disabled(store.isBusy)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BarMetrics.s)
    }
}

/// Shown while discovery is in flight so the panel never flashes an empty state.
struct BarLoadingView: View {
    var body: some View {
        VStack(spacing: BarMetrics.m) {
            ProgressView()
            Text("Looking for your SteelSeries devices…")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BarMetrics.xl)
    }
}
