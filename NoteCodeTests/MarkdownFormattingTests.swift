//
//  MarkdownFormattingTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

// Selections are written into the text: «» around what is selected, and «»
// with nothing between for a bare caret. So `a «b» c` is "a b c" with the b
// selected, and the result reads back the same way.

private func unpack(_ marked: String) -> (text: String, selection: NSRange) {
    let ns = marked as NSString
    let open = ns.range(of: "«")
    let close = ns.range(of: "»")
    precondition(open.location != NSNotFound && close.location != NSNotFound, "no selection in \(marked)")

    let text = marked.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
    return (text, NSRange(location: open.location, length: close.location - open.location - 1))
}

private func pack(_ text: String, _ selection: NSRange) -> String {
    let ns = text as NSString
    return ns.substring(to: selection.location)
        + "«" + ns.substring(with: selection) + "»"
        + ns.substring(from: NSMaxRange(selection))
}

private func run(_ marked: String, _ format: (String, NSRange) -> TextEdit) -> String {
    let (text, selection) = unpack(marked)
    let edit = format(text, selection)
    return pack(edit.applied(to: text), edit.selection)
}

/// A toggle with nothing to do leaves the text and selection as they were.
private func toggled(_ style: MarkdownFormatting.InlineStyle, _ marked: String) -> String {
    let (text, selection) = unpack(marked)
    guard let edit = MarkdownFormatting.toggle(style, in: text, selection: selection) else { return marked }
    return pack(edit.applied(to: text), edit.selection)
}

private func headed(_ level: Int, _ marked: String) -> String {
    run(marked) { MarkdownFormatting.setHeading(level: level, in: $0, selection: $1) }
}

private func bulleted(_ marked: String) -> String {
    run(marked) { MarkdownFormatting.toggleBullet(in: $0, selection: $1) }
}

private func fenced(_ language: CodeLanguage?, _ marked: String) -> String {
    run(marked) { MarkdownFormatting.insertCodeBlock(language: language, in: $0, selection: $1) }
}

@Suite("Formatting: inline styles")
struct InlineFormattingTests {

    @Test("Each style wraps a selection and keeps the words selected", arguments: [
        (MarkdownFormatting.InlineStyle.bold, "a **«word»** b"),
        (.italic, "a *«word»* b"),
        (.strikethrough, "a ~~«word»~~ b"),
        (.code, "a `«word»` b"),
    ])
    func wraps(style: MarkdownFormatting.InlineStyle, expected: String) {
        #expect(toggled(style, "a «word» b") == expected)
    }

    @Test("What a button writes, the parser reads as that style", arguments: MarkdownFormatting.InlineStyle.allCases)
    func parserAgrees(style: MarkdownFormatting.InlineStyle) throws {
        let (text, selection) = unpack("a «word» b")
        let result = try #require(MarkdownFormatting.toggle(style, in: text, selection: selection)).applied(to: text)
        let kinds = TopLevelSpan.read(result).map(\.kind)

        #expect(kinds == [.text, style.topLevelKind, .text])
    }

    @Test("Pressing again removes the style", arguments: MarkdownFormatting.InlineStyle.allCases)
    func roundTrips(style: MarkdownFormatting.InlineStyle) {
        let once = toggled(style, "a «word» b")
        #expect(toggled(style, once) == "a «word» b")
    }

    @Test("A caret strictly inside a word takes the style off that word, not the span")
    func caretInsideRemoves() {
        #expect(toggled(.bold, "a **wo«»rd** b") == "a wo«»rd b")
        #expect(toggled(.bold, "**one tw«»o**") == "**one** tw«»o")
    }

    @Test("A caret at a word's end, or at its start, writes nothing: the button sets the typing style")
    func caretAtAnEdgeWritesNothing() {
        for style in MarkdownFormatting.InlineStyle.allCases {
            #expect(toggled(style, "a **«»word** b") == "a **«»word** b")
            #expect(toggled(style, "a **word«»** b") == "a **word«»** b")
            #expect(toggled(style, "a word«» b") == "a word«» b")
        }
    }

    @Test("A caret strictly inside a word gives it the style, as selecting it would", arguments: [
        (MarkdownFormatting.InlineStyle.bold, "a **wo«»rd** b"),
        (.italic, "a *wo«»rd* b"),
        (.strikethrough, "a ~~wo«»rd~~ b"),
        (.code, "a `wo«»rd` b"),
    ])
    func caretInAWord(style: MarkdownFormatting.InlineStyle, expected: String) {
        #expect(toggled(style, "a wo«»rd b") == expected)
        #expect(toggled(style, expected) == "a wo«»rd b", "pressing again takes it off")
    }

    @Test("Selecting a span with its markers removes them")
    func selectingMarkersRemoves() {
        #expect(toggled(.bold, "a «**word**» b") == "a «word» b")
    }

    @Test("A different style is added to the span's: styles combine")
    func otherStyleCombines() {
        #expect(toggled(.italic, "a **«word»** b") == "a ***«word»*** b")
        #expect(toggled(.strikethrough, "a *wo«»rd* b") == "a *~~wo«»rd~~* b")
    }

    @Test("Italic inside bold is not mistaken for italic already present")
    func italicIsNotBold() {
        // `**word**` has a single star either side of the selection as well.
        // Reading that as italic would strip one star each side and leave
        // `*word*`, when the button asked for italic *added*.
        #expect(toggled(.italic, "**«word»**") == "***«word»***")
    }

    @Test("With nothing selected between words, no empty pair goes in")
    func noEmptyPair() {
        for style in MarkdownFormatting.InlineStyle.allCases {
            #expect(toggled(style, "a «»b") == "a «»b")
            #expect(toggled(style, "«»") == "«»")
            #expect(toggled(style, "line one\n«»\nline three") == "line one\n«»\nline three")
        }
    }

