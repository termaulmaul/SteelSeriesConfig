import AppKit
import SwiftUI

/// Visual editor for the three lit strips down the Aerox 3's base.
///
/// Each strip is addressed independently by the firmware (`21 01 <zone> R G B`), so
/// the mouse artwork carries one hotspot per strip: click a hotspot or its row to pick
/// a zone, then open the colour well to change that zone only. The preview lights the
/// hotspot with the zone's current colour, which is the only feedback the write-only
/// HID protocol allows.
struct IlluminationZonesEditor: View {

    @Environment(ConfigurationStore.self) private var store

    @State private var selectedZone = MouseSettings.LightingZone.all[0]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            zoneMap

            VStack(alignment: .leading, spacing: 10) {
                ForEach(MouseSettings.LightingZone.all) { zone in
                    zoneRow(zone)
                }

                Text("One colour per strip. Changes reach the mouse and the profile automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Artwork

    /// Hotspot positions as fractions of the artwork's bounds. The strip runs along the
    /// left flank and around the heel, matching how the lighting shows on the shell.
    private func hotspot(for index: Int) -> CGPoint {
        switch index {
        case 0: return CGPoint(x: 0.16, y: 0.38)
        case 1: return CGPoint(x: 0.14, y: 0.62)
        default: return CGPoint(x: 0.50, y: 0.90)
        }
    }

    private var zoneMap: some View {
        ZStack {
            if let image = DeviceArtwork.image(named: "DeviceAerox3") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay {
                        Image(systemName: "computermouse")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    }
            }

            GeometryReader { proxy in
                ForEach(MouseSettings.LightingZone.all) { zone in
                    zoneMarker(zone)
                        .position(
                            x: proxy.size.width * hotspot(for: zone.index).x,
                            y: proxy.size.height * hotspot(for: zone.index).y
                        )
                }
            }
        }
        .frame(width: 118, height: 212)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Light strip zones")
    }

    private func zoneMarker(_ zone: MouseSettings.LightingZone) -> some View {
        let color = color(for: zone)
        let isSelected = zone == selectedZone

        return Circle()
            .fill(Color(nsColor: NSColor(
                srgbRed: CGFloat(color.red) / 255,
                green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255,
                alpha: 1
            )))
            .frame(width: isSelected ? 22 : 16, height: isSelected ? 22 : 16)
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(isSelected ? 1 : 0.55), lineWidth: isSelected ? 2.5 : 1.5)
                    .shadow(color: .black.opacity(0.45), radius: 2)
            }
            .shadow(color: Color(nsColor: NSColor(
                srgbRed: CGFloat(color.red) / 255,
                green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255,
                alpha: 1
            )).opacity(0.8), radius: isSelected ? 7 : 4)
            .contentShape(Circle())
            .onTapGesture { selectedZone = zone }
            .help(zone.title)
            .accessibilityIdentifier("lighting.zone.\(zone.index)")
            .accessibilityLabel("\(zone.title), \(hex(color))")
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Rows

    private func zoneRow(_ zone: MouseSettings.LightingZone) -> some View {
        let isSelected = zone == selectedZone

        return HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: nsColor(color(for: zone))))
                .frame(width: 11, height: 11)

            VStack(alignment: .leading, spacing: 1) {
                Text(zone.title)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(zone.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            Text(hex(color(for: zone)))
                .font(.caption.monospaced())
                .foregroundColor(.secondary)

            ColorPicker(
                "",
                selection: colorBinding(for: zone),
                supportsOpacity: false
            )
            .labelsHidden()
            .accessibilityIdentifier("lighting.color.\(zone.index)")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedZone = zone }
    }

    // MARK: - Colours

    private func color(for zone: MouseSettings.LightingZone) -> MouseSettings.LightingColor {
        store.mouseSettings?.zoneColor(zone) ?? MouseSettings.LightingColor.defaults[zone.index]
    }

    private func nsColor(_ color: MouseSettings.LightingColor) -> NSColor {
        NSColor(
            srgbRed: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: 1
        )
    }

    private func colorBinding(for zone: MouseSettings.LightingZone) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: nsColor(color(for: zone))) },
            set: { newValue in
                guard let rgb = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                let color = MouseSettings.LightingColor(
                    red: Int((rgb.redComponent * 255).rounded()),
                    green: Int((rgb.greenComponent * 255).rounded()),
                    blue: Int((rgb.blueComponent * 255).rounded())
                )
                store.mutate { $0.setZoneColor(zone, color) }
            }
        )
    }

    private func hex(_ color: MouseSettings.LightingColor) -> String {
        String(format: "#%02X%02X%02X", color.red, color.green, color.blue)
    }
}
