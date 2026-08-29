//
//  DocumentNode.swift
//  NoteCode
//
//  The document model: block-level nodes, each carrying inline spans.
//
//  Replaces the flat two-case region list. That shape could express "this run
//  of text is code and this run isn't" and nothing more — no nesting depth for
//  lists, no spans *inside* a block for bold, nowhere for a node that renders
//  as something other than text. Every node keeps its source range, which is
//  what lets the editor show markdown markers only where the caret is.
//

import Foundation

// MARK: - Language

/// A language a fenced code block can be tagged with.
nonisolated enum CodeLanguage: String, CaseIterable, Sendable {
    case cpp
    case java
    case python

    /// Maps what the user typed after the fence onto a known language.
    /// People write `c++`, `py`, `python3` — all of them should work.
    init?(tag: String) {
        switch tag.lowercased() {
        case "cpp", "c++", "cc", "cxx":  self = .cpp
        case "java":                     self = .java
        case "py", "python", "python3":  self = .python
        default:                         return nil
        }
    }

    /// The name the Piston API expects when Phase 3 sends this block off to run.
    var pistonName: String {
        switch self {
        case .cpp:    "c++"
        case .java:   "java"
        case .python: "python"
        }
    }
}

// MARK: - Code

/// A fenced code block's metadata.
nonisolated struct CodeBlock: Equatable, Sendable {
    /// Survives edits elsewhere in the document — see `CodeBlockID`.
    var id: CodeBlockID
    /// Recognized language, or `nil` if the fence had no tag or an unknown one.
    var language: CodeLanguage?
    /// The raw text after the opening backticks, exactly as typed.
    var infoString: String
    /// `false` while the user is still typing and no closing fence exists yet.
    var isClosed: Bool
    /// Just the code between the fences — excludes both fence lines.
    /// This is what gets sent to Piston; the block's `range` is what gets styled.
    var contentRange: Range<String.Index>
}

// MARK: - Lists

/// What introduces a list item.
nonisolated enum ListMarker: Equatable, Sendable {
    /// `-`, `*` or `+`
    case bullet
    /// `1.` or `1)`, carrying the number the user actually typed.
    case ordered(Int)
}

// MARK: - Inline

/// A span *within* a block.
nonisolated struct InlineNode: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text
        /// `**bold**` or `__bold__`
        case strong
        /// `*italic*` or `_italic_`
        case emphasis
        /// `` `code` ``
        case inlineCode
        // .math arrives with a later step.
    }

    var kind: Kind
    /// The whole span, markers included — what gets dimmed.
    var range: Range<String.Index>
    /// Just the text between the markers — what gets bolded, italicised or
    /// monospaced. Equal to `range` for `.text`.
    ///
    /// Two ranges for the same reason `CodeBlock` has them: the markers are
    /// part of the document and stay visible, but they aren't the content.
    var contentRange: Range<String.Index>

    /// The marker characters, as the ranges either side of the content.
    var markerRanges: [Range<String.Index>] {
        guard kind != .text else { return [] }
        return [range.lowerBound..<contentRange.lowerBound, contentRange.upperBound..<range.upperBound]
            .filter { !$0.isEmpty }
    }
}

// MARK: - Block

/// One block-level element of the document.
///
/// Blocks are returned in document order, never overlap, and together cover the
/// whole string — the same invariant the old region list guaranteed, and one
/// the styling and layout code both rely on.
///
/// Prose is one block per source line. That is deliberate: TextKit 2 lays out a
/// paragraph at a time, and a paragraph is exactly a line-terminated run, so a
/// block maps one-to-one onto an `NSTextElement`. Headings and list items are
/// line-based too, which makes them a natural fit for the same granularity.
/// A code block is the exception — it spans several lines as a single node,
/// which is why `CodeBlockPosition` exists to tell its fragments apart.
nonisolated struct BlockNode: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case paragraph(inlines: [InlineNode])
        /// `# Heading` through `###### Heading`.
        case heading(level: Int, inlines: [InlineNode])
        /// `- item`, `* item`, `+ item`, `1. item`, `1) item`.
        /// `depth` is the nesting level, counted from the line's indentation.
        case listItem(depth: Int, marker: ListMarker, inlines: [InlineNode])
        case code(CodeBlock)
        // .blockQuote and .math arrive with later steps.
    }

    var kind: Kind
    /// The whole block, markers and fence lines included. Line-aligned: a block
    /// starts at the beginning of a line and ends at the start of the next one,
    /// which is what makes drawing a block background straightforward.
    var range: Range<String.Index>
    /// The block minus its block-level marker — a heading's `#`s and the space
    /// after them. Equal to `range` for a paragraph. Inline spans cover exactly
    /// this, not `range`.
    var contentRange: Range<String.Index>

    var isCode: Bool {
        if case .code = kind { return true }
        return false
    }

    var codeBlock: CodeBlock? {
        if case .code(let block) = kind { return block }
        return nil
    }

    var inlines: [InlineNode] {
        switch kind {
        case .paragraph(let inlines):     inlines
        case .heading(_, let inlines):    inlines
        case .listItem(_, _, let inlines): inlines
        case .code:                       []
        }
    }

    var headingLevel: Int? {
        if case .heading(let level, _) = kind { return level }
        return nil
    }

    /// The block-level marker, if any — a heading's `#`s or a list item's
    /// bullet, each including the space after it.
    ///
    /// `nil` for a paragraph, whose content is the whole block. Code blocks
    /// handle their fence lines separately, since they have one at each end.
    var markerRange: Range<String.Index>? {
        guard !isCode, range.lowerBound < contentRange.lowerBound else { return nil }
        return range.lowerBound..<contentRange.lowerBound
    }

    var listDepth: Int? {
        if case .listItem(let depth, _, _) = kind { return depth }
        return nil
    }

    var listMarker: ListMarker? {
        if case .listItem(_, let marker, _) = kind { return marker }
        return nil
    }
}
