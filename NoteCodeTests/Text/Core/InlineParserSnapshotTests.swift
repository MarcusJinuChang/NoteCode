//
//  InlineParserSnapshotTests.swift
//  NoteCodeTests
//
//  2T8: `InlineParser.collect` is split into one tokenizer per case and a
//  delimiter resolver. This suite pins what `parse` returns, node by node,
//  for the `-debug-note` fixtures and for a corpus of the awkward lines
//  (nesting, crossing pairs, rule of three, tags, links, math, escapes),
//  taken from the code before the split.
//

#if DEBUG
import Foundation
import Testing
@testable import NoteCode

@Suite("Inline parser snapshot", .tags(.pure))
struct InlineParserSnapshotTests {

    /// One line per node: kind, UTF-16 range, attributes, destination.
    static func render(_ line: String) -> String {
        let nodes = InlineParser.parse(line, in: line.startIndex..<line.endIndex)
        func offset(_ index: String.Index) -> Int { line.utf16.distance(from: line.startIndex, to: index) }
        return nodes.map { node in
            let destination = node.destination.map { " ->\(offset($0.lowerBound))..<\(offset($0.upperBound))" } ?? ""
            return "\(node.kind) \(offset(node.range.lowerBound))..<\(offset(node.range.upperBound)) \(node.attributes)\(destination)"
        }.joined(separator: "\n")
    }

    /// FNV-1a over the UTF-8 of `text`: stable between runs, unlike `hashValue`.
    static func digest(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }

    static func snapshot(of lines: [String]) -> String {
        lines.map { "### \($0)\n\(render($0))" }.joined(separator: "\n")
    }

    static let corpus: [String] = [
        "plain text", "**bold**", "__bold__", "*italic*", "_italic_", "~~struck~~", "~5ms and ~/Developer",
        "***x***", "**a *b* c**", "*a **b** c*", "*foo**bar**baz*", "**a *b** c*", "*a **b* c**",
        "2 * 3 * 4", "snake_case_name", "_a_b_", "a _b_ c", "__init__ and *x*", "** not bold **", "* *", "a*b*c",
        "`code`", "`a *b* c`", "``x``", "`", "`unclosed *bold*", "**`code` inside**", "*a `b*` c*",
        "[link](https://example.com)", "[**bold** link](https://a.b/c)", "[a *b](u) c*", "[x](y) and [z](w)",
        "[nested [brackets]](u)", "[no destination]", "[empty]()", "see https://example.com/a?b=c now",
        "(https://example.com)", "**https://example.com/x**", "[https://a.b](https://c.d)", "http://x.y/z.",
        "==🟡hi==", "==🔴a **b** c==", "==🟢a== and ==🔵b==", "a == b", "====", "====🔴", "===", "==🟡==", "==🟡**x==**",
        "<u>under</u>", "<u>a *b* c</u>", "<u>unclosed", "</u> stray", "<u>a</span>",
        "<span style=\"color: red\">red</span>", "<span style=\"color: red; font-size: 1.5em\">big **red**</span>",
        "<span style=\"color: red\">a *b</span> c*", "<span style=\"color: red\"></span>",
        "<span style=\"color: red\"><u>x</u></span>", "<span style=\"color: red\"><u>x</span></u>",
        "<span style=\"font-size: 2em\"><span style=\"font-size: 2em\">x</span></span>", "<b>not a tag</b>",
        "$x$", "$$x$$", "$a*b*c$", "a $ b $ c", "$unclosed", "\\$5 and \\$6", "\\$x\\$", "cost \\$5 *emph*",
        "[$x$](u)", "$a$ and `b` and **c**", "~~**a**~~", "**~~a~~**", "~~a *b* c~~", "~~~a~~~", "~~a~~b~~",
        "**a** and **b**", "*a* *b* *c*", "***a** b*", "***a* b**", "_a **b** c_", "**a _b_ c**",
        "emoji 😀 **bold 😀** after", "é *é* é", "日本語 **太字** 日本語",
        " ", "*", "**", "***", "_", "__", "~~", "~", "[", "]", "()", "\\", "<", "=", "`**`",
    ]

    @Test("The corpus parses as it did before the split")
    func corpusSnapshot() {
        let snapshot = Self.snapshot(of: Self.corpus)
        #expect(Self.digest(snapshot) == 16385165296402238719, "digest \(Self.digest(snapshot)) over \(snapshot.count) characters")
    }

    @Test("The pages and code fixtures parse as they did before the split", arguments: [DebugFixture.pages, .code])
    func fixtureSnapshot(_ fixture: DebugFixture) {
        let lines = fixture.text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let snapshot = Self.snapshot(of: lines)
        let expected: [DebugFixture: UInt64] = [.pages: 712555648150131963, .code: 2016263849149010324]
        #expect(Self.digest(snapshot) == expected[fixture], "\(fixture) digest \(Self.digest(snapshot)) over \(lines.count) lines")
    }
}
#endif
