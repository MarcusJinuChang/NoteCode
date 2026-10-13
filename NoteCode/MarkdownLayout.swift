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
    }

    struct Run: Equatable {
        var range: NSRange
        var kind: Kind

        /// What TextKit lays out in place of the run: always `range.length` units.
        var replacement: String {
            switch kind {
            case .joiners: String(repeating: joiner, count: range.length)
            case .bullet:  String(bullet)
            case .box:     String(box) + String(repeating: joiner, count: max(range.length - 1, 0))
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

            case .paragraph:
                break

            case .heading:
                let length = layout.contentRange.location - layout.range.location
                if length > 0 {
                    runs.append(Run(range: NSRange(location: layout.range.location, length: length), kind: .joiners))
                }

            case .listItem(_, let marker, _):
                runs += listRuns(of: layout, marker: marker, in: source)
            }

            for inline in layout.inlines {
                for marker in inline.markers {
                    runs.append(Run(range: marker, kind: .joiners))
                }
            }
        }
        return runs
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
            text.mutableString.replaceCharacters(in: local, with: run.replacement)
        }
        return text
    }
}

#endif
