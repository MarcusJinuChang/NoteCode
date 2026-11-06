//
//  DocumentSnapshot.swift
//  NoteCode
//
//  The document as one edit left it: its text in Swift's own UTF-8 storage,
//  and everything worked out from it, each part once and only if asked for.
//  Pure: Foundation only.
//

import Foundation

/// One edit's view of the note (docs/refactor/2T-text.md › 2T1).
///
/// A keystroke used to copy the whole note many times over, once for each
/// reader that wanted to parse or index it, and kept four caches of its own
/// (`DocumentCache`, and the coordinator's code ranges, newlines and marker
/// runs). A snapshot is made once per edit; readers share it and ask it for
/// what they need.
///
/// Nothing is worked out in `init`. Each derived value is computed the first
/// time it is read, so a path that only needs the code ranges (the layout
/// delegate, once per paragraph) never pays for the layouts, and the other
/// way round. Nothing changes after that, so it is a value in all but its
/// storage: a class, because a struct cannot fill in a lazy property
/// through a `let`.
///
/// It holds a native `String`, never the text storage's `NSString`: that
/// is the reason `nativeUTF8` exists. Every index it hands out belongs to
/// `source`, and ranges derived from them are UTF-16 offsets into the same
/// text.
///
/// Not `Sendable`: the lazy values are filled in without a lock. It belongs
/// to whoever made it, one edit at a time on the main actor.
nonisolated final class DocumentSnapshot {
    /// The text, converted once. Parse and index this, not the text view's.
    let source: String

    /// How many times the text had been edited when this was made, so a
    /// reader can tell a snapshot of the current text from an older one.
    let editCount: Int

    /// `text` is converted with `nativeUTF8` here, so a caller can hand over
    /// `textView.text ?? ""` as it comes.
    init(text: String, editCount: Int = 0) {
        self.source = text.nativeUTF8
        self.editCount = editCount
    }

    /// The parse.
    private(set) lazy var blocks: [BlockNode] = DocumentParser.parse(source)

    /// Every block and span as UTF-16 ranges, with the signatures that decide
    /// what needs restyling. The styler's input.
    private(set) lazy var layouts: [DocumentStyler.BlockLayout] =
        DocumentStyler.layouts(for: blocks, in: source)

    /// Each block's range in UTF-16, from one forward pass: a block starts
    /// where the one before it ends. `NSRange(_:in:)` per block would
    /// measure from the start of the note each time.
    private lazy var blockRanges: [NSRange] = {
        var ranges: [NSRange] = []
        ranges.reserveCapacity(blocks.count)
        var offset = 0
        for block in blocks {
            let length = source[block.range].utf16.count
            ranges.append(NSRange(location: offset, length: length))
            offset += length
        }
        return ranges
    }()

    /// The code blocks as UTF-16 ranges, for layout, line numbers and
    /// deciding what shows its fences.
    private(set) lazy var codeRanges: [CodeRange] = {
        var result: [CodeRange] = []
        for (index, block) in blocks.enumerated() {
            guard let code = block.codeBlock else { continue }
            let range = blockRanges[index]
            // A closed block's range ends with the closing fence's newline,
            // if it has one; the caret on that line stops before it.
            let terminator = code.isClosed
                ? source[block.range].last.flatMap { $0.isNewline ? $0.utf16.count : nil } ?? 0
                : 0
            result.append(CodeRange(
                range: range,
                isClosed: code.isClosed,
                lastCaret: range.location + range.length - terminator,
                isOutput: code.isOutput,
                language: code.language,
                tag: code.tag.map(String.init) ?? ""
            ))
        }
        return result
    }()

    /// The code blocks as the action bars, Run and Copy know them.
    private(set) lazy var targets: [CodeBlockTarget] = {
        var result: [CodeBlockTarget] = []
        for (index, block) in blocks.enumerated() {
            guard let code = block.codeBlock else { continue }
            result.append(CodeBlockTarget(
                id: code.id,
                range: blockRanges[index],
                language: code.language,
                code: String(source[code.contentRange]),
                tag: code.tag.map(String.init) ?? ""
            ))
        }
        return result
    }()

    /// The runs `MarkdownLayout` collapses, for the content storage
    /// delegate, which asks once per paragraph.
    private(set) lazy var markerRuns: [MarkdownLayout.Run] =
        MarkdownLayout.runs(for: blocks, in: source)

    /// Where each code block's newlines are, by its index in `codeRanges`,
    /// worked out the first time a line number asks.
    private var newlineCache: [Int: [Int]] = [:]

    /// `blocks` index of each entry of `codeRanges`.
    private lazy var codeBlockSlots: [Int] = blocks.indices.filter { blocks[$0].codeBlock != nil }

    /// The UTF-16 offsets of the newlines in the `index`th code block, in order.
    func newlines(ofCodeBlock index: Int) -> [Int] {
        if let found = newlineCache[index] { return found }
        let slot = codeBlockSlots[index]
        var offset = blockRanges[slot].location
        var result: [Int] = []
        for unit in source[blocks[slot].range].utf16 {
            if unit == UTF16Unit.newline { result.append(offset) }
            offset += 1
        }
        newlineCache[index] = result
        return result
    }
}
