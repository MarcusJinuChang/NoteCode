//
//  InlineMarksTests.swift
//  NoteCodeTests
//
//  Text overhaul, phase 6: underline, `<u>text</u>`, and highlight,
//  `==🟡text==`. Reading, writing, drawing, and the colours' legibility.
//

import Foundation
import Testing
@testable import NoteCode

private func nodes(_ line: String) -> [InlineNode] {
    InlineParser.parse(line, in: line.startIndex..<line.endIndex)
}

/// The text a line shows, each run with what it is drawn with.
private func drawn(_ line: String) -> [(text: String, attributes: InlineAttributes)] {
    nodes(line).filter { !$0.kind.isMarker }.map { (String(line[$0.range]), $0.attributes) }
}

/// The marker characters, in order.
private func markers(_ line: String) -> [String] {
    nodes(line).filter { $0.kind.isMarker }.map { String(line[$0.range]) }
}

@Suite("Inline marks: reading")
struct InlineMarkReadingTests {

    @Test("<u> and </u> are markers, and the text between is underlined")
    func underline() {
        #expect(markers("a <u>b</u> c") == ["<u>", "</u>"])
        let runs = drawn("a <u>b</u> c")
        #expect(runs.map(\.text) == ["a ", "b", " c"])
        #expect(runs.map(\.attributes.underline) == [false, true, false])
    }

    @Test("The tags are read in either case, as a run's are")
    func underlineAnyCase() {
        #expect(markers("<U>b</U>") == ["<U>", "</U>"])
        #expect(drawn("<U>b</U>").first?.attributes.underline == true)
    }

    @Test("Each of the six emoji is a highlight of its own colour, and the emoji is part of the marker", arguments: HighlightColour.allCases)
    func highlight(colour: HighlightColour) {
        let line = "a ==\(colour.emoji)b== c"
        #expect(markers(line) == ["==\(colour.emoji)", "=="])
        let runs = drawn(line)
        #expect(runs.map(\.text) == ["a ", "b", " c"])
        #expect(runs.map(\.attributes.highlight) == [nil, colour, nil])
    }

    /// A note about code is full of these. With markers hidden, a false
    /// highlight would make the `==` vanish.
    @Test("Equals signs that aren't a highlight stay text", arguments: [
        "a == b", "a==b", "a==b==c", "if (a == b) { return; }", "==x==", "x ==🟡", "====", "===🟡x==",
        "==🟡==", "a ===🟡b==", "x = y", "<=", "a === b",
    ])
    func notHighlights(line: String) {
        #expect(markers(line).isEmpty, "\(line)")
        #expect(drawn(line).count == 1)
    }

    @Test("A tag with nothing to close it, or nothing between, or a lone closer, is text", arguments: [
        "<u>x", "x</u>", "<u></u>", "a <u> b", "vector<u>", "</u><u>",
    ])
    func notUnderlines(line: String) {
        #expect(markers(line).isEmpty, "\(line)")
    }

    @Test("A highlight ends at the first == after it; the leftover of a longer run is text")
    func closing() {
        #expect(markers("==🟡a===b") == ["==🟡", "=="])
        #expect(drawn("==🟡a===b").map(\.text) == ["a", "=b"])
    }

    @Test("A run of four ends one highlight and starts the next, so two colours can sit side by side")
    func adjacent() {
        let line = "==🟡a====🔴b=="
        #expect(markers(line) == ["==🟡", "==", "==🔴", "=="])
        #expect(drawn(line).map(\.attributes.highlight) == [.yellow, .red])
    }

    @Test("Marks nest with emphasis, links and each other, in either order")
    func nesting() {
        let a = drawn("**==🟡x==**")
        #expect(a.count == 1 && a[0].attributes.bold && a[0].attributes.highlight == .yellow)
        let b = drawn("==🟡**x**==")
        #expect(b.count == 1 && b[0].attributes.bold && b[0].attributes.highlight == .yellow)
        let c = drawn("<u>*x*</u>")
        #expect(c.count == 1 && c[0].attributes.italic && c[0].attributes.underline)
        let d = drawn("==🟡<u>x</u>==")
        #expect(d.count == 1 && d[0].attributes.underline && d[0].attributes.highlight == .yellow)
        let e = drawn("<u>==🔵x==</u>")
        #expect(e.count == 1 && e[0].attributes.underline && e[0].attributes.highlight == .blue)
        let f = drawn("==🟡[x](u)==")
        #expect(f.count == 1 && f[0].attributes.link && f[0].attributes.highlight == .yellow)
        let g = drawn("[==🟡x==](u)")
        #expect(g.count == 1 && g[0].attributes.link && g[0].attributes.highlight == .yellow)
        let h = drawn("<span style=\"color:#E5484D\">==🟡x==</span>")
        #expect(h.count == 1 && h[0].attributes.colour == 0xE5484D && h[0].attributes.highlight == .yellow)
    }

