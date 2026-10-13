import Foundation

/// The small subset used by the official Kiro portal's Smithy RPC v2 CBOR schemas.
/// No unbounded allocation, duplicate keys, arbitrary tags, or coercion of bools to numbers.
enum KiroCBOR {
    indirect enum Value: Equatable, Sendable {
        case map([String: Value]), array([Value]), string(String), integer(Int64), number(Double), bool(Bool), null, timestamp(Double)

        var object: [String: Value]? { if case .map(let value) = self { value } else { nil } }
        var list: [Value]? { if case .array(let value) = self { value } else { nil } }
        var text: String? { if case .string(let value) = self { value } else { nil } }
        var numeric: Double? {
            switch self {
            case .number(let value): value
            case .integer(let value) where (-9_007_199_254_740_991...9_007_199_254_740_991).contains(value): Double(value)
            default: nil
            }
        }
        var date: Date? { if case .timestamp(let value) = self, value >= 0, value <= 32_503_680_000 { Date(timeIntervalSince1970: value) } else { nil } }
    }

    static func decode(_ data: Data) throws -> Value {
        guard !data.isEmpty, data.count <= 1_000_000 else { throw RefreshFailure.unreadableResponse }
        var reader = Reader(bytes: Array(data))
        let value = try reader.value(depth: 0)
        guard reader.offset == data.count else { throw RefreshFailure.unreadableResponse }
        return value
    }

