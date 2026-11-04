//
//  MarkerEditingTests.swift
//  NoteCodeTests
//
//  Where the caret stops among hidden markers, and what Backspace does there.
//  Tables, since the rules are pure.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Editing hidden markers")
struct MarkerEditingTests {

    private func stop(_ text: String, _ offset: Int, _ direction: Int = 0) -> Int {
        let ns = text as NSString
        return MarkdownFormatting.caretStop(
            for: offset, direction: direction, in: ns, codeRanges: DocumentCache().codeRanges(for: text)
        )
    }

    // `Keep **load factor** low`: the opening `**` is [5, 7), the closing [18, 20).
    static let bold = "Keep **load factor** low"

    @Test("An inline stretch is one stop, at its left edge, for a tap")
    func tapStops() {
        // Opening markers: 5 is before them (outside the bold), 6 and 7 are the same place as 5.
        #expect(stop(Self.bold, 5) == 5)
        #expect(stop(Self.bold, 6) == 5)
        #expect(stop(Self.bold, 7) == 5)
        // Closing markers: 18 is the end of the bold word (inside it); 19 and 20 are the same place.
        #expect(stop(Self.bold, 18) == 18)
        #expect(stop(Self.bold, 19) == 18)
        #expect(stop(Self.bold, 20) == 18)
        // Away from the markers nothing moves.
        for offset in [0, 4, 8, 12, 17, 21, 24] { #expect(stop(Self.bold, offset) == offset, "offset \(offset)") }
    }

    @Test("Arrow keys leave a stretch the way they came in")
    func arrows() {
        // Right from the opening stop: UIKit steps to 6. One visible place on is 8, after the `l`.
        #expect(stop(Self.bold, 6, +1) == 8)
        // Right from the closing stop: UIKit steps to 19. One visible place on is 21, after the space.
        #expect(stop(Self.bold, 19, +1) == 21)
        // Left from just past the closing markers: UIKit steps to 20, which is the stop.
        #expect(stop(Self.bold, 20, -1) == 18)
        // Left from just past the opening markers: UIKit steps to 7, which is the stop.
        #expect(stop(Self.bold, 7, -1) == 5)
    }

    @Test("At the end of a line the caret can go just past the closing markers, the one way out of bold there")
    func lineEnd() {
        let text = "Keep **load factor**"
        #expect(stop(text, 19, +1) == 20, "right from inside the bold at the line's end exits it")
        #expect(stop(text, 20, +1) == 20, "and the caret then stays outside")
        #expect(stop(text, 20) == 18, "a tap there is inside the bold")
        #expect(stop(text, 19, -1) == 18)
    }

    @Test("A heading's stop is after its marker, whatever way the caret arrives")
    func headingStops() {
        let text = "intro\n## Hash tables\nbody"
        let line = 6
        for offset in line...(line + 3) { #expect(stop(text, offset) == line + 3, "tap at \(offset)") }
        #expect(stop(text, line, +1) == line + 3, "down or right onto the line lands after the marker")
        #expect(stop(text, line + 2, -1) == line - 1, "left from the stop goes to the end of the line above")
        #expect(stop("# Title", 1, -1) == 2, "nowhere above to go: stay at the stop")
        #expect(stop(text, line + 3) == line + 3)
        #expect(stop(text, line + 8) == line + 8)
    }

    @Test("A checklist item's stop is after its box")
    func checklistStops() {
        let text = "- [ ] buy milk"
        for offset in 0...6 { #expect(stop(text, offset) == 6, "tap at \(offset)") }
        #expect(stop(text, 7) == 7)
        let nested = "  - [x] done"
        for offset in 2...8 { #expect(stop(nested, offset) == 8, "tap at \(offset)") }
        #expect(stop(nested, 1) == 1, "the indentation is ordinary text")
    }

    @Test("Touching markers are one stretch, and a heading's marker pins before an opening marker")
    func merged() {
        let text = "**a**[b](c) end"
        // `**` [0,2), `**` [3,5) and `[` [5,6): the closing `**` and the link's `[` touch.
        #expect(stop(text, 4) == 3)
        #expect(stop(text, 5) == 3)
        #expect(stop(text, 6) == 3)
        let heading = "# **Title** x"
        #expect(stop(heading, 0) == 2, "the heading's marker pins after itself, ahead of the bold's")
        #expect(stop(heading, 3) == 2)
    }

    @Test("Code blocks, plain text and bullets are left alone")
    func untouched() {
        let code = "```\n**not bold**\n```\nafter"
        for offset in 4...(4 + 14) { #expect(stop(code, offset) == offset, "offset \(offset)") }
        #expect(stop("a * b * c", 3) == 3)
        #expect(stop("- an item", 1) == 1)
        #expect(stop("1. an item", 1) == 1)
        #expect(stop("", 0) == 0)
        #expect(stop("**x**", 5) == 3, "past the markers at the end of the note, by a tap")
    }

    @Test("Links hide their brackets and address; the text is inside")
    func links() {
        let text = "see [the notes](https://a.b/c) now"
        // `[` is [4,5), `](https://a.b/c)` is [14,30).
        #expect(stop(text, 5) == 4)
        #expect(stop(text, 14) == 14)
        #expect(stop(text, 22) == 14)
        #expect(stop(text, 30) == 14)
        #expect(stop(text, 31) == 31)
        let bare = "go to https://a.b/c now"
        #expect(stop(bare, 12) == 12, "a bare address shows exactly as typed")
    }

    // MARK: Backspace

    private func backspace(_ text: String, _ caret: Int) -> String? {
        let ns = text as NSString
        guard let edit = MarkdownFormatting.backspace(at: caret, in: ns, codeRanges: DocumentCache().codeRanges(for: text)) else { return nil }
        let result = edit.applied(to: text)
        return result + "|\(edit.selection.location)"
    }

    @Test("At the start of a heading's text, Backspace removes the marker")
    func backspaceHeading() {
        #expect(backspace("## Title", 3) == "Title|0")
        #expect(backspace("intro\n# Title\nx", 8) == "intro\nTitle\nx|6")
        #expect(backspace("# ", 2) == "|0")
        #expect(backspace("## Title", 5) == nil, "elsewhere it is an ordinary Backspace")
    }

    @Test("At the start of a list item's text, Backspace removes the marker and keeps the indentation")
    func backspaceList() {
        #expect(backspace("- item", 2) == "item|0")
        #expect(backspace("  - item", 4) == "  item|2")
        #expect(backspace("3. item", 3) == "item|0")
        #expect(backspace("- [ ] item", 6) == "item|0")
        #expect(backspace("- [x] ", 6) == "|0")
        #expect(backspace("- item", 4) == nil)
    }

    @Test("Into a closing marker, Backspace deletes the last visible character inside the span")
    func backspaceSpan() {
        // `Keep **load factor** low`: content [7,18).
        #expect(backspace(Self.bold, 18) == "Keep **load facto** low|17")
        #expect(backspace(Self.bold, 19) == "Keep **load facto** low|17", "inside the markers")
        #expect(backspace(Self.bold, 20) == "Keep **load facto** low|17", "just past them, which the page can't tell from the end of the word")
        #expect(backspace(Self.bold, 21) == nil, "after the space is an ordinary Backspace")
        #expect(backspace(Self.bold, 5) == nil, "before the opening markers too")
        #expect(backspace("a `x` b", 5) == "a  b|2", "an emptied span takes its markers with it")
        #expect(backspace("**é**", 3) == "|0")
        #expect(backspace("**ab**", 4) == "**a**|3")
        #expect(backspace("~~old~~", 6) == "~~ol~~|4")
        #expect(backspace("see [ab](http://x.y)", 8) == "see [a](http://x.y)|6")
        #expect(backspace("see [a](http://x.y)", 7) == "see |4", "a one-letter link goes whole")
        #expect(backspace("x **👍🏽** y", 8) == "x  y|2", "a skin-toned emoji is one character")
    }

    @Test("Backspace in a code block is the ordinary one")
    func backspaceInCode() {
        #expect(backspace("```\n**x**\n```", 8) == nil)
        #expect(backspace("```\n# x", 7) == nil)
    }
}

// MARK: - Lists, boxes, links and the state at the caret

@Suite("Lists, boxes and links")
struct ListEditingTests {

    private func codeRanges(_ text: String) -> [CodeRange] { DocumentCache().codeRanges(for: text) }

    /// The text after Return at `|`, with the caret marked. `nil` for a plain newline.
    private func returned(_ marked: String, rendered: Bool = false) -> String? {
        let caret = (marked as NSString).range(of: "|").location
        let text = marked.replacingOccurrences(of: "|", with: "")
        guard let edit = MarkdownFormatting.returnEdit(
            in: text as NSString, caret: caret, rendered: rendered, codeRanges: codeRanges(text)
        ) else { return nil }
        var result = edit.applied(to: text) as NSString
        result = result.replacingCharacters(in: NSRange(location: edit.selection.location, length: 0), with: "|") as NSString
        return result as String
    }

    @Test("Return in a list item continues it, with the text after the caret", arguments: [
        ("- one|", "- one\n- |"),
        ("* one|", "* one\n* |"),
        ("+ one|", "+ one\n+ |"),
        ("  - nested|", "  - nested\n  - |"),
        ("1. one|", "1. one\n2. |"),
        ("9) nine|", "9) nine\n10) |"),
        ("- [ ] todo|", "- [ ] todo\n- [ ] |"),
        ("- [x] done|", "- [x] done\n- [ ] |"),
        ("* [x] done|", "* [x] done\n* [ ] |"),
        ("- **bold**|", "- **bold**\n- |"),
    ])
    func continues(_ marked: String, _ expected: String) {
        #expect(returned(marked) == expected)
    }

    @Test("Whatever follows the caret moves to the new item")
    func splits() {
        #expect(returned("- one|two") == "- one\n- |two")
        #expect(returned("1. one|two") == "1. one\n2. |two")
        #expect(returned("- [x] one|two") == "- [x] one\n- [ ] |two")
    }

    @Test("Return on an empty item ends the list", arguments: [
        ("- |", "|"),
        ("1. |", "|"),
        ("- [ ] |", "|"),
        ("  - |", "|"),
        ("- [x]|", "|"),
    ])
    func ends(_ marked: String, _ expected: String) {
        #expect(returned(marked) == expected)
    }

    @Test("Return elsewhere is a plain newline")
    func plain() {
        #expect(returned("plain text|") == nil)
        #expect(returned("# Heading|") == nil)
        #expect(returned("|- item") == nil, "in front of the marker, nothing continues")
        #expect(returned("```\n- in code|\n```") == nil)
    }

    @Test("In a rendered note, Return at the end of bold goes after its closing markers")
    func returnAfterBold() {
        // The caret is in front of the hidden `**`, where the page shows the end of the word.
        #expect(returned("**word|**", rendered: true) == "**word**\n|")
        #expect(returned("a `code|`", rendered: true) == "a `code`\n|")
        #expect(returned("# **Title|**", rendered: true) == "# **Title**\n|")
        #expect(returned("**word|**", rendered: false) == nil, "legacy: the caret is where it looks")
        #expect(returned("**wo|rd**", rendered: true) == nil, "mid-word is a plain newline")
        #expect(returned("**word|** more", rendered: true) == nil, "mid-line markers aren't at the end")
        #expect(returned("- **word|**", rendered: true) == "- **word**\n- |", "and a list continues after them")
    }

    // MARK: Nesting

    private func indented(_ text: String, _ selection: NSRange, outdent: Bool = false) -> String? {
        guard let edit = MarkdownFormatting.indent(
            in: text as NSString, selection: selection, outdent: outdent, codeRanges: codeRanges(text)
        ) else { return nil }
        return edit.applied(to: text) + "|\(edit.selection.location),\(edit.selection.length)"
    }

    @Test("Tab nests an item two spaces and ⇧Tab takes it back")
    func nesting() {
        #expect(indented("- one", NSRange(location: 5, length: 0)) == "  - one|7,0")
        #expect(indented("  - one", NSRange(location: 7, length: 0), outdent: true) == "- one|5,0")
        #expect(indented("\t- one", NSRange(location: 6, length: 0), outdent: true) == "- one|5,0")
        #expect(indented("- one", NSRange(location: 3, length: 0), outdent: true) == nil, "nothing to take back")
        #expect(indented(" - one", NSRange(location: 6, length: 0), outdent: true) == "- one|5,0", "one space")
        #expect(indented("1. one\n- two", NSRange(location: 0, length: 12)) == "  1. one\n  - two|0,16")
        #expect(indented("- a\n\n- b", NSRange(location: 0, length: 8)) == "  - a\n\n  - b|0,12", "blank lines are left alone")
    }

    @Test("Tab is left alone outside a list, and in code")
    func tabElsewhere() {
        #expect(indented("plain", NSRange(location: 5, length: 0)) == nil)
        #expect(indented("- a\nplain", NSRange(location: 0, length: 9)) == nil, "a mixed selection")
        #expect(indented("```\n- a\n```", NSRange(location: 6, length: 0)) == nil)
    }

    // MARK: List menu

    private func listed(_ style: MarkdownFormatting.ListStyle, _ text: String, _ selection: NSRange) -> String {
        MarkdownFormatting.toggleList(style, in: text, selection: selection).applied(to: text)
    }

    @Test("Numbered and Checklist make, change and remove lists")
    func listMenu() {
        #expect(listed(.numbered, "one\ntwo\nthree", NSRange(location: 0, length: 13)) == "1. one\n2. two\n3. three")
        #expect(listed(.checklist, "one\ntwo", NSRange(location: 0, length: 7)) == "- [ ] one\n- [ ] two")
        #expect(listed(.numbered, "- a\n- b", NSRange(location: 0, length: 7)) == "1. a\n2. b", "a bullet list becomes numbered")
        #expect(listed(.checklist, "- a\n1. b", NSRange(location: 0, length: 8)) == "- [ ] a\n- [ ] b")
        #expect(listed(.numbered, "1. a\n2. b", NSRange(location: 0, length: 9)) == "a\nb", "again takes it off")
        #expect(listed(.checklist, "- [ ] a\n- [x] b", NSRange(location: 0, length: 15)) == "a\nb")
        #expect(listed(.bullet, "- [ ] a", NSRange(location: 0, length: 7)) == "- a", "a checklist item becomes a bullet")
        #expect(listed(.numbered, "a\n\nb", NSRange(location: 0, length: 4)) == "1. a\n\n2. b", "blank lines don't count")
    }

    // MARK: Boxes

    @Test("Toggling a box changes one character and keeps the caret")
    func toggle() {
        let text = "intro\n- [ ] one\n  - [x] two\n- plain"
        func toggled(_ offset: Int) -> String? {
            MarkdownFormatting.toggleCheckbox(onLineAt: offset, in: text as NSString, keeping: NSRange(location: 3, length: 0))
                .map { $0.applied(to: text) }
        }
        #expect(toggled(8) == "intro\n- [x] one\n  - [x] two\n- plain")
        #expect(toggled(20) == "intro\n- [ ] one\n  - [ ] two\n- plain")
        #expect(toggled(2) == nil)
        #expect(toggled(text.count - 2) == nil)
        let edit = MarkdownFormatting.toggleCheckbox(onLineAt: 8, in: text as NSString, keeping: NSRange(location: 3, length: 0))
        #expect(edit?.selection == NSRange(location: 3, length: 0))
        #expect(edit?.range.length == 1)
    }

    // MARK: Links

    @Test("A line's links, as typed")
    func links() {
        let text = "see [the notes](https://a.b/c) and https://x.y/z. Also `[no](x)`"
        let found = MarkdownFormatting.links(onLineAt: 3, in: text as NSString, codeRanges: [])
        #expect(found.map(\.destination) == ["https://a.b/c", "https://x.y/z"])
        #expect((text as NSString).substring(with: found[0].text) == "the notes")
        #expect((text as NSString).substring(with: found[1].text) == "https://x.y/z")
        #expect(MarkdownFormatting.links(onLineAt: 2, in: "```\n[a](b)\n```" as NSString, codeRanges: codeRanges("```\n[a](b)\n```")).isEmpty)
    }

    @Test("What a link opens")
    func linkURLs() {
        #expect(LinkTarget.url(for: "https://example.com/a?b=c")?.absoluteString == "https://example.com/a?b=c")
        #expect(LinkTarget.url(for: "http://example.com")?.absoluteString == "http://example.com")
        #expect(LinkTarget.url(for: "example.com/notes")?.absoluteString == "https://example.com/notes")
        #expect(LinkTarget.url(for: "mailto:me@example.com") != nil)
        #expect(LinkTarget.url(for: "javascript:alert(1)") == nil)
        #expect(LinkTarget.url(for: "file:///etc/passwd") == nil)
        #expect(LinkTarget.url(for: "") == nil)
    }

    // MARK: State at the caret

    private func state(_ marked: String, selection length: Int = 0) -> MarkdownFormatting.CaretFormatting {
        let caret = (marked as NSString).range(of: "|").location
        let text = marked.replacingOccurrences(of: "|", with: "")
        return MarkdownFormatting.formatting(
            at: NSRange(location: caret, length: length), in: text as NSString, codeRanges: DocumentCache().codeRanges(for: text)
        )
    }

    @Test("The hotbar lights what the caret is in")
    func caretState() {
        #expect(state("Keep **load| factor** low").bold)
        #expect(state("Keep **load factor|** low").bold, "the end of a bold word is bold")
        #expect(!state("Keep |**load factor** low").bold, "the start of one isn't")
        #expect(!state("Keep **load factor**| low").bold, "past the markers, as typing there is plain")
        #expect(state("a *it|* b").italic)
        #expect(state("a `co|de` b").code)
        #expect(state("a ~~go|ne~~ b").strikethrough)
        #expect(state("see [the no|tes](http://a.b)").link)
        #expect(state("# Head|ing").headingLevel == 1)
        #expect(state("### Head|ing").headingLevel == 3)
        #expect(state("- ite|m").list == .bullet)
        #expect(state("3. ite|m").list == .numbered)
        #expect(state("- [ ] ite|m").list == .checklist)
        // Nothing lit; the size control reads body text, and has a word to size.
        var plain = MarkdownFormatting.CaretFormatting()
        plain.sizes = [MarkdownFormatting.SizeSample(headingLevel: 0, size: nil)]
        plain.canResize = true
        #expect(state("plain| text") == plain)
        // Code has no inline formatting, though the row now knows it is in code.
        var inCode = MarkdownFormatting.CaretFormatting()
        inCode.block = .code(label: "Code", kind: .plain, isClosed: true)
        #expect(state("```\n**x|**\n```") == inCode, "code has no formatting")
        #expect(!state("**a** b *c|*").bold)
    }

    @Test("A selection is bold when every letter in it is, which is when Bold takes it off")
    func selectionState() {
        let text = "Keep **load factor** low"
        func bold(_ range: NSRange, in text: String = text) -> Bool {
            MarkdownFormatting.formatting(at: range, in: text as NSString, codeRanges: []).bold
        }
        #expect(bold(NSRange(location: 7, length: 4)))
        #expect(bold(NSRange(location: 7, length: 11)))
        #expect(!bold(NSRange(location: 0, length: 11)), "reaching outside the span")
        #expect(bold(NSRange(location: 7, length: 14)), "the space after it doesn't count")
        #expect(!bold(NSRange(location: 7, length: 15)), "the l of low does")

        // Two bold words and the space between: every letter is bold.
        let two = "**a** **b**\n**c**"
        #expect(bold(NSRange(location: 0, length: 11), in: two))
        #expect(bold(NSRange(location: 0, length: (two as NSString).length), in: two), "over lines")
        #expect(MarkdownFormatting.toggle(.bold, in: two, selection: NSRange(location: 0, length: 11))?.applied(to: two) == "a b\n**c**")
    }
}
