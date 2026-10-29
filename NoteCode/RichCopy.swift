//
//  RichCopy.swift
//  NoteCode
//
//  Text overhaul, phase 5: a copy from a note puts the Markdown on the
//  pasteboard as it always has, and beside it the text as it reads, as RTF,
//  so Pages, Mail and Notes keep the bold, the sizes and the colours.
//

#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

/// The selection as the page shows it: the characters that can be seen, with
/// what they are drawn with, and none of the markers that are hidden.
///
/// - **The selection is of visible characters.** The lines it touches are
///   read whole (`StyledLine`), so a selection that starts inside `**` or ends
///   in the middle of a span still has the span's style; a character is in the
///   copy if the selection touches it. Markers are never glyphs, so none
///   appear.
/// - **Fonts are the page's** (`DocumentStyler.font(for:over:)`): a heading is
///   the heading font, a run its size against it. Colours are drawn as a
///   light page draws them (`AccentPalette.textHex`), since Pages' page is
///   light whatever the device is; plain text has no colour, so a dark
///   document keeps its own.
/// - **Lists keep their markers** (a bullet, the number, a box) when the
///   selection reaches them, indented by depth.
/// - **Code is monospaced text without its fences.** No syntax colours and
///   no panel: a block's text, a line each.
/// - **A formula is its source in Menlo**, dollars included (`$x^2$`, or
///   the lines of a `$$` block): a receiving app can't draw TeX, and the
///   source is what a person can read there and paste back.
/// - **The Markdown stays the plain text**, and the Markdown also rides in a
///   type of the app's own (`RichPaste.ownType`), so a paste into a note
///   takes the Markdown whole instead of reading the RTF back.
enum RichCopy {

    /// Past this the RTF is left out: a copy of a book isn't worth building.
    static let maxCharacters = 200_000

    /// The selection as styled text, or `nil` where there is none to make.
    static func attributedString(
        selection: NSRange,
        in text: NSString,
        codeRanges: [CodeRange],
        typography: NoteTypography
    ) -> NSAttributedString? {
        guard selection.length > 0, selection.length <= maxCharacters,
              NSMaxRange(selection) <= text.length
        else { return nil }

        let mathRanges = Self.mathBlockRanges(in: text)
        let result = NSMutableAttributedString()
        var lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
        while lineStart < NSMaxRange(selection) {
            let full = text.lineRange(for: NSRange(location: lineStart, length: 0))
            guard full.length > 0 else { break }
            var contentEnd = NSMaxRange(full)
            while contentEnd > full.location, [10, 13].contains(text.character(at: contentEnd - 1)) { contentEnd -= 1 }
            let content = NSRange(location: full.location, length: contentEnd - full.location)
            let part = NSIntersectionRange(content, selection)
            let endsLine = contentEnd < NSMaxRange(full) && NSMaxRange(selection) > contentEnd
            lineStart = NSMaxRange(full)

            if mathRanges.contains(where: { NSLocationInRange(content.location, $0) }) {
                // Every line of a display block, its `$$` lines too.
                if part.length > 0 {
                    result.append(NSAttributedString(
                        string: text.substring(with: part), attributes: [.font: portable(typography.code)]
                    ))
                }
                if endsLine { result.append(NSAttributedString(string: "\n", attributes: [.font: portable(typography.prose)])) }
                continue
            }

            let block = codeRanges.first { NSLocationInRange(content.location, $0.range) }
            if let block {
                // A fence line is the block's chrome, with its line end.
                if content.location == block.range.location || (block.isClosed && contentEnd == block.lastCaret) { continue }
                result.append(NSAttributedString(
                    string: part.length > 0 ? text.substring(with: part) : "",
                    attributes: [.font: portable(typography.code)]
                ))
            } else {
                result.append(proseLine(text.substring(with: content), content: content, part: part, typography: typography))
            }
            if endsLine { result.append(NSAttributedString(string: "\n", attributes: [.font: portable(typography.prose)])) }
        }
        return result.length > 0 ? result : nil
    }

    /// Where the `$$` blocks are, found by parsing the note only when it has
    /// a `$$` to find.
    static func mathBlockRanges(in text: NSString) -> [NSRange] {
        guard text.range(of: "$$").location != NSNotFound else { return [] }
        let source = String(text)
        return DocumentParser.parse(source).compactMap { block in
            block.isMath ? NSRange(block.range, in: source) : nil
        }
    }

