import SwiftUI

/// Entry point for opening the Settings window from anywhere that has no
/// `OpenWindowAction` in scope (the popover lives in an `NSPanel` hosted outside the
/// SwiftUI scene graph).
///
/// The App scene assigns this once during body evaluation; see `SSConfigApp`.
@MainActor
enum SettingsWindowOpener {
    static var requested: (() -> Void)?
}

/// Product artwork for the device, as SteelSeries GG shows it; a symbol when there is
/// no device or no bundled image for it.
struct DeviceGlyph: View {

    let imageName: String?
    let systemImage: String
    let height: CGFloat

    var body: some View {
        if let imageName, let image = NSImage(named: imageName) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
                .frame(minWidth: height)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: height * 0.8))
                .foregroundColor(.primary)
                .frame(height: height)
                .frame(minWidth: height)
        }
    }
}
