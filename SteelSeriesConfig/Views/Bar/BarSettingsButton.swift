import AppKit
import SwiftUI

/// Gear button in the popover header: opens Settings, and offers Quit from its menu.
struct BarSettingsButton: View {

    var body: some View {
        Button {
            openFocusedSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14))
                .foregroundColor(.primary)
        }
        .buttonStyle(HoverButtonStyle())
        .help("Settings")
        .contextMenu {
            Button {
                openFocusedSettings()
            } label: {
                Text("Open Settings")
                Image(systemName: "gearshape.fill")
            }

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Text("Quit App")
                Image(systemName: "xmark.circle.fill")
            }
        }
    }

    private func openFocusedSettings() {
        SettingsWindowOpener.requested?()
    }
}

/// Circular hover/press backdrop for icon-only buttons in the popover header.
struct HoverButtonStyle: ButtonStyle {

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(BarMetrics.xxs)
            .background(Circle().fill(backgroundColor(configuration: configuration)))
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        if configuration.isPressed {
            .secondary.opacity(0.4)
        } else if isHovering {
            .secondary.opacity(0.2)
        } else {
            .clear
        }
    }
}
