//
//  PastedHTML.swift
//  NoteCode
//
//  Pasted HTML, rebuilt from only what carries formatting, so that reading
//  it loads nothing. The HTML import RichPaste uses is WebKit's, and WebKit
//  fetches what a page refers to: images (`src`, `srcset`, `poster`, `data`,
//  `background`), stylesheets, `@import`, fonts and `url(…)` in a style. A
//  page copied from a browser refers to its own servers, so a paste told
//  them a note was being written (RichPasteNetworkTests, 18 Nov). A Content
//  Security Policy in a `<meta>` was tried first: the import ignores it.
//
//  So the HTML is read here and written out again: the tags and attributes
//  that format text, everything else dropped (an image would have been
//  dropped from the Markdown anyway). Attribute values are decoded and
//  written back escaped, so an entity can't spell a URL the check missed,
//  and in a style every `url(`, `image-set(`, `src(` and `@import` is made
//  into something CSS throws away, after its escapes are taken out. What the
//  import then reads is only what is written here, so how this reads odd
//  markup only changes what formatting survives, never what is fetched.
//

import Foundation

nonisolated enum PastedHTML {

    /// Tags kept, with no attributes beyond `attributes(of:)`'s.
    static let tags: Set<String> = [
        "a", "abbr", "address", "article", "aside", "b", "bdi", "bdo", "big", "blockquote", "body", "br",
        "caption", "center", "cite", "code", "col", "colgroup", "dd", "del", "details", "dfn", "div", "dl", "dt",
        "em", "figcaption", "figure", "font", "footer", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header",
        "hr", "html", "i", "ins", "kbd", "label", "li", "main", "mark", "nav", "ol", "p", "pre", "q", "s",
        "samp", "section", "small", "span", "strike", "strong", "sub", "summary", "sup", "table", "tbody", "td",
        "tfoot", "th", "thead", "time", "tr", "tt", "u", "ul", "var", "wbr",
    ]

    /// Elements whose content goes with them, as raw text up to their end
    /// tag. `style` is kept, its content made safe (`safeCSS`), and what a
    /// `textarea` holds is kept as text (`shownRawText`). A `noscript` isn't
    /// here: the import runs no script, so what it holds is read as markup,
    /// rebuilt like the rest.
    static let rawText: Set<String> = [
        "script", "style", "title", "textarea", "xmp", "iframe", "noembed", "noframes", "plaintext",
    ]

    /// Raw-text elements whose text a page shows.
    static let shownRawText: Set<String> = ["textarea"]

    static func attributes(of tag: String) -> Set<String> {
        // `class` and `id` load nothing, and a style block's rules find what
        // they style by them: the Cocoa HTML Writer (Notes, Pages, TextEdit)
        // puts every style in class rules.
        let everywhere: Set<String> = ["style", "class", "id", "dir", "align", "colspan", "rowspan"]
        switch tag {
        case "a": return everywhere.union(["href"])
        case "font": return everywhere.union(["color", "face", "size"])
        case "ol": return everywhere.union(["start", "type", "reversed"])
        case "ul": return everywhere.union(["type"])
        case "li": return everywhere.union(["value", "type"])
        default: return everywhere
        }
    }

    /// `html` rebuilt so that reading it loads nothing, as UTF-8 (which is
    /// what the import is told it is, and the `<meta>` that said otherwise
    /// is dropped). It is read in the charset its byte order mark or `<meta>`
    /// names (`utf8`).
    static func sanitised(_ html: Data) -> Data {
        Data(sanitised(utf8(html)))
    }

    /// `html` as UTF-8: read as UTF-16 after a UTF-16 byte order mark, with
    /// a UTF-8 one dropped; as UTF-16 with no mark when its first character
    /// is ASCII with a NUL beside it (the order of the two says which end
    /// first); or else in the charset a `<meta>` in its first 1,024 bytes
    /// names (`charset=`, as `<meta charset>` and a `content-type` both put
    /// it), as a browser reads it. A charset that is UTF-8 already, isn't
    /// known or doesn't read the bytes leaves them be.
    static func utf8(_ html: Data) -> [UInt8] {
        let bytes = Array(html)
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            return String(data: html, encoding: .utf16).map { Array($0.utf8) } ?? bytes
        }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return Array(bytes.dropFirst(3)) }
        if bytes.count >= 2, (bytes[0] == 0) != (bytes[1] == 0), max(bytes[0], bytes[1]) < 0x80 {
            let encoding: String.Encoding = bytes[0] == 0 ? .utf16BigEndian : .utf16LittleEndian
            return String(data: html, encoding: encoding).map { Array($0.utf8) } ?? bytes
        }
        guard let encoding = declaredEncoding(bytes), encoding != .utf8,
              let text = String(data: html, encoding: encoding)
        else { return bytes }
        return Array(text.utf8)
    }

    /// The encoding a `<meta>` near the start names, if it is one Foundation
    /// knows. As in a browser, a `<meta>` naming UTF-16 means UTF-8 (the
    /// `<meta>` itself was read as ASCII, so the bytes aren't UTF-16), and
    /// `x-user-defined` means windows-1252.
    static func declaredEncoding(_ bytes: [UInt8]) -> String.Encoding? {
        let head = String(decoding: bytes.prefix(1024), as: UTF8.self)
        guard let match = metaCharset.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
              let range = Range(match.range(at: 1), in: head)
        else { return nil }
        let name = String(head[range]).lowercased()
        if name == "x-user-defined" { return .windowsCP1252 }
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        return [.utf16, .utf16BigEndian, .utf16LittleEndian].contains(encoding) ? .utf8 : encoding
    }

    static let metaCharset = try! NSRegularExpression(
        pattern: #"<meta\b[^>]*?charset\s*=\s*["']?\s*([A-Za-z0-9._:-]+)"#, options: .caseInsensitive)

    static func sanitised(_ html: [UInt8]) -> [UInt8] {
        var reader = Reader(bytes: html)
        var out: [UInt8] = []
        out.reserveCapacity(html.count)
        while let byte = reader.peek() {
            guard byte == scalarByte("<") else {
                out.append(byte)
                reader.index += 1
                continue
            }
            let next = reader.peek(1)
            if next == scalarByte("!") {
                if reader.starts(with: "<!--") {
                    reader.index += 4
                    reader.skip(past: "-->")
                } else {
                    reader.skip(past: ">")
                }
            } else if next == scalarByte("?") {
                reader.skip(past: ">")
            } else if next == scalarByte("/") {
                if let letter = reader.peek(2), isLetter(letter) {
                    reader.index += 2
                    let name = reader.tagName()
                    guard reader.attributes() != nil else { break }
                    if tags.contains(name) { out += Array("</\(name)>".utf8) }
                } else {
                    reader.skip(past: ">")
                }
            } else if let next, isLetter(next) {
                reader.index += 1
                let name = reader.tagName()
                guard let attributes = reader.attributes() else { break }
                if rawText.contains(name) {
                    let content = reader.rawText(until: name)
                    if name == "style" {
                        out += Array("<style>\(safeCSS(content))</style>".utf8)
                    } else if shownRawText.contains(name) {
                        out += Array(escaped(decoded(Array(content.utf8))).utf8)
                    }
                } else if tags.contains(name) {
                    out += Array(startTag(name, attributes).utf8)
                }
            } else {
                out += Array("&lt;".utf8)
                reader.index += 1
            }
        }
        return out
    }

    /// A start tag with only the attributes `attributes(of:)` keeps, their
    /// values escaped and a style's made safe. A style's references are all
    /// read first, so none can spell a loader after `safeCSS`; in the others,
    /// none of which loads, a named reference `named` doesn't have is left
    /// for the import to read (`reescaped`).
    static func startTag(_ name: String, _ given: [(name: String, value: [UInt8])]) -> String {
        let kept = attributes(of: name)
        var tag = "<" + name
        var seen: Set<String> = []
        for attribute in given where kept.contains(attribute.name) && seen.insert(attribute.name).inserted {
            let value = attribute.name == "style" ? escaped(safeCSS(decoded(attribute.value))) : reescaped(attribute.value)
            tag += " \(attribute.name)=\"\(value)\""
        }
        return tag + ">"
    }

    /// `value`, as written in an attribute, written again escaped: what
    /// `decoded` reads is escaped (`escaped`), and a named reference it
    /// doesn't know is kept as it was written, so the import reads it.
    static func reescaped(_ value: [UInt8]) -> String {
        var out = ""
        var index = 0
        var plain = 0
        func flush(to end: Int) {
            if plain < end { out += escaped(decoded(Array(value[plain..<end]))) }
        }
        while index < value.count {
            guard value[index] == scalarByte("&") else {
                index += 1
                continue
            }
            var end = index + 1
            if end < value.count, isLetter(value[end]) {
                while end < value.count, isLetter(value[end]) || (scalarByte("0")...scalarByte("9")).contains(value[end]) { end += 1 }
                if end < value.count, value[end] == scalarByte(";"),
                   named[String(decoding: value[(index + 1)..<end], as: UTF8.self)] == nil {
                    flush(to: index)
                    out += String(decoding: value[index...end], as: UTF8.self)
                    index = end + 1
                    plain = index
                    continue
                }
            }
            index += 1
        }
        flush(to: value.count)
        return out
    }

    /// `css` with nothing in it that loads: its escapes are taken out, then
    /// each function that names a resource is renamed, which makes the
    /// declaration invalid, and `@import` becomes an at-rule no one knows.
    static func safeCSS(_ css: String) -> String {
        var text = css.replacingOccurrences(of: "\\", with: "")
        let range = NSRange(text.startIndex..., in: text)
        text = loader.stringByReplacingMatches(in: text, range: range, withTemplate: "invalid-$1(")
        return importRule.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "@invalid-import")
    }

    static let loader = try! NSRegularExpression(pattern: #"(url|src|image-set|image)\s*\("#, options: .caseInsensitive)
    static let importRule = try! NSRegularExpression(pattern: "@import", options: .caseInsensitive)

    static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }

    static func isLetter(_ byte: UInt8) -> Bool {
        (scalarByte("a")...scalarByte("z")).contains(byte | 0x20)
    }

    static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
    }

    /// The named references read: the common ones, and every one that
    /// stands for ASCII punctuation, a tab or a line end, which is all a
    /// named reference can add to a URL (none stands for an ASCII letter).
    /// Any other stays as written, and is then escaped, so it reads as its
    /// letters.
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "Tab": "\t", "NewLine": "\n", "excl": "!", "num": "#", "dollar": "$", "percnt": "%", "lpar": "(",
        "rpar": ")", "ast": "*", "midast": "*", "plus": "+", "comma": ",", "period": ".", "sol": "/",
        "colon": ":", "semi": ";", "equals": "=", "quest": "?", "commat": "@", "lsqb": "[", "lbrack": "[",
        "bsol": "\\", "rsqb": "]", "rbrack": "]", "Hat": "^", "lowbar": "_", "UnderBar": "_", "grave": "`",
        "DiacriticalGrave": "`", "lcub": "{", "lbrace": "{", "verbar": "|", "vert": "|", "VerticalLine": "|",
        "rcub": "}", "rbrace": "}", "AMP": "&", "LT": "<", "GT": ">", "QUOT": "\"",
    ]

    /// Whether `html`, read as it is, might load something: any web
    /// address, a `data:` one (whose content, base64 or not, may refer to a
    /// server: a stylesheet's `@import`, an SVG's image, a frame's page),
    /// `//`, a backslash, a CSS function that names a resource,
    /// `@import` or a script, once character references are read and tabs
    /// and line ends (which a URL drops) taken out. Only a leading doctype is
    /// passed over, which names its DTD and loads nothing. It reads no
    /// structure, so no markup can hide an address from it; it says yes to
    /// much that loads nothing (a link, `//` in code), which only means the
    /// paste reads the HTML rather than the RTF beside it. HTML that isn't
    /// UTF-8 or ASCII-like (a UTF-16 byte order mark, a NUL, ISO-2022's
    /// escape) is a yes, since an address in it wouldn't be seen.
    static func mayLoad(_ html: Data) -> Bool {
        var bytes = Array(html)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) || bytes.contains(0) || bytes.contains(0x1B) {
            return true
        }
        var reader = Reader(bytes: bytes)
        while let byte = reader.peek(), isSpace(byte) { reader.index += 1 }
        if reader.index + 9 <= bytes.count,
           String(decoding: bytes[reader.index..<(reader.index + 9)], as: UTF8.self).lowercased() == "<!doctype" {
            reader.skip(past: ">")
        }
        let rest = Array(bytes[reader.index...])
        // As written, and as the charset a `<meta>` names reads it.
        let transcoded = utf8(Data(rest))
        return mentionsLoader(rest) || (transcoded != rest && mentionsLoader(transcoded))
    }

    static func mentionsLoader(_ bytes: [UInt8]) -> Bool {
        let text = decoded(bytes)
            .filter { $0 != "\t" && $0 != "\n" && $0 != "\r" && $0 != "\r\n" }
            .lowercased()
        return ["http:", "https:", "ftp:", "data:", "//", "\\", "url(", "image-set(", "src(", "@import", "<script"]
            .contains { text.contains($0) }
    }

    /// `value` with its character references read.
    static func decoded(_ value: [UInt8]) -> String {
        var out: [UInt8] = []
        var index = 0
        while index < value.count {
            guard value[index] == scalarByte("&") else {
                out.append(value[index])
                index += 1
                continue
            }
            var end = index + 1
            var scalar: Unicode.Scalar?
            if end < value.count, value[end] == scalarByte("#") {
                end += 1
                let hex = end < value.count && (value[end] | 0x20) == scalarByte("x")
                if hex { end += 1 }
                let start = end
                var number: UInt32 = 0
                while end < value.count, let digit = digit(value[end], hex: hex) {
                    number = number > 0x10FFFF ? number : number * (hex ? 16 : 10) + digit
                    end += 1
                }
                if end > start {
                    scalar = Unicode.Scalar(number).flatMap { $0 == "\0" ? nil : $0 } ?? "\u{FFFD}"
                    if end < value.count, value[end] == scalarByte(";") { end += 1 }
                }
            } else {
                while end < value.count, isLetter(value[end]) || (scalarByte("0")...scalarByte("9")).contains(value[end]) { end += 1 }
                if end < value.count, value[end] == scalarByte(";"),
                   let text = named[String(decoding: value[(index + 1)..<end], as: UTF8.self)] {
                    out += Array(text.utf8)
                    index = end + 1
                    continue
                }
            }
            if let scalar {
                out += Array(String(Character(scalar)).utf8)
                index = end
            } else {
                out.append(value[index])
                index += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func digit(_ byte: UInt8, hex: Bool) -> UInt32? {
        switch byte {
        case scalarByte("0")...scalarByte("9"): return UInt32(byte - scalarByte("0"))
        case scalarByte("a")...scalarByte("f") where hex: return UInt32(byte - scalarByte("a") + 10)
        case scalarByte("A")...scalarByte("F") where hex: return UInt32(byte - scalarByte("A") + 10)
        default: return nil
        }
    }

    /// Reads tags the way HTML does, closely enough: what it reads oddly is
    /// only formatting lost.
    struct Reader {
        let bytes: [UInt8]
        var index = 0

        func peek(_ offset: Int = 0) -> UInt8? {
            index + offset < bytes.count ? bytes[index + offset] : nil
        }

        func starts(with text: String) -> Bool {
            let pattern = Array(text.utf8)
            guard index + pattern.count <= bytes.count else { return false }
            return Array(bytes[index..<(index + pattern.count)]) == pattern
        }

        /// Moves past the next `text`, or to the end.
        mutating func skip(past text: String) {
            while index < bytes.count, !starts(with: text) { index += 1 }
            index = min(index + text.utf8.count, bytes.count)
        }

        /// A tag's name, lowercased, from just after `<` or `</`.
        mutating func tagName() -> String {
            let start = index
            while let byte = peek(), !isSpace(byte), byte != scalarByte("/"), byte != scalarByte(">") { index += 1 }
            return String(decoding: bytes[start..<index], as: UTF8.self).lowercased()
        }

        /// The attributes up to and past the tag's `>`, as written, or `nil`
        /// if the text ends inside the tag (which HTML drops).
        mutating func attributes() -> [(name: String, value: [UInt8])]? {
            var found: [(name: String, value: [UInt8])] = []
            while true {
                while let byte = peek(), isSpace(byte) || byte == scalarByte("/") { index += 1 }
                guard let byte = peek() else { return nil }
                if byte == scalarByte(">") {
                    index += 1
                    return found
                }
                let start = index
                index += 1
                while let byte = peek(), !isSpace(byte), byte != scalarByte("/"), byte != scalarByte(">"), byte != scalarByte("=") { index += 1 }
                let name = String(decoding: bytes[start..<index], as: UTF8.self).lowercased()
                while let byte = peek(), isSpace(byte) { index += 1 }
                var value: [UInt8] = []
                if peek() == scalarByte("=") {
                    index += 1
                    while let byte = peek(), isSpace(byte) { index += 1 }
                    if let quote = peek(), quote == scalarByte("\"") || quote == scalarByte("'") {
                        index += 1
                        let valueStart = index
                        while let byte = peek(), byte != quote { index += 1 }
                        guard index < bytes.count else { return nil }
                        value = Array(bytes[valueStart..<index])
                        index += 1
                    } else {
                        let valueStart = index
                        while let byte = peek(), !isSpace(byte), byte != scalarByte(">") { index += 1 }
                        value = Array(bytes[valueStart..<index])
                    }
                }
                found.append((name, value))
            }
        }

        /// The raw text up to `</name`, and past that end tag.
        mutating func rawText(until name: String) -> String {
            let start = index
            let end = Array("</\(name)".utf8)
            while index < bytes.count {
                if index + end.count <= bytes.count,
                   zip(bytes[index..<(index + end.count)], end).allSatisfy({ $0 | 0x20 == $1 | 0x20 }),
                   peek(end.count).map({ isSpace($0) || $0 == scalarByte("/") || $0 == scalarByte(">") }) ?? true {
                    let text = String(decoding: bytes[start..<index], as: UTF8.self)
                    index += end.count
                    _ = attributes()
                    return text
                }
                index += 1
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }
    }
}

/// The byte a one-byte character is, in UTF-8.
private nonisolated func scalarByte(_ scalar: Unicode.Scalar) -> UInt8 { UInt8(truncatingIfNeeded: scalar.value) }