    @Test("A highlight doesn't hold another: the next == ends it, and what follows is text")
    func noNestedHighlights() {
        // `==` closes the nearest open highlight first, so the second
        // `==🔴` ends the first, and the rest has nothing to open.
        #expect(markers("==🟡a ==🔴b== c==") == ["==🟡", "=="])
        #expect(drawn("==🟡a ==🔴b== c==").map(\.text) == ["a ", "🔴b== c=="])
    }

    @Test("Marks that would cross are text, as emphasis that crosses is")
    func crossing() {
        // The bold would end inside the highlight, so it isn't bold.
        let line = "**a ==🟡b** c=="
        #expect(markers(line) == ["==🟡", "=="])
        #expect(drawn(line).allSatisfy { !$0.attributes.bold })

        let underlineAcross = "<u>a ==🟡b</u> c=="
        #expect(markers(underlineAcross) == ["<u>", "</u>"])
    }

    @Test("Nothing in inline code is read")
    func inCode() {
        #expect(markers("`==🟡x==`") == ["`", "`"])
        #expect(markers("`<u>x</u>`") == ["`", "`"])
        #expect(drawn("`==🟡x==`").first?.attributes.highlight == nil)
    }

    @Test("A bare address inside a highlight stops before the closing ==; outside one it keeps its own")
    func addresses() {
        let inside = drawn("==🟡https://x.io==")
        #expect(inside.map(\.text) == ["https://x.io"])
        #expect(inside[0].attributes.link && inside[0].attributes.highlight == .yellow)
        // A padded base64 query ends in `==` and is the address's.
        let padded = drawn("see https://x.io/?d=YWJj== ok")
        #expect(padded.map(\.text) == ["see ", "https://x.io/?d=YWJj==", " ok"])
        // And an address inside an underline stops at its `<`.
        #expect(drawn("<u>https://x.io</u>").map(\.text) == ["https://x.io"])
    }

    @Test("The block signature tells the marks apart, since a restyle must notice them")
    func signatures() {
        var seen: Set<Int> = []
        for colour in HighlightColour.allCases {
            var attributes = InlineAttributes.plain
            attributes.highlight = colour
            #expect(seen.insert(attributes.signature).inserted)
        }
        var underlined = InlineAttributes.plain
        underlined.underline = true
        #expect(seen.insert(underlined.signature).inserted)
        var struck = InlineAttributes.plain
        struck.strikethrough = true
        #expect(seen.insert(struck.signature).inserted)
        var both = underlined
        both.highlight = .green
        #expect(seen.insert(both.signature).inserted)
        // The marks and a colour and a size all fit without touching.
        var everything = both
        everything.colour = 0xFFFFFF
        everything.size = SpanSize(em: 10)
        everything.bold = true
        #expect(seen.insert(everything.signature).inserted)
        #expect(InlineAttributes.plain.signature == 0)

        // And the markers' own numbers.
        let kinds: [InlineNode.Kind] = [.opening(.underline), .closing(.underline)]
            + HighlightColour.allCases.flatMap { [InlineNode.Kind.opening(.highlight($0)), .closing(.highlight($0))] }
            + [.opening(.strong), .opening(.emphasis), .opening(.inlineCode), .opening(.strikethrough), .opening(.link),
               .opening(.styled(SpanStyle(colour: 0x000000))), .opening(.styled(SpanStyle(colour: 0x000001))), .text]
        #expect(Set(kinds.map(\.discriminant)).count == kinds.count)
    }
}

@Suite("Inline marks: writing")
struct InlineMarkWritingTests {

    private func toggled(_ style: MarkdownFormatting.InlineStyle, _ marked: String) -> String? {
        let text = marked.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
        let ns = marked as NSString
        let open = ns.range(of: "«").location
        let close = ns.range(of: "»").location
        guard let edit = MarkdownFormatting.toggle(style, in: text, selection: NSRange(location: open, length: close - open - 1)) else { return nil }
        return edit.applied(to: text)
    }

