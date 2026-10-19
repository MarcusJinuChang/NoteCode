//
//  NestingInlineTests.swift
//  NoteCodeTests
//
//  The nesting inline parser (text overhaul, phase 2): CommonMark's delimiter
//  stack over today's flanking rules, styled runs on the same stack, and the
//  editing rules that read the nodes it makes.
//

import Foundation
import Testing
@testable import NoteCode

/// One of the CommonMark spec's examples (0.31.2, "Emphasis and strong
/// emphasis"), its Markdown and the HTML inside its paragraph.
struct SpecExample: Sendable, CustomTestStringConvertible {
    let number: Int
    let markdown: String
    let html: String

    init(_ number: Int, _ markdown: String, _ html: String) {
        self.number = number
        self.markdown = markdown
        self.html = html
    }

    var testDescription: String { "example \(number): \(markdown)" }
}

/// A line's nodes written out as the spec writes its examples.
func inlineHTML(_ line: String) -> String {
    func escaped(_ text: Substring) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    func tag(_ markup: InlineMarkup) -> String {
        switch markup {
        case .strong:        "strong"
        case .emphasis:      "em"
        case .inlineCode:    "code"
        case .strikethrough: "del"
        case .link:          "a"
        case .styled:        "span"
        }
    }

    var html = ""
    for node in InlineParser.parse(line, in: line.startIndex..<line.endIndex) {
        switch node.kind {
        case .text where node.destination == node.range:
            html += "<a href=\"\(escaped(line[node.range]))\">\(escaped(line[node.range]))</a>"
        case .text:
            html += escaped(line[node.range])
        case .opening(.link):
            html += "<a href=\"\(node.destination.map { escaped(line[$0]) } ?? "")\">"
        case .opening(.styled):
            html += String(line[node.range])
        case .opening(let markup):
            html += "<\(tag(markup))>"
        case .closing(let markup):
            html += "</\(tag(markup))>"
        }
    }
    return html
}

@Suite("Inline parser: nesting")
struct NestingInlineTests {

    static let red = TextColour.red.hex
    static let redTag = SpanStyle(colour: red).openTag
    static let close = SpanStyle.close

    /// The text node holding the first `word` in `line`, and what it is
    /// drawn with.
    static func attributes(of word: String, in line: String) -> InlineAttributes? {
        guard let found = line.range(of: word) else { return nil }
        return InlineParser.parse(line, in: line.startIndex..<line.endIndex)
            .first { $0.kind == .text && $0.range.contains(found.lowerBound) }?
            .attributes
    }

    /// The text that is drawn: every node but the markers.
    static func drawn(_ line: String) -> String {
        InlineParser.parse(line, in: line.startIndex..<line.endIndex)
            .filter { !$0.kind.isMarker }
            .map { String(line[$0.range]) }
            .joined()
    }

    // MARK: The spec

