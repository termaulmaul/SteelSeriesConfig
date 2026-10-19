import SwiftUI

/// Content of the menu bar popover.
///
/// Layout mirrors the reference app: a fixed 320pt column, a header, then Dividers
/// separating independent control groups. Sections are conditional on capability —
/// a device that does not model CPI simply does not render the CPI block, rather
/// than rendering controls that write keys the device never had.
///
/// The controls also collapse entirely while the device is unreachable, on the same
/// principle: a disabled control reads as "the app is broken", where an absent one
/// leaves room for an explanation of what the user should do about it.
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

            if store.canReachDevice {
                if store.mouseSettings == nil {
                    ReadOnlyNoticeView()
                } else {
                    Divider()
                    BarCPIView()
                    Divider()
                    BarPollingView()
                }
            } else {
                DisconnectedNoticeView(phase: store.displayPhase)
            }

            // A save that failed just as the device dropped is the one case worth
            // keeping on screen while the controls are gone.
            if store.canReachDevice || store.statusMessage != nil {
                Divider()
                BarActionsView()
            }
        }
        .padding(16)
        // Animate only the width/height consequence of the collapse; the header itself
        // stays put so the panel never appears to jump.
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.canReachDevice)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.mouseSettings != nil)
    }
}
