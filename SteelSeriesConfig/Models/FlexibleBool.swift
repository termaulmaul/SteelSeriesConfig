import Foundation

/// The engine is inconsistent about booleans: `GET /devices` reports
/// `"connected": 1` but `"hidden": false` in the very same object.
///
/// A strict `Bool` field would fail to decode the whole payload and take the device
/// list down with it, so every boolean-ish field goes through this.
struct FlexibleBool: Codable, Equatable, Sendable {
    var value: Bool

    init(_ value: Bool) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self.value = value; return }
        if let value = try? container.decode(Int.self) { self.value = value != 0; return }
        if let value = try? container.decode(Double.self) { self.value = value != 0; return }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Value is not a boolean or a number"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension FlexibleBool: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) { self.init(value) }
}
