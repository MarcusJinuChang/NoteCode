//
//  RichPaste.swift
//  NoteCode
//
//  Text overhaul, phase 5: styled text pasted into a note keeps its bold,
//  italic, strikethrough, underline, highlight, links, colour and size,
//  written as Markdown by
//  phase 3's writer. The conversion is pure (`RichPaste.markdown(from:)`);
//  reading the pasteboard is the UIKit part at the foot of the file.
//

import Foundation

/// What a character pasted from elsewhere was drawn with.
nonisolated struct PastedAttributes: Hashable, Sendable {
    var bold = false
    var italic = false
    var strikethrough = false
    var monospaced = false
    /// Where it links, as the source wrote it.
    var link: String?
    /// `0xRRGGBB`, or `nil` for none.
    var colour: Int?
    /// In the source's own points; 0 where it didn't say.
    var pointSize: Double = 0
    var underline = false
    /// The nearest of the six highlights to the source's background colour.
    var highlight: HighlightColour?
}

/// A stretch of pasted text drawn one way.
nonisolated struct PastedRun: Sendable {
    var text: String
    var attributes: PastedAttributes
}

/// Styled text from the pasteboard, turned into the Markdown a note holds.
///
/// - **Sizes are against the paste's own body.** The size most of the pasted
///   characters have is the body (Pages' 12pt, Safari's 16px), and every
///   other size is written as its ratio to it. Taken against the note's font
///   directly, all text from a 16pt page would be written as 0.94em of the
///   note's 17.
/// - **Colour keeps only colours.** Black, white and greys are the source's
///   text colour, not a choice (`isDefaultColour`), as are the colours of
///   links and code, which the app draws itself.
/// - **Code stays code.** A line that is all monospaced is pasted as plain
///   text, since code pasted into prose in backticks is worse than none; a
///   monospaced stretch among proportional text is an inline code span.
/// - **Underline and highlight** are phase 6's marks. A link's underline is
///   the browser's, not the writer's, so it isn't one. A background colour is
///   a highlight only if it is a colour, and is the nearest of the six by hue
///   (`highlight(forBackground:)`); white and greys are the page's.
/// - **Lists** the source drew with a bullet or number and a tab become `- `
///   and `1. ` items, nested by their tabs.
/// - **Never a line that shows its markers.** Each line goes through
///   `StyledLine`, which reads back what it writes. One that can't be
///   written with its links is written without them, and one that still
///   can't is plain.
nonisolated enum RichPaste {

    /// Past this, a paste is left to the text view as plain text: a line's
    /// rewrite is tried in several nestings, each parsed and compared.
    static let maxCharacters = 200_000
    static let maxLineCharacters = 4_000

    /// A size within this of the body's is the body's.
    static let sizeTolerance = 0.04

    /// The Markdown for `runs`, or `nil` where it comes to the same as the
    /// text pasted plain: nothing in it is styled, so the text view's own
    /// paste (and a typing style's) is the right one.
    ///
    /// - Parameter atLineStart: whether the paste lands at the start of a
    ///   line. A list item pasted mid-line has no place to start a list, so its
    ///   marker is left out.
    static func markdown(from runs: [PastedRun], atLineStart: Bool = true) -> String? {
        let glyphs = self.glyphs(of: runs)
        guard !glyphs.isEmpty, glyphs.count <= maxCharacters else { return nil }
        let body = bodySize(of: glyphs)

        var lines: [[Glyph]] = [[]]
        for glyph in glyphs {
            if glyph.text == "\n" { lines.append([]) } else { lines[lines.count - 1].append(glyph) }
        }
        let written = escapingAccidentalMath(in: lines.enumerated().map { index, line in
            self.line(line, body: body, listMarkerAllowed: index > 0 || atLineStart)
        }.joined(separator: "\n"))
        return written == glyphs.map(\.text).joined() ? nil : written
    }

    /// `markdown` with the dollars that would make a formula the source never
    /// had written as `\$`: "$a+1$" pasted into a note would draw
    /// "a+1" as TeX. A `$` that is already escaped, or in code, isn't a
    /// formula to the parser and is left as it is; so is a text with no `$`.
    static func escapingAccidentalMath(in markdown: String) -> String {
        guard markdown.contains("$") else { return markdown }
        var markers: [Range<String.Index>] = []
        for block in DocumentParser.parse(markdown) {
            if let math = block.mathBlock {
                markers += [math.openingRange, math.closingRange]
            }
            for node in block.inlines {
                if case .math? = node.kind.markup { markers.append(node.range) }
            }
        }
        guard !markers.isEmpty else { return markdown }
        // Back to front, so an insertion doesn't move the ones still to do.
        var written = markdown
        for marker in markers.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            for index in written[marker].indices.reversed() where written[index] == "$" {
                written.insert("\\", at: index)
            }
        }
        return written
    }

    // MARK: Glyphs

    struct Glyph {
        var text: String
        var attributes: PastedAttributes
    }

    /// The characters of `runs`, with line ends as `\n`, no-break spaces as
    /// spaces, and the object-replacement character an attachment leaves
    /// behind gone.
    static func glyphs(of runs: [PastedRun]) -> [Glyph] {
        var glyphs: [Glyph] = []
        for run in runs {
            for character in run.text {
                if character.isNewline {
                    glyphs.append(Glyph(text: "\n", attributes: run.attributes))
                } else if character == "\u{00A0}" || character == "\u{202F}" {
                    glyphs.append(Glyph(text: " ", attributes: run.attributes))
                } else if character != "\u{FFFC}" {
                    glyphs.append(Glyph(text: String(character), attributes: run.attributes))
                }
            }
        }
        return glyphs
    }

    /// The point size most of the text has, in half points: the paste's
    /// body. Monospaced text and white space don't vote, since code is
    /// drawn smaller than the text around it. `nil` where nothing votes.
    static func bodySize(of glyphs: [Glyph]) -> Double? {
        var votes: [Double: Int] = [:]
        for glyph in glyphs where glyph.attributes.pointSize > 0 && !glyph.attributes.monospaced
            && !glyph.text.allSatisfy(\.isWhitespace) {
            votes[(glyph.attributes.pointSize * 2).rounded() / 2, default: 0] += 1
        }
        // The size with the most votes; of equals, the smaller.
        return votes.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// A colour that is the source's text colour and not a choice: black,
    /// white and greys, anything within 15% of grey.
    static func isDefaultColour(_ hex: Int) -> Bool {
        let channels = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF]
        return (channels.max() ?? 0) - (channels.min() ?? 0) < 38
    }

    /// The highlight a background colour stands for: the one of the six whose
    /// hue is nearest, within 45 degrees. White, greys and anything too pale
    /// to have a hue are the page's own background and no highlight.
    static func highlight(forBackground hex: Int) -> HighlightColour? {
        guard !isDefaultColour(hex), let hue = hue(of: hex) else { return nil }
        let nearest = HighlightColour.allCases
            .compactMap { colour in self.hue(of: colour.hex.light).map { (colour, angle(hue, $0)) } }
            .min { $0.1 < $1.1 }
        guard let nearest, nearest.1 <= 45 else { return nil }
        return nearest.0
    }

    /// The hue of `0xRRGGBB` in degrees, or `nil` for a grey.
    private static func hue(of hex: Int) -> Double? {
        let red = Double((hex >> 16) & 0xFF), green = Double((hex >> 8) & 0xFF), blue = Double(hex & 0xFF)
        let high = max(red, green, blue), low = min(red, green, blue)
        guard high > low else { return nil }
        let spread = high - low
        let degrees: Double
        switch high {
        case red:   degrees = (green - blue) / spread
        case green: degrees = (blue - red) / spread + 2
        default:    degrees = (red - green) / spread + 4
        }
        return (degrees * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func angle(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    // MARK: Lists

    private static let bullets: Set<Character> = ["•", "◦", "▪", "▫", "‣", "⁃", "●", "○", "■", "□", "–", "—", "-", "*"]

    /// A list item's marker at the start of a line as the source drew it, a
    /// bullet or a number with a tab after it and tabs before for how deep
    /// it is, as the Markdown that says the same, and how many glyphs it
    /// took. A `-` or `*` needs a tab before it, or `-\tx` is only text.
    static func listMarker(_ glyphs: [Glyph]) -> (markdown: String, length: Int)? {
        let tabs = glyphs.prefix { $0.text == "\t" }.count
        let indent = String(repeating: " ", count: max(0, tabs - 1) * 2)
        var index = tabs

        if index + 1 < glyphs.count, glyphs[index + 1].text == "\t",
           glyphs[index].text.count == 1, let bullet = glyphs[index].text.first, bullets.contains(bullet),
           tabs > 0 || !"-*".contains(bullet) {
            return (indent + "- ", index + 2)
        }

        var digits = ""
        while index < glyphs.count, glyphs[index].text.count == 1, let digit = glyphs[index].text.first,
              digit.isASCII, digit.isNumber {
            digits += glyphs[index].text
            index += 1
        }
        guard !digits.isEmpty, digits.count <= 3, index + 1 < glyphs.count,
              glyphs[index].text == "." || glyphs[index].text == ")", glyphs[index + 1].text == "\t",
              let number = Int(digits)
        else { return nil }
        return (indent + "\(number). ", index + 2)
    }

    // MARK: A line

    /// One line, as Markdown.
    private static func line(_ glyphs: [Glyph], body: Double?, listMarkerAllowed: Bool) -> String {
        var glyphs = glyphs
        var prefix = ""
        if let marker = listMarker(glyphs) {
            if listMarkerAllowed { prefix = marker.markdown }
            glyphs.removeFirst(marker.length)
        }

        let texts = glyphs.map(\.text)
        let styles = self.styles(of: glyphs, body: body)
        guard styles.contains(where: { $0 != StyledLine.Style() }), glyphs.count <= maxLineCharacters else {
            return prefix + texts.joined()
        }

        // The whole style if it reads back, then without links, then plain.
        var attempts = [styles]
        if styles.contains(where: { $0.link != nil }) {
            attempts.append(styles.map { var style = $0; style.link = nil; return style })
        }
        for attempt in attempts {
            if let written = StyledLine(prefix)?.edited(replacing: 0..<0, with: texts, styles: attempt) {
                return written.line
            }
        }
        return prefix + texts.joined()
    }

    /// What each glyph is drawn with in the note.
    private static func styles(of glyphs: [Glyph], body: Double?) -> [StyledLine.Style] {
        // Code on a line of its own is plain; code among words is a span.
        let words = glyphs.filter { !$0.text.allSatisfy(\.isWhitespace) }
        guard !(words.isEmpty || words.allSatisfy { $0.attributes.monospaced }) else {
            return glyphs.map { _ in StyledLine.Style() }
        }

        var linkID = 0
        var previousLink: String?
        return glyphs.map { glyph in
            let attributes = glyph.attributes
            var style = StyledLine.Style()
            style.strikethrough = attributes.strikethrough
            if attributes.monospaced {
                style.code = true
                previousLink = nil
                return style
            }
            style.bold = attributes.bold
            style.italic = attributes.italic
            style.highlight = attributes.highlight
            if let address = attributes.link.flatMap(address(of:)) {
                if address != previousLink { linkID += 1 }
                previousLink = address
                style.link = StyledLine.Link(id: linkID, address: address)
            } else {
                previousLink = nil
                style.underline = attributes.underline
                if let colour = attributes.colour, !isDefaultColour(colour) { style.colour = colour }
            }
            if let body, attributes.pointSize > 0, abs(attributes.pointSize / body - 1) >= sizeTolerance {
                style.size = SpanSize(em: attributes.pointSize / body)
            }
            return style
        }
    }

    /// A link's address as it is written into `(…)`, or `nil` where the app
    /// wouldn't open it (only web addresses and mail do, `LinkTarget`).
    static func address(of link: String) -> String? {
        guard LinkTarget.url(for: link) != nil else { return nil }
        return MarkdownFormatting.linkAddress(from: link)
    }
}

// MARK: - The pasteboard

#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

extension RichPaste {

    /// Put on the pasteboard beside the RTF by a copy from a note, with the
    /// Markdown, so a paste into a note takes the Markdown whole: the RTF
    /// would lose what Markdown holds that RTF doesn't.
    static let ownType = "com.marcus.NoteCode.markdown"

    /// Past these the data is left alone. HTML is parsed on the main thread and
    /// a page's worth takes seconds, so it gets the smaller allowance.
    static let maxBytes = 2_000_000
    static let maxHTMLBytes = 400_000

    /// The pasteboard's styled text, richest first, or `nil` when it holds
    /// none, came from a note, or is too large.
    static func attributedString(from pasteboard: UIPasteboard) -> NSAttributedString? {
        guard !pasteboard.contains(pasteboardTypes: [ownType]) else { return nil }
        let sources: [(type: String, limit: Int, options: [NSAttributedString.DocumentReadingOptionKey: Any])] = [
            (UTType.rtf.identifier, maxBytes, [.documentType: NSAttributedString.DocumentType.rtf]),
            (UTType.flatRTFD.identifier, maxBytes, [.documentType: NSAttributedString.DocumentType.rtfd]),
            (UTType.html.identifier, maxHTMLBytes, [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]),
        ]
        for source in sources {
            guard pasteboard.contains(pasteboardTypes: [source.type]),
                  let data = pasteboard.data(forPasteboardType: source.type), data.count <= source.limit,
                  let text = try? NSAttributedString(data: data, options: source.options, documentAttributes: nil)
            else { continue }
            return text
        }
        return nil
    }

    /// `0xRRGGBB` for a colour that is mostly opaque, or `nil`.
    private nonisolated static func hex(of colour: UIColor) -> Int? {
        var (red, green, blue, alpha) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        guard colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha), alpha > 0.5 else { return nil }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }

    /// `attributed` as runs: what each stretch is drawn with, in the terms
    /// `markdown(from:)` reads.
    static func runs(from attributed: NSAttributedString) -> [PastedRun] {
        var runs: [PastedRun] = []
        let text = attributed.string as NSString
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attributes, range, _ in
            var pasted = PastedAttributes()
            if let font = attributes[.font] as? UIFont {
                let traits = font.fontDescriptor.symbolicTraits
                let weight = (font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat
                pasted.bold = traits.contains(.traitBold) || (weight ?? 0) >= UIFont.Weight.semibold.rawValue
                pasted.italic = traits.contains(.traitItalic)
                pasted.monospaced = traits.contains(.traitMonoSpace)
                pasted.pointSize = Double(font.pointSize)
            }
            pasted.strikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
            pasted.underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
            if let background = (attributes[.backgroundColor] as? UIColor).flatMap(Self.hex(of:)) {
                pasted.highlight = highlight(forBackground: background)
            }
            if let link = attributes[.link] {
                pasted.link = (link as? URL)?.absoluteString ?? (link as? String)
            }
            pasted.colour = (attributes[.foregroundColor] as? UIColor).flatMap(Self.hex(of:))
            runs.append(PastedRun(text: text.substring(with: range), attributes: pasted))
        }
        return runs
    }

    /// The Markdown for the pasteboard's styled text, or `nil` when there is
    /// none, or nothing in it that plain text wouldn't give.
    static func markdown(from pasteboard: UIPasteboard, atLineStart: Bool) -> String? {
        guard let attributed = attributedString(from: pasteboard) else { return nil }
        return markdown(from: runs(from: attributed), atLineStart: atLineStart)
    }
}
#endif