    /// The examples whose every star and underscore can open and close the
    /// same under today's rules as under CommonMark's flanking, on one line,
    /// with no escapes, HTML or entities: 105 of the section's 132, and
    /// 419, 433 and 473, where a link's text is read on its own and the two
    /// agree again. Those left out turn on punctuation (`a*"foo"*`), which
    /// today's rule doesn't look at, or on a paragraph of several lines.
    static let examples: [SpecExample] = [
        SpecExample(350, #"*foo bar*"#, #"<em>foo bar</em>"#),
        SpecExample(351, #"a * foo bar*"#, #"a * foo bar*"#),
        SpecExample(353, #"* a *"#, #"* a *"#),
        SpecExample(355, #"foo*bar*"#, #"foo<em>bar</em>"#),
        SpecExample(356, #"5*6*78"#, #"5<em>6</em>78"#),
        SpecExample(357, #"_foo bar_"#, #"<em>foo bar</em>"#),
        SpecExample(358, #"_ foo bar_"#, #"_ foo bar_"#),
        SpecExample(359, #"a_"foo"_"#, #"a_&quot;foo&quot;_"#),
        SpecExample(360, #"foo_bar_"#, #"foo_bar_"#),
        SpecExample(361, #"5_6_78"#, #"5_6_78"#),
        SpecExample(362, #"пристаням_стремятся_"#, #"пристаням_стремятся_"#),
        SpecExample(363, #"aa_"bb"_cc"#, #"aa_&quot;bb&quot;_cc"#),
        SpecExample(364, #"foo-_(bar)_"#, #"foo-<em>(bar)</em>"#),
        SpecExample(365, #"_foo*"#, #"_foo*"#),
        SpecExample(366, #"*foo bar *"#, #"*foo bar *"#),
        SpecExample(370, #"*foo*bar"#, #"<em>foo</em>bar"#),
        SpecExample(371, #"_foo bar _"#, #"_foo bar _"#),
        SpecExample(372, #"_(_foo)"#, #"_(_foo)"#),
        SpecExample(373, #"_(_foo_)_"#, #"<em>(<em>foo</em>)</em>"#),
        SpecExample(374, #"_foo_bar"#, #"_foo_bar"#),
        SpecExample(375, #"_пристаням_стремятся"#, #"_пристаням_стремятся"#),
        SpecExample(376, #"_foo_bar_baz_"#, #"<em>foo_bar_baz</em>"#),
        SpecExample(377, #"_(bar)_."#, #"<em>(bar)</em>."#),
        SpecExample(378, #"**foo bar**"#, #"<strong>foo bar</strong>"#),
        SpecExample(379, #"** foo bar**"#, #"** foo bar**"#),
        SpecExample(381, #"foo**bar**"#, #"foo<strong>bar</strong>"#),
        SpecExample(382, #"__foo bar__"#, #"<strong>foo bar</strong>"#),
        SpecExample(383, #"__ foo bar__"#, #"__ foo bar__"#),
        SpecExample(385, #"a__"foo"__"#, #"a__&quot;foo&quot;__"#),
        SpecExample(386, #"foo__bar__"#, #"foo__bar__"#),
        SpecExample(387, #"5__6__78"#, #"5__6__78"#),
        SpecExample(388, #"пристаням__стремятся__"#, #"пристаням__стремятся__"#),
        SpecExample(389, #"__foo, __bar__, baz__"#, #"<strong>foo, <strong>bar</strong>, baz</strong>"#),
        SpecExample(390, #"foo-__(bar)__"#, #"foo-<strong>(bar)</strong>"#),
        SpecExample(391, #"**foo bar **"#, #"**foo bar **"#),
        SpecExample(396, #"**foo**bar"#, #"<strong>foo</strong>bar"#),
        SpecExample(397, #"__foo bar __"#, #"__foo bar __"#),
        SpecExample(398, #"__(__foo)"#, #"__(__foo)"#),
        SpecExample(399, #"_(__foo__)_"#, #"<em>(<strong>foo</strong>)</em>"#),
        SpecExample(400, #"__foo__bar"#, #"__foo__bar"#),
        SpecExample(401, #"__пристаням__стремятся"#, #"__пристаням__стремятся"#),
        SpecExample(402, #"__foo__bar__baz__"#, #"<strong>foo__bar__baz</strong>"#),
        SpecExample(403, #"__(bar)__."#, #"<strong>(bar)</strong>."#),
        SpecExample(404, #"*foo [bar](/url)*"#, #"<em>foo <a href="/url">bar</a></em>"#),
        SpecExample(406, #"_foo __bar__ baz_"#, #"<em>foo <strong>bar</strong> baz</em>"#),
        SpecExample(407, #"_foo _bar_ baz_"#, #"<em>foo <em>bar</em> baz</em>"#),
        SpecExample(408, #"__foo_ bar_"#, #"<em><em>foo</em> bar</em>"#),
        SpecExample(409, #"*foo *bar**"#, #"<em>foo <em>bar</em></em>"#),
        SpecExample(410, #"*foo **bar** baz*"#, #"<em>foo <strong>bar</strong> baz</em>"#),
        SpecExample(411, #"*foo**bar**baz*"#, #"<em>foo<strong>bar</strong>baz</em>"#),
        SpecExample(412, #"*foo**bar*"#, #"<em>foo**bar</em>"#),
        SpecExample(413, #"***foo** bar*"#, #"<em><strong>foo</strong> bar</em>"#),
        SpecExample(414, #"*foo **bar***"#, #"<em>foo <strong>bar</strong></em>"#),
        SpecExample(415, #"*foo**bar***"#, #"<em>foo<strong>bar</strong></em>"#),
        SpecExample(416, #"foo***bar***baz"#, #"foo<em><strong>bar</strong></em>baz"#),
        SpecExample(417, #"foo******bar*********baz"#, #"foo<strong><strong><strong>bar</strong></strong></strong>***baz"#),
        SpecExample(418, #"*foo **bar *baz* bim** bop*"#, #"<em>foo <strong>bar <em>baz</em> bim</strong> bop</em>"#),
        SpecExample(419, #"*foo [*bar*](/url)*"#, #"<em>foo <a href="/url"><em>bar</em></a></em>"#),
        SpecExample(420, #"** is not an empty emphasis"#, #"** is not an empty emphasis"#),
        SpecExample(421, #"**** is not an empty strong emphasis"#, #"**** is not an empty strong emphasis"#),
        SpecExample(422, #"**foo [bar](/url)**"#, #"<strong>foo <a href="/url">bar</a></strong>"#),
        SpecExample(424, #"__foo _bar_ baz__"#, #"<strong>foo <em>bar</em> baz</strong>"#),
        SpecExample(425, #"__foo __bar__ baz__"#, #"<strong>foo <strong>bar</strong> baz</strong>"#),
        SpecExample(426, #"____foo__ bar__"#, #"<strong><strong>foo</strong> bar</strong>"#),
        SpecExample(427, #"**foo **bar****"#, #"<strong>foo <strong>bar</strong></strong>"#),
        SpecExample(428, #"**foo *bar* baz**"#, #"<strong>foo <em>bar</em> baz</strong>"#),
        SpecExample(429, #"**foo*bar*baz**"#, #"<strong>foo<em>bar</em>baz</strong>"#),
        SpecExample(430, #"***foo* bar**"#, #"<strong><em>foo</em> bar</strong>"#),
        SpecExample(431, #"**foo *bar***"#, #"<strong>foo <em>bar</em></strong>"#),
        SpecExample(433, #"**foo [*bar*](/url)**"#, #"<strong>foo <a href="/url"><em>bar</em></a></strong>"#),
        SpecExample(434, #"__ is not an empty emphasis"#, #"__ is not an empty emphasis"#),
        SpecExample(435, #"____ is not an empty strong emphasis"#, #"____ is not an empty strong emphasis"#),
        SpecExample(436, #"foo ***"#, #"foo ***"#),
        SpecExample(438, #"foo *_*"#, #"foo <em>_</em>"#),
        SpecExample(439, #"foo *****"#, #"foo *****"#),
        SpecExample(441, #"foo **_**"#, #"foo <strong>_</strong>"#),
        SpecExample(442, #"**foo*"#, #"*<em>foo</em>"#),
        SpecExample(443, #"*foo**"#, #"<em>foo</em>*"#),
        SpecExample(444, #"***foo**"#, #"*<strong>foo</strong>"#),
        SpecExample(445, #"****foo*"#, #"***<em>foo</em>"#),
        SpecExample(446, #"**foo***"#, #"<strong>foo</strong>*"#),
        SpecExample(447, #"*foo****"#, #"<em>foo</em>***"#),
        SpecExample(448, #"foo ___"#, #"foo ___"#),
        SpecExample(450, #"foo _*_"#, #"foo <em>*</em>"#),
        SpecExample(451, #"foo _____"#, #"foo _____"#),
        SpecExample(453, #"foo __*__"#, #"foo <strong>*</strong>"#),
        SpecExample(454, #"__foo_"#, #"_<em>foo</em>"#),
        SpecExample(455, #"_foo__"#, #"<em>foo</em>_"#),
        SpecExample(456, #"___foo__"#, #"_<strong>foo</strong>"#),
        SpecExample(457, #"____foo_"#, #"___<em>foo</em>"#),
        SpecExample(458, #"__foo___"#, #"<strong>foo</strong>_"#),
        SpecExample(459, #"_foo____"#, #"<em>foo</em>___"#),
        SpecExample(460, #"**foo**"#, #"<strong>foo</strong>"#),
        SpecExample(461, #"*_foo_*"#, #"<em><em>foo</em></em>"#),
        SpecExample(462, #"__foo__"#, #"<strong>foo</strong>"#),
        SpecExample(464, #"****foo****"#, #"<strong><strong>foo</strong></strong>"#),
        SpecExample(465, #"____foo____"#, #"<strong><strong>foo</strong></strong>"#),
        SpecExample(466, #"******foo******"#, #"<strong><strong><strong>foo</strong></strong></strong>"#),
        SpecExample(467, #"***foo***"#, #"<em><strong>foo</strong></em>"#),
        SpecExample(468, #"_____foo_____"#, #"<em><strong><strong>foo</strong></strong></em>"#),
        SpecExample(469, #"*foo _bar* baz_"#, #"<em>foo _bar</em> baz_"#),
        SpecExample(470, #"*foo __bar *baz bim__ bam*"#, #"<em>foo <strong>bar *baz bim</strong> bam</em>"#),
        SpecExample(471, #"**foo **bar baz**"#, #"**foo <strong>bar baz</strong>"#),
        SpecExample(472, #"*foo *bar baz*"#, #"*foo <em>bar baz</em>"#),
        SpecExample(473, #"*[bar*](/url)"#, #"*<a href="/url">bar*</a>"#),
        SpecExample(474, #"_foo [bar_](/url)"#, #"_foo <a href="/url">bar_</a>"#),
        SpecExample(478, #"*a `*`*"#, #"<em>a <code>*</code></em>"#),
        SpecExample(479, #"_a `_`_"#, #"<em>a <code>_</code></em>"#),
    ]

    @Test("The CommonMark spec's emphasis examples inside the subset", arguments: examples)
    func spec(_ example: SpecExample) {
        #expect(inlineHTML(example.markdown) == example.html)
    }

    // MARK: Nesting

    @Test("What didn't nest before now does, with its markers hidden", arguments: [
        ("***x***", "<em><strong>x</strong></em>", "x"),
        ("**a *b* c**", "<strong>a <em>b</em> c</strong>", "a b c"),
        ("**\(redTag)x\(close)**", "<strong>\(redTag)x</span></strong>", "x"),
        ("\(redTag)**x**\(close)", "\(redTag)<strong>x</strong></span>", "x"),
    ])
    func nests(line: String, html: String, drawn: String) {
        #expect(inlineHTML(line) == html)
        #expect(Self.drawn(line) == drawn)
    }

    @Test("Text carries what every pair around it says")
    func attributesAccumulate() throws {
        let both = try #require(Self.attributes(of: "x", in: "***x***"))
        #expect(both.bold && both.italic && !both.code)

        let outer = try #require(Self.attributes(of: "a", in: "**a *b* c**"))
        let inner = try #require(Self.attributes(of: "b", in: "**a *b* c**"))
        #expect(outer.bold && !outer.italic)
        #expect(inner.bold && inner.italic)

        let colouredBold = try #require(Self.attributes(of: "x", in: "**\(Self.redTag)x\(Self.close)**"))
        #expect(colouredBold.bold && colouredBold.colour == Self.red)
        let boldColoured = try #require(Self.attributes(of: "x", in: "\(Self.redTag)**x**\(Self.close)"))
        #expect(boldColoured == colouredBold)

        let code = try #require(Self.attributes(of: "x", in: "**`x`**"))
        #expect(code.code && code.bold)
        let struck = try #require(Self.attributes(of: "b", in: "~~a **b**~~"))
        #expect(struck.strikethrough && struck.bold)
    }

    @Test("A run inside a run: the inner colour, the sizes multiplied")
    func runsNest() throws {
        let big = SpanStyle(size: SpanSize(em: 2)).openTag
        let bigger = SpanStyle(size: SpanSize(em: 1.5)).openTag
        let line = "\(Self.redTag)\(big)x\(Self.close) q\(Self.close)"
        let x = try #require(Self.attributes(of: "x", in: line))
        let q = try #require(Self.attributes(of: "q", in: line))
        #expect(x.colour == Self.red && x.size == SpanSize(em: 2))
        #expect(q.colour == Self.red && q.size == nil)

        let product = try #require(Self.attributes(of: "x", in: "\(big)\(bigger)x\(Self.close)\(Self.close)"))
        #expect(product.size == SpanSize(em: 3))

        let blue = SpanStyle(colour: TextColour.blue.hex).openTag
        let recoloured = try #require(Self.attributes(of: "x", in: "\(Self.redTag)a \(blue)x\(Self.close)\(Self.close)"))
        #expect(recoloured.colour == TextColour.blue.hex)
    }

    @Test("A link's text is read, on its own")
    func linkText() throws {
        #expect(inlineHTML("[**a**](https://e.com)") == #"<a href="https://e.com"><strong>a</strong></a>"#)
        #expect(inlineHTML("**[a](https://e.com)**") == #"<strong><a href="https://e.com">a</a></strong>"#)
        #expect(inlineHTML("[a `b` c](u)") == #"<a href="u">a <code>b</code> c</a>"#)
        let bold = try #require(Self.attributes(of: "a", in: "[**a**](https://e.com)"))
        #expect(bold.bold && bold.link)
        // Nothing in it pairs with anything outside.
        #expect(inlineHTML("**a [b** c](u)") == #"**a <a href="u">b** c</a>"#)
    }

    // MARK: Crossing

    @Test("Pairs that would cross: the first to close wins, the other is text")
    func crossing() {
        #expect(inlineHTML("**a _b** c_") == "<strong>a _b</strong> c_")
        #expect(inlineHTML("~~a *b~~ c*") == "<del>a *b</del> c*")
        // Stars pair with stars of any run, nearest first, as in the spec's
        // example 409: the `**` before b gives one to each closer after it.
        #expect(inlineHTML("*a **b* c**") == "<em>a <em><em>b</em> c</em></em>")
    }

    @Test("Across a run's edge the run wins, so a tag never shows: only the emphasis's markers do")
    func crossingARun() {
        #expect(inlineHTML("**a \(Self.redTag)b** c\(Self.close)") == "**a \(Self.redTag)b** c</span>")
        #expect(inlineHTML("\(Self.redTag)a *b\(Self.close) c*") == "\(Self.redTag)a *b</span> c*")
        #expect(inlineHTML("*a \(Self.redTag)b* c") == "<em>a &lt;span style=&quot;color:#E5484D&quot;&gt;b</em> c")
    }

    @Test("A run with nothing in it, or nothing to close it, is text", arguments: [
        "\(redTag)\(close)",
        "\(redTag)a",
        "a\(close)",
        "\(redTag)\(close)x\(close)",
    ])
    func emptyRuns(line: String) {
        #expect(!InlineParser.parse(line, in: line.startIndex..<line.endIndex).contains { $0.kind.isSpanTag })
    }

    @Test("Inside code nothing is read, a run's tags included")
    func codeIsCode() {
        #expect(inlineHTML("`\(Self.redTag)x\(Self.close)`") == "<code>&lt;span style=&quot;color:#E5484D&quot;&gt;x&lt;/span&gt;</code>")
        #expect(inlineHTML("**a `*b*` c**") == "<strong>a <code>*b*</code> c</strong>")
    }

    // MARK: Addresses

    @Test("A bare address ends before the markers or tag around it", arguments: [
        ("**https://example.com**", #"<strong><a href="https://example.com">https://example.com</a></strong>"#),
        ("_https://example.com/ab_", #"<em><a href="https://example.com/ab">https://example.com/ab</a></em>"#),
        ("\(redTag)https://example.com\(close)", #"<span style="color:#E5484D"><a href="https://example.com">https://example.com</a></span>"#),
        ("see https://example.com.", #"see <a href="https://example.com">https://example.com</a>."#),
    ])
    func addressEnds(line: String, html: String) {
        #expect(inlineHTML(line) == html)
    }

    @Test("An address that holds the character keeps it at its end")
    func addressKeepsItsOwnStars() {
        #expect(inlineHTML("https://example.com/*b*") == #"<a href="https://example.com/*b*">https://example.com/*b*</a>"#)
        #expect(inlineHTML("https://example.com/~me~") == #"<a href="https://example.com/~me~">https://example.com/~me~</a>"#)
        #expect(inlineHTML("_https://example.com/a_b_") == #"_<a href="https://example.com/a_b_">https://example.com/a_b_</a>"#)
    }

    // MARK: Invariants

    /// SplitMix64: the same lines on every run.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test("Any line gives contiguous nodes, pairs that nest, and text drawn as its pairs say")
    func randomLines() {
        let pieces = ["a", "b", " ", "*", "**", "_", "__", "~~", "~", "`", "[", "](u)", "(", ")", "é", "👩‍💻",
                      "https://x.io", Self.redTag, SpanStyle(size: SpanSize(em: 1.5)).openTag, Self.close, "\n"]
        var random = Seeded(state: 18_10_2026)
        for _ in 0..<4000 {
            let line = (0..<Int.random(in: 1...14, using: &random)).map { _ in pieces.randomElement(using: &random)! }.joined()
            let nodes = InlineParser.parse(line, in: line.startIndex..<line.endIndex)

            #expect(nodes.first?.range.lowerBound == line.startIndex, "\(line)")
            #expect(nodes.last?.range.upperBound == line.endIndex, "\(line)")
            for (current, next) in zip(nodes, nodes.dropFirst()) {
                #expect(current.range.upperBound == next.range.lowerBound, "\(line)")
            }
            #expect(nodes.allSatisfy { !$0.range.isEmpty }, "\(line)")

            // Every closing marker closes the innermost open pair, and text
            // has exactly what the pairs around it say.
            var open: [InlineMarkup] = []
            var attributes = InlineAttributes.plain
            var outside: [InlineAttributes] = []
            for node in nodes {
                switch node.kind {
                case .opening(let markup):
                    #expect(node.attributes == attributes, "\(line)")
                    open.append(markup)
                    outside.append(attributes)
                    attributes = attributes.inside(markup)
                case .closing(let markup):
                    #expect(open.popLast() == markup, "\(line)")
                    attributes = outside.popLast() ?? .plain
                    #expect(node.attributes == attributes, "\(line)")
                case .text:
                    var expected = attributes
                    if node.destination == node.range { expected.link = true }
                    #expect(node.attributes == expected, "\(line)")
                }
            }
            #expect(open.isEmpty, "\(line)")
        }
    }

    // MARK: The editing rules

    @Test("Touching markers of nested pairs are one hidden stretch")
    func stretches() {
        let text = "a ***x*** b" as NSString
        let stretches = MarkdownFormatting.hiddenStretches(inLine: NSRange(location: 0, length: text.length), of: text)
        #expect(stretches.map(\.range) == [NSRange(location: 2, length: 3), NSRange(location: 6, length: 3)])
        #expect(MarkdownFormatting.caretStop(for: 4, direction: 0, in: text, codeRanges: []) == 2)
    }

    @Test("The caret's formatting is every span it is in")
    func caretFormatting() {
        func state(_ line: String, at offset: Int) -> MarkdownFormatting.CaretFormatting {
            MarkdownFormatting.formatting(at: NSRange(location: offset, length: 0), in: line as NSString, codeRanges: [])
        }
        let both = state("***x***", at: 4)
        #expect(both.bold && both.italic)

        let line = "**\(Self.redTag)x\(Self.close)**"
        let inRun = state(line, at: (line as NSString).range(of: "x").location + 1)
        #expect(inRun.bold && inRun.colour == Self.red)

        let big = SpanStyle(size: SpanSize(em: 2)).openTag
        let sized = "\(big)\(big)x\(Self.close)\(Self.close)"
        #expect(state(sized, at: (sized as NSString).range(of: "x").location + 1).size == SpanSize(em: 4))
    }

    @Test("Backspace deletes the last letter on the page, and every span it empties")
    func backspace() throws {
        func backspace(_ line: String, at caret: Int) -> String? {
            MarkdownFormatting.backspace(at: caret, in: line as NSString, codeRanges: [])?.applied(to: line)
        }
        #expect(backspace("a ***x*** b", at: 9) == "a  b")
        #expect(backspace("**a *b***", at: 9) == "**a **")
        #expect(backspace("**a *bc***", at: 10) == "**a *b***")

        // From in front of the bold's closing markers too: the run it
        // empties goes, rather than leaving its tags on the page.
        let line = "a \(Self.redTag)**x**\(Self.close) b"
        let caret = (line as NSString).range(of: "x").location + 1
        #expect(backspace(line, at: caret) == "a  b")
    }

    @Test("Bold toggles the bold of nested emphasis, Italic the italic")
    func toggle() {
        func toggled(_ style: MarkdownFormatting.InlineStyle, _ line: String, _ selection: NSRange) -> String {
            MarkdownFormatting.toggle(style, in: line, selection: selection)?.applied(to: line) ?? line
        }
        #expect(toggled(.bold, "***x***", NSRange(location: 3, length: 1)) == "*x*")
        #expect(toggled(.italic, "***x***", NSRange(location: 3, length: 1)) == "**x**")
        #expect(toggled(.italic, "**a *b* c**", NSRange(location: 5, length: 1)) == "**a b c**")
    }

    @Test("A styled run's tags are never swapped for a style's markers")
    func toggleLeavesTags() {
        let line = "\(Self.redTag)word\(Self.close)"
        let end = (line as NSString).range(of: Self.close).location
        let result = MarkdownFormatting.toggle(.bold, in: line, selection: NSRange(location: end, length: 0))?.applied(to: line) ?? line
        #expect(result.contains(Self.close))
    }

    @Test("A link in bold is found, its text and where it goes")
    func linksInBold() throws {
        let line = "see **[the notes](https://example.com)** now" as NSString
        let link = try #require(MarkdownFormatting.links(onLineAt: 0, in: line, codeRanges: []).first)
        #expect(line.substring(with: link.text) == "the notes")
        #expect(link.destination == "https://example.com")
    }

    @Test("Inline code inside bold is code to the keyboard")
    func codeInBoldIsCode() {
        let source = "a **`int lo`** b"
        let caret = (source as NSString).range(of: "lo").location
        #expect(TextRewritingPolicy.at(caret, in: source, blocks: DocumentParser.parse(source)) == .code)
    }

    @Test("Outline titles, word counts, search and sizes read the nested text")
    func elsewhere() {
        #expect(NoteOutline.entries(in: "# **a *b* c**").first?.title == "a b c")
        #expect(NoteInfo(content: "**a *b* c**").words == 3)

        let note = "**\(Self.redTag)load factor\(Self.close)** low"
        #expect(NoteSearch("span").match(title: "Note", content: note) == nil)
        #expect(NoteSearch("factor").match(title: "Note", content: note) != nil)

        let big = SpanStyle(size: SpanSize(em: 2)).openTag
        let bigger = SpanStyle(size: SpanSize(em: 1.5)).openTag
        let line = "\(big)\(bigger)x\(Self.close) y\(Self.close)" as NSString
        let sizes = MarkdownFormatting.sizes(at: NSRange(location: 0, length: line.length), in: line, codeRanges: [])
        #expect(sizes.samples.map(\.size) == [SpanSize(em: 3), SpanSize(em: 2)])
    }
}

#if canImport(UIKit)

import UIKit

@Suite("Inline parser: nesting, styled")
@MainActor
struct NestingStylingTests {

    static func styled(_ text: String) -> UITextView {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = text
        DocumentStyler.applyStyling(to: textView)
        return textView
    }

    static func font(at word: String, in textView: UITextView) -> UIFont? {
        let offset = (textView.text as NSString).range(of: word).location
        return textView.textStorage.attribute(.font, at: offset, effectiveRange: nil) as? UIFont
    }

    @Test("Nested text is drawn with every trait and size around it")
    func drawn() throws {
        let both = try #require(Self.font(at: "x", in: Self.styled("a ***x*** b")))
        #expect(both.fontDescriptor.symbolicTraits.contains([.traitBold, .traitItalic]))

        let body = try #require(Self.font(at: "a", in: Self.styled("a ***x*** b")))
        let large = SpanStyle(size: SpanSize(em: 1.5)).openTag
        let sized = try #require(Self.font(at: "x", in: Self.styled("a **\(large)x\(SpanStyle.close)** b")))
        #expect(sized.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(abs(sized.pointSize - body.pointSize * 1.5) < 0.5)

        let red = SpanStyle(colour: TextColour.red.hex).openTag
        let textView = Self.styled("a \(red)**x**\(SpanStyle.close) b")
        let offset = (textView.text as NSString).range(of: "x").location
        #expect(textView.textStorage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor === DocumentStyler.textColour(hex: TextColour.red.hex))
        #expect((textView.textStorage.attribute(.font, at: offset, effectiveRange: nil) as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }

    @Test("One character that turns text into an address changes the block's signature")
    func signatureCarriesAttributes() {
        func signature(_ line: String) -> DocumentStyler.BlockSignature {
            DocumentStyler.layouts(for: DocumentParser.parse(line), in: line)[0].signature
        }
        // One text node of the same length either way: only what it is drawn
        // with differs.
        #expect(signature("hxtp://a.io") != signature("http://a.io"))
    }
}

#endif
