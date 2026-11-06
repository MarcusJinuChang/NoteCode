//
//  ProseLine.swift
//  NoteCode
//
//  Which headings show their marker, and reading one line of prose for the
//  fragments that decorate it. Pure: no UIKit, no TextKit.
//

import Foundation

/// Which headings draw their `#`s in the margin. Pure, like `FenceVisibility`.
///
/// **Drawn, never laid out.** The heading's text sits at the column edge
/// whether its hashes are showing or not; they are painted in the margin to
/// the left, so showing and hiding them moves nothing, and a stroke drawn
/// beside the heading stays beside it.
nonisolated struct HeadingMarkerVisibility: Equatable, Sendable {

    /// The start offset of each heading line the caret or a selection is on.
    var editing: Set<Int> = []

    /// Show Markdown: Always.
    var showsEvery = false

    static let hidden = HeadingMarkerVisibility()

    func shows(headingAt lineStart: Int) -> Bool {
        showsEvery || editing.contains(lineStart)
    }

    /// - Parameters:
    ///   - text: the note, so the lines under a selection can be found.
    ///   - codeRanges: the code blocks, whose lines are never headings.
    ///   - isInk: in ink mode nothing is being edited and the margin is left
    ///     bare, whatever the setting says: the page is for drawing on.
    static func at(
        selection: NSRange,
        in text: NSString,
        codeRanges: [CodeRange],
        mode: ShowMarkdown,
        isInk: Bool
    ) -> HeadingMarkerVisibility {
        guard !isInk else { return .hidden }
        var state = HeadingMarkerVisibility(showsEvery: mode == .always)

        for line in MarkdownFormatting.lines(touching: selection, in: text) {
            guard line.length > 0,
                  FenceVisibility.blockIndex(containing: line.location, in: codeRanges) == nil,
                  ProseLine.headingHashes(in: text, line: line) != nil
            else { continue }
            state.editing.insert(line.location)
        }
        return state
    }
}

/// Reading a single line of prose, for the fragments that decorate it.
///
/// Through `DocumentParser`, on the one line, so the fragments and the parser
/// can't disagree about what a heading or a checkbox is. A prefilter looks at
/// the first characters first: this runs for every paragraph TextKit lays out.
nonisolated enum ProseLine {

    /// The number of `#`s of a heading line, `nil` for anything else.
    static func headingHashes(in text: NSString, line: NSRange) -> Int? {
        guard line.length > 1, text.character(at: line.location) == 0x23 else { return nil }
        let content = text.substring(with: line)
        return DocumentParser.parse(content).first?.headingLevel
    }

    /// How many `>`s a quote line has, `nil` for anything else.
    static func quoteDepth(in text: NSString, line: NSRange) -> Int? {
        guard let first = firstCharacter(in: text, line: line), first == 0x3E else { return nil }
        return DocumentParser.parse(text.substring(with: line)).first?.quoteDepth
    }

    /// Whether the line is a horizontal rule.
    static func isRule(in text: NSString, line: NSRange) -> Bool {
        guard line.length >= 3, let first = firstCharacter(in: text, line: line), first == 0x2D else { return false }
        return DocumentParser.parse(text.substring(with: line)).first?.isRule == true
    }

    /// The first character after up to three spaces: what a line begins
    /// with, for the prefilter every paragraph TextKit lays out goes through.
    private static func firstCharacter(in text: NSString, line: NSRange) -> unichar? {
        var cursor = line.location
        let end = min(NSMaxRange(line), line.location + 4)
        while cursor < end, text.character(at: cursor) == 0x20 { cursor += 1 }
        return cursor < NSMaxRange(line) ? text.character(at: cursor) : nil
    }

    /// A checklist line's indentation (in UTF-16 units) and whether it is ticked.
    static func checkbox(in text: NSString, line: NSRange) -> (indent: Int, checked: Bool)? {
        var cursor = line.location
        let end = NSMaxRange(line)
        while cursor < end, text.character(at: cursor) == 0x20 || text.character(at: cursor) == 0x09 { cursor += 1 }
        guard cursor + 5 <= end else { return nil }
        let bullet = text.character(at: cursor)
        guard bullet == 0x2D || bullet == 0x2A || bullet == 0x2B, text.character(at: cursor + 1) == 0x20,
              text.character(at: cursor + 2) == 0x5B
        else { return nil }
        let content = text.substring(with: line)
        guard let block = DocumentParser.parse(content).first,
              case .checkbox(let checked)? = block.listMarker
        else { return nil }
        return (cursor - line.location, checked)
    }
}
