import SwiftUI

/// Content of the menu bar popover.
///
/// Layout mirrors the reference app: a fixed 320pt column, a header, then Dividers
/// separating independent control groups. Sections are conditional on capability —
/// a device that does not model CPI simply does not render the CPI block, rather
/// than rendering controls that write keys the device never had.
struct BarView: View {

    @Environment(ConfigurationStore.self) private var store

    var body: some View {
        Group {
            switch store.phase {
            case .booting:
                BarLoadingView()
                    .padding(16)

            case .unavailable(let message):
                VStack(spacing: 16) {
                    EngineUnavailableView(message: message)
                }
                .padding(16)

            case .ready:
                if store.selectedDevice == nil {
                    NoDeviceView()
                        .padding(16)
                } else {
                    connectedLayout
                }
            }
        }
        .frame(width: 320)
    }

    private var connectedLayout: some View {
        VStack(spacing: 16) {
            BarHeaderView()

            if store.selectedDevice?.connected.value != true {
                Text("Turn the device on to change its settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if store.mouseSettings == nil {
                Text("This device is read-only: its settings schema is not modelled yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            BarCPIView()

            Divider()

            BarPollingView()

            Divider()

            BarActionsView()
        }
        .padding(16)
    }
}
