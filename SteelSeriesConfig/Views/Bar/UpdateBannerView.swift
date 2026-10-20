import SwiftUI

/// Offers a verified update from the popover. Installing relaunches the app, so when it
/// is not safe yet (a save in flight, unsaved edits) the banner says why instead of
/// disappearing.
struct UpdateBannerView: View {

    private let updates = UpdateChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: BarMetrics.s) {
            if let build = updates.readyBuild {
                Label("Update available (build \(build))", systemImage: "arrow.down.circle.fill")
                    .font(.callout)
            }

            if let reason = updates.installBlockReason {
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Install & Relaunch") {
                updates.install()
            }
            .controlSize(.regular)
            .buttonStyle(.bordered)
            .disabled(updates.installBlockReason != nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
