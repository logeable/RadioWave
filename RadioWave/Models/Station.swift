import Foundation

/// A station keeps every field returned by Radio Browser. Known fields are exposed
/// as typed accessors below; unrecognized and nested fields remain in `attributes`.
struct Station: Codable, Identifiable {
    let attributes: [String: StationJSONValue]

    var id: String { stationuuid }
    var stationuuid: String { string("stationuuid") ?? "" }
    var name: String { string("name") ?? "" }
    var url: String { string("url") ?? "" }
    var urlResolved: String? { string("url_resolved") ?? string("urlResolved") }
    var homepage: String? { string("homepage") }
    var favicon: String? { string("favicon") }
    var tags: String? { string("tags") }
    var country: String? { string("country") }
    var countrycode: String? { string("countrycode") }
    var codec: String? { string("codec") }
    var bitrate: Int? { integer("bitrate") }
    var language: String? { string("language") }
    var clickcount: Int? { integer("clickcount") }

    var streamURL: URL? {
        if let urlResolved, !urlResolved.isEmpty, let resolvedURL = URL(string: urlResolved) {
            return resolvedURL
        }
        return URL(string: url)
    }

    var safeName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown station" : name
    }

    var detail: String {
        [country, codec?.uppercased(), bitrate.flatMap { $0 > 0 ? "\($0) kbps" : nil }]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var fallbackDetail: String {
        let tagList = tags?.components(separatedBy: ",").prefix(2).joined(separator: " · ")
        if !detail.isEmpty { return detail }
        if let tagList, !tagList.isEmpty { return tagList }
        return "Live radio"
    }

    subscript(attribute name: String) -> StationJSONValue? {
        attributes[name]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var decodedAttributes: [String: StationJSONValue] = [:]
        for key in container.allKeys {
            decodedAttributes[key.stringValue] = try container.decode(StationJSONValue.self, forKey: key)
        }
        attributes = decodedAttributes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (name, value) in attributes {
            try container.encode(value, forKey: DynamicCodingKey(stringValue: name))
        }
    }

    private func string(_ key: String) -> String? {
        guard let value = attributes[key] else { return nil }
        switch value {
        case .string(let string): return string
        case .integer(let number): return String(number)
        case .number(let number): return String(number)
        case .bool(let boolean): return String(boolean)
        case .object, .array, .null: return nil
        }
    }

    private func integer(_ key: String) -> Int? {
        guard let value = attributes[key] else { return nil }
        switch value {
        case .integer(let number): return number
        case .number(let number): return Int(number)
        case .string(let string): return Int(string)
        case .bool, .object, .array, .null: return nil
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum StationJSONValue: Codable {
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case object([String: StationJSONValue])
    case array([StationJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: StationJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([StationJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported station JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct StationSearch: Hashable {
    let query: String
    let tag: String?
    let country: String
    let language: String
    let codec: String
    let minimumBitrate: Int
    let sort: StationSort

    init(query: String,
         tag: String? = nil,
         country: String = "",
         language: String = "",
         codec: String = "",
         minimumBitrate: Int = 0,
         sort: StationSort = .popular) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tag = tag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language.trimmingCharacters(in: .whitespacesAndNewlines)
        self.codec = codec.trimmingCharacters(in: .whitespacesAndNewlines)
        self.minimumBitrate = minimumBitrate
        self.sort = sort
    }
}

struct StationFilterOption: Hashable, Identifiable {
    let value: String
    let count: Int

    var id: String { value }
    var title: String { value }
}

enum StationSort: String, CaseIterable, Identifiable {
    case popular
    case name
    case bitrate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .popular: return "热度优先"
        case .name: return "名称排序"
        case .bitrate: return "码率从高到低"
        }
    }
}

struct StationCacheEntry: Codable {
    let schemaVersion: Int
    let stations: [Station]
    let updatedAt: Date
}
