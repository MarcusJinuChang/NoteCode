//
//  MarkdownLayout.swift
//  NoteCode
//
//  Markdown markers that take no room on the page.
//

#if canImport(UIKit)

import UIKit

/// Which characters of a note TextKit lays out as something else, so that
/// Markdown's markers take no width.
///
/// **Why layout, and never the caret.** A marker that appeared when the caret
/// arrived would push the words after it and could re-wrap the lines below,
/// while ink stays where it was drawn. So whether a marker takes room is a
/// function of the text alone: the same with the caret anywhere, in either
/// mode, with either Show Markdown setting. What the caret changes is only
/// what is *drawn* (a heading's `#` in the margin), and that is a redraw.
///
/// **How.** Like `BlankLineLayout`, the paragraph TextKit lays out is swapped
/// for one of the same length, one UTF-16 unit for one, so every offset still
/// lines up with the note. A marker becomes U+2060 WORD JOINER: zero width,
/// and unlike a zero-width space it doesn't allow a line break. The note's
/// text, and so search, export and copy, still holds the Markdown.
///
/// The ranges come from `DocumentStyler.layouts`, the same ones that dim the
/// markers in a legacy note, so styling and layout can't disagree.
enum MarkdownLayout {

    static let joiner: Character = "\u{2060}"
    static let box: Character = "\u{2003}"   // em space: the checkbox is drawn in it
    static let bullet: Character = "\u{2022}"

    enum Kind: Equatable {
        /// Every unit becomes a word joiner.
        case joiners
        /// One unit, `-`, `*` or `+`, becomes a bullet.
        case bullet
        /// `[ ]` or `[x]` (three units) becomes an em space and two joiners.
        case box
        /// A whole `$…$` (markers included) laid out as one attachment: the
        /// typeset `tex` (aliases resolved), whether it is display style
        /// (`$$x$$` in a line), and how many units the opening marker takes,
        /// so the TeX's own attributes (colour, size) can be found.
        case formula(tex: String, display: Bool, opening: Int)
        /// The first line of a `$$` block: the whole line is the formula's
        /// attachment, centred on a line of its own (`DisplayFormula`). The
        /// block's other lines are `.joiners`.
        case displayFormula(tex: String)
    }

    /// U+FFFC, which the text view draws as the formula's attachment.
    static let attachmentCharacter: Character = "\u{FFFC}"

    struct Run: Equatable {
        var range: NSRange
        var kind: Kind

        /// What TextKit lays out in place of the run: always `range.length` units.
        var replacement: String {
            switch kind {
            case .joiners: String(repeating: joiner, count: range.length)
            case .bullet:  String(bullet)
            case .box:     String(box) + String(repeating: joiner, count: max(range.length - 1, 0))
            case .formula, .displayFormula: String(attachmentCharacter) + String(repeating: joiner, count: max(range.length - 1, 0))
            }
        }
    }

    /// The runs to collapse in a rendered note, in document order.
    ///
    /// Nothing in a code block collapses: its fences are drawn or hidden by
    /// the fragment. Inline code collapses its backticks only.
    static func runs(for blocks: [BlockNode], in source: String) -> [Run] {
        runs(from: DocumentStyler.layouts(for: blocks, in: source), in: source)
    }

    static func runs(from layouts: [DocumentStyler.BlockLayout], in source: String) -> [Run] {
        var runs: [Run] = []
        for layout in layouts {
            switch layout.block.kind {
            case .code:
                continue

            case .math(let math):
                runs += displayRuns(of: layout, math: math, in: source)
                continue

            case .paragraph:
                break

            case .heading, .blockQuote, .rule:
                // A heading's hashes, a quote's `>`s and a rule's dashes.
                let length = layout.contentRange.location - layout.range.location
                if length > 0 {
                    runs.append(Run(range: NSRange(location: layout.range.location, length: length), kind: .joiners))
                }

            case .listItem(_, let marker, _):
                runs += listRuns(of: layout, marker: marker, in: source)
            }

            var index = 0
            while index < layout.inlines.count {
                let inline = layout.inlines[index]
                if let formula = formulaRun(at: index, in: layout, source: source) {
                    runs.append(formula)
                    index += 3
                    continue
                }
                // A formula that can't be drawn keeps its dollars: it shows
                // as typed, dimmed by the styler.
                if !isMathMarker(inline.kind) {
                    for marker in inline.markers {
                        runs.append(Run(range: marker, kind: .joiners))
                    }
                }
                index += 1
            }
        }
        return runs
    }

