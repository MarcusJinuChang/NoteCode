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

private func toggled(_ style: MarkdownFormatting.InlineStyle, _ marked: String) -> String {
    run(marked) { MarkdownFormatting.toggle(style, in: $0, selection: $1) }
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
    func parserAgrees(style: MarkdownFormatting.InlineStyle) {
        let (text, selection) = unpack("a «word» b")
        let result = MarkdownFormatting.toggle(style, in: text, selection: selection).applied(to: text)
        let kinds = InlineParser.parse(result, in: result.startIndex..<result.endIndex).map(\.kind)

        #expect(kinds == [.text, style.kind, .text])
    }

    @Test("Pressing again removes the style", arguments: MarkdownFormatting.InlineStyle.allCases)
    func roundTrips(style: MarkdownFormatting.InlineStyle) {
        let once = toggled(style, "a «word» b")
        #expect(toggled(style, once) == "a «word» b")
    }

    @Test("A caret anywhere inside a span removes the whole span")
    func caretInsideRemoves() {
        #expect(toggled(.bold, "a **wo«»rd** b") == "a wo«»rd b")
        #expect(toggled(.bold, "a **«»word** b") == "a «»word b")
        #expect(toggled(.bold, "a **word«»** b") == "a word«» b")
    }

    @Test("Selecting a span with its markers removes them")
    func selectingMarkersRemoves() {
        #expect(toggled(.bold, "a «**word**» b") == "a «word» b")
    }

    @Test("A different style replaces the span's markers, since spans don't nest")
    func otherStyleReplaces() {
        #expect(toggled(.italic, "a **«word»** b") == "a *«word»* b")
        #expect(toggled(.strikethrough, "a *wo«»rd* b") == "a ~~wo«»rd~~ b")
    }

    @Test("Italic inside bold is not mistaken for italic already present")
    func italicIsNotBold() {
        // `**word**` has a single star either side of the selection as well.
        // Reading that as italic would strip one star each side and leave
        // `*word*` — italic, when the button asked for italic *added*.
        #expect(toggled(.italic, "**«word»**") == "*«word»*")
    }

    @Test("With nothing selected, an empty pair goes in with the caret between")
    func emptyPair() {
        #expect(toggled(.bold, "a «»b") == "a **«»**b")
        #expect(toggled(.strikethrough, "«»") == "~~«»~~")
    }

    @Test("Pressing again on an empty pair takes it back out")
    func emptyPairRemoves() {
        #expect(toggled(.bold, "a **«»**b") == "a «»b")
        #expect(toggled(.italic, "*«»*") == "«»")
    }

    @Test("An empty bold pair isn't read as an empty italic pair")
    func emptyBoldIsNotItalic() {
        #expect(toggled(.italic, "**«»**") == "***«»***")
    }

    @Test("Several lines are styled one line at a time, skipping blank ones")
    func acrossLines() {
        #expect(toggled(.bold, "«one\n\ntwo»") == "«**one**\n\n**two**»")
    }

    @Test("Several lines that all carry the style lose it")
    func acrossLinesRemoves() {
        #expect(toggled(.bold, "«**one**\n**two**»") == "«one\ntwo»")
    }

    @Test("Several lines with the style on only some gain it on the rest")
    func acrossLinesMixed() {
        #expect(toggled(.bold, "«**one**\ntwo»") == "«**one**\n**two**»")
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
