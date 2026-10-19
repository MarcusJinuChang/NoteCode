//
//  TypingStyleTests.swift
//  NoteCodeTests
//
//  Text overhaul, phase 4 (docs/text-system-overhaul.md, decision 5): a
//  button with no word to act on sets the typing style, and the next text
//  typed is written with it.
//

import Foundation
import Testing
@testable import NoteCode

// MARK: - Where a press goes, and what typed text is written as

@Suite("Typing style: where a press goes")
struct TypingStyleRuleTests {

    static let red = StyledLineTests.red
    static let close = SpanStyle.close

    /// `|` marks the caret.
    static func target(_ marked: String, code: [CodeRange] = []) -> MarkdownFormatting.CaretTarget {
        let caret = (marked as NSString).range(of: "|").location
        let text = marked.replacingOccurrences(of: "|", with: "")
        return MarkdownFormatting.caretTarget(at: caret, in: text as NSString, codeRanges: code)
    }

    @Test("A caret strictly inside a word is the word's; a word's ends, between words and a blank line are the typing style's")
    func caretTargets() {
        #expect(Self.target("hel|lo there") == .word)
        #expect(Self.target("a **bo|ld** b") == .word, "markers around the word don't count")
        #expect(Self.target("snake_c|ase") == .word, "the underscore is part of a word")
        #expect(Self.target("hello| there") == .typing, "a word's end")
        #expect(Self.target("hello |there") == .typing, "a word's start")
        #expect(Self.target("hello |") == .typing, "after a space at a line's end")
        #expect(Self.target("hello|") == .typing, "at a line's end")
        #expect(Self.target("hello  | there") == .typing, "between words")
        #expect(Self.target("|") == .typing, "a blank line")
        #expect(Self.target("one\n|\ntwo") == .typing, "a blank line among others")
        #expect(Self.target("# Ti|tle") == .word)
        #expect(Self.target("# Title|") == .typing)
        #expect(Self.target("- ite|m") == .word)
        #expect(Self.target("- |") == .typing, "an empty list item")
    }

    @Test("In code, in a line's marker and at the edge of a link or inline code there is nothing to do")
    func nothing() {
        let text = "prose\n```cpp\nint x;\n```\n"
        let code = [CodeRange(range: NSRange(location: 6, length: 18), isClosed: true, language: .cpp, tag: "cpp")]
        #expect(MarkdownFormatting.caretTarget(at: 15, in: text as NSString, codeRanges: code) == .nothing)
        #expect(MarkdownFormatting.caretTarget(at: 3, in: text as NSString, codeRanges: code) == .word, "prose above is still prose")
        #expect(Self.target("## |Title") == .typing, "after a heading's marker")
        #expect(MarkdownFormatting.caretTarget(at: 1, in: "## Title" as NSString, codeRanges: []) == .nothing, "inside the marker")
        #expect(Self.target("see [the note|](u) now") == .nothing, "typed there would join the link")
        #expect(Self.target("call `push_back|` here") == .nothing, "or the code")
        #expect(Self.target("see [the no|te](u) now") == .word, "inside a word of the link it acts on the link")
    }

    @Test("A colour or size with a caret inside a word acts on that word, not the run it is in")
    func wordNotRun() throws {
        let tag = SpanStyle(colour: Self.red).openTag
        let text = "\(tag)one two\(Self.close)"
        let caret = NSRange(location: (text as NSString).range(of: "two").location + 1, length: 0)
        let edit = try #require(MarkdownFormatting.colour(StyledLineTests.blue, selection: caret, in: text as NSString, codeRanges: []))
        let result = edit.applied(to: text)
        #expect(StyledLineTests.drawn(result) == ["o#E5484D", "n#E5484D", "e#E5484D", " #E5484D", "t#3B82F6", "w#3B82F6", "o#3B82F6"])
    }