    /// A `$$` block drawable as a formula: its first line becomes the
    /// attachment and every other non-empty line collapses to joiners (their
    /// height is the styler's, `DisplayFormula.sourceLineHeight`). An
    /// undrawable block keeps its source, dimmed by the styler.
    static func displayRuns(of layout: DocumentStyler.BlockLayout, math: MathBlock, in source: String) -> [Run] {
        guard let tex = FormulaValidity.check(String(source[math.contentRange])).tex else { return [] }
        var runs: [Run] = []
        let text = source as NSString
        var location = layout.range.location
        let end = NSMaxRange(layout.range)
        while location < end {
            var lineEnd = location
            while lineEnd < end, text.character(at: lineEnd) != 0x0A { lineEnd += 1 }
            let length = lineEnd - location
            if length > 0 {
                let range = NSRange(location: location, length: length)
                runs.append(Run(range: range, kind: runs.isEmpty ? .displayFormula(tex: tex) : .joiners))
            } else if runs.isEmpty {
                return []
            }
            location = lineEnd + 1
        }
        return runs
    }

    private static func isMathMarker(_ kind: InlineNode.Kind) -> Bool {
        if case .math? = kind.markup { return true }
        return false
    }

    /// The run for the formula whose opening `$` is inline `index` of
    /// `layout`, when its TeX is one that can be drawn
    /// (`FormulaValidity`, the same answer the styler dims by).
    static func formulaRun(at index: Int, in layout: DocumentStyler.BlockLayout, source: String) -> Run? {
        guard index + 2 < layout.inlines.count,
              case .opening(.math(let style)) = layout.inlines[index].kind,
              layout.inlines[index + 1].kind == .text,
              case .closing(.math) = layout.inlines[index + 2].kind,
              layout.block.inlines.count == layout.inlines.count,
              let tex = FormulaValidity.check(String(source[layout.block.inlines[index + 1].range])).tex
        else { return nil }
        let opening = layout.inlines[index].range
        let closing = layout.inlines[index + 2].range
        return Run(
            range: NSRange(location: opening.location, length: NSMaxRange(closing) - opening.location),
            kind: .formula(tex: tex, display: style == .display, opening: opening.length)
        )
    }

    /// A list item's marker as laid out: its bullet as `•`, a checkbox as an
    /// em space the box is drawn in. A number stays as typed.
    private static func listRuns(of layout: DocumentStyler.BlockLayout, marker: ListMarker, in source: String) -> [Run] {
        let start = layout.range.location
        let end = layout.contentRange.location
        let indent = source[layout.block.range].prefix { $0 == " " || $0 == "\t" }.utf16.count
        let at = start + indent

        switch marker {
        case .ordered:
            return []
        case .bullet:
            return [Run(range: NSRange(location: at, length: 1), kind: .bullet)]
        case .checkbox:
            // `- ` then `[x]` then the space after, if there is one. The
            // bullet and its space go; the space after the box stays, as the
            // gap between the box and the words.
            var runs = [Run(range: NSRange(location: at, length: 2), kind: .joiners)]
            let boxStart = at + 2
            if boxStart + 3 <= end {
                runs.append(Run(range: NSRange(location: boxStart, length: 3), kind: .box))
            }
            return runs
        }
    }

