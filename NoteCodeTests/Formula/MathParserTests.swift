//
//  MathParserTests.swift
//  NoteCodeTests
//
//  LaTeX, step 1 (docs/design/latex.md): the parser reads `$…$`, `$$…$$` and
//  `\$`, and nothing else knows yet. Pure: no SwiftMath, no UIKit.
//

import Foundation
import Testing
@testable import NoteCode

struct MathParserTests {

    // MARK: Helpers

    private func nodes(_ line: String) -> [InlineNode] {
        InlineParser.parse(line, in: line.startIndex..<line.endIndex)
    }

    /// The formulas in a line: style and the TeX between the dollars.
    private func formulas(_ line: String) -> [(MathStyle, String)] {
        let all = nodes(line)
        var found: [(MathStyle, String)] = []
        for (index, node) in all.enumerated() {
            if case .opening(.math(let style)) = node.kind {
                found.append((style, String(line[all[index + 1].range])))
            }
        }
        return found
    }

    private func isMath(_ line: String) -> Bool { !formulas(line).isEmpty }

    private func escapes(_ line: String) -> [String] {
        nodes(line).filter { $0.kind == .escape }.map { String(line[$0.range]) }
    }

    private func blocks(_ text: String) -> [BlockNode] { DocumentParser.parse(text) }

    private func mathSources(_ text: String) -> [String] {
        blocks(text).compactMap { $0.mathBlock.map { String(text[$0.contentRange]) } }
    }

    // MARK: Inline

    @Test("A formula is its dollars and one text node between")
    func inlineShape() {
        let line = "a $x_1+y_2$ b"
        let all = nodes(line)
        #expect(all.map { String(line[$0.range]) } == ["a ", "$", "x_1+y_2", "$", " b"])
        #expect(all.map(\.kind) == [.text, .opening(.math(.inline)), .text, .closing(.math(.inline)), .text])
        #expect(all[2].attributes.math)
        #expect(!all[0].attributes.math && !all[4].attributes.math)
    }

    @Test("Mid-line $$ is display style, spaces allowed")
    func displayInline() {
        #expect(formulas("see $$x^2$$ here").map(\.1) == ["x^2"])
        #expect(formulas("see $$x^2$$ here").map(\.0) == [.display])
        #expect(formulas("see $$ x $$ here").map(\.1) == [" x "])
        #expect(!isMath("see $$ $$ here"))
        // No closing $$: the second dollar opens an inline one instead.
        #expect(formulas("see $$x$ here").map(\.0) == [.inline])
        #expect(formulas("see $$x$ here").map(\.1) == ["x"])
    }

    @Test("Currency stays text")
    func currency() {
        for line in ["costs $5 and $10", "$5–$10", "it is $5.", "$ 5 $", "a $ b", "$", "$$", "$x ", "x$", "$a $ b"] {
            #expect(!isMath(line), "\(line)")
        }
        #expect(formulas("$x$5").isEmpty, "a closing $ before a digit is a dollar")
        #expect(formulas("$x$ 5").map(\.1) == ["x"])
        #expect(formulas(#"pay \$5 for $x$"#).map(\.1) == ["x"])
    }

    @Test("The flanking rule: no space inside either dollar")
    func flanking() {
        #expect(!isMath("$ x$"))
        #expect(!isMath("$x $"))
        #expect(formulas("$x$ and $y$").map(\.1) == ["x", "y"])
    }

    @Test("A formula is an atom: nothing in it is emphasis, a link or a tag")
    func atom() {
        #expect(formulas("$a*b*c$").map(\.1) == ["a*b*c"])
        #expect(!nodes("$a*b*c$").contains { $0.kind.markup == .emphasis })
        #expect(formulas("$x_1+y_2$").map(\.1) == ["x_1+y_2"])
        #expect(!nodes("$[a](b)$").contains { $0.kind.markup == .link })
        // Emphasis around one still pairs.
        let line = "*a $x$ b*"
        #expect(nodes(line).contains { $0.kind == .opening(.emphasis) })
        // A pair that would cross a formula is text.
        #expect(!nodes("*a $x* b$").contains { $0.kind == .opening(.emphasis) })
    }

    @Test("Text inside a formula carries math, and nothing else")
    func attributes() {
        let line = "**a $x$ b**"
        let formula = nodes(line).first { $0.attributes.math && !$0.kind.isMarker }
        #expect(formula.map { String(line[$0.range]) } == "x")
        #expect(formula?.attributes.bold == true)
        #expect(InlineAttributes.plain.signature != InlineAttributes(math: true).signature)
    }