    @Test("A caret off a word changes no text, from the colour and the size either")
    func offAWord() {
        let text = "hello " as NSString
        let caret = NSRange(location: 6, length: 0)
        #expect(MarkdownFormatting.colour(Self.red, selection: caret, in: text, codeRanges: []) == nil)
        #expect(MarkdownFormatting.size(points: 24, blockSizes: StyledLineTests.blockSizes, selection: caret, in: text, codeRanges: []) == nil)
    }

    // MARK: Typed text

    /// The note with `run` just typed at the `|`, written with `typing`, and
    /// where the caret is: `nil` where there is no edit.
    static func typed(
        _ marked: String, run: String, _ typing: TypingStyle, code: [CodeRange] = []
    ) -> String? {
        let caret = (marked as NSString).range(of: "|").location
        let before = marked.replacingOccurrences(of: "|", with: "")
        let text = (before as NSString).replacingCharacters(in: NSRange(location: caret, length: 0), with: run)
        let range = NSRange(location: caret, length: (run as NSString).length)
        guard let edit = MarkdownFormatting.typed(
            typing, run: range, in: text as NSString, blockSizes: StyledLineTests.blockSizes, codeRanges: code
        ) else { return nil }
        let result = edit.applied(to: text)
        return (result as NSString).replacingCharacters(in: NSRange(location: edit.selection.location, length: 0), with: "|")
    }

    static let bold = TypingStyle(bold: true)

    @Test("Text typed after a space is written in the style, the caret inside its closing marker")
    func typedAfterASpace() {
        #expect(Self.typed("hello |", run: "w", Self.bold) == "hello **w|**")
        #expect(Self.typed("hello |", run: "wor", Self.bold) == "hello **wor|**")
        #expect(Self.typed("hello |", run: "w", TypingStyle(italic: true)) == "hello *w|*")
        #expect(Self.typed("hello |", run: "w", TypingStyle(strikethrough: true)) == "hello ~~w|~~")
        #expect(Self.typed("hello |", run: "w", TypingStyle(code: true)) == "hello `w|`")
        #expect(Self.typed("|", run: "x", Self.bold) == "**x|**", "on a blank line")
        #expect(Self.typed("# Title |", run: "w", Self.bold) == "# Title **w|**")
        #expect(Self.typed("- item |", run: "w", Self.bold) == "- item **w|**")
        #expect(Self.typed("hello |", run: "👩‍💻", Self.bold) == "hello **👩‍💻|**")
    }

    @Test("Text typed beside a word, or in the middle of a line, goes in as its own")
    func typedBesideAWord() {
        #expect(Self.typed("hello|", run: "x", Self.bold) == "hello**x|**")
        #expect(Self.typed("hello| world", run: "x", Self.bold) == "hello**x|** world")
        #expect(Self.typed("hello |world", run: "x", Self.bold) == "hello **x|**world")
    }

    @Test("Text already drawn in the style is left as it is")
    func alreadyStyled() {
        #expect(Self.typed("**w|**", run: "o", Self.bold) == nil)
        #expect(Self.typed("**hello wor|**", run: "l", Self.bold) == nil)
        #expect(Self.typed("hello|", run: "w", TypingStyle(bold: false)) == nil, "plain text, bold off")
    }

    @Test("Bold off at the end of a bold word: the text typed goes outside it")
    func styleOff() {
        #expect(Self.typed("**hello|**", run: "x", TypingStyle(bold: false)) == "**hello**x|")
        #expect(Self.typed("**hello|**", run: "x", TypingStyle(colour: .clear)) == nil, "nothing to take off")
        let tag = SpanStyle(colour: Self.red).openTag
        #expect(Self.typed("\(tag)hello|\(Self.close)", run: "x", TypingStyle(colour: .clear)) == "\(tag)hello\(Self.close)x|")
    }