    private func highlighted(_ colour: HighlightColour?, _ marked: String) -> String? {
        let text = marked.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
        let ns = marked as NSString
        let open = ns.range(of: "«").location
        let close = ns.range(of: "»").location
        guard let edit = MarkdownFormatting.highlight(colour, selection: NSRange(location: open, length: close - open - 1), in: text as NSString, codeRanges: []) else { return nil }
        return edit.applied(to: text)
    }

    @Test("Underline wraps the selection in <u>, and again takes it off")
    func underline() {
        #expect(toggled(.underline, "a «word» b") == "a <u>word</u> b")
        #expect(toggled(.underline, "a <u>«word»</u> b") == "a word b")
        #expect(toggled(.underline, "a <u>wo«r»d</u> b") == "a <u>wo</u>r<u>d</u> b")
    }

    @Test("Underline and bold combine, whichever comes first, and either comes off alone")
    func underlineAndBold() throws {
        let both = try #require(toggled(.underline, "a **«word»** b"))
        let styled = try #require(StyledLine(both))
        let word = styled.glyphs.filter { ["w", "o", "r", "d"].contains($0.text) }
        #expect(word.allSatisfy { $0.style.bold && $0.style.underline })
        // Bold off leaves the underline.
        let noBold = try #require(toggled(.bold, both.replacingOccurrences(of: "word", with: "«word»")))
        let rest = try #require(StyledLine(noBold))
        #expect(rest.glyphs.filter { ["w", "o", "r", "d"].contains($0.text) }.allSatisfy { !$0.style.bold && $0.style.underline })
    }

    @Test("A highlight writes ==, its emoji, the text and ==; a new colour replaces it")
    func highlight() {
        #expect(highlighted(.yellow, "a «word» b") == "a ==🟡word== b")
        #expect(highlighted(.red, "a ==🟡«word»== b") == "a ==🔴word== b")
        #expect(highlighted(nil, "a ==🟡«word»== b") == "a word b")
        #expect(highlighted(nil, "a «word» b") == nil)
    }

    @Test("Highlighting part of a highlight in another colour writes the two side by side, and they read back")
    func twoColours() throws {
        let result = try #require(highlighted(.red, "==🟡wo«rd»=="))
        #expect(result == "==🟡wo====🔴rd==")
        #expect(drawn(result).map(\.attributes.highlight) == [.yellow, .red])
        #expect(drawn(result).map(\.text) == ["wo", "rd"])
    }

    @Test("A highlight round bold text keeps the bold, with the highlight outside it")
    func highlightRoundBold() throws {
        let result = try #require(highlighted(.green, "a «**word**» b"))
        let runs = drawn(result)
        #expect(runs.map(\.text) == ["a ", "word", " b"])
        #expect(runs[1].attributes.bold && runs[1].attributes.highlight == .green)
        #expect(result.count <= "a ==🟢**word**== b".count)
    }

    @Test("A highlight over a sentence with one word bold is one highlight, not one per piece")
    func oneHighlight() throws {
        let result = try #require(highlighted(.yellow, "«a **b** c»"))
        #expect(result == "==🟡a **b** c==")
    }

    @Test("A tag holds the spaces it is given: Underline keeps a selection's, Highlight trims them as Colour does")
    func spaces() throws {
        // `*`, `**` and `~~` can't open before or close after a space, and
        // shed them; a tag can hold them, so Underline, which acts on the
        // selection as it is, underlines the spaces in it. Highlight is a
        // style like Colour and Size, which leave a selection's end spaces out.
        #expect(toggled(.underline, "a« word »b") == "a<u> word </u>b")
        #expect(highlighted(.yellow, "a« word »b") == "a ==🟡word== b")
        // Inside the selection they stay, and the highlight holds them.
        #expect(highlighted(.yellow, "«a b»") == "==🟡a b==")
    }

    @Test("Text that holds an = can still be highlighted when it can be read back; otherwise nothing is written")
    func equalsInText() {
        // `a=` at the end of a highlight would be read as `a` and `=`, so
        // that edit is refused and the line is left whole.
        #expect(highlighted(.yellow, "«x=»") == nil)
        #expect(highlighted(.yellow, "«x=y»") == "==🟡x=y==")
    }

