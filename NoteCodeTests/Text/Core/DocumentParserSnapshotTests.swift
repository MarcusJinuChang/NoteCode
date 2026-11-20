//
//  DocumentParserSnapshotTests.swift
//  NoteCodeTests
//
//  2T8: `DocumentParser.parse` is split into a fence scanner and a math
//  scanner. This suite pins what `parse` returns, block by block, for the
//  `-debug-note` fixtures and for a corpus of awkward documents (open and
//  unclosed fences, widths, tagged closers, math in all its shapes, CRLF),
//  taken from the code before the split.
//

#if DEBUG
import Foundation
import Testing
@testable import NoteCode

@Suite("Document parser snapshot", .tags(.pure))
struct DocumentParserSnapshotTests {

    static func render(_ text: String) -> String {
        func at(_ index: String.Index) -> Int { text.utf16.distance(from: text.startIndex, to: index) }
        func span(_ range: Range<String.Index>) -> String { "\(at(range.lowerBound))..<\(at(range.upperBound))" }
        func inlines(_ nodes: [InlineNode]) -> String {
            nodes.map { "\($0.kind) \(span($0.range)) \($0.attributes)" }.joined(separator: "; ")
        }
        return DocumentParser.parse(text).map { block in
            let head = "\(span(block.range)) content \(span(block.contentRange))"
            switch block.kind {
            case .paragraph(let nodes): return "paragraph \(head) [\(inlines(nodes))]"
            case .heading(let level, let nodes): return "heading\(level) \(head) [\(inlines(nodes))]"
            case .listItem(let depth, let marker, let nodes): return "list\(depth) \(marker) \(head) [\(inlines(nodes))]"
            case .blockQuote(let depth, let nodes): return "quote\(depth) \(head) [\(inlines(nodes))]"
            case .rule(let nodes): return "rule \(head) [\(inlines(nodes))]"
            case .code(let code):
                return "code \(head) id \(code.id.ordinal) lang \(String(describing: code.language)) info '\(code.infoString)' closed \(code.isClosed) code \(span(code.contentRange))"
            case .math(let math):
                return "math \(head) open \(span(math.openingRange)) close \(span(math.closingRange)) tex \(span(math.contentRange)) hash \(math.contentHash)"
            }
        }.joined(separator: "\n")
    }

    /// FNV-1a over the UTF-8 of `text`: stable between runs, unlike `hashValue`.
    static func digest(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }

    static func snapshot(of documents: [String]) -> String {
        documents.map { "### \($0.debugDescription)\n\(render($0))" }.joined(separator: "\n")
    }

    static let corpus: [String] = [
        "", "\n", "plain", "a\nb\n", "a\r\nb\r\n",
        "```\ncode\n```", "```\ncode\n```\n", "```swift\nlet x = 1\n```\nafter",
        "```cpp\nint x;", "```", "```\n", "```py", "before\n```py\nprint(1)",
        "````\n```\nnested\n```\n````", "```\n````\ntail", "````\n```\nx\n````\n",
        "```swift\na\n```swift\nb\n```", "```swift\na\n``` \nb\n```", "``` swift extra\nx\n```",
        "```\na\n```\n```\nb\n```", "```c\r\nint x;\r\n```\r\ntext", "text ```not a fence```",
        "# Head\n- item\n1. one\n> quote\n---\nplain **bold**",
        "$$x$$", "$$ x $$", "$$\nx\n$$", "$$\na\nb\n$$\nafter", "$$x$$ and more", "$$", "$$$", "$$ $$", "$$\n\n$$",
        "$$x", "$$x\ny", "$$x\ny$$", "$$x\ny $$  ", "$$x\\$$", "$$x\ny\\$$\nz$$", "$$\n```\nx\n```\n$$",
        "$$\nx\n```\n$$", "```\n$$\nx\n$$\n```", "$$\nx\n$$\n$$\ny\n$$", "$$a$$\n$$b$$", "text\n$$\nx\n$$\ntext",
        "$$ é 日本語 $$", "$$\n😀\n$$", "$$\r\nx\r\n$$\r\n",
        (["$$"] + Array(repeating: "x", count: 48) + ["$$"]).joined(separator: "\n"),
        (["$$"] + Array(repeating: "x", count: 49) + ["$$"]).joined(separator: "\n"),
        (["$$"] + Array(repeating: "x", count: 60) + ["$$"]).joined(separator: "\n"),
        "$$\nx\n$$ \n```\nc\n```\n$$y$$\n",
    ]

    @Test("The corpus parses as it did before the split")
    func corpusSnapshot() {
        let snapshot = Self.snapshot(of: Self.corpus)
        #expect(Self.digest(snapshot) == 6112648562883756245, "digest \(Self.digest(snapshot)) over \(snapshot.count) characters")
    }

    @Test("The pages and code fixtures parse as they did before the split", arguments: [DebugFixture.pages, .code])
    func fixtureSnapshot(_ fixture: DebugFixture) {
        let snapshot = Self.snapshot(of: [fixture.text])
        let expected: [DebugFixture: UInt64] = [.pages: 18318712532066576314, .code: 13829446353940305859]
        #expect(Self.digest(snapshot) == expected[fixture], "\(fixture) digest \(Self.digest(snapshot)) over \(snapshot.count) characters")
    }
}
#endif