    @Test("A space can't end bold, so it goes outside it; the next text brings the style back across the space")
    func spaces() {
        #expect(Self.typed("**hello|**", run: " ", Self.bold) == "**hello** |")
        #expect(Self.typed("**hello** |", run: "w", Self.bold) == "**hello w|**", "one bold, not a bold word, a space and a bold word")
        #expect(Self.typed("**hello**  |", run: "w", Self.bold) == "**hello  w|**")
        // After text that isn't in the style there is nothing to bridge to.
        #expect(Self.typed("hello |", run: "w", Self.bold) == "hello **w|**")
        // Spaces inside a tag are kept.
        let tag = SpanStyle(colour: Self.red).openTag
        #expect(Self.typed("\(tag)hello|\(Self.close)", run: " ", TypingStyle(colour: .set(Self.red))) == nil)
    }

    @Test("A style combines with the text around the caret")
    func combines() {
        #expect(StyledLineTests.drawn(Self.typed("**hello|**", run: "x", TypingStyle(italic: true))!.replacingOccurrences(of: "|", with: ""))
                == ["hB", "eB", "lB", "lB", "oB", "xBI"])
        let tag = SpanStyle(colour: Self.red).openTag
        let result = Self.typed("\(tag)hello|\(Self.close)", run: "x", Self.bold)!.replacingOccurrences(of: "|", with: "")
        #expect(StyledLineTests.drawn(result) == ["h#E5484D", "e#E5484D", "l#E5484D", "l#E5484D", "o#E5484D", "xB#E5484D"])
    }

    @Test("A colour or a size is written as a run, a size in points against the line's own text")
    func colourAndSize() {
        let red = SpanStyle(colour: Self.red).openTag
        #expect(Self.typed("hello |", run: "w", TypingStyle(colour: .set(Self.red))) == "hello \(red)w|\(Self.close)")
        let big = SpanStyle(size: SpanSize(em: 1.412)).openTag
        #expect(Self.typed("hello |", run: "w", TypingStyle(points: .set(24))) == "hello \(big)w|\(Self.close)")
        // 34 is a heading's own size in a heading: no size at all.
        #expect(Self.typed("# Title |", run: "w", TypingStyle(points: .set(34))) == nil)
        #expect(Self.typed("# Title |", run: "w", TypingStyle(points: .set(20))) != nil)
        let both = SpanStyle(colour: Self.red, size: SpanSize(em: 1.412)).openTag
        #expect(Self.typed("hello |", run: "w", TypingStyle(colour: .set(Self.red), points: .set(24))) == "hello \(both)w|\(Self.close)")
        // A size taken off the text typed at the end of a sized run.
        #expect(Self.typed("\(big)hello|\(Self.close)", run: "x", TypingStyle(points: .clear)) == "\(big)hello\(Self.close)x|")
    }

    @Test("Nothing is written for a run that crosses a line, is in code, or joins a link or code")
    func noEdit() {
        #expect(Self.typed("hello |", run: "a\nb", Self.bold) == nil)
        #expect(Self.typed("see [the note|](u) now", run: "x", Self.bold) == nil)
        #expect(Self.typed("call `push|` here", run: "x", Self.bold) == nil)
        #expect(Self.typed("hello |", run: "w", .none) == nil)
        let code = [CodeRange(range: NSRange(location: 6, length: 19), isClosed: true, language: .cpp, tag: "cpp")]
        #expect(Self.typed("prose\n```cpp\nint |;\n```\n", run: "y", Self.bold, code: code) == nil)
    }

    @Test("What can't be written to read as asked is left as typed, never showing its markers")
    func unwritable() throws {
        // `*x_` made bold can't be written (see StyledLine); neither can a
        // star typed against a bold span be bold beside its own stars.
        let marked = "*x|"
        let text = "*x_"
        let edit = MarkdownFormatting.typed(Self.bold, run: NSRange(location: 2, length: 1), in: text as NSString, blockSizes: StyledLineTests.blockSizes, codeRanges: [])
        if let edit {
            let result = edit.applied(to: text)
            let styled = try #require(StyledLine(result), "\(marked) → \(result)")
            #expect(styled.glyphs.map(\.text).joined() == text, "\(result)")
        }
    }

    /// What each keystroke costs while a style is on: the line without the run
    /// read once and the stretch written and read once. The loose bound is for a
    /// busy machine; the measured figure is in AGENTS.md.
    @Test("A keystroke under a typing style costs well under a millisecond")
    func cost() {
        let line = "A fairly long line of ordinary prose with some **bold words** and `code` in it, then more text |"
        let caret = (line as NSString).range(of: "|").location
        let before = line.replacingOccurrences(of: "|", with: "")
        let text = (before as NSString).replacingCharacters(in: NSRange(location: caret, length: 0), with: "w")
        let run = NSRange(location: caret, length: 1)
        let clock = ContinuousClock()
        let rounds = 2000
        var edits = 0
        let elapsed = clock.measure {
            for _ in 0..<rounds {
                if MarkdownFormatting.typed(Self.bold, run: run, in: text as NSString, blockSizes: StyledLineTests.blockSizes, codeRanges: []) != nil { edits += 1 }
            }
        }
        #expect(edits == rounds)
        let perCall = elapsed / rounds
        #expect(perCall < .milliseconds(1), "\(perCall) a keystroke")
    }

    static func characters(of text: String) -> [String] {
        let ns = text as NSString
        var texts: [String] = []
        var position = 0
        while position < ns.length {
            let piece = ns.rangeOfComposedCharacterSequence(at: position)
            texts.append(ns.substring(with: piece))
            position = NSMaxRange(piece)
        }
        return texts
    }

    // MARK: Always reads back

    @Test("Typed text, written with any typing style on any line, reads back as asked and shows no marker")
    func property() throws {
        let pieces = ["a", "b", " ", "x", "é", "*", "**", "_", "~~", "`", "[", "](u)", "https://x.io",
                      SpanStyle(colour: Self.red).openTag, Self.close]
        let runs = ["a", "b", " ", "xy", "é", " a", "a ", "*", "_"]
        var random = NestingInlineTests.Seeded(state: 18_10_2026)
        var edits = 0
        var asked = 0
        for _ in 0..<5000 {
            let text = (0..<Int.random(in: 0...9, using: &random)).map { _ in pieces.randomElement(using: &random)! }.joined()
            guard let before = StyledLine(text) else { continue }
            let index = Int.random(in: 0...before.glyphs.count, using: &random)
            let raw = before.earliestPosition(at: index)
            let run = runs.randomElement(using: &random)!
            let typing = TypingStyle(
                bold: [nil, true, false].randomElement(using: &random)!,
                italic: [nil, true, false].randomElement(using: &random)!,
                strikethrough: [nil, true, false].randomElement(using: &random)!,
                code: [nil, nil, nil, true].randomElement(using: &random)!,
                colour: [nil, .set(Self.red), .clear].randomElement(using: &random)!,
                points: [nil, .set(24), .clear].randomElement(using: &random)!
            )
            guard !typing.isEmpty else { continue }

            let current = (text as NSString).replacingCharacters(in: NSRange(location: raw, length: 0), with: run)
            let range = NSRange(location: raw, length: (run as NSString).length)
            let context = before.typedStyle(at: raw)
            let edit = MarkdownFormatting.typed(
                typing, run: range, in: current as NSString, blockSizes: StyledLineTests.blockSizes, codeRanges: []
            )
            guard let edit else { continue }
            #expect(!context.joinsLinkOrCode, "\(text) + \(run) at \(raw)")
            edits += 1

            let result = edit.applied(to: current)
            let after = try #require(StyledLine(result), "\(text) + \(run) → \(result)")
            let runTexts = Self.characters(of: run)
            #expect(after.glyphs.map(\.text) == before.glyphs.prefix(index).map(\.text) + runTexts + before.glyphs.dropFirst(index).map(\.text),
                    "\(text) + \(run) → \(result)")
            guard after.glyphs.count == before.glyphs.count + runTexts.count else { continue }

            // The caret just after the run, inside what closes behind it.
            #expect(edit.selection.location == after.earliestPosition(at: index + runTexts.count), "\(text) + \(run) → \(result)")

            func plain(_ style: StyledLine.Style, space: Bool) -> StyledLine.Style {
                var style = style
                style.link = style.link.map { StyledLine.Link(id: 0, address: $0.address) }
                if space { (style.bold, style.italic, style.strikethrough) = (false, false, false) }
                return style
            }
            var wanted = context.style
            typing.apply(to: &wanted, headingLevel: before.headingLevel, blockSizes: StyledLineTests.blockSizes)
            var ranAsAsked = true
            for (position, glyph) in after.glyphs.enumerated() {
                let isRun = (index..<(index + runTexts.count)).contains(position)
                let space = glyph.isSpace
                if isRun {
                    let got = plain(glyph.style, space: space)
                    if got != plain(wanted, space: space) {
                        ranAsAsked = false
                        // Or, where it can't be written, as the text around it.
                        #expect(got == plain(context.style, space: space), "\(text) + \(run) → \(result) at \(position)")
                    }
                } else {
                    let old = before.glyphs[position < index ? position : position - runTexts.count]
                    // Spaces next to the run may take the run's style, to join it.
                    guard !old.isSpace else { continue }
                    #expect(plain(glyph.style, space: false) == plain(old.style, space: false), "\(text) + \(run) → \(result) at \(position)")
                }
            }
            if ranAsAsked { asked += 1 }
        }
        #expect(edits > 1500)
        #expect(Double(asked) > Double(edits) * 0.9, "\(asked) of \(edits) were written as asked")
    }
}