    /// The writer is shown thousands of stylings in `StyledLineTests`; this
    /// is the same idea for underline and highlight alone, with the text
    /// allowed to hold the characters that look like their markers, where a
    /// line that can't be written is left alone and never half written.
    @Test("Underline and highlight over text with lookalikes: refused or read back exactly")
    func lookalikes() {
        let letters = ["a", "b", " ", "=", "==", "<", ">", "u", "🟡", "/"]
        var random = NestingInlineTests.Seeded(state: 21_10_2026)
        var written = 0
        for _ in 0..<3000 {
            let texts = (0..<Int.random(in: 1...9, using: &random)).map { _ in letters.randomElement(using: &random)! }
            guard let line = StyledLine(texts.joined()), !line.glyphs.isEmpty else { continue }
            let count = line.glyphs.count
            let a = Int.random(in: 0...count, using: &random)
            let b = Int.random(in: 0...count, using: &random)
            guard a != b else { continue }
            var styles = line.glyphs.map(\.style)
            let colour = [HighlightColour.yellow, .red, nil].randomElement(using: &random)!
            let underline = Bool.random(using: &random)
            for index in min(a, b)..<max(a, b) {
                styles[index].highlight = colour
                styles[index].underline = underline
            }
            guard styles != line.glyphs.map(\.style), let read = line.restyled(styles) else { continue }
            written += 1
            #expect(read.glyphs.map(\.text) == line.glyphs.map(\.text), "\(line.line) → \(read.line)")
            for index in styles.indices {
                #expect(read.glyphs[index].style.highlight == styles[index].highlight, "\(read.line) at \(index)")
                #expect(read.glyphs[index].style.underline == styles[index].underline, "\(read.line) at \(index)")
            }
        }
        #expect(written > 500)
    }
}

@Suite("Highlight colours")
struct HighlightColourTests {

    @Test("Six colours, each its own emoji, number and name")
    func six() {
        #expect(HighlightColour.allCases.count == 6)
        #expect(Set(HighlightColour.allCases.map(\.emoji)).count == 6)
        #expect(HighlightColour.allCases.map(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(Set(HighlightColour.allCases.map(\.name)).count == 6)
        for colour in HighlightColour.allCases {
            #expect(colour.emoji.count == 1, "\(colour.name) is one character")
            #expect(HighlightColour(emoji: Character(colour.emoji)) == colour)
        }
    }

    /// Blends `hex` at `alpha` over a page colour, as the display does.
    private static func blend(_ hex: Int, alpha: Double, over page: Int) -> Int {
        func channel(_ shift: Int) -> Int {
            let top = Double((hex >> shift) & 0xFF)
            let below = Double((page >> shift) & 0xFF)
            return Int((top * alpha + below * (1 - alpha)).rounded())
        }
        return channel(16) << 16 | channel(8) << 8 | channel(0)
    }

    @Test("The label colour reads on every highlight, light and dark: 4.5:1 or better", arguments: HighlightColour.allCases)
    func legible(colour: HighlightColour) {
        let light = Self.blend(colour.hex.light, alpha: HighlightColour.alpha(isDark: false), over: 0xFFFFFF)
        let dark = Self.blend(colour.hex.dark, alpha: HighlightColour.alpha(isDark: true), over: 0x000000)
        #expect(AccentPalette.contrast(light, 0x000000) >= 4.5, "\(colour.name) light: \(AccentPalette.contrast(light, 0x000000))")
        #expect(AccentPalette.contrast(dark, 0xFFFFFF) >= 4.5, "\(colour.name) dark: \(AccentPalette.contrast(dark, 0xFFFFFF))")
    }

    @Test("A highlight shows: it differs from the page in both appearances, by at least a visible amount", arguments: HighlightColour.allCases)
    func visible(colour: HighlightColour) {
        let light = Self.blend(colour.hex.light, alpha: HighlightColour.alpha(isDark: false), over: 0xFFFFFF)
        let dark = Self.blend(colour.hex.dark, alpha: HighlightColour.alpha(isDark: true), over: 0x000000)
        #expect(AccentPalette.contrast(light, 0xFFFFFF) >= 1.15, "\(colour.name) light")
        #expect(AccentPalette.contrast(dark, 0x000000) >= 1.5, "\(colour.name) dark")
    }
}

@Suite("Inline marks: search and Get Info")
struct InlineMarkSearchTests {

