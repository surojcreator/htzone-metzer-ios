//
//  JSONValue.swift
//  HTZoneMetzer
//
//  Tolerant JSON envelope. The HTZone API mixes strings, numbers, arrays and
//  keyed objects for the same logical field, so responses decode into this and
//  typed values are pulled where needed.
//

import Foundation
import CoreFoundation

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

// MARK: - Tolerant response decoding

extension JSONValue {
    /// Decodes one API response, tolerating what this backend actually emits:
    /// a UTF-8 BOM, raw control characters inside string literals, or trailing
    /// PHP notices after the JSON payload. Returns nil when nothing is readable.
    static func decodeResponse(_ data: Data) -> JSONValue? {
        guard !data.isEmpty else { return nil }
        if let value = decodeStrict(data) { return value }
        if let repaired = sanitizedJSON(data) {
            if let value = decodeStrict(repaired) { return value }
            if let value = decodeFoundation(repaired) { return value }
        }
        if let value = decodeFoundation(data) { return value }
        // Some rows are stored as Windows-1255; re-encode before giving up.
        if let text = String(data: data, encoding: .windowsCP1255),
           let utf8 = text.data(using: .utf8), utf8 != data {
            if let value = decodeStrict(utf8) { return value }
            if let repaired = sanitizedJSON(utf8) {
                if let value = decodeStrict(repaired) { return value }
                if let value = decodeFoundation(repaired) { return value }
            }
        }
        return nil
    }

    private static func decodeStrict(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func decodeFoundation(_ data: Data) -> JSONValue? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return JSONValue(foundation: object)
    }

    /// Converts a `JSONSerialization` value, which tolerates top-level fragments.
    init?(foundation value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.compactMap { JSONValue(foundation: $0) })
        case let map as [String: Any]:
            var object: [String: JSONValue] = [:]
            for (key, item) in map {
                if let converted = JSONValue(foundation: item) {
                    object[key] = converted
                }
            }
            self = .object(object)
        default:
            return nil
        }
    }

    /// True when the server answered with an HTML challenge page instead of JSON.
    static func responseLooksLikeHTML(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(256), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return head.hasPrefix("<")
    }

    /// Extracts the first balanced top-level JSON container and escapes raw
    /// control characters inside strings, dropping anything after the payload.
    static func sanitizedJSON(_ data: Data) -> Data? {
        var bytes = Array(data)
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            bytes.removeFirst(3)
        }
        guard let start = bytes.firstIndex(where: { $0 == 0x7B || $0 == 0x5B }) else {
            return nil
        }

        var output: [UInt8] = []
        output.reserveCapacity(bytes.count - start)
        var depth = 0
        var inString = false
        var escaped = false
        var index = start

        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped {
                    output.append(byte)
                    escaped = false
                } else if byte == 0x5C { // backslash
                    output.append(byte)
                    escaped = true
                } else if byte == 0x22 { // closing quote
                    output.append(byte)
                    inString = false
                } else if byte < 0x20 {
                    // Raw control character (newlines from HTML fragments etc.).
                    output.append(0x5C)
                    output.append(0x75)
                    output.append(0x30)
                    output.append(0x30)
                    output.append(hexDigit(byte >> 4))
                    output.append(hexDigit(byte & 0x0F))
                } else {
                    output.append(byte)
                }
            } else {
                if byte == 0x22 {
                    inString = true
                    output.append(byte)
                } else if byte == 0x7B || byte == 0x5B { // { or [
                    depth += 1
                    output.append(byte)
                } else if byte == 0x7D || byte == 0x5D { // } or ]
                    depth -= 1
                    output.append(byte)
                    if depth <= 0 {
                        break
                    }
                } else {
                    output.append(byte)
                }
            }
            index += 1
        }

        guard depth == 0, !inString else { return nil }
        return Data(output)
    }

    private static func hexDigit(_ value: UInt8) -> UInt8 {
        value < 10 ? 0x30 + value : 0x41 + value - 10
    }
}