    /// The runs that touch `paragraph`, from the sorted list `runs`.
    static func runs(in runs: [Run], touching paragraph: NSRange) -> ArraySlice<Run> {
        var low = 0
        var high = runs.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(runs[mid].range) <= paragraph.location { low = mid + 1 } else { high = mid }
        }
        var end = low
        while end < runs.count, runs[end].range.location < NSMaxRange(paragraph) { end += 1 }
        return runs[low..<end]
    }

    /// `paragraph` of `storage`, with the runs inside it collapsed.
    static func laidOut(_ paragraph: NSRange, of storage: NSTextStorage, runs: ArraySlice<Run>) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: paragraph))
        for run in runs {
            let local = NSRange(location: run.range.location - paragraph.location, length: run.range.length)
            guard local.location >= 0, NSMaxRange(local) <= text.length else { continue }
            if case .formula(let tex, let display, let opening) = run.kind {
                // The TeX's own font and colour, not the dimmed dollars'.
                let at = min(local.location + opening, text.length - 1)
                let attributes = text.attributes(at: at, effectiveRange: nil)
                let size = (attributes[.font] as? UIFont)?.pointSize ?? 17
                text.mutableString.replaceCharacters(in: local, with: run.replacement)
                text.setAttributes(attributes, range: local)
                if let attachment = FormulaAttachment.make(tex: tex, pointSize: size, display: display) {
                    text.addAttribute(.attachment, value: attachment, range: NSRange(location: local.location, length: 1))
                    text.addAttribute(FormulaAttachment.sourceKey, value: FormulaAttachment.Source(tex: tex, pointSize: size, display: display), range: NSRange(location: local.location, length: 1))
                }
                continue
            }
            if case .displayFormula(let tex) = run.kind {
                let attributes = text.attributes(at: local.location, effectiveRange: nil)
                let font = attributes[.font] as? UIFont
                text.mutableString.replaceCharacters(in: local, with: run.replacement)
                text.setAttributes(attributes, range: local)
                if let attachment = FormulaAttachment.make(tex: tex, pointSize: font?.pointSize ?? 17, display: true, fitting: true) {
                    text.addAttribute(.attachment, value: attachment, range: NSRange(location: local.location, length: 1))
                    text.addAttribute(FormulaAttachment.sourceKey, value: FormulaAttachment.Source(tex: tex, pointSize: font?.pointSize ?? 17, display: true), range: NSRange(location: local.location, length: 1))
                    let lift = DisplayFormula.baselineLift(tex: tex, font: font ?? .preferredFont(forTextStyle: .body))
                    text.addAttribute(.baselineOffset, value: lift, range: NSRange(location: local.location, length: 1))
                }
                continue
            }
            text.mutableString.replaceCharacters(in: local, with: run.replacement)
        }
        anchorTrailingJoiners(in: text)
        return text
    }

    static let anchor: Character = "\u{00A0}"

    /// Gives joiners that end a paragraph a glyph to be measured against.
    ///
    /// TextKit puts a caret in front of a zero-width character at the line's
    /// *start* when nothing drawn follows it on the line (probe, 15 Oct, a
    /// plain `UITextView` with no app code: U+2060, U+200B and U+FEFF alike).
    /// So in `[Apple](apple.com)` on a line of its own, the offset after
    /// "Apple" sat at x = 0: the link measured no width and a tap on it never
    /// found it, and a caret after a bold word that ends its line was drawn at
    /// the line's start. Anything drawn after the joiners puts them right,
    /// which is why a link with words after it always worked.
    ///
    /// So the last of them is laid out as a no-break space, kerned back by
    /// its own advance: a glyph, and still no width and no break. Not when
    /// the font has no glyph for it, since a fallback font's advance wouldn't
    /// be cancelled exactly.
    private static func anchorTrailingJoiners(in text: NSMutableAttributedString) {
        let units = text.mutableString
        var end = units.length
        while end > 0, isParagraphSeparator(units.character(at: end - 1)) { end -= 1 }
        let joiner = UInt16(MarkdownLayout.joiner.unicodeScalars.first!.value)
        guard end > 0, units.character(at: end - 1) == joiner,
              let font = text.attribute(.font, at: end - 1, effectiveRange: nil) as? UIFont
        else { return }

        var character = UniChar(anchor.unicodeScalars.first!.value)
        var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1) else { return }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font as CTFont, .horizontal, &glyph, &advance, 1)

        let last = NSRange(location: end - 1, length: 1)
        units.replaceCharacters(in: last, with: String(anchor))
        text.addAttribute(.kern, value: -advance.width, range: last)
    }

    private static func isParagraphSeparator(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029
    }
}

#endif