    @Test("\\$ is a dollar, in and out of math")
    func escapedDollar() {
        #expect(escapes(#"costs \$5 and \$10"#) == ["\\", "\\"])
        #expect(!isMath(#"\$5 and $10"#.replacingOccurrences(of: "$10", with: "")))
        // It doesn't open a formula …
        #expect(!isMath(#"\$x$"#))
        // … nor close one.
        #expect(formulas(#"$a\$b$"#).map(\.1) == [#"a\$b"#])
        #expect(formulas(#"$a\$b"#).isEmpty)
        #expect(escapes(#"$a\$b$"#).isEmpty, "inside a formula it is TeX's own")
        // The escape is a marker of its own, and the dollar stays text.
        let line = #"a \$ b"#
        let all = nodes(line)
        #expect(all.map { String(line[$0.range]) } == ["a ", "\\", "$ b"])
        #expect(all[1].kind.isMarker && all[2].kind == .text)
        // A backslash before anything else is just a backslash.
        #expect(escapes(#"a \n b \\ c"#).isEmpty)
    }

    @Test("Code wins, left to right")
    func code() {
        #expect(!isMath("`$x$`"))
        #expect(nodes("`$x$`").contains { $0.kind == .opening(.inlineCode) })
        #expect(formulas("`a` $x$ `b`").map(\.1) == ["x"])
        // A dollar in a code span is not a closer.
        #expect(!isMath("$5 and `a$b` c"))
        #expect(formulas("$a `b$` c$").map(\.1) == ["a `b$` c"])
        // A code span in a formula that starts first is still its TeX.
        #expect(escapes(#"`\$`"#).isEmpty)
        // An unmatched backtick is text.
        #expect(formulas("$a ` b$").map(\.1) == ["a ` b"])
    }

    @Test("Math in a link's text is text")
    func link() {
        let line = "[a $x$ b](https://example.com)"
        #expect(!isMath(line))
        #expect(nodes(line).contains { $0.kind == .opening(.link) })
        #expect(formulas("$x$ and [y](https://example.com)").map(\.1) == ["x"])
    }

    @Test("Nodes cover the line, in any case")
    func covering() {
        for line in ["$x$", "$$x$$", #"\$"#, "a $b$ c $$d$$ e \\$ f", "$ $ $", "`$`$x$`$`"] {
            let all = nodes(line)
            #expect(all.first?.range.lowerBound == line.startIndex, "\(line)")
            #expect(all.last?.range.upperBound == line.endIndex, "\(line)")
            for (current, next) in zip(all, all.dropFirst()) {
                #expect(current.range.upperBound == next.range.lowerBound, "\(line)")
            }
        }
    }

    // MARK: Blocks

    @Test("$$ x $$ on a line is a block")
    func oneLineBlock() {
        let text = "before\n$$ x^2 $$\nafter\n"
        let parsed = blocks(text)
        #expect(parsed.count == 3)
        #expect(parsed[1].isMath)
        #expect(String(text[parsed[1].range]) == "$$ x^2 $$\n")
        #expect(String(text[parsed[1].mathBlock!.contentRange]) == " x^2 ")
        #expect(String(text[parsed[1].mathBlock!.openingRange]) == "$$")
        #expect(String(text[parsed[1].mathBlock!.closingRange]) == "$$")
        #expect(parsed[1].inlines.isEmpty)
        #expect(parsed[1].markerRange == nil)
    }

    @Test("$$ over lines is one block, and its lines are not read alone")
    func manyLineBlock() {
        let text = "$$\n\\sum_{i=1}^n i\n= \\frac{n(n+1)}{2}\n$$\nnext"
        let parsed = blocks(text)
        #expect(parsed.map(\.isMath) == [true, false])
        #expect(parsed[0].range == text.startIndex..<text.index(text.startIndex, offsetBy: 40))
        #expect(mathSources(text) == ["\n\\sum_{i=1}^n i\n= \\frac{n(n+1)}{2}\n"])
        // Text on the opening and closing lines is the formula's.
        #expect(mathSources("$$ a\nb $$") == [" a\nb "])
        #expect(mathSources("$$ a\nb $$  \nx") == [" a\nb "])
    }

    @Test("$$ in the middle of a line is inline")
    func notABlock() {
        for text in ["a $$x$$", "$$x$$ and more", "- $$x$$", "  $$ x $$"] {
            #expect(blocks(text).allSatisfy { !$0.isMath }, "\(text)")
        }
        #expect(formulas("$$x$$ and more").map(\.0) == [.display])
    }

    @Test("An unclosed $$ is text, never a block to the end")
    func unclosed() {
        let text = "$$\nx\ny\nz\n"
        #expect(blocks(text).count == 4)
        #expect(blocks(text).allSatisfy { !$0.isMath })
        #expect(mathSources("$$ x\ny") == [])
        // Closing it later makes the block, with no stale state.
        #expect(mathSources("$$\nx\n$$") == ["\nx\n"])
    }

