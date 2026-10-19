import Foundation

/// Battery percentage for a Bluetooth peripheral, read from macOS itself.
///
/// The engine's `charge_status` only answers over a 2.4 GHz dongle link. A mouse
/// paired over Bluetooth returns an empty `command_data` — `rf_status` is a dongle
/// concept — so the engine has no battery reading to give, and the GG client paints
/// nothing either. macOS does have one, and it is the same number the user sees when
/// the mouse shows up under Bluetooth in System Settings, so that is what is read here.
///
/// Source is `system_profiler SPBluetoothDataType -json`. Its `device_connected` array
/// maps each connected device's name to a dictionary carrying `device_batteryLevelMain`
/// (a string such as `"82%"`) and `device_minorType` (`"Mouse"`, `"Keyboard"`, …).
///
/// This is a fallback, never the primary: over a dongle the engine's own
/// `charge_status` also reports whether the device is *charging*, which macOS does not,
/// so the engine's answer wins whenever it exists.
enum HostBatteryReader {

    struct Reading: Equatable, Sendable {
        let name: String
        let minorType: String
        let percent: Int
    }

    /// Parse a `system_profiler SPBluetoothDataType -json` document.
    ///
    /// Pure, so it can be pinned by tests against a captured document. Every entry is
    /// defensive: a device with no `device_batteryLevelMain`, or a level that is not a
    /// percentage, is skipped rather than failing the whole read — one odd peripheral
    /// must not be able to blank out a perfectly good battery reading.
    static func parse(_ data: Data) -> [Reading] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let blocks = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        var readings: [Reading] = []
        for block in blocks {
            guard let connected = block["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard
                        let info = value as? [String: Any],
                        let levelString = info["device_batteryLevelMain"] as? String,
                        let percent = percentage(from: levelString)
                    else { continue }

                    let minorType = info["device_minorType"] as? String ?? ""
                    readings.append(Reading(name: name, minorType: minorType, percent: percent))
                }
            }
        }
        return readings
    }

    private static func percentage(from raw: String) -> Int? {
        let digits = raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Int(digits) else { return nil }
        return min(max(value, 0), 100)
    }

    /// Run `system_profiler` off the main thread and hand back its raw output.
    ///
    /// Returns `nil` when the tool cannot be launched or produces nothing, which callers
    /// must read as "no reading available", never as "0%".
    static func rawJSON() async -> Data? {
        await Task.detached(priority: .utility, operation: { run() }).value
    }

    private static func run() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        // Read to EOF *before* waiting: the output can exceed the pipe buffer, and a
        // child blocked on a full pipe would never exit.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data.isEmpty ? nil : data
    }

    /// The battery of the first connected device that identifies as a mouse.
    ///
    /// `preferringName` is only a tie-breaker. macOS' own device name ("Aerox 3 WL")
    /// does not match the engine's ("aerox_3_wireless"), so a name match is used when
    /// one exists and otherwise ignored rather than treated as a miss.
    static func mouse(in readings: [Reading], preferringName name: String?) -> Reading? {
        let mice = readings.filter { $0.minorType.caseInsensitiveCompare("Mouse") == .orderedSame }
        guard !mice.isEmpty else { return nil }
        guard let name, !name.isEmpty else { return mice.first }

        let needle = name.lowercased().replacingOccurrences(of: "_", with: " ")
        if let match = mice.first(where: { reading in
            let hay = reading.name.lowercased()
            return hay.contains(needle) || needle.contains(hay)
        }) {
            return match
        }
        return mice.first
    }
}
