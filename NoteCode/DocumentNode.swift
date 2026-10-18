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
    case c
    case javascript
    case rust
    case go
    case sql

    /// Maps what the user typed after the fence onto a known language.
    /// People write `c++`, `py`, `python3`, `js`, `golang` — all of them
    /// should work.
    init?(tag: String) {
        switch tag.lowercased() {
        case "cpp", "c++", "cc", "cxx":  self = .cpp
        case "java":                     self = .java
        case "py", "python", "python3":  self = .python
        case "c":                        self = .c
        case "js", "javascript", "node", "nodejs", "mjs":
                                         self = .javascript
        case "rs", "rust":               self = .rust
        case "go", "golang":             self = .go
        case "sql", "sqlite", "mysql", "postgres", "postgresql", "pgsql":
                                         self = .sql
        default:                         return nil
        }
    }

    /// The language's name as people write it, for menus and note info.
    var displayName: String {
        switch self {
        case .cpp:        "C++"
        case .java:       "Java"
        case .python:     "Python"
        case .c:          "C"
        case .javascript: "JavaScript"
        case .rust:       "Rust"
        case .go:         "Go"
        case .sql:        "SQL"
        }
    }

    /// The language's canonical lowercase name, as online compilers spell it.
    ///
    /// Named after the Piston API originally, which the cut run phase was going
    /// to post to. The strings outlived it: `CodeDestination` hands exactly
    /// these to Compiler Explorer, whose own language ids they are.
    var canonicalName: String {
        switch self {
        case .cpp:        "c++"
        case .java:       "java"
        case .python:     "python"
        case .c:          "c"
        case .javascript: "javascript"
        case .rust:       "rust"
        case .go:         "go"
        case .sql:        "sql"
        }
    }

    /// The name highlight.js knows the language by. Used instead of whatever
    /// was typed after the fence, so `golang`, `js` and `postgres` colour as
    /// the language they mean without depending on highlight.js's aliases.
    var highlightName: String {
        switch self {
        case .cpp:        "cpp"
        case .java:       "java"
        case .python:     "python"
        case .c:          "c"
        case .javascript: "javascript"
        case .rust:       "rust"
        case .go:         "go"
        case .sql:        "sql"
        }
    }

    /// Whether a block in this language gets a Run button.
    ///
    /// SQL has nowhere free to run: the sites that take it keep their editor
    /// in the browser and run it against a database of their own, so a run
    /// would only open a page with a different schema. Copy is all it keeps.
    var canRun: Bool {
        self != .sql
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
    /// This is what gets copied or sent to a compiler; the block's `range` is
    /// what gets styled.
    var contentRange: Range<String.Index>

    /// Whether this is an output block: what a program printed, kept beside
    /// the code that printed it. Not a language, so it has no `language`.
    var isOutput: Bool {
        CodeBlockKind.isOutputTag(infoString.split(separator: " ").first)
    }

    /// Whether the fence names anything at all, known or not. A bare fence is
    /// plain text, and nothing is ever coloured in one.
    var hasLanguageTag: Bool {
        infoString.split(separator: " ").first != nil
    }
}

/// What a code block can be turned into, from the Code Block ▾ menu and a
/// block's language button.
///
/// A language is one kind of block. Output is another: a console panel with
/// Copy and no Run, tagged ```` ```output ````. Plain text is a fence with no
/// tag. Tags the app doesn't know are none of these; they stay as typed.
nonisolated enum CodeBlockKind: Equatable, Hashable, Sendable {
    case language(CodeLanguage)
    case output
    case plain

    /// The fence tag for a new block of this kind, `nil` for none.
    var tag: String? {
        switch self {
        case .language(let language): language.rawValue
        case .output:                 Self.outputTag
        case .plain:                  nil
        }
    }

    var displayName: String {
        switch self {
        case .language(let language): language.displayName
        case .output:                 "Output"
        case .plain:                  "Plain Text"
        }
    }

    static let outputTag = "output"

    /// Every choice, in the order a menu lists them: the languages, then
    /// Output, then Plain Text. The hotbar's Code Block ▾ and a block's
    /// language button both read this, so they can't disagree.
    static let menu: [CodeBlockKind] = languages + others

    /// The menu's first group, and its second after a divider.
    static let languages: [CodeBlockKind] = CodeLanguage.allCases.map(CodeBlockKind.language)
    static let others: [CodeBlockKind] = [.output, .plain]

    /// What the menu says under the name, where a choice needs it: SQL has
    /// nowhere free to run, so a block in it keeps only Copy.
    var subtitle: String? {
        if case .language(let language) = self, !language.canRun { return "Copy only" }
        return nil
    }

    /// Whether the first word of an info string names an output block.
    static func isOutputTag(_ word: Substring?) -> Bool {
        word?.lowercased() == outputTag
    }
}