    @Test("Several lines are styled one line at a time, skipping blank ones")
    func acrossLines() {
        // The selection keeps its characters: from the first one on the page
        // to the last, inside the markers.
        #expect(toggled(.bold, "«one\n\ntwo»") == "**«one**\n\n**two»**")
    }

    @Test("Several lines that all carry the style lose it")
    func acrossLinesRemoves() {
        #expect(toggled(.bold, "«**one**\n**two**»") == "«one\ntwo»")
    }

    @Test("Several lines with the style on only some gain it on the rest")
    func acrossLinesMixed() {
        #expect(toggled(.bold, "«**one**\ntwo»") == "**«one**\n**two»**")
    }

    @Test("Offsets are UTF-16, so text after an emoji still lines up")
    func utf16Offsets() {
        #expect(toggled(.bold, "🧪 «word»") == "🧪 **«word»**")
    }
}

@Suite("Formatting: headings")
struct HeadingFormattingTests {

    @Test("A heading marker goes in front, and the caret keeps its place in the words")
    func addsHeading() {
        #expect(headed(2, "Binary «»search") == "## Binary «»search")
    }

    @Test("A caret at the very start lands after the new marker")
    func caretAtStart() {
        #expect(headed(1, "«»Title") == "# «»Title")
    }

    @Test("Changing level replaces the marker rather than stacking another")
    func changesLevel() {
        #expect(headed(1, "### Tit«»le") == "# Tit«»le")
    }

    @Test("Pressing the level a line already has makes it body text")
    func sameLevelRemoves() {
        #expect(headed(2, "## Tit«»le") == "Tit«»le")
    }

    @Test("Level 0 is body text")
    func levelZero() {
        #expect(headed(0, "## Tit«»le") == "Tit«»le")
        #expect(headed(0, "Tit«»le") == "Tit«»le")
    }

    @Test("A caret inside the old marker lands at the start of the words")
    func caretInsideMarker() {
        #expect(headed(1, "#«»## Title") == "# «»Title")
    }

    @Test("An empty line can become a heading")
    func emptyLine() {
        #expect(headed(1, "above\n«»\nbelow") == "above\n# «»\nbelow")
    }

    @Test("Only the lines the selection touches change")
    func onlyTouchedLines() {
        #expect(headed(1, "one\nt«w»o\nthree") == "one\n# t«w»o\nthree")
    }

    @Test("A #include line is not a heading, so it gains a marker rather than losing one")
    func includeIsNotAHeading() {
        #expect(headed(1, "«»#include") == "# «»#include")
    }

    @Test("The parser reads the result as the heading asked for", arguments: 1...6)
    func parserAgrees(level: Int) {
        let (text, selection) = unpack("Tit«»le")
        let result = MarkdownFormatting.setHeading(level: level, in: text, selection: selection).applied(to: text)
        #expect(DocumentParser.parse(result).first?.headingLevel == level)
    }
}

@Suite("Formatting: bullets")
struct BulletFormattingTests {

    @Test("A bullet goes in front of a line")
    func addsBullet() {
        #expect(bulleted("it«»em") == "- it«»em")
    }

    @Test("A bulleted line loses its bullet")
    func removesBullet() {
        #expect(bulleted("- it«»em") == "it«»em")
        #expect(bulleted("* it«»em") == "it«»em")
    }

    @Test("Indentation is kept, since it sets the list's depth")
    func keepsIndent() {
        #expect(bulleted("    it«»em") == "    - it«»em")
        #expect(bulleted("    - it«»em") == "    it«»em")
    }

    @Test("A numbered item becomes a bullet instead of gaining one")
    func numberedBecomesBullet() {
        #expect(bulleted("1. it«»em") == "- it«»em")
    }

    @Test("Several lines are bulleted together, and blank lines between are left alone")
    func severalLines() {
        #expect(bulleted("«one\n\ntwo»") == "«- one\n\n- two»")
    }

    @Test("If only some lines are bulleted, the rest gain bullets")
    func mixedAddsToTheRest() {
        #expect(bulleted("«- one\ntwo»") == "«- one\n- two»")
    }

    @Test("A triple-click selection, newline included, doesn't reach the next line")
    func trailingNewline() {
        #expect(bulleted("«one\n»two") == "«- one\n»two")
    }
}

@Suite("Formatting: code blocks")
struct CodeBlockFormattingTests {

    @Test("An empty block opens with the caret on its first line")
    func emptyBlock() {
        #expect(fenced(.cpp, "«»") == "```cpp\n«»\n```")
    }

    @Test("A block started mid-line gets lines of its own")
    func midLine() {
        #expect(fenced(.python, "notes «»more") == "notes \n```python\n«»\n```\nmore")
    }

    @Test("Selected lines become the block's contents")
    func wrapsSelection() {
        #expect(fenced(.java, "above\n«int x;\nint y;»\nbelow") == "above\n```java\n«int x;\nint y;»\n```\nbelow")
    }

    @Test("No language leaves the fence untagged")
    func untagged() {
        #expect(fenced(nil, "«»") == "```\n«»\n```")
    }

    @Test("The parser reads the result as one code block in the language asked for")
    func parserAgrees() {
        let (text, selection) = unpack("notes «»more")
        let result = MarkdownFormatting.insertCodeBlock(language: .cpp, in: text, selection: selection).applied(to: text)
        let code = DocumentParser.parse(result).compactMap(\.codeBlock)

        #expect(code.count == 1)
        #expect(code.first?.infoString == "cpp")
    }
}
