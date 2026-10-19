import XCTest
@testable import SteelSeriesConfig

/// Fixture taken verbatim from the engine for a SteelSeries Aerox 3 Wireless
/// (`settings`, 14 top-level keys), trimmed of the three lighting colour-sequence
/// arrays only where the test does not depend on them.
enum Fixture {
    static let aeroxSettings = """
    {
      "batch_resolution": {"active_level_index": 0, "num_cpi_levels": 5, \
    "resolution_1": 4, "resolution_2": 9, "resolution_3": 13, "resolution_4": 27, "resolution_5": 38},
      "polling_rate": {"val": 0},
      "angle_snapping": {"level": 0},
      "exact_aim": {"level": 0},
      "exact_accel": {"level": 0},
      "power_saving_timeout": {"timeout": 300000},
      "low_power_gaming_mode_sensor": {"lpgm_mode_on": 0},
      "lighting_settings": {"brightness": 15, "idle_brightness": 1, "smart_lighting": 1, "idle_timeout": 30000},
      "default_lighting_enabled": {"default_lighting_enabled": 1},
      "reactive_lighting": {"enable_random_color": 0, "color": {"r": 255, "g": 255, "b": 255}},
      "button_mappings": {
        "buttons": [
          {"function": 1, "key_codes": [0, 0, 0, 0]},
          {"function": 49, "key_codes": [0, 0, 0, 0]}
        ],
        "no_live_deploy": 1
      },
      "aerox_3_wireless_z1_color_sequence": {"steps": []}
    }
    """

    static func makeConfiguration(
        id: String = "ce00433a-eb6c-4cfd-8eab-417077533753",
        name: String = "Default",
        settings: String = aeroxSettings
    ) -> DeviceConfiguration {
        DeviceConfiguration(
            id: id,
            name: name,
            settings: settings,
            undeployedSettings: "{}",
            active: FlexibleBool(true),
            applications: .null,
            bindings: .array([]),
            universalTriggers: .null,
            isQuicksetAutoCreated: FlexibleBool(false)
        )
    }
}