#if canImport(UIKit)

import UIKit

// MARK: - In the editor

@Suite("Typing style: in the editor", .serialized)
@MainActor
struct TypingStyleEditorTests {

    typealias Harness = TextRowEditorTests.Harness

    static let red = StyledLineTests.red

    /// The text with `|` at the caret.
    static func shown(_ harness: Harness) -> String {
        let ns = harness.text as NSString
        return ns.replacingCharacters(in: NSRange(location: harness.textView.selectedRange.location, length: 0), with: "|")
    }

    /// What the keyboard does to type: `insertText` on the text view, in a turn
    /// of the run loop of its own, as a key is.
    static func type(_ text: String, into harness: Harness) async {
        harness.textView.insertText(text)
        await harness.nextTap()
    }

    // MARK: Setting it

    @Test("Bold at the end of a line lights the bar and writes nothing")
    func setsWithoutWriting() {
        let harness = Harness("hello |")
        #expect(!harness.editor.formattingShown.bold)
        harness.editor.toggle(.bold)
        #expect(harness.text == "hello ")
        #expect(harness.editor.formattingShown.bold, "the bar shows what the next text typed will be")
        #expect(harness.editor.typingStyle.bold == true)
        harness.editor.toggle(.bold)
        #expect(!harness.editor.formattingShown.bold, "pressed again, it is off")
        #expect(harness.text == "hello ")
    }