    @Test("Search masks the marks' markers and nothing else, unit for unit")
    func masking() {
        let text = "a <u>b</u> ==🟡c== d"
        let masked = SpanStyle.maskingTags(in: text)
        #expect((masked as NSString).length == (text as NSString).length)
        #expect(masked.replacingOccurrences(of: "\u{2060}", with: "") == "a b c d")
        // So a search for a marker's characters finds nothing.
        #expect(masked.range(of: "<u>") == nil)
        #expect(masked.range(of: "🟡") == nil)
    }

    @Test("A note whose only mark is a highlight is masked too")
    func highlightAlone() {
        let masked = SpanStyle.maskingTags(in: "x ==🟡y== z")
        #expect(masked.replacingOccurrences(of: "\u{2060}", with: "") == "x y z")
    }

    @Test("A ==🟡 in a code block is code, and isn't masked")
    func codeIsNotMasked() {
        let text = "if (a == b) {}\n```cpp\nx ==🟡 y\n```"
        let masked = SpanStyle.maskingTags(in: text)
        #expect(masked.contains("x ==🟡 y"))
        #expect(masked.contains("a == b"))
    }

    @Test("Get Info counts the words, not the marks' markers")
    func words() {
        #expect(NoteInfo(content: "one <u>two</u> ==🟡three== four").words == 4)
    }
}

#if canImport(UIKit)

import UIKit

@Suite("Inline marks: drawn")
@MainActor
struct InlineMarkDrawingTests {

    private func styled(_ source: String) -> UITextView {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = source
        DocumentStyler.applyStyling(to: textView)
        return textView
    }

    private func offset(_ text: String, in source: String) -> Int {
        (source as NSString).range(of: text).location
    }

    @Test("Underline underlines its text and leaves its tags alone")
    func underline() {
        let source = "a <u>word</u> b"
        let storage = styled(source).textStorage
        func underlined(_ offset: Int) -> Bool {
            storage.attribute(.underlineStyle, at: offset, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue
        }
        #expect(underlined(offset("word", in: source)))
        #expect(underlined(offset("word", in: source) + 3))
        #expect(!underlined(offset("<u>", in: source)))
        #expect(!underlined(offset("</u>", in: source)))
        #expect(!underlined(0))
        #expect(!underlined(offset(" b", in: source)))
    }

    @Test("Each highlight is its colour as a background on its text, and nowhere else", arguments: HighlightColour.allCases)
    func highlight(colour: HighlightColour) {
        let source = "a ==\(colour.emoji)word== b"
        let storage = styled(source).textStorage
        func background(_ offset: Int) -> UIColor? {
            storage.attribute(.backgroundColor, at: offset, effectiveRange: nil) as? UIColor
        }
        #expect(background(offset("word", in: source)) === DocumentStyler.highlightColour(colour))
        #expect(background(offset("==", in: source)) == nil)
        #expect(background(offset("word", in: source) + 4) == nil, "the closing ==")
        #expect(background(0) == nil)
        #expect(background(source.utf16.count - 1) == nil)
    }

    @Test("A highlighted word of code shows the highlight, not the code's grey")
    func overCode() {
        let source = "==🟡`code`=="
        let storage = styled(source).textStorage
        let at = offset("code", in: source)
        #expect(storage.attribute(.backgroundColor, at: at, effectiveRange: nil) as? UIColor === DocumentStyler.highlightColour(.yellow))
    }

    @Test("The six colours are six colours, and each differs between the appearances")
    func colours() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        var seen: Set<String> = []
        for colour in HighlightColour.allCases {
            let a = DocumentStyler.highlightColour(colour).resolvedColor(with: light)
            let b = DocumentStyler.highlightColour(colour).resolvedColor(with: dark)
            #expect(seen.insert("\(a)").inserted)
            // Translucent in both, more so in light: the page shows through.
            var (alphaLight, alphaDark): (CGFloat, CGFloat) = (0, 0)
            a.getRed(nil, green: nil, blue: nil, alpha: &alphaLight)
            b.getRed(nil, green: nil, blue: nil, alpha: &alphaDark)
            #expect(abs(alphaLight - HighlightColour.alpha(isDark: false)) < 0.01)
            #expect(abs(alphaDark - HighlightColour.alpha(isDark: true)) < 0.01)
        }
    }

