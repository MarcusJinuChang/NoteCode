//
//  NoteOutline.swift
//  NoteCode
//
//  The headings of a note, for the outline popover. Pure: a string in, a list
//  out, so the outline can be tested against the parser with no view around it.
//

import Foundation

/// A note's headings, in order, as the parser finds them.
nonisolated enum NoteOutline {

    struct Entry: Equatable, Identifiable, Sendable {
        /// 1 to 6, the number of `#`.
        var level: Int
        /// The heading's words as they read on the page: no `#`, and no
        /// bold, italic, code or link markers around them.
        var title: String
        /// Where the heading's line starts, in the text storage's UTF-16
        /// units, which is what the text view and `PageView` count in.
        var location: Int

        var id: Int { location }
    }

    /// The note's headings.
    ///
    /// Read from `DocumentParser`, the parser the styler uses, so a line is
    /// in the outline exactly when the page draws it as a heading: a `#` line
    /// inside a code block is code, and `#hashtag` with no space is prose.
    /// A heading with no words still has an entry (an empty title), because
    /// it is a heading on the page; the popover calls it "Untitled".
    static func entries(in source: String) -> [Entry] {
        entries(in: source, blocks: DocumentParser.parse(source))
    }

    static func entries(in source: String, blocks: [BlockNode]) -> [Entry] {
        var entries: [Entry] = []
        // Blocks are contiguous and in order, so a running total gives each
        // one's UTF-16 offset in one pass. Converting every heading's index
        // from the start would be quadratic in the note's length.
        var offset = 0
        for block in blocks {
            if let level = block.headingLevel {
                entries.append(Entry(level: level, title: title(of: block, in: source), location: offset))
            }
            offset += source[block.range].utf16.count
        }
        return entries
    }

    /// The index of the heading the reader is under: the last one at or
    /// before `character`. `nil` above the first heading.
    static func currentIndex(in entries: [Entry], atCharacter character: Int) -> Int? {
        entries.lastIndex { $0.location <= character }
    }

    /// The lowest level in the outline, so a note that starts at `##` isn't
    /// indented by a level nobody wrote.
    static func topLevel(of entries: [Entry]) -> Int {
        entries.map(\.level).min() ?? 1
    }

    private static func title(of block: BlockNode, in source: String) -> String {
        // The text that is drawn, markers left out. Link text is the words
        // between the brackets.
        let words = block.inlines.filter { !$0.kind.isMarker }.map { String(source[$0.range]) }.joined()
        return words.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