    @Test("A $$ is text when it has no TeX")
    func empty() {
        for text in ["$$$$", "$$ $$", "$$\n$$", "$$\n\n  \n$$", "$$$"] {
            #expect(mathSources(text).isEmpty, "\(text)")
        }
    }

    @Test("The block closes within 50 lines or it is text")
    func fiftyLines() {
        func note(inside count: Int) -> String {
            "$$\n" + String(repeating: "x\n", count: count) + "$$\n"
        }
        // 50 lines is both `$$` lines and 48 between.
        #expect(mathSources(note(inside: 48)).count == 1)
        #expect(mathSources(note(inside: 49)).isEmpty)
        #expect(mathSources(note(inside: 200)).isEmpty)
        #expect(DocumentParser.maxMathLines == 50)
    }

    @Test("A fence stops the search for the close")
    func fence() {
        let text = "$$\nx\n```swift\nlet a = 1\n$$\n```\n"
        let parsed = blocks(text)
        #expect(parsed.map(\.isMath) == [false, false, false])
        #expect(parsed.last?.isCode == true)
        // `$$` inside a fence is code.
        let inCode = "```\n$$ x $$\n```\n"
        #expect(blocks(inCode).count == 1 && blocks(inCode)[0].isCode)
    }

    @Test("A closing $$ that is escaped is not a close")
    func escapedClose() {
        #expect(mathSources("$$\nx \\$$\n").isEmpty)
    }

    @Test("Blocks keep the invariants: contiguous, whole, ordered")
    func tiling() {
        let text = "# t\n$$ a $$\ntext $b$\n$$\nc\n$$\n- item\n```\ncode\n```\n$$ d\n"
        let parsed = blocks(text)
        #expect(parsed.first?.range.lowerBound == text.startIndex)
        #expect(parsed.last?.range.upperBound == text.endIndex)
        for (current, next) in zip(parsed, parsed.dropFirst()) {
            #expect(current.range.upperBound == next.range.lowerBound)
        }
        #expect(parsed.filter(\.isMath).count == 2)
    }

    @Test("Its identity changes with the TeX, not with where it is")
    func identity() {
        let one = blocks("$$ a $$").first!
        let other = blocks("$$ b $$").first!
        let same = blocks("x\n$$ a $$").last!
        #expect(one.styleDetail != other.styleDetail)
        #expect(one.styleDetail == same.styleDetail)
        #expect(one.kindDiscriminant == 6)
    }

    // MARK: Property

    @Test("Any lines tile the note and give nodes that nest, with dollars in them")
    func randomLines() {
        let pieces = ["a", " ", "$", "$$", "\\", "\\$", "`", "*", "_", "5", "[", "](u)", "x^2", "\n", "\n", "```", "é"]
        var random = NestingInlineTests.Seeded(state: 26_10_2026)
        for _ in 0..<3000 {
            let text = (0..<Int.random(in: 1...22, using: &random)).map { _ in pieces.randomElement(using: &random)! }.joined()

            let parsed = blocks(text)
            if !text.isEmpty {
                #expect(parsed.first?.range.lowerBound == text.startIndex, "\(text.debugDescription)")
                #expect(parsed.last?.range.upperBound == text.endIndex, "\(text.debugDescription)")
            }
            for (current, next) in zip(parsed, parsed.dropFirst()) {
                #expect(current.range.upperBound == next.range.lowerBound, "\(text.debugDescription)")
            }
            for block in parsed {
                if let math = block.mathBlock {
                    #expect(math.contentRange.lowerBound == math.openingRange.upperBound, "\(text.debugDescription)")
                    #expect(math.contentRange.upperBound == math.closingRange.lowerBound, "\(text.debugDescription)")
                    #expect(text[block.range].split(whereSeparator: \.isNewline).count <= DocumentParser.maxMathLines, "\(text.debugDescription)")
                    #expect(text[math.contentRange].contains { !$0.isWhitespace }, "\(text.debugDescription)")
                }
                guard !block.isCode, !block.isMath else { continue }
                let nodes = block.inlines
                guard !nodes.isEmpty else { continue }
                var open: [InlineMarkup] = []
                for node in nodes {
                    switch node.kind {
                    case .opening(let markup): open.append(markup)
                    case .closing(let markup): #expect(open.popLast() == markup, "\(text.debugDescription)")
                    case .escape: #expect(text[node.range] == "\\", "\(text.debugDescription)")
                    case .text: #expect(node.attributes.math == open.contains { if case .math = $0 { true } else { false } }, "\(text.debugDescription)")
                    }
                    #expect(!node.range.isEmpty, "\(text.debugDescription)")
                }
                #expect(open.isEmpty, "\(text.debugDescription)")
                #expect(nodes.first?.range.lowerBound == block.contentRange.lowerBound, "\(text.debugDescription)")
                #expect(nodes.last?.range.upperBound == block.contentRange.upperBound, "\(text.debugDescription)")
            }
        }
    }
}
