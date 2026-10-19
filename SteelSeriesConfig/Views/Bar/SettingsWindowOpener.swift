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

/// Device artwork served by the engine over its self-signed local endpoint.
///
/// Goes through `EngineClient` on purpose: a plain `AsyncImage` would fail TLS
/// verification against the engine's `O=SteelSeries ApS` certificate.
struct EngineDeviceImage: View {

    let urlString: String?
    let fallbackSystemImage: String
    let height: CGFloat

    @Environment(ConfigurationStore.self) private var store
    @State private var data: Data?

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: height)
                    .frame(minWidth: height)
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: height * 0.8))
                    .foregroundColor(.primary)
                    .frame(height: height)
                    .frame(minWidth: height)
            }
        }
        .task(id: urlString) {
            await load()
        }
    }

    private func load() async {
        guard let urlString, let engine = store.engine else { return }
        do {
            data = try await engine.imageData(at: urlString)
        } catch {
            // Falling back to the symbol is correct here: the image is decorative and
            // the engine being unhappy about it is not a user-facing failure.
            data = nil
        }
    }
}
