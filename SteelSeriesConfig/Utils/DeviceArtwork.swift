import AppKit

/// Resolves the bundled product artwork a device reports in `imageUrl`.
///
/// The device payloads carry a *name* (`"DeviceAerox3"`), not a file, and the artwork
/// ships as a loose `.png` in `Resources` rather than an asset catalogue. That rules
/// out `NSImage(named:)`, which only searches asset catalogues and registered image
/// names — it returns `nil` for a loose bundle file, so every caller silently fell back
/// to its placeholder glyph and the mouse icon went missing from the popover header and
/// the notifications. `Bundle.image(forResource:)` is the lookup that actually finds a
/// loose resource, so both go through here.
enum DeviceArtwork {
    static func image(named name: String?) -> NSImage? {
        guard let name, !name.isEmpty else { return nil }
        if let image = Bundle.main.image(forResource: name) { return image }
        // `NSImage(named:)` still covers artwork that later moves into an asset
        // catalogue, where it is the correct lookup and `image(forResource:)` is not.
        return NSImage(named: name)
    }
}
