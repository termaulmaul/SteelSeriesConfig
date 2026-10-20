import SwiftUI

/// Spacing for the popover, on a Fibonacci scale: each step is the previous one × φ
/// (1.618), so every gap is in golden ratio with its neighbour. Use only these.
enum BarMetrics {
    static let phi: CGFloat = 1.618

    static let xxs: CGFloat = 3
    static let xs: CGFloat = 5
    static let s: CGFloat = 8
    static let m: CGFloat = 13
    static let l: CGFloat = 21
    static let xl: CGFloat = 34

    static let width: CGFloat = 320
    /// Content column inside the panel padding.
    static let column: CGFloat = width - 2 * l

    /// How far a `Slider`'s knob spills past the control's own frame. AppKit draws a
    /// 20pt knob in a 16pt slider, so 2pt hangs off the top and the bottom; a gap the
    /// layout declares next to a slider loses that much again.
    static let knobOverhang: CGFloat = 2
}

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
    private let updates = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 0) {
            content

            // Shown on every page, not just the connected one: a downloaded update is
            // independent of whether the mouse is currently reachable.
            if updates.readyBuild != nil {
                Divider()
                UpdateBannerView()
                    .padding(.horizontal, BarMetrics.l)
                    .padding(.vertical, BarMetrics.m)
            }
        }
    }

    private var content: some View {
        Group {
            switch store.phase {
            case .booting:
                BarLoadingView()
                    .padding(BarMetrics.l)

            case .unavailable(let message):
                VStack(spacing: BarMetrics.m) {
                    EngineUnavailableView(message: message)
                }
                .padding(BarMetrics.l)

            case .ready:
                if store.selectedDevice == nil {
                    NoDeviceView()
                        .padding(BarMetrics.l)
                } else {
                    connectedLayout
                }
            }
        }
        .frame(width: BarMetrics.width)
    }

    private var connectedLayout: some View {
        VStack(spacing: 0) {
            BarHeaderView()
                .padding(.horizontal, BarMetrics.l)
                .padding(.top, BarMetrics.l)
                .padding(.bottom, BarMetrics.m)

            if store.canReachDevice {
                if store.mouseSettings == nil {
                    ReadOnlyNoticeView()
                        .padding(.horizontal, BarMetrics.l)
                } else {
                    sectionDivider
                    BarCPIView()
                        .padding(.vertical, BarMetrics.m)
                        .padding(.horizontal, BarMetrics.l)
                    sectionDivider
                    BarPollingView()
                        .padding(.vertical, BarMetrics.m)
                        .padding(.horizontal, BarMetrics.l)
                }
            } else {
                DisconnectedNoticeView(phase: store.displayPhase)
                    .padding(.horizontal, BarMetrics.l)
            }

            // A save that failed just as the device dropped is the one case worth
            // keeping on screen while the controls are gone.
            if store.canReachDevice || store.statusMessage != nil {
                sectionDivider
                BarActionsView()
                    .padding(BarMetrics.m)
                    .padding(.horizontal, BarMetrics.s)
            }
        }
        .padding(.bottom, BarMetrics.s)
        // Animate only the width/height consequence of the collapse; the header itself
        // stays put so the panel never appears to jump.
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.canReachDevice)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.mouseSettings != nil)
    }

    /// Full-bleed hairline. Inset by the panel padding it would read as a broken
    /// rectangle; edge to edge it reads as the panel's own seam, which is what it is.
    private var sectionDivider: some View {
        Divider()
    }
}