    @Test("Bold pressed inside a word is the word's, and sets no typing style")
    func insideAWord() {
        let harness = Harness("hel|lo there")
        harness.editor.toggle(.bold)
        #expect(harness.text == "**hello** there")
        #expect(harness.editor.typingStyle.isEmpty)
    }

    @Test("Pressed at the end of a bold word, Bold turns bold off for the next text")
    func offAtTheEndOfBold() async {
        let harness = Harness("**word|**")
        #expect(harness.editor.formattingShown.bold)
        harness.editor.toggle(.bold)
        #expect(!harness.editor.formattingShown.bold)
        #expect(harness.editor.typingStyle.bold == false)
        await Self.type("x", into: harness)
        #expect(Self.shown(harness) == "**word**x|")
    }

    @Test("Nothing is set in code, in a locked note or in ink mode")
    func nowhere() {
        let code = Harness("```cpp\nint x|;\n```\n")
        code.editor.toggle(.bold)
        #expect(code.editor.typingStyle.isEmpty)
        #expect(code.text == "```cpp\nint x;\n```\n")

        let locked = Harness("hello |")
        locked.editor.setTextLocked(true)
        locked.editor.toggle(.bold)
        #expect(locked.editor.typingStyle.isEmpty)

        let ink = Harness("hello |")
        ink.editor.setMode(.ink)
        ink.editor.toggle(.bold)
        #expect(ink.editor.typingStyle.isEmpty)
    }

