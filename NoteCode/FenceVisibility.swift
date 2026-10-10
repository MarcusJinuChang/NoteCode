//
//  FenceVisibility.swift
//  NoteCode
//
//  Which code blocks show their backticks. Pure: no UIKit, no TextKit.
//

import Foundation

/// Settings › Writing › Show Markdown.
nonisolated enum ShowMarkdown: String, CaseIterable, Sendable {
    /// A block shows its fences while the caret or a selection is in it, and
    /// hides them otherwise. The default.
    case whileEditing
    /// Every block shows its fences all the time.
    case always

    static let defaultsKey = "showMarkdown"

    var title: String {
        switch self {
        case .whileEditing: "While Editing"
        case .always:       "Always"
        }
    }
}

/// Which code blocks are being edited, and so which show their fences.
///
/// Blocks are named by their place among the note's code blocks, in document
/// order: the same index `CodeBlockOverlay` and `CodeBlockAction.targets` use.
/// The state is drawn, never laid out: hiding a fence's glyphs leaves its
/// line exactly as tall as it was, since collapsing it would move every line
/// below it and leave ink over the wrong words (AGENTS.md, "Code-block
/// fences").
nonisolated struct FenceVisibility: Equatable, Sendable {

    /// The blocks the caret or a selection is in. Each gets its fences, its
    /// ring and no language button.
    var editing: Set<Int> = []

    /// Show Markdown: Always. Every block's fences are drawn; the ring still
    /// marks only the block being edited.
    var showsEveryFence = false

    /// Nothing being edited, nothing forced: every block away.
    static let away = FenceVisibility()

    func showsFences(ofBlock index: Int) -> Bool {
        showsEveryFence || editing.contains(index)
    }

    func isEditing(block index: Int) -> Bool {
        editing.contains(index)
    }

    /// Works out the state for a selection.
    ///
    /// - Parameters:
    ///   - selection: the text view's selected range; a caret has length 0.
    ///   - ranges: the note's code blocks, in order.
    ///   - mode: the Show Markdown setting.
    ///   - isInk: in ink mode nothing is being edited, whatever the selection
    ///     last was, so every block is away. Always still shows them: the
    ///     setting asks for the markdown to stay.
    static func at(
        selection: NSRange,
        in ranges: [CodeRange],
        mode: ShowMarkdown,
        isInk: Bool
    ) -> FenceVisibility {
        var state = FenceVisibility(showsEveryFence: mode == .always)
        guard !isInk else { return state }

        for (index, code) in ranges.enumerated() where code.contains(selection) {
            state.editing.insert(index)
        }
        return state
    }

    /// The block whose range holds `offset`, by binary search: it runs for
    /// every fragment drawn. `ranges` are sorted and never overlap.
    static func blockIndex(containing offset: Int, in ranges: [CodeRange]) -> Int? {
        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let range = ranges[middle].range
            if offset < range.location {
                high = middle - 1
            } else if offset >= range.location + range.length {
                low = middle + 1
            } else {
                return middle
            }
        }
        return nil
    }
}

extension CodeRange {

    /// Whether a caret or selection is in this block, opening fence to
    /// closing fence.
    ///
    /// A caret counts from the start of the opening fence's line to the end
    /// of the closing fence's line, before its newline: the line after is
    /// prose. An unclosed block has no closing line, so its caret runs to the
    /// end of the note, including the empty line after a final newline, which
    /// is still code. A selection counts when it overlaps the block by at
    /// least a character, so one that ends where the block starts doesn't.
    nonisolated func contains(_ selection: NSRange) -> Bool {
        if selection.length == 0 {
            return selection.location >= range.location && selection.location <= lastCaret
        }
        return NSIntersectionRange(selection, range).length > 0
    }
}

// MARK: - Fence tags

/// Changing a block's language by rewriting its opening fence.
nonisolated enum FenceTag {

    /// What the language button says: the language's name, the tag as typed
    /// when the app doesn't know it, or "Plain Text" for a bare fence.
    static func label(language: CodeLanguage?, tag: String) -> String {
        language?.displayName ?? (tag.isEmpty ? "Plain Text" : tag)
    }

    /// The edit that points an opening fence at `language`, `nil` for plain
    /// text. Returns `nil` when the fence is already as wanted, or isn't one.
    ///
    /// - Parameter line: the opening fence's line, with or without its
    ///   terminator.
    /// - Returns: a range within `line`, in UTF-16, and what replaces it.
    ///
    /// Only the first word of the info string is the tag, so a language
    /// replaces just that and anything after it is kept. Plain text drops the
    /// whole info string: what's left after taking out the tag would be read
    /// as a tag of its own.
    static func retag(line: String, as language: CodeLanguage?) -> (range: NSRange, replacement: String)? {
        let text = line as NSString
        var end = text.length
        while end > 0, [10, 13].contains(text.character(at: end - 1)) { end -= 1 }

        func isBlank(_ unit: unichar) -> Bool { unit == 32 || unit == 9 }

        var cursor = 0
        while cursor < end, text.character(at: cursor) == 32 { cursor += 1 }
        let ticksStart = cursor
        while cursor < end, text.character(at: cursor) == 96 { cursor += 1 }
        guard cursor - ticksStart >= 3 else { return nil }
        let afterTicks = cursor

        while cursor < end, isBlank(text.character(at: cursor)) { cursor += 1 }
        let tagStart = cursor
        while cursor < end, !isBlank(text.character(at: cursor)) { cursor += 1 }
        let tagEnd = cursor
        let hasTag = tagStart < tagEnd

        guard let language else {
            return hasTag ? (NSRange(location: afterTicks, length: end - afterTicks), "") : nil
        }
        let name = language.rawValue
        if hasTag {
            guard text.substring(with: NSRange(location: tagStart, length: tagEnd - tagStart)) != name else { return nil }
            return (NSRange(location: tagStart, length: tagEnd - tagStart), name)
        }
        return (NSRange(location: tagStart, length: 0), name)
    }
}
