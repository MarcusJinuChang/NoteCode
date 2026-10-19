//
//  StyledLineTests.swift
//  NoteCodeTests
//
//  Formatting per character (text overhaul, phase 3): what the buttons
//  write, and that it always reads back as asked.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Formatting per character")
struct StyledLineTests {

    typealias Style = StyledLine.Style

    static let red = 0xE5484D
    static let blue = 0x3B82F6
    static let close = SpanStyle.close

    static func range(of part: String, in text: String) -> NSRange {
        (text as NSString).range(of: part)
    }

    static func toggled(_ style: MarkdownFormatting.InlineStyle, _ text: String, _ selection: NSRange) -> (text: String, selected: String)? {
        guard let edit = MarkdownFormatting.toggle(style, in: text, selection: selection) else { return nil }
        let result = edit.applied(to: text)
        return (result, (result as NSString).substring(with: edit.selection))
    }

    static func toggled(_ style: MarkdownFormatting.InlineStyle, _ text: String, selecting part: String) -> (text: String, selected: String)? {
        toggled(style, text, range(of: part, in: text))
    }

    static let blockSizes = MarkdownFormatting.BlockSizes(body: 17, headings: [34, 28, 22, 20, 17, 15])

    /// What a line shows, glyph by glyph: its text and what it is drawn
    /// with, links compared by address.
    static func drawn(_ line: String) -> [String] {
        guard let styled = StyledLine(line) else { return [] }
        return styled.glyphs.map { glyph in
            let style = glyph.style
            var flags = ""
            if style.bold { flags += "B" }
            if style.italic { flags += "I" }
            if style.strikethrough { flags += "S" }
            if style.code { flags += "C" }
            if let link = style.link { flags += "L(\(link.address ?? "bare"))" }
            if let colour = style.colour { flags += String(format: "#%06X", colour) }
            if let size = style.size { flags += "@\(size.written)" }
            return glyph.text + flags
        }
    }

    // MARK: On the page

    @Test("Bold, then Italic, on a word is bold italic; Italic again leaves it bold")
    func stylesCombine() throws {
        let bold = try #require(Self.toggled(.bold, "a word b", selecting: "word"))
        #expect(bold.text == "a **word** b")
        let both = try #require(Self.toggled(.italic, bold.text, selecting: "word"))
        #expect(both.text == "a ***word*** b")
        #expect(both.selected == "word")
        let back = try #require(Self.toggled(.italic, both.text, selecting: "word"))
        #expect(back.text == "a **word** b")

        // From a caret inside the bold word, the same.
        let caret = NSRange(location: Self.range(of: "word", in: bold.text).location + 2, length: 0)
        let atCaret = try #require(MarkdownFormatting.toggle(.italic, in: bold.text, selection: caret))
        #expect(atCaret.applied(to: bold.text) == "a ***word*** b")
        #expect(atCaret.selection == NSRange(location: Self.range(of: "word", in: "a ***word*** b").location + 2, length: 0))
    }

    @Test("Bold off part of a bold italic word leaves that part italic")
    func partOff() throws {
        let result = try #require(Self.toggled(.bold, "***word***", selecting: "rd"))
        #expect(Self.drawn(result.text) == ["wBI", "oBI", "rI", "dI"])
        #expect(result.selected == "rd")
    }