    // MARK: Typing

    @Test("The next text typed is written in the style, and what follows carries on in it")
    func typesWithTheStyle() async {
        let harness = Harness("hello |")
        harness.editor.toggle(.bold)
        await Self.type("w", into: harness)
        #expect(Self.shown(harness) == "hello **w|**")
        await Self.type("o", into: harness)
        await Self.type("r", into: harness)
        #expect(Self.shown(harness) == "hello **wor|**")
        #expect(harness.editor.formattingShown.bold)
        // The note's own text agrees with the bar: Bold is lit with no typing style.
        harness.editor.clearTypingStyle()
        harness.coordinator.refreshCaretFormatting(in: harness.textView)
        #expect(harness.editor.formattingShown.bold)
    }

    @Test("A letter and the markers round it are one undo step")
    func oneUndoStep() async {
        let harness = Harness("hello |")
        harness.editor.toggle(.bold)
        await Self.type("w", into: harness)
        #expect(harness.text == "hello **w**")
        harness.editor.undo()
        #expect(harness.text == "hello ", "\(harness.text.debugDescription)")
        harness.editor.redo()
        #expect(harness.text == "hello **w**")
    }

    @Test("A space typed in bold goes outside it, and the next word is bold across it")
    func spacesAndWords() async {
        let harness = Harness("hello |")
        harness.editor.toggle(.bold)
        for piece in ["h", "i", " ", "y", "o"] { await Self.type(piece, into: harness) }
        #expect(Self.shown(harness) == "hello **hi yo|**")
    }

    @Test("Italic, a colour, a size and Code are written the same way")
    func otherStyles() async {
        let italic = Harness("a |")
        italic.editor.toggle(.italic)
        await Self.type("b", into: italic)
        #expect(Self.shown(italic) == "a *b|*")

        let code = Harness("a |")
        code.editor.toggle(.code)
        await Self.type("b", into: code)
        #expect(Self.shown(code) == "a `b|`")

        let colour = Harness("a |")
        colour.editor.setColour(Self.red)
        #expect(colour.editor.formattingShown.colour == Self.red, "the colour menu shows it")
        await Self.type("b", into: colour)
        #expect(Self.shown(colour) == "a \(SpanStyle(colour: Self.red).openTag)b|\(SpanStyle.close)")

        let size = Harness("a |")
        size.editor.setSelectionSize(points: 24)
        #expect(size.editor.selectionTextSize.points == 24, "the size control shows it")
        await Self.type("b", into: size)
        #expect(Self.shown(size) == "a \(SpanStyle(size: SpanSize(em: 1.412)).openTag)b|\(SpanStyle.close)")
    }

    @Test("Bold and a colour together are one run's worth of markers")
    func combined() async {
        let harness = Harness("a |")
        harness.editor.toggle(.bold)
        harness.editor.setColour(Self.red)
        harness.editor.stepSelectionSize(by: 7)
        #expect(harness.editor.typingStyle.points == .set(24))
        await Self.type("bc", into: harness)
        #expect(StyledLineTests.drawn(harness.text) == ["a", " ", "bB#E5484D@1.412em", "cB#E5484D@1.412em"])
    }

    @Test("The size control steps the typing size from the size the text has now")
    func stepsTheTypingSize() async {
        let harness = Harness("# Title |")
        #expect(harness.editor.selectionTextSize.points == 34)
        harness.editor.stepSelectionSize(by: 1)
        harness.editor.stepSelectionSize(by: 1)
        #expect(harness.editor.selectionTextSize.points == 36)
        #expect(harness.text == "# Title ", "the text itself is not resized")
        harness.editor.setSelectionSize(points: nil)
        #expect(harness.editor.selectionTextSize.points == harness.editor.selectionTextSize.ownPoints, "Default")
        await Self.type("x", into: harness)
        #expect(harness.text == "# Title x")
    }

