//
//  JSONValue.swift
//  HTZoneMetzer
//
//  Tolerant JSON envelope. The HTZone API mixes strings, numbers, arrays and
//  keyed objects for the same logical field, so responses decode into this and
//  typed values are pulled where needed.
//

import Foundation

enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue {
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            if value.rounded() == value, abs(value) < 9_000_000_000_000_000 {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value): return value ? "1" : "0"
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value):
            if let int = Int(value) { return int }
            if let double = Double(value) { return Int(double) }
            return nil
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .string(let value):
            switch value.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no", "": return false
            default: return nil
            }
        default: return nil
        }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    subscript(index: Int) -> JSONValue? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }
}

enum JSONCollections {
    /// Arrays for arrays, keyed values (ordered by numeric key) for maps.
    static func array(_ value: JSONValue?) -> [JSONValue] {
        guard let value else { return [] }
        if let array = value.arrayValue { return array }
        if let object = value.objectValue {
            return object.keys
                .sorted { numericOrder($0, $1) }
                .compactMap { object[$0] }
        }
        return []
    }

    static func numericOrder(_ lhs: String, _ rhs: String) -> Bool {
        if let l = Int(lhs), let r = Int(rhs) { return l < r }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
