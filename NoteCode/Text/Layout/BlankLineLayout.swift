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

    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let storage = textContentStorage.textStorage, range.location < storage.length else { return nil }

        if let markerRuns {
            let touching = MarkdownLayout.runs(in: markerRuns(), touching: range)
            if !touching.isEmpty {
                return NSTextParagraph(attributedString: MarkdownLayout.laidOut(range, of: storage, runs: touching))
            }
        }

        guard range.length == 1,
              (storage.string as NSString).character(at: range.location) == 0x0A
        else { return nil }

        let attributes = storage.attributes(at: range.location, effectiveRange: nil)
        return NSTextParagraph(attributedString: NSAttributedString(string: Self.stand, attributes: attributes))
    }

    /// Whether the character at `offset` is a blank line: a newline that
    /// starts its paragraph.
    static func isBlankLine(at offset: Int, in text: NSString) -> Bool {
        guard offset >= 0, offset < text.length, text.character(at: offset) == 0x0A else { return false }
        return offset == 0 || text.character(at: offset - 1) == 0x0A
    }
}

#endif