    /// The part of a prose line that the selection touches.
    private static func proseLine(_ line: String, content: NSRange, part: NSRange, typography: NoteTypography) -> NSAttributedString {
        let plain = NSAttributedString(
            string: part.length > 0 ? (line as NSString).substring(with: NSRange(location: part.location - content.location, length: part.length)) : "",
            attributes: [.font: portable(typography.prose)]
        )
        guard let styled = StyledLine(line) else { return plain }
        let selected = NSRange(location: part.location - content.location, length: part.length)
        let block = DocumentParser.parse(line).first
        let blockFont = styled.headingLevel > 0 ? typography.heading(level: styled.headingLevel) : typography.prose

        let result = NSMutableAttributedString()
        var paragraph: NSParagraphStyle?

        // A list item's marker, when the selection reaches it.
        if case .listItem(let depth, let marker, _)? = block?.kind {
            let indent = CGFloat(depth) * 20
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = indent
            style.headIndent = indent + 20
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent + 20)]
            paragraph = style
            if selected.location < styled.content.location {
                let text = switch marker {
                case .bullet:               "•"
                case .ordered(let number):  "\(number)."
                case .checkbox(let checked): checked ? "☑" : "☐"
                }
                result.append(NSAttributedString(string: text + "\t", attributes: [.font: portable(blockFont), .paragraphStyle: style]))
            }
        }

        // Each formula's whole span, dollars included, and which of them a
        // glyph is in: the glyphs hold only the TeX, the markers being hidden.
        let formulas = Self.formulaRanges(in: styled)
        func formula(of glyph: StyledLine.Glyph) -> Int? {
            formulas.firstIndex { NSLocationInRange(glyph.source.location, $0) }
        }

        var index = 0
        while index < styled.glyphs.count {
            if let spanIndex = formula(of: styled.glyphs[index]) {
                var end = index
                while end < styled.glyphs.count, formula(of: styled.glyphs[end]) == spanIndex { end += 1 }
                index = end
                let span = formulas[spanIndex]
                if NSIntersectionRange(span, selected).length > 0 {
                    var attributes: [NSAttributedString.Key: Any] = [.font: portable(typography.code)]
                    if let paragraph { attributes[.paragraphStyle] = paragraph }
                    result.append(NSAttributedString(string: (line as NSString).substring(with: span), attributes: attributes))
                }
                continue
            }
            let style = styled.glyphs[index].style
            var text = ""
            var end = index
            while end < styled.glyphs.count, styled.glyphs[end].style == style, formula(of: styled.glyphs[end]) == nil {
                if NSIntersectionRange(styled.glyphs[end].source, selected).length > 0 { text += styled.glyphs[end].text }
                end += 1
            }
            index = end
            guard !text.isEmpty else { continue }
            var attributes = Self.attributes(for: style, text: text, over: blockFont)
            if let paragraph { attributes[.paragraphStyle] = paragraph }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }
        return result
    }

    /// The inline formulas of a line, each from its opening dollar to its
    /// closing one, in UTF-16 units.
    static func formulaRanges(in line: StyledLine) -> [NSRange] {
        var ranges: [NSRange] = []
        var opened: String.Index?
        for node in line.inlines {
            switch node.kind {
            case .opening(.math): opened = node.range.lowerBound
            case .closing(.math):
                if let start = opened {
                    ranges.append(NSRange(start..<node.range.upperBound, in: line.line))
                    opened = nil
                }
            default: break
            }
        }
        return ranges
    }

    /// What one stretch of a line is drawn with.
    static func attributes(for style: StyledLine.Style, text: String, over blockFont: UIFont) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: portable(DocumentStyler.font(
                for: InlineAttributes(
                    bold: style.bold, italic: style.italic, strikethrough: style.strikethrough,
                    code: style.code, link: style.link != nil, colour: style.colour, size: style.size
                ),
                over: blockFont
            )),
        ]
        if style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if let highlight = style.highlight {
            // RTF has no translucency: the colour as it looks over a white page.
            let alpha = HighlightColour.alpha(isDark: false)
            let hex = highlight.hex.light
            func channel(_ shift: Int) -> CGFloat {
                (CGFloat((hex >> shift) & 0xFF) * alpha + 255 * (1 - alpha)) / 255
            }
            attributes[.backgroundColor] = UIColor(red: channel(16), green: channel(8), blue: channel(0), alpha: 1)
        }
        if let link = style.link {
            if let url = LinkTarget.url(for: link.address ?? text) { attributes[.link] = url }
        } else if let colour = style.colour {
            let hex = AccentPalette.textHex(for: colour, isDark: false)
            attributes[.foregroundColor] = UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1
            )
        }
        return attributes
    }

    /// The same size and weight in a face Pages and Mail have. The system
    /// font has a private name in RTF, which another app may not find, and
    /// would show in whatever it falls back to.
    static func portable(_ font: UIFont) -> UIFont {
        let traits = font.fontDescriptor.symbolicTraits
        var wanted: UIFontDescriptor.SymbolicTraits = []
        if traits.contains(.traitBold) { wanted.insert(.traitBold) }
        if traits.contains(.traitItalic) { wanted.insert(.traitItalic) }
        let family = UIFontDescriptor(fontAttributes: [.family: traits.contains(.traitMonoSpace) ? "Menlo" : "Helvetica Neue"])
        return UIFont(descriptor: family.withSymbolicTraits(wanted) ?? family, size: font.pointSize)
    }

    // MARK: The pasteboard

    /// `attributed` as RTF.
    static func rtf(_ attributed: NSAttributedString) -> Data? {
        try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// Adds the RTF and the note's own Markdown to what a copy put on
    /// `pasteboard`, which is the selection as plain text.
    static func add(_ rtf: Data, to pasteboard: UIPasteboard) {
        var item = pasteboard.items.first ?? [:]
        guard let plain = item[UTType.utf8PlainText.identifier] as? String ?? pasteboard.string else { return }
        item[UTType.rtf.identifier] = rtf
        item[RichPaste.ownType] = Data(plain.utf8)
        pasteboard.items = [item]
    }
}
#endif