// MARK: - Lists

/// What introduces a list item.
nonisolated enum ListMarker: Equatable, Sendable {
    /// `-`, `*` or `+`
    case bullet
    /// `1.` or `1)`, carrying the number the user actually typed.
    case ordered(Int)
    /// `- [ ]` or `- [x]`: a bullet with a box. The marker range covers the
    /// bullet, the box and the space after it.
    case checkbox(checked: Bool)
}

// MARK: - Inline

/// What a pair of markers does to the text between them.
nonisolated enum InlineMarkup: Hashable, Sendable {
    /// `**bold**` or `__bold__`
    case strong
    /// `*italic*` or `_italic_`
    case emphasis
    /// `` `code` ``
    case inlineCode
    /// `~~struck~~`
    case strikethrough
    /// `[text](url)`, whose markers are `[` and `](url)`; or a bare
    /// `http(s)://` address, which has none (`InlineSpan`).
    case link
    /// `<span style="…">` and `</span>`, a styled run (`SpanStyle`): a
    /// colour, a size or both.
    case styled(SpanStyle)

    var isStyled: Bool {
        if case .styled = self { return true }
        return false
    }
}

/// How a stretch of a line is drawn: what every pair of markers around it
/// says, so `***x***` is bold and italic and bold inside a run is coloured.
nonisolated struct InlineAttributes: Hashable, Sendable {
    var bold = false
    var italic = false
    var strikethrough = false
    var code = false
    var link = false
    /// The innermost run's colour (`TextColour`), or `nil` for none.
    var colour: Int?
    /// The size against the block's text, or `nil` for its own. A run
    /// inside a sized run multiplies, as em does in Obsidian's HTML.
    var size: SpanSize?

    static let plain = InlineAttributes()

    /// What text inside one more pair has.
    func inside(_ markup: InlineMarkup) -> InlineAttributes {
        var inner = self
        switch markup {
        case .strong:        inner.bold = true
        case .emphasis:      inner.italic = true
        case .inlineCode:    inner.code = true
        case .strikethrough: inner.strikethrough = true
        case .link:          inner.link = true
        case .styled(let style):
            if let colour = style.colour { inner.colour = colour }
            if let runSize = style.size {
                inner.size = if let outer = size { SpanSize(em: outer.em * runSize.em) } else { runSize }
            }
        }
        return inner
    }

    /// Cheap and exact, for the block signature: two different sets of
    /// attributes never give the same number.
    var signature: Int {
        let flags = (bold ? 1 : 0) | (italic ? 2 : 0) | (strikethrough ? 4 : 0) | (code ? 8 : 0) | (link ? 16 : 0)
        let colourBits = colour.map { ($0 & 0xFFFFFF) + 1 } ?? 0
        let sizeBits = size.map { $0.thousandths + 1 } ?? 0
        return flags | colourBits << 5 | sizeBits << 30
    }
}

