import Foundation

/// A JSON value that preserves its exact shape.
///
/// The engine's `settings` document is free-form and device-specific: the Aerox 3
/// ships 14 top-level keys, other peripherals carry different ones. Decoding into a
/// rigid `Codable` struct would silently drop every key we do not model, and
/// `PUT /configuration/{id}` replaces the document wholesale — so an unmodelled key
/// would not merely display wrong, it would be *deleted on the mouse*.
///
/// Round-trip safety is therefore a data-loss guard, not a convenience.
indirect enum AnyJSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyJSONValue])
    case object([String: AnyJSONValue])
}

extension AnyJSONValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int64.self) { self = .int(Int(value)); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([AnyJSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: AnyJSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Value is not representable as JSON"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension AnyJSONValue {
    var objectValue: [String: AnyJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [AnyJSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value != 0
        default: return nil
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Parse a raw JSON document. Throws on malformed input — callers treat a throw
    /// as "leave the existing value untouched", never as "write an empty document".
    static func parse(_ raw: String) throws -> AnyJSONValue {
        try JSONDecoder().decode(AnyJSONValue.self, from: Data(raw.utf8))
    }

    /// Compact JSON text for writing back to the engine.
    ///
    /// Key order is not semantically meaningful to the engine, and the GG client
    /// itself re-serialises on every save.
    func compactString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    func prettyString() -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: toJSONObject(),
            options: [.prettyPrinted, .sortedKeys]
        ) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Bridge to `JSONSerialization` for pretty-printing only.
    func toJSONObject() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map { $0.toJSONObject() }
        case .object(let value): return value.mapValues { $0.toJSONObject() }
        }
    }
}