    // MARK: Clearing it

    @Test("A caret moved elsewhere clears it, typing's own caret moves do not")
    func caretMoveClears() async {
        let harness = Harness("hello |")
        harness.editor.toggle(.bold)
        await Self.type("w", into: harness)
        #expect(!harness.editor.typingStyle.isEmpty, "typing moves the caret and keeps the style")
        harness.textView.selectedRange = NSRange(location: 2, length: 0)
        #expect(harness.editor.typingStyle.isEmpty)
        #expect(!harness.editor.formattingShown.bold)
    }

    @Test("A caret moved before anything is typed clears it")
    func caretMoveClearsBeforeTyping() async {
        let harness = Harness("hello |")
        harness.editor.toggle(.bold)
        harness.textView.selectedRange = NSRange(location: 3, length: 0)
        #expect(harness.editor.typingStyle.isEmpty)
        await Self.type("x", into: harness)
        #expect(harness.text == "helxlo ")
    }

    @Test("A selection clears it")
    func selectionClears() {
        let harness = Harness("hello |")
        harness.editor.toggle(.bold)
        harness.textView.selectedRange = NSRange(location: 0, length: 5)
        #expect(harness.editor.typingStyle.isEmpty)
    }

    @Test("A mode switch, the keyboard going away and a lock each clear it")
    func otherClears() {
        // Ink mode and a lock both put the keyboard away, which clears it too
        // (`textViewDidEndEditing`); so the first and last are tried with the
        // text view's delegate away, where only the editor's own rule can.
        let mode = Harness("hello |")
        mode.editor.toggle(.bold)
        mode.textView.delegate = nil
        mode.editor.setMode(.ink)
        #expect(mode.editor.typingStyle.isEmpty)

        let keyboard = Harness("hello |")
        keyboard.editor.toggle(.bold)
        keyboard.coordinator.textViewDidEndEditing(keyboard.textView)
        #expect(keyboard.editor.typingStyle.isEmpty)

        let lock = Harness("hello |")
        lock.editor.toggle(.bold)
        lock.textView.delegate = nil
        lock.editor.setTextLocked(true)
        #expect(lock.editor.typingStyle.isEmpty)
    }

    @Test("Return ends it, and so does a pasted line break")
    func returnClears() async {
        let harness = Harness("hello |")
        harness.editor.toggle(.bold)
        await Self.type("\n", into: harness)
        #expect(harness.editor.typingStyle.isEmpty)
        #expect(harness.text == "hello \n")

        let paste = Harness("hello |")
        paste.editor.toggle(.bold)
        await Self.type("a\nb", into: paste)
        #expect(paste.editor.typingStyle.isEmpty)
        #expect(paste.text == "hello a\nb")
    }

    // MARK: What the keyboard does around it

    @Test("A list's Return, which the app makes, ends it as a typed one does")
    func listReturnClears() {
        let harness = Harness("- item |")
        harness.editor.toggle(.bold)
        let selection = harness.textView.selectedRange
        let allowed = harness.coordinator.textView(harness.textView, shouldChangeTextIn: selection, replacementText: "\n")
        #expect(!allowed, "the coordinator makes the edit itself")
        #expect(harness.text.hasPrefix("- item \n- "))
        #expect(harness.editor.typingStyle.isEmpty)
    }