/// A piece of a line: some text, or a marker that opens or closes a pair.
///
/// A line's nodes are flat and contiguous, and cover its content exactly,
/// so a caller can walk them without checking for holes. Pairs nest, and
/// what a stretch of text is drawn with is on its node (`attributes`), so
/// nothing has to work out what it is inside. `InlineSpan` reads the pairs
/// back out, for the editing rules that act on a whole span.
nonisolated struct InlineNode: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text
        /// The markers that open a pair: `**`, `[`, `<span style="…">`.
        case opening(InlineMarkup)
        /// The markers that close one: `**`, `](url)`, `</span>`.
        case closing(InlineMarkup)

        var isMarker: Bool { self != .text }

        var markup: InlineMarkup? {
            switch self {
            case .text:                 nil
            case .opening(let markup):  markup
            case .closing(let markup):  markup
            }
        }

        /// A run's tag, which marks where a style starts or stops and holds
        /// no text of its own.
        var isSpanTag: Bool { markup?.isStyled ?? false }

        /// For the block signature. The style is in it: a recolour keeps
        /// every length the same, and the styler must still notice.
        var discriminant: Int {
            let side = switch self {
            case .text:    0
            case .opening: 1
            case .closing: 2
            }
            let markupBits: Int = switch markup {
            case nil:                 0
            case .strong?:            1
            case .emphasis?:          2
            case .inlineCode?:        3
            case .strikethrough?:     4
            case .link?:              5
            case .styled(let style)?: 6 &+ (style.colour ?? 0x1000000) &* 8 &+ (style.size.map { $0.thousandths + 1 } ?? 0) &* 0x8000_0000
            }
            return side &+ markupBits &* 4
        }
    }

    var kind: Kind
    /// The node's characters: text, or markers alone.
    var range: Range<String.Index>
    /// For text, how it is drawn. For a marker, how the text around its
    /// pair is drawn, which is the font a hidden marker keeps.
    var attributes: InlineAttributes
    /// Where a link goes: the address inside `(…)`, on a link's text and
    /// both its markers, or a bare address itself. `nil` elsewhere.
    var destination: Range<String.Index>? = nil
}

/// A pair of markers and the text between them, or a bare address: a line
/// read as spans, for the rules that act on one whole (Backspace, the
/// caret's formatting, links, colour and size).
nonisolated struct InlineSpan: Equatable, Sendable {
    var markup: InlineMarkup
    /// The whole span, markers included.
    var range: Range<String.Index>
    /// Between the markers; the whole span for a bare address.
    var contentRange: Range<String.Index>
    /// Where a link goes; `nil` for everything else.
    var destination: Range<String.Index>? = nil

    /// The marker characters, as the ranges either side of the content.
    var markerRanges: [Range<String.Index>] {
        [range.lowerBound..<contentRange.lowerBound, contentRange.upperBound..<range.upperBound].filter { !$0.isEmpty }
    }

    /// Every pair among `nodes` and every bare address, in the order they
    /// start, so a pair comes before the pairs inside it.
    static func spans(in nodes: [InlineNode]) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        var open: [(index: Int, markers: Range<String.Index>)] = []
        for node in nodes {
            switch node.kind {
            case .text:
                if let destination = node.destination, destination == node.range {
                    spans.append(InlineSpan(markup: .link, range: node.range, contentRange: node.range, destination: destination))
                }
            case .opening(let markup):
                open.append((spans.count, node.range))
                spans.append(InlineSpan(markup: markup, range: node.range, contentRange: node.range, destination: node.destination))
            case .closing:
                // The parser only makes pairs that nest, so the innermost
                // open one is this one's.
                guard let start = open.popLast() else { continue }
                spans[start.index].range = start.markers.lowerBound..<node.range.upperBound
                spans[start.index].contentRange = start.markers.upperBound..<node.range.lowerBound
            }
        }
        return spans
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

    /// Cheap identity of the case, for change detection.
    var kindDiscriminant: Int {
        switch kind {
        case .paragraph: 0
        case .heading:   1
        case .listItem:  2
        case .code:      3
        }
    }

    /// The part of a block's identity that changes how it is drawn, beyond its
    /// kind and length: heading level, list depth, or the code's content hash.
    var styleDetail: Int {
        switch kind {
        case .paragraph:                 0
        case .heading(let level, _):     level
        case .listItem(let depth, _, _): depth
        // Output is part of it: python -> output is the same length, and the
        // styler must still notice, since the text colour changes.
        case .code(let code):
            code.isOutput ? ~Int(truncatingIfNeeded: code.id.contentHash) : Int(truncatingIfNeeded: code.id.contentHash)
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