    /// Setting attributes is an edit even when they're the ones already
    /// there, and with page breaks TextKit then lays out everything below it
    /// again, so the colours are objects made once.
    @Test("Restyling a note that has them leaves the storage alone")
    func restyleIsNotAnEdit() {
        let textView = styled("a <u>u</u> ==🟡y== ==🔴r====🔵b==\n> quoted\n---\n#### four\n")
        var edits = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: textView.textStorage, queue: nil
        ) { _ in edits += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        DocumentStyler.applyStyling(to: textView)
        #expect(edits == 0)
    }

    @Test("A heading of any of the six levels is that level's font")
    func headings() {
        let source = (1...6).map { String(repeating: "#", count: $0) + " h\($0)" }.joined(separator: "\n")
        let storage = styled(source).textStorage
        for level in 1...6 {
            let font = storage.attribute(.font, at: offset("h\(level)", in: source), effectiveRange: nil) as? UIFont
            #expect(font == DocumentStyler.headingFont(level: level), "level \(level)")
        }
    }
}

#endif

#if canImport(UIKit)

@Suite("Inline marks: typing style", .serialized)
@MainActor
struct InlineMarkTypingTests {

    typealias Harness = TextRowEditorTests.Harness

    @Test("Text typed under Underline or a highlight is written inside the marks, the caret in front of the closing one")
    func written() {
        #expect(TypingStyleRuleTests.typed("hello |", run: "w", TypingStyle(underline: true)) == "hello <u>w|</u>")
        #expect(TypingStyleRuleTests.typed("hello |", run: "w", TypingStyle(highlight: .set(.yellow))) == "hello ==🟡w|==")
        #expect(TypingStyleRuleTests.typed("hello |", run: "w", TypingStyle(bold: true, underline: true)) == "hello <u>**w|**</u>")
        // Off at the end of a highlighted word: what is typed goes outside it.
        #expect(TypingStyleRuleTests.typed("==🟡hi|==", run: "x", TypingStyle(highlight: .clear)) == "==🟡hi==x|")
        #expect(TypingStyleRuleTests.typed("<u>hi|</u>", run: "x", TypingStyle(underline: false)) == "<u>hi</u>x|")
    }

    @Test("The bar shows what is set, and the next text typed carries it")
    func inTheEditor() async {
        let underline = Harness("a |")
        #expect(!underline.editor.formattingShown.underline)
        underline.editor.toggle(.underline)
        #expect(underline.editor.formattingShown.underline)
        #expect(underline.text == "a ", "nothing is written until text is typed")
        await TypingStyleEditorTests.type("b", into: underline)
        #expect(TypingStyleEditorTests.shown(underline) == "a <u>b|</u>")
        await TypingStyleEditorTests.type("c", into: underline)
        #expect(TypingStyleEditorTests.shown(underline) == "a <u>bc|</u>")

        let highlight = Harness("a |")
        highlight.editor.setHighlight(.green)
        #expect(highlight.editor.formattingShown.highlight == .green, "the highlight menu shows it")
        await TypingStyleEditorTests.type("b", into: highlight)
        #expect(TypingStyleEditorTests.shown(highlight) == "a ==🟢b|==")
        highlight.editor.setHighlight(nil)
        #expect(highlight.editor.formattingShown.highlight == nil)
    }

    @Test("A highlight on a selection, or a word, is written and undone in one step")
    func selection() {
        let harness = Harness("a word b")
        harness.textView.selectedRange = NSRange(location: 2, length: 4)
        harness.coordinator.refreshCaretFormatting(in: harness.textView)
        harness.editor.setHighlight(.blue)
        #expect(harness.text == "a ==🔵word== b")
        harness.editor.undo()
        #expect(harness.text == "a word b")
    }

    @Test("The bar lights Underline and the highlight at the caret, and the Style menu knows a quote")
    func lit() {
        let harness = Harness("a <u>wo|rd</u> ==🔴x== > not\n> quoted")
        #expect(harness.editor.caretFormatting.underline)
        #expect(harness.editor.caretFormatting.highlight == nil)
        #expect(harness.editor.caretFormatting.quoteDepth == 0)
    }

    @Test("Nothing is set in a locked note")
    func locked() {
        let harness = Harness("a |")
        harness.editor.setTextLocked(true)
        harness.editor.toggle(.underline)
        harness.editor.setHighlight(.red)
        #expect(harness.editor.typingStyle.isEmpty)
    }
}

#endif