    static func encode(_ value: Value) throws -> Data {
        var bytes: [UInt8] = []
        var nodes = 0
        func head(_ major: UInt8, _ value: UInt64) {
            if value < 24 { bytes.append(major << 5 | UInt8(value)); return }
            let length = value <= 255 ? 1 : value <= 65_535 ? 2 : value <= UInt32.max ? 4 : 8
            bytes.append(major << 5 | (length == 1 ? 24 : length == 2 ? 25 : length == 4 ? 26 : 27))
            for index in (0..<length).reversed() { bytes.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
        }
        func write(_ value: Value, _ depth: Int) throws {
            nodes += 1
            guard depth <= 12, nodes <= 4_096, bytes.count <= 1_000_000 else { throw RefreshFailure.unreadableResponse }
            switch value {
            case .map(let values):
                guard values.count <= 1_024 else { throw RefreshFailure.unreadableResponse }
                head(5, UInt64(values.count))
                for key in values.keys.sorted() { try write(.string(key), depth + 1); try write(values[key]!, depth + 1) }
            case .array(let values):
                guard values.count <= 1_024 else { throw RefreshFailure.unreadableResponse }
                head(4, UInt64(values.count)); for item in values { try write(item, depth + 1) }
            case .string(let value):
                let text = Array(value.utf8); guard text.count <= 65_536 else { throw RefreshFailure.unreadableResponse }
                head(3, UInt64(text.count)); bytes.append(contentsOf: text)
            case .integer(let value): head(value >= 0 ? 0 : 1, value >= 0 ? UInt64(value) : UInt64(-(value + 1)))
            case .number(let value):
                guard value.isFinite else { throw RefreshFailure.unreadableResponse }
                bytes.append(0xfb)
                for index in (0..<8).reversed() { bytes.append(UInt8(truncatingIfNeeded: value.bitPattern >> (index * 8))) }
            case .bool(let value): bytes.append(value ? 0xf5 : 0xf4)
            case .null: bytes.append(0xf6)
            case .timestamp(let value): head(6, 1); try write(.number(value), depth + 1)
            }
        }
        try write(value, 0)
        guard bytes.count <= 1_000_000 else { throw RefreshFailure.unreadableResponse }
        return Data(bytes)
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        var nodes = 0

        mutating func read(_ count: Int) throws -> UInt64 {
            guard count > 0, count <= 8, count <= bytes.count - offset else { throw RefreshFailure.unreadableResponse }
            var result: UInt64 = 0
            for _ in 0..<count { result = result << 8 | UInt64(bytes[offset]); offset += 1 }
            return result
        }

        mutating func size(_ info: UInt8) throws -> UInt64 {
            switch info {
            case 0..<24: UInt64(info)
            case 24: try read(1)
            case 25: try read(2)
            case 26: try read(4)
            case 27: try read(8)
            default: throw RefreshFailure.unreadableResponse
            }
        }

        mutating func value(depth: Int) throws -> Value {
            nodes += 1
            guard depth <= 12, nodes <= 4_096, offset < bytes.count else { throw RefreshFailure.unreadableResponse }
            let first = bytes[offset]; offset += 1
            let major = first >> 5, info = first & 31
            // Official service responses can use break-terminated containers (observed anonymous CBOR error).
            // Only map/array indefinite lengths are supported, under the same depth/node/member limits.
            if info == 31 {
                guard major == 4 || major == 5 else { throw RefreshFailure.unreadableResponse }
            }
            switch major {
            case 0, 1:
                let magnitude = try size(info)
                guard magnitude <= UInt64(Int64.max) else { throw RefreshFailure.unreadableResponse }
                return .integer(major == 0 ? Int64(magnitude) : -1 - Int64(magnitude))
            case 3:
                let length = try size(info)
                guard length <= 65_536, length <= UInt64(bytes.count - offset) else { throw RefreshFailure.unreadableResponse }
                let end = offset + Int(length)
                guard let text = String(bytes: bytes[offset..<end], encoding: .utf8) else { throw RefreshFailure.unreadableResponse }
                offset = end; return .string(text)
            case 4, 5:
                let count = info == 31 ? nil : try size(info)
                guard count.map({ $0 <= 1_024 }) != false else { throw RefreshFailure.unreadableResponse }
                var items: [Value] = [], object: [String: Value] = [:]
                var seen = 0
                while count.map({ UInt64(seen) < $0 }) ?? true {
                    guard offset < bytes.count else { throw RefreshFailure.unreadableResponse }
                    if count == nil, bytes[offset] == 0xff { offset += 1; return major == 4 ? .array(items) : .map(object) }
                    guard seen < 1_024 else { throw RefreshFailure.unreadableResponse }; seen += 1
                    if major == 4 { items.append(try value(depth: depth + 1)) }
                    else {
                        guard case .string(let key) = try value(depth: depth + 1), !key.isEmpty, object[key] == nil else { throw RefreshFailure.unreadableResponse }
                        object[key] = try value(depth: depth + 1)
                    }
                }
                return major == 4 ? .array(items) : .map(object)
            case 6:
                guard try size(info) == 1, let seconds = try value(depth: depth + 1).numeric, seconds.isFinite else { throw RefreshFailure.unreadableResponse }
                return .timestamp(seconds)
            case 7:
                switch info {
                case 20: return .bool(false)
                case 21: return .bool(true)
                case 22: return .null
                case 25, 26, 27:
                    let bits = try read(info == 25 ? 2 : info == 26 ? 4 : 8)
                    let number: Double
                    if info == 25 {
                        let sign: Double = bits & 0x8000 == 0 ? 1 : -1
                        let exponent = Int((bits >> 10) & 31), mantissa = Double(bits & 1_023)
                        guard exponent != 31 else { throw RefreshFailure.unreadableResponse }
                        number = sign * (exponent == 0 ? pow(2, -14) * mantissa / 1_024 : pow(2, Double(exponent - 15)) * (1 + mantissa / 1_024))
                    } else if info == 26 { number = Double(Float(bitPattern: UInt32(bits))) }
                    else { number = Double(bitPattern: bits) }
                    guard number.isFinite else { throw RefreshFailure.unreadableResponse }
                    return .number(number)
                default: throw RefreshFailure.unreadableResponse
                }
            default: throw RefreshFailure.unreadableResponse
            }
        }
    }
}
