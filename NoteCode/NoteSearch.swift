//
//  NoteSearch.swift
//  NoteCode
//
//  Finding notes by their words, for the note list's search field.
//

import Foundation
import SwiftData

/// A search of every note's title and text.
///
/// Every word typed has to appear, in the title or the text, in any order,
/// ignoring case and accents, and inside longer words too: "vec" finds
/// "vector". Ink isn't searched, since it's drawn rather than typed.
///
/// Pure, so what matches and how it reads are tested without SwiftUI.
nonisolated struct NoteSearch: Equatable, Sendable {
    /// The words searched for, as typed.
    let terms: [String]

    init(_ query: String) {
        terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether there's anything to search for. An empty search shows the
    /// list as it is.
    var isEmpty: Bool { terms.isEmpty }

    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    /// How one note matches.
    struct Match: Equatable, Sendable {
        /// Every word is in the title, which lists the note first.
        var inTitle: Bool
        /// The line holding the text's first match, shortened to start near
        /// it, for the result's row. `nil` when only the title matched.
        var excerpt: String?
    }

    /// How a note with this title and text matches, or `nil` if it doesn't.
    func match(title: String, content: String) -> Match? {
        guard !isEmpty else { return nil }
        // A run's tags aren't words in the note (`TextColour`).
        let content = SpanStyle.maskingTags(in: content)

        var inTitle = true
        var first: Range<String.Index>?
        for term in terms {
            let isInTitle = title.range(of: term, options: Self.options) != nil
            let found = content.range(of: term, options: Self.options)
            guard isInTitle || found != nil else { return nil }

            inTitle = inTitle && isInTitle
            if let found, first.map({ found.lowerBound < $0.lowerBound }) ?? true {
                first = found
            }
        }
        return Match(inTitle: inTitle, excerpt: first.map { Self.excerpt(around: $0, in: content) })
    }

    /// Every match of every word in `content`, in order, as UTF-16 ranges for
    /// the text view: what opening a result highlights, the first of them
    /// being where it scrolls.
    ///
    /// - Parameter limit: how many to find at most. A one-letter search of a
    ///   long note matches thousands of times, and nobody reads that many.
    func matches(in content: String, limit: Int = 500) -> [NSRange] {
        let content = SpanStyle.maskingTags(in: content)
        return ranges(in: content, limit: limit).map { NSRange($0, in: content) }
    }

    /// `text` with every match marked strongly emphasised, which SwiftUI's
    /// `Text` draws bold.
    func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        for range in ranges(in: text) {
            result += AttributedString(String(text[cursor..<range.lowerBound]))
            var match = AttributedString(String(text[range]))
            match.inlinePresentationIntent = .stronglyEmphasized
            result += match
            cursor = range.upperBound
        }
        result += AttributedString(String(text[cursor...]))
        return result
    }

    /// Every match of every word, in order, with overlapping ones merged: a
    /// search for "vec vector" marks "vector" once.
    private func ranges(in text: String, limit: Int = .max) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for term in terms {
            var rest = text.startIndex..<text.endIndex
            while found.count < limit,
                  let range = text.range(of: term, options: Self.options, range: rest),
                  !range.isEmpty {
                found.append(range)
                rest = range.upperBound..<text.endIndex
            }
        }

        var merged: [Range<String.Index>] = []
        for range in found.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return Array(merged.prefix(limit))
    }

    /// How much of a line to keep before a match. A row shows two lines of
    /// excerpt, so a match far along a long paragraph would otherwise fall
    /// off the end of it.
    static let excerptLead = 30

    /// The line holding `match`, trimmed, and starting near the match when
    /// it's far along: at a word, after an ellipsis.
    private static func excerpt(around match: Range<String.Index>, in content: String) -> String {
        let line = content.lineRange(for: match)
        // The words the page draws, not the Markdown typed: a heading's `#`
        // and a line's `**` are left out. A match that sat inside a marker
        // (a search for `**`) isn't in the words, and the line reads as typed.
        if let plain = plainLine(line, in: content),
           let found = plain.range(of: content[match], options: options) {
            return shortened(plain, around: found)
        }
        let typed = String(content[line])
        return shortened(typed, around: typed.range(of: content[match]) ?? typed.startIndex..<typed.startIndex)
    }

    /// The line as the page draws it: a block's words without its markers
    /// (as the outline's titles and Home's excerpt have them), or the line as
    /// is in a code block or formula, whose characters are all drawn.
    ///
    /// Parsed up to the end of the line only, which is all the context a
    /// block needs to be told from code, and keeps a long note cheap.
    private static func plainLine(_ line: Range<String.Index>, in content: String) -> String? {
        let source = String(content[..<line.upperBound])
        guard let block = DocumentParser.parse(source).last(where: { $0.range.lowerBound <= line.lowerBound }) else {
            return nil
        }
        switch block.kind {
        case .code, .math:
            return String(source[line])
        case .paragraph, .heading, .listItem, .blockQuote, .rule:
            // Only a block that starts on this line is read as a block.
            guard block.range.lowerBound == line.lowerBound else { return nil }
            return block.inlines.filter { !$0.kind.isMarker }
                .map { String(source[$0.range]) }.joined()
                .replacingOccurrences(of: "\u{2060}", with: "")
        }
    }

    /// `line` trimmed, and starting near `match` when it's far along.
    private static func shortened(_ line: String, around match: Range<String.Index>) -> String {
        let before = line[line.startIndex..<match.lowerBound].drop(while: \.isWhitespace)
        let after = line[match.lowerBound...]

        var lead = String(before)
        if before.count > excerptLead {
            let tail = before.suffix(excerptLead)
            // Start at the next word, rather than partway into one.
            let fromWord = tail.firstIndex(where: \.isWhitespace).map { tail[$0...].drop(while: \.isWhitespace) } ?? tail
            lead = "…" + fromWord
        }
        return (lead + after).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Results

@MainActor
extension NoteSearch {
    /// A note that matches, with how.
    struct Result: Identifiable {
        let page: Page
        let match: Match
        var id: PersistentIdentifier { page.persistentModelID }
    }

    /// The notes that match, title matches first and each group in the
    /// reader's sort.
    ///
    /// Folders and pins don't group results: a search is for one note, and
    /// one flat list is quicker to read than sections that might each hold
    /// one row.
    ///
    /// Notes in Recently Deleted aren't found (`Page.isLive`).
    func results(in pages: [Page], sort: NoteSort) -> [Result] {
        pages.live
            .compactMap { page in match(title: page.title, content: page.content).map { Result(page: page, match: $0) } }
            .sorted { a, b in
                if a.match.inTitle != b.match.inTitle { return a.match.inTitle }
                return sort.areInIncreasingOrder(
                    (a.page.title, a.page.modifiedAt, a.page.createdAt),
                    (b.page.title, b.page.modifiedAt, b.page.createdAt)
                )
            }
    }
}