    @Test("An autocorrect of the word just typed keeps the style on")
    func autocorrect() async {
        let harness = Harness("hello |")
        harness.editor.toggle(.bold)
        for letter in ["t", "e", "h"] { await Self.type(letter, into: harness) }
        #expect(Self.shown(harness) == "hello **teh|**")
        // The keyboard replaces the word it has been following, markers not in it.
        let word = (harness.text as NSString).range(of: "teh")
        _ = harness.coordinator.textView(harness.textView, shouldChangeTextIn: word, replacementText: "the")
        harness.textView.replace(harness.textView.textRange(from: harness.textView.position(from: harness.textView.beginningOfDocument, offset: word.location)!, to: harness.textView.position(from: harness.textView.beginningOfDocument, offset: NSMaxRange(word))!)!, withText: "the")
        await harness.nextTap()
        #expect(Self.shown(harness) == "hello **the|**")
        await Self.type(" ", into: harness)
        #expect(Self.shown(harness) == "hello **the** |")
        await Self.type("a", into: harness)
        #expect(Self.shown(harness) == "hello **the a|**")
    }

    @Test("An autocorrect of the word behind the caret is not taken for text typed")
    func autocorrectBehind() async {
        let harness = Harness("teh|")
        harness.editor.toggle(.bold)
        #expect(harness.editor.typingStyle.bold == true, "a word's end is the typing style's")
        // The keyboard corrects the word on the space, and the word grows.
        let range = NSRange(location: 0, length: 3)
        _ = harness.coordinator.textView(harness.textView, shouldChangeTextIn: range, replacementText: "they")
        harness.textView.replace(harness.textView.textRange(from: harness.textView.beginningOfDocument, to: harness.textView.endOfDocument)!, withText: "they")
        await harness.nextTap()
        #expect(harness.text == "they", "the y the keyboard added isn't typed text: \(harness.text)")
    }

    @Test("A composition that replaces the character before the caret, as Korean does, goes on inside the markers")
    func koreanComposition() async {
        let harness = Harness("a |")
        harness.editor.toggle(.bold)
        await Self.type("ㅎ", into: harness)
        #expect(Self.shown(harness) == "a **ㅎ|**")
        // 하: the keyboard replaces ㅎ, with the caret after it. 한 the same.
        for syllable in ["하", "한"] {
            let start = harness.textView.position(from: harness.textView.beginningOfDocument, offset: 4)!
            let end = harness.textView.position(from: start, offset: 1)!
            harness.textView.replace(harness.textView.textRange(from: start, to: end)!, withText: syllable)
            await harness.nextTap()
            #expect(Self.shown(harness) == "a **\(syllable)|**")
        }
        await Self.type("ㄱ", into: harness)
        #expect(Self.shown(harness) == "a **한ㄱ|**")
    }

    @Test("Marked text is the keyboard's until it commits: the style goes on at the commit")
    func markedText() async {
        let harness = Harness("a |")
        harness.editor.toggle(.bold)
        harness.textView.setMarkedText("ひ", selectedRange: NSRange(location: 1, length: 0))
        harness.textView.setMarkedText("ひら", selectedRange: NSRange(location: 2, length: 0))
        await harness.nextTap()
        #expect(harness.text == "a ひら", "nothing is written into the composition")
        harness.textView.unmarkText()
        await harness.nextTap()
        #expect(Self.shown(harness) == "a **ひら|**")
        #expect(harness.textView.markedTextRange == nil)
    }

    @Test("An edit of the app's own, a heading, moves the place and is not taken for typing")
    func headingIsNotTyping() async {
        let harness = Harness("hello |")
        harness.editor.toggle(.bold)
        harness.editor.setHeading(level: 1)
        #expect(harness.text == "# hello ")
        #expect(!harness.editor.typingStyle.isEmpty)
        await Self.type("w", into: harness)
        #expect(Self.shown(harness) == "# hello **w|**")
    }

    @Test("Undo takes the style's text back, and typing after it is plain")
    func undoThenType() async {
        let harness = Harness("hello |")
        harness.editor.toggle(.bold)
        await Self.type("w", into: harness)
        harness.editor.undo()
        #expect(harness.text == "hello ")
        harness.editor.clearTypingStyle()
        await Self.type("z", into: harness)
        #expect(harness.text == "hello z")
    }
}

#endif
