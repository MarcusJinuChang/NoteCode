//
//  MarkdownLayout+Layout.swift
//  NoteCode
//
//  Lays a paragraph out with its Markdown markers collapsed. The planning
//  half, which works out the runs, is Text/Core/MarkdownLayout.swift.
//

#if canImport(UIKit)

import UIKit

extension MarkdownLayout {

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
