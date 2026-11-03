//
//  NoteTitle.swift
//  NoteCode
//
//  What a note is called until its reader names it. Pure: strings in, a string
//  out, so it is tested with no store or view around it.
//

import Foundation

/// A note's displayed title: the name the reader gave it, or else its first
/// line of text.
///
/// `Page.title` stays "Untitled" until the reader renames the note, so every
/// place that shows a title calls `Page.displayTitle` (list, Home, search,
/// the top bar, the PDF and exported file names) rather than reading it.
nonisolated enum NoteTitle {

    /// What `Page.title` holds before the reader names the note, and what an
    /// empty note is called.
    static let placeholder = "Untitled"

    /// The most characters a title taken from the text keeps.
    static let limit = 60

    /// How much of a note is looked at: enough to pass a code block or two.
    private static let scannedBytes = 2_000

    /// The title to show: `stored` when the reader named the note, else the
    /// first line of `content`, else "Untitled".
    static func display(stored: String, content: String) -> String {
        let named = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if !named.isEmpty && named != placeholder { return named }
        return derived(from: content) ?? placeholder
    }

    /// The first non-empty line of prose, as the page draws it: no `#`, bold,
    /// italic, code or link markers, and no list bullet. Lines inside a code
    /// block, fences and rules are passed over. Cut to `limit` characters
    /// with an ellipsis. `nil` when there is no such line.
    ///
    /// Cheap by construction: it reads the first 2,000 bytes a line at a
    /// time and parses only the line it is going to use, so it can run for
    /// every row of the list and on every keystroke.
    static func derived(from content: String) -> String? {
        let head = String(decoding: content.utf8.prefix(scannedBytes), as: UTF8.self)
        var inFence = false
        for rawLine in head.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence || line.hasPrefix("$$") { continue }
            let text = plainText(of: line)
            if !text.isEmpty { return shortened(text) }
        }
        return nil
    }

    /// One line's words with the Markdown markers left out; the same
    /// projection as the outline's titles.
    private static func plainText(of line: String) -> String {
        for block in DocumentParser.parse(line) {
            switch block.kind {
            case .code, .rule, .math: continue
            case .heading, .paragraph, .listItem, .blockQuote: break
            }
            let words = block.inlines.filter { !$0.kind.isMarker }.map { String(line[$0.range]) }.joined()
            return words.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private static func shortened(_ text: String) -> String {
        guard text.count > limit else { return text }
        return text.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
    }
}

extension Page {
    /// The title to show for the note. Not stored: see `NoteTitle`. Rename
    /// writes `title`, and from then on that is what shows.
    var displayTitle: String {
        NoteTitle.display(stored: title, content: content)
    }

    /// Names the note from what the reader typed. Typing the title it
    /// already shows changes nothing, so opening the rename field and
    /// leaving doesn't freeze a title taken from the text; clearing it
    /// goes back to that.
    func rename(to typed: String) {
        let name = Page.title(fromTyped: typed)
        if name == displayTitle { return }
        title = name
    }
}
