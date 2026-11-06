//
//  BlankLineLayout.swift
//  NoteCode
//
//  Keeps blank lines out of page breaks.
//

#if canImport(UIKit)

import UIKit

/// Lays each blank line out as a zero-width space, so TextKit keeps it out of
/// the bands between pages the way it keeps every other line out.
///
/// **Why.** TextKit 2 doesn't apply a text container's exclusion paths to an
/// empty paragraph. It asks the container where the line may go, is told
/// "below the band", and puts the line where it proposed anyway (probe,
/// 23 September). Blank lines flowed straight through the breaks: print
/// layout's band holds about seven of them and seamless's none, so text after
/// a run of blank lines landed on different pages in different modes — which
/// is what ink relies on never happening — and the caret on a blank line was
/// drawn in the gap between sheets. A line holding a space is pushed like any
/// other, and a zero-width one looks exactly like a blank line.
///
/// **Only the layout changes.** The paragraph TextKit lays out is swapped; the
/// text storage, and so the note, still holds the newline. The swap is the
/// same length, one character for one, so every offset maps straight through.
///
/// The cost is one extra caret stop per blank line, after the space, which is
/// really the start of the next line. `DocumentUITextView` takes a tap there
/// back to the blank line.
final class BlankLineLayout: NSObject, NSTextContentStorageDelegate {

    static let stand = "\u{200B}"

    /// The Markdown markers to collapse, for a note laid out `rendered`
    /// (`Page.markdownLayout`). `nil` for a legacy note, which swaps blank
    /// lines only. Asked once per paragraph, so the owner caches the answer
    /// until the text changes.
    var markerRuns: (() -> [MarkdownLayout.Run])?

    /// The pushes that keep each paragraph on one page (`PagePaginator`),
    /// laid in as paragraph spacing on the copy TextKit lays out.
    let pushes = PagePushTable()

    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let storage = textContentStorage.textStorage, range.location < storage.length else { return nil }

        var laidOut: NSAttributedString?
        if let markerRuns {
            let touching = MarkdownLayout.runs(in: markerRuns(), touching: range)
            if !touching.isEmpty {
                laidOut = MarkdownLayout.laidOut(range, of: storage, runs: touching)
            }
        }

        if laidOut == nil,
           range.length == 1,
           (storage.string as NSString).character(at: range.location) == UTF16Unit.newline {
            let attributes = storage.attributes(at: range.location, effectiveRange: nil)
            laidOut = NSAttributedString(string: Self.stand, attributes: attributes)
        }

        let push = pushes.push(at: range.location)
        if push > 0 {
            laidOut = Self.pushed(laidOut ?? storage.attributedSubstring(from: range), by: push, gap: pushes.layout?.gap ?? 0)
        }
        return laidOut.map { NSTextParagraph(attributedString: $0) }
    }

    /// `paragraph` with `push` more space above it. Only the layout's copy:
    /// the note's text and styles are untouched, and the paragraph style's
    /// own spacing stays.
    static func pushed(_ paragraph: NSAttributedString, by push: CGFloat, gap: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: paragraph)
        let whole = NSRange(location: 0, length: result.length)
        let base = result.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle ?? .default
        let style = base.mutableCopy() as! NSMutableParagraphStyle
        style.paragraphSpacingBefore += push
        result.addAttribute(.paragraphStyle, value: style, range: whole)
        result.addAttribute(.pagePush, value: Double(push), range: whole)
        result.addAttribute(.pageGap, value: Double(gap), range: whole)
        return result
    }

    /// Whether the character at `offset` is a blank line: a newline that
    /// starts its paragraph.
    static func isBlankLine(at offset: Int, in text: NSString) -> Bool {
        guard offset >= 0, offset < text.length, text.character(at: offset) == UTF16Unit.newline else { return false }
        return offset == 0 || text.character(at: offset - 1) == UTF16Unit.newline
    }
}

#endif