    @Test("A size on two letters of a bold word sizes those two, still bold")
    func sizeOnPartOfABoldWord() throws {
        let text = "a **bold** b"
        let edit = try #require(MarkdownFormatting.size(
            points: 24, blockSizes: Self.blockSizes, selection: Self.range(of: "ld", in: text), in: text as NSString, codeRanges: []
        ))
        let result = edit.applied(to: text)
        #expect(result == "a **bo\(SpanStyle(size: SpanSize(em: 1.412)).openTag)ld\(Self.close)** b")
        #expect((result as NSString).substring(with: edit.selection) == "ld")
    }

    @Test("Italic on two letters of a bold word")
    func italicOnPartOfABoldWord() throws {
        #expect(try #require(Self.toggled(.italic, "**bold**", selecting: "ld")).text == "**bo*ld***")
    }

    @Test("A colour on half a word, and Default on half a coloured word")
    func colourOnPart() throws {
        let edit = try #require(MarkdownFormatting.colour(Self.red, selection: NSRange(location: 2, length: 2), in: "abcd", codeRanges: []))
        #expect(edit.applied(to: "abcd") == "ab\(SpanStyle(colour: Self.red).openTag)cd\(Self.close)")

        let coloured = "\(SpanStyle(colour: Self.red).openTag)abcd\(Self.close)"
        let off = try #require(MarkdownFormatting.colour(nil, selection: Self.range(of: "ab", in: coloured), in: coloured as NSString, codeRanges: []))
        #expect(off.applied(to: coloured) == "ab\(SpanStyle(colour: Self.red).openTag)cd\(Self.close)")
    }

    // MARK: What is rewritten

    @Test("Only the stretch between places where nothing is open is rewritten")
    func minimalRewrite() throws {
        let text = "__keep__ and _this_ word"
        let result = try #require(Self.toggled(.bold, text, selecting: "word"))
        #expect(result.text == "__keep__ and _this_ **word**")

        let edit = try #require(MarkdownFormatting.toggle(.bold, in: text, selection: Self.range(of: "word", in: text)))
        #expect(edit.range == Self.range(of: "word", in: text), "the edit touches only what changes")
    }

    @Test("A neighbour already in the style is joined, not written beside")
    func joinsNeighbours() throws {
        #expect(try #require(Self.toggled(.bold, "**a**b", selecting: "b")).text == "**ab**")
        #expect(try #require(Self.toggled(.bold, "a**b**", selecting: "a")).text == "**ab**")
        let red = SpanStyle(colour: Self.red).openTag
        let coloured = "\(red)a\(Self.close)b"
        let edit = try #require(MarkdownFormatting.colour(
            Self.red, selection: NSRange(location: (coloured as NSString).length - 1, length: 1), in: coloured as NSString, codeRanges: []
        ))
        #expect(edit.applied(to: coloured) == "\(red)ab\(Self.close)")
    }

    @Test("Spaces at a selection's ends don't count, and go outside the markers")
    func spaces() throws {
        #expect(try #require(Self.toggled(.bold, "a word b", selecting: " word ")).text == "a **word** b")
        // "word" and the space after it are all bold where they can be: Bold
        // takes it off.
        #expect(try #require(Self.toggled(.bold, "**word** next", NSRange(location: 2, length: 7))).text == "word next")
    }

    @Test("Code spans and links are taken whole")
    func atoms() throws {
        #expect(try #require(Self.toggled(.bold, "see [the notes](https://e.io) now", selecting: "notes")).text
                == "see **[the notes](https://e.io)** now")
        #expect(try #require(Self.toggled(.bold, "at https://e.io/x now", selecting: "e.io")).text == "at **https://e.io/x** now")

        let text = "call `push_back` here"
        let edit = try #require(MarkdownFormatting.colour(Self.red, selection: Self.range(of: "back", in: text), in: text as NSString, codeRanges: []))
        #expect(edit.applied(to: text) == "call \(SpanStyle(colour: Self.red).openTag)`push_back`\(Self.close) here")

        // Code off part of a code span takes it all off.
        #expect(try #require(Self.toggled(.code, text, selecting: "back")).text == "call push_back here")
    }

    @Test("A bold sentence holding a link is one bold; a link with part of its text bold keeps its link")
    func linksAndEmphasis() throws {
        let sentence = "see [it](u) now"
        #expect(try #require(Self.toggled(.bold, sentence, selecting: sentence)).text == "**see [it](u) now**")

        let partly = "[a **b**](u) c"
        let result = try #require(Self.toggled(.italic, partly, selecting: partly))
        // Italic goes inside the link, so the spaces at its ends shed it.
        #expect(Self.drawn(result.text) == ["aIL(u)", " L(u)", "bBIL(u)", " ", "cI"])
        #expect(MarkdownFormatting.links(onLineAt: 0, in: result.text as NSString, codeRanges: []).count == 1)
    }

    @Test("A caret inside a word of a link or of code gives the whole link or code the style; inside a bold word, takes it off the word")
    func caretInSpans() throws {
        let link = "see [the notes](u) now"
        let caret = NSRange(location: Self.range(of: "notes", in: link).location + 1, length: 0)
        #expect(MarkdownFormatting.toggle(.bold, in: link, selection: caret)?.applied(to: link) == "see **[the notes](u)** now")

        let code = "call `push_back` here"
        let inCode = NSRange(location: Self.range(of: "back", in: code).location + 1, length: 0)
        #expect(MarkdownFormatting.toggle(.bold, in: code, selection: inCode)?.applied(to: code) == "call **`push_back`** here")

        let bold = "**two words**"
        let inBold = NSRange(location: Self.range(of: "words", in: bold).location + 2, length: 0)
        #expect(MarkdownFormatting.toggle(.bold, in: bold, selection: inBold)?.applied(to: bold) == "**two** words")

        // At the end of the link's text there is no word to act on.
        let atEnd = NSRange(location: Self.range(of: "notes", in: link).location + 5, length: 0)
        #expect(MarkdownFormatting.toggle(.bold, in: link, selection: atEnd) == nil)
    }

    @Test("A line that can't be written to read as asked is left alone")
    func refusesWhatWouldShowMarkers() {
        // A star typed as text beside new stars joins their run: `**x***`
        // is a bold x and a star. Underscores get round that, `__x*__`…
        #expect(MarkdownFormatting.toggle(.bold, in: "x*", selection: NSRange(location: 0, length: 2))?.applied(to: "x*") == "__x*__")
        // …but not with an underscore at the other end, and nothing is
        // better than a line that shows its markers.
        #expect(MarkdownFormatting.toggle(.bold, in: "*x_", selection: NSRange(location: 0, length: 3)) == nil)
        // Code holding stars, taken out of code, would be bold.
        #expect(MarkdownFormatting.toggle(.code, in: "`**x**`", selection: NSRange(location: 3, length: 1)) == nil)
    }

    @Test("Nothing in a code block is styled, from a caret or a selection")
    func notInCode() {
        let text = "prose\n```cpp\nint x;\n```\n"
        let codeRanges = [CodeRange(range: NSRange(location: 6, length: 18), isClosed: true, language: .cpp, tag: "cpp")]
        #expect(MarkdownFormatting.toggle(.bold, in: text, selection: NSRange(location: 15, length: 0), codeRanges: codeRanges) == nil)
        let edit = MarkdownFormatting.toggle(.bold, in: text, selection: NSRange(location: 0, length: 20), codeRanges: codeRanges)
        #expect(edit?.applied(to: text) == "**prose**\n```cpp\nint x;\n```\n")
    }

    // MARK: Always reads back

    /// Random styles over random text with no marker characters in it:
    /// every one is written, and reads back as asked, less bold, italic and
    /// strikethrough on spaces at the end of a stretch, which can't carry
    /// them.
    @Test("Any styling of a line is written so it reads back as asked")
    func roundTrip() {
        let letters = ["a", "b", "c", "x", "é", "👩‍💻", " ", " ", ",", "(", ")", ":", "'"]
        let colours: [Int?] = [nil, Self.red, Self.blue]
        let sizes: [SpanSize?] = [nil, SpanSize(em: 1.25), SpanSize(em: 0.85), SpanSize(em: 2)]
        let highlights: [HighlightColour?] = [nil, .yellow, .red, .blue]
        var random = NestingInlineTests.Seeded(state: 19_10_2026)
        var failures: [String] = []
        var written = 0

        for _ in 0..<3000 {
            let count = Int.random(in: 1...12, using: &random)
            let texts = (0..<count).map { _ in letters.randomElement(using: &random)! }
            guard let line = StyledLine(texts.joined()), line.glyphs.count == count else {
                Issue.record("not one glyph each: \(texts)")
                continue
            }

            func stretch() -> Range<Int> {
                let a = Int.random(in: 0...count, using: &random)
                let b = Int.random(in: 0...count, using: &random)
                return min(a, b)..<max(a, b)
            }
            var styles = line.glyphs.map(\.style)
            let flags: [WritableKeyPath<Style, Bool>] = [\.bold, \.italic, \.strikethrough, \.underline, \.code]
            for flag in flags {
                for _ in 0..<Int.random(in: 0...2, using: &random) {
                    for index in stretch() { styles[index][keyPath: flag] = true }
                }
            }
            for _ in 0..<Int.random(in: 0...2, using: &random) {
                let colour = colours.randomElement(using: &random)!
                for index in stretch() { styles[index].colour = colour }
            }
            for _ in 0..<Int.random(in: 0...2, using: &random) {
                let size = sizes.randomElement(using: &random)!
                for index in stretch() { styles[index].size = size }
            }
            // Highlights of different colours side by side too: `====🔴` ends
            // one and starts the next.
            for _ in 0..<Int.random(in: 0...3, using: &random) {
                let highlight = highlights.randomElement(using: &random)!
                for index in stretch() { styles[index].highlight = highlight }
            }
            if Bool.random(using: &random) {
                let span = stretch()
                // A link's text can't be blank.
                if span.contains(where: { texts[$0] != " " }) {
                    let link = StyledLine.Link(id: span.lowerBound, address: Bool.random(using: &random) ? "u" : "https://e.io/a")
                    for index in span { styles[index].link = link }
                }
            }
            guard styles != line.glyphs.map(\.style) else { continue }

            guard let read = line.restyled(styles) else {
                failures.append(Self.describe(texts, styles))
                continue
            }
            written += 1
            #expect(read.glyphs.map(\.text) == texts)
            for index in read.glyphs.indices {
                var (got, asked) = (read.glyphs[index].style, styles[index])
                #expect((got.link == nil) == (asked.link == nil) && got.link?.address == asked.link?.address, "\(read.line)")
                if index > 0 {
                    #expect((got.link == read.glyphs[index - 1].style.link) == (asked.link == styles[index - 1].link), "\(read.line)")
                }
                got.link = nil
                asked.link = nil
                if read.glyphs[index].isSpace {
                    // A space may lose emphasis, never gain it.
                    for flag in [\Style.bold, \.italic, \.strikethrough] where !asked[keyPath: flag] {
                        #expect(!got[keyPath: flag], "\(read.line)")
                    }
                    got.bold = asked.bold
                    got.italic = asked.italic
                    got.strikethrough = asked.strikethrough
                }
                #expect(got == asked, "\(read.line) at \(index)")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) not written, first: \(failures.prefix(3))")
        #expect(written > 2500)
    }

    static func describe(_ texts: [String], _ styles: [Style]) -> String {
        zip(texts, styles).map { text, style in
            var flags = ""
            if style.bold { flags += "B" }
            if style.italic { flags += "I" }
            if style.strikethrough { flags += "S" }
            if style.code { flags += "C" }
            if style.underline { flags += "U" }
            if style.highlight != nil { flags += "H" }
            if let link = style.link { flags += "L\(link.id)" }
            if style.colour != nil { flags += "#" }
            if style.size != nil { flags += "@" }
            return "\(text)\(flags)"
        }.joined(separator: "|")
    }

    /// Lines with markers in them, text that looks like markers included,
    /// and a random selection made bold, italic, struck or code: either no
    /// edit, or every character the same, the selection's characters (spaces
    /// aside) with the style set or cleared, and everything else as it was.
    @Test("A button never changes what a line shows but the style it sets")
    func neverCorrupts() throws {
        let pieces = ["a", "b", " ", "*", "**", "_", "__", "~~", "`", "[", "](u)", "é",
                      "https://x.io", SpanStyle(colour: Self.red).openTag, Self.close,
                      "<u>", "</u>", "==", "==🟡", "==🔴", "🟡", "="]
        var random = NestingInlineTests.Seeded(state: 20_10_2026)
        var edits = 0
        for _ in 0..<4000 {
            let text = (0..<Int.random(in: 1...10, using: &random)).map { _ in pieces.randomElement(using: &random)! }.joined()
            guard let before = StyledLine(text), !before.glyphs.isEmpty else { continue }
            let length = (text as NSString).length
            let a = Int.random(in: 0...length, using: &random)
            let b = Int.random(in: 0...length, using: &random)
            let selection = NSRange(location: min(a, b), length: max(a, b) - min(a, b))
            guard selection.length > 0 else { continue }
            let style = MarkdownFormatting.InlineStyle.allCases.randomElement(using: &random)!
            guard let edit = MarkdownFormatting.toggle(style, in: text, selection: selection) else { continue }
            edits += 1

            let result = edit.applied(to: text)
            let after = try #require(StyledLine(result), "\(text) → \(result)")
            #expect(after.glyphs.map(\.text) == before.glyphs.map(\.text), "\(text) → \(result)")
            guard after.glyphs.count == before.glyphs.count else { continue }

            let target = before.wholeAtoms(
                before.glyphCount(endingBy: selection.location)..<before.glyphCount(startingBefore: NSMaxRange(selection))
            )
            let removing = target.filter { !before.glyphs[$0].isSpace }.allSatisfy { before.glyphs[$0].style[keyPath: style.attribute] }
            for index in before.glyphs.indices {
                var (old, new) = (before.glyphs[index].style, after.glyphs[index].style)
                old.link = old.link.map { StyledLine.Link(id: 0, address: $0.address) }
                new.link = new.link.map { StyledLine.Link(id: 0, address: $0.address) }
                if target.contains(index) { old[keyPath: style.attribute] = !removing }
                // A space, once the change is made, may shed emphasis.
                if after.glyphs[index].isSpace {
                    old.bold = new.bold
                    old.italic = new.italic
                    old.strikethrough = new.strikethrough
                }
                #expect(old == new, "\(text) → \(result) at \(index)")
            }
        }
        #expect(edits > 1000)
    }
}

#if canImport(UIKit)
import UIKit

@MainActor
@Suite("Formatting per character in the editor")
struct StyledLineEditorTests {

    typealias Harness = TextSizeEditorTests.Harness

    @Test("Two letters of a bold word sized, then one undo puts them back")
    func sizeAndUndo() async {
        let harness = Harness(withInk: false)
        harness.textView.text = "a **bold** b\n"
        harness.textView.selectedRange = (harness.textView.text as NSString).range(of: "ld")
        harness.editor.setSelectionSize(points: 24)
        #expect(harness.textView.text == "a **bo\(SpanStyle(size: SpanSize(em: 1.412)).openTag)ld</span>** b\n")
        #expect((harness.textView.text as NSString).substring(with: harness.textView.selectedRange) == "ld")

        try? await Task.sleep(for: .milliseconds(50))
        harness.editor.undo()
        #expect(harness.textView.text == "a **bold** b\n")
    }
}
#endif
