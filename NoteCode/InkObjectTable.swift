//
//  InkObjectTable.swift
//  NoteCode
//
//  What a note's ink says about its objects beyond the PaperKit bytes, and the
//  container that carries it. See docs/design/object-system.md, decision 6.
//

import Foundation

/// A JSON value, so a table entry can keep fields this build has never heard of
/// and write them back as they were.
nonisolated enum JSONValue: Codable, Equatable, Sendable {
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
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
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

private nonisolated struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Where an object hangs. `kind` is open: `"text"` is the anchoring phase's
/// (`offset`, `dx`, `dy`), and a kind this build doesn't know is kept whole.
nonisolated struct InkAnchor: Codable, Equatable, Sendable {
    var kind: String
    /// Everything but `kind`.
    var fields: [String: JSONValue]

    init(kind: String, fields: [String: JSONValue] = [:]) {
        self.kind = kind
        self.fields = fields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var fields: [String: JSONValue] = [:]
        var kind = ""
        for key in container.allKeys {
            if key.stringValue == "kind" {
                kind = try container.decode(String.self, forKey: key)
            } else {
                fields[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }
        }
        self.kind = kind
        self.fields = fields
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(kind, forKey: DynamicKey("kind"))
        for (name, value) in fields {
            try container.encode(value, forKey: DynamicKey(name))
        }
    }
}

/// An entry exists only for an object with something the PaperKit bytes don't
/// say: an anchor, a group. Everything else is page-anchored by default and has
/// no entry. Selection is never stored.
nonisolated struct InkObjectTable: Codable, Equatable, Sendable {

    /// The table's own format. A newer one is unreadable here, and the bytes
    /// are left alone (see `DrawingCodec`).
    static let currentVersion = 1

    struct Entry: Codable, Equatable, Sendable {
        /// The stroke's `id` or the shape's or image's `MarkupID`.
        var id: UUID
        /// `"stroke"`, `"shape"`, `"image"`, or a kind from a newer build.
        var kind: String
        var group: UUID?
        var anchor: InkAnchor?
        /// Fields this build doesn't know, kept and written back.
        var extra: [String: JSONValue] = [:]

        init(id: UUID, kind: String, group: UUID? = nil, anchor: InkAnchor? = nil, extra: [String: JSONValue] = [:]) {
            self.id = id
            self.kind = kind
            self.group = group
            self.anchor = anchor
            self.extra = extra
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            id = try container.decode(UUID.self, forKey: DynamicKey("id"))
            kind = try container.decode(String.self, forKey: DynamicKey("kind"))
            group = try container.decodeIfPresent(UUID.self, forKey: DynamicKey("group"))
            anchor = try container.decodeIfPresent(InkAnchor.self, forKey: DynamicKey("anchor"))
            var extra: [String: JSONValue] = [:]
            for key in container.allKeys where !["id", "kind", "group", "anchor"].contains(key.stringValue) {
                extra[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }
            self.extra = extra
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicKey.self)
            try container.encode(id, forKey: DynamicKey("id"))
            try container.encode(kind, forKey: DynamicKey("kind"))
            try container.encodeIfPresent(group, forKey: DynamicKey("group"))
            try container.encodeIfPresent(anchor, forKey: DynamicKey("anchor"))
            for (name, value) in extra {
                try container.encode(value, forKey: DynamicKey(name))
            }
        }
    }

    var version = Self.currentVersion
    var entries: [Entry] = []

    static let empty = InkObjectTable()

    var isEmpty: Bool { entries.isEmpty }

    /// Sorted keys, so the same table is the same bytes.
    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    init(version: Int = InkObjectTable.currentVersion, entries: [Entry] = []) {
        self.version = version
        self.entries = entries
    }
}

/// The bytes `Page.drawingData` holds: either a bare PaperKit blob (every note
/// until something uses the table) or this container.
///
/// `NCOB`, a version byte, the table's length as a little-endian `UInt32`, the
/// table's JSON, then the PaperKit bytes. Bytes that don't start with the magic
/// are legacy and are the PaperKit bytes whole. PaperKit refuses a container
/// (measured, scripts/spikes/object-system-probe.swift), so a build without this
/// type treats it as unreadable and leaves it alone.
nonisolated enum InkContainer {

    static let magic = Data("NCOB".utf8)
    static let formatVersion: UInt8 = 1
    private static let headerLength = 9

    enum Unwrapped: Equatable {
        /// No container: the bytes are PaperKit's (or empty).
        case legacy(Data)
        case container(table: InkObjectTable, paper: Data)
        /// A container this build can't read, and why.
        case unreadable(reason: String)
    }

    /// `paper` alone when `table` is empty, so a note that uses nothing is
    /// stored exactly as it always was.
    static func wrap(table: InkObjectTable, paper: Data) throws -> Data {
        guard !table.isEmpty else { return paper }
        let json = try table.data()
        var out = magic
        out.append(formatVersion)
        var length = UInt32(json.count).littleEndian
        out.append(Data(bytes: &length, count: 4))
        out.append(json)
        out.append(paper)
        return out
    }

    static func unwrap(_ data: Data) -> Unwrapped {
        guard data.prefix(magic.count) == magic else { return .legacy(data) }
        let newer = "This note's drawing was saved by a newer version of NoteCode."
        guard data.count >= headerLength else {
            return .unreadable(reason: "This note's drawing couldn't be read.")
        }
        let bytes = [UInt8](data)
        guard bytes[4] <= formatVersion else { return .unreadable(reason: newer) }
        let length = Int(UInt32(bytes[5]) | UInt32(bytes[6]) << 8 | UInt32(bytes[7]) << 16 | UInt32(bytes[8]) << 24)
        guard data.count >= headerLength + length else {
            return .unreadable(reason: "This note's drawing couldn't be read.")
        }
        let json = data.subdata(in: data.startIndex + headerLength..<data.startIndex + headerLength + length)
        let paper = data.subdata(in: data.startIndex + headerLength + length..<data.endIndex)
        guard let table = try? JSONDecoder().decode(InkObjectTable.self, from: json) else {
            return .unreadable(reason: "This note's drawing couldn't be read.")
        }
        guard table.version <= InkObjectTable.currentVersion else { return .unreadable(reason: newer) }
        return .container(table: table, paper: paper)
    }
}
