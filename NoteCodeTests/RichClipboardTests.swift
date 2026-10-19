//
//  RichClipboardTests.swift
//  NoteCodeTests
//
//  Text overhaul, phase 5: copy and paste with formatting, in an editor with a
//  real text view.
//

import Testing
import UIKit
import UniformTypeIdentifiers
@testable import NoteCode

@Suite("Rich copy and paste: in the editor", .serialized)
@MainActor
struct RichClipboardTests {

    typealias Harness = TextRowEditorTests.Harness

    // Fonts every app has, so the RTF reads back with its weights.
    static let regular = UIFont(name: "Helvetica", size: 12)!
    static let bold = UIFont(name: "Helvetica-Bold", size: 12)!
    static let oblique = UIFont(name: "Helvetica-Oblique", size: 12)!
    static let mono = UIFont(name: "Menlo-Regular", size: 10)!

    /// What another app puts on the pasteboard: RTF.
    static func putRTF(_ parts: [(String, [NSAttributedString.Key: Any])]) throws {
        let text = NSMutableAttributedString()
        for (string, attributes) in parts { text.append(NSAttributedString(string: string, attributes: attributes)) }
        let data = try text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        UIPasteboard.general.setItems([[UTType.rtf.identifier: data]])
    }

    static func clearPasteboard() {
        UIPasteboard.general.setItems([[:]])
    }

    /// The RTF a copy left, read back.
    static func copiedText() -> NSAttributedString? {
        guard let data = UIPasteboard.general.data(forPasteboardType: UTType.rtf.identifier) else { return nil }
        return try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
    }

    /// An attribute of the first occurrence of `word`.
    static func attribute(_ key: NSAttributedString.Key, of word: String, in text: NSAttributedString) -> Any? {
        let range = (text.string as NSString).range(of: word)
        guard range.location != NSNotFound else { return nil }
        return text.attribute(key, at: range.location, effectiveRange: nil)
    }

    static func traits(of word: String, in text: NSAttributedString) -> UIFontDescriptor.SymbolicTraits {
        (attribute(.font, of: word, in: text) as? UIFont)?.fontDescriptor.symbolicTraits ?? []
    }

    static func size(of word: String, in text: NSAttributedString) -> CGFloat? {
        (attribute(.font, of: word, in: text) as? UIFont)?.pointSize
    }

    // MARK: The adapter

    @Test("An attributed string's fonts, strikes, links and colours are read off as runs")
    func readsAttributes() throws {
        let url = URL(string: "https://example.com/a")!
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "plain ", attributes: [.font: Self.regular]))
        text.append(NSAttributedString(string: "bold", attributes: [.font: Self.bold]))
        text.append(NSAttributedString(string: "slant", attributes: [.font: Self.oblique]))
        text.append(NSAttributedString(string: "code", attributes: [.font: Self.mono]))
        text.append(NSAttributedString(string: "gone", attributes: [.font: Self.regular, .strikethroughStyle: NSUnderlineStyle.single.rawValue]))
        text.append(NSAttributedString(string: "site", attributes: [.font: Self.regular, .link: url]))
        text.append(NSAttributedString(string: "red", attributes: [.font: Self.regular, .foregroundColor: UIColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1)]))

        let runs = RichPaste.runs(from: text)
        func attributes(_ word: String) -> PastedAttributes? { runs.first { $0.text == word }?.attributes }
        #expect(attributes("plain ")?.bold == false)
        #expect(attributes("bold")?.bold == true)
        #expect(attributes("slant")?.italic == true)
        #expect(attributes("code")?.monospaced == true)
        #expect(attributes("code")?.pointSize == 10)
        #expect(attributes("gone")?.strikethrough == true)
        #expect(attributes("site")?.link == "https://example.com/a")
        #expect(attributes("red")?.colour == 0xE6334D)
    }

    @Test("HTML, which Safari puts on the pasteboard, comes through: emphasis, a link, a colour, a heading and code")
    func html() throws {
        let html = """
        <html><body style="font-family:-apple-system;font-size:16px"><p>See <b>bold</b>, <i>slant</i>, \
        <a href="https://example.com/x">a link</a>, <span style="color:#E5484D">red</span> and <del>gone</del>.</p>\
        <h1>Title</h1><pre><code>int x;
        return x;</code></pre><p>Use <code>foo()</code> here.</p></body></html>
        """
        let attributed = try NSAttributedString(
            data: Data(html.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        )
        let markdown = try #require(RichPaste.markdown(from: RichPaste.runs(from: attributed)))
        #expect(markdown.contains("See **bold**, *slant*, [a link](https://example.com/x), "))
        #expect(markdown.contains("<span style=\"color:#E5484D\">red</span> and ~~gone~~."), "a colour, and a strike")
        #expect(markdown.contains("<span style=\"font-size:2em\">**Title**</span>"), "an h1 is bold at twice the body")
        #expect(markdown.contains("\nint x;\nreturn x;\n"), "a block of code is plain text, with no backticks")
        #expect(markdown.contains("Use `foo()` here."), "code among words is a span")
        #expect(!markdown.contains("000000"), "the page's black is its text colour and not a choice")
        #expect(!markdown.contains("0000EE"), "a link's blue is the app's to draw")
    }

    // MARK: Paste

    @Test("Styled text from another app is pasted as Markdown, in one undo step")
    func pastes() throws {
        try Self.putRTF([("a ", [.font: Self.regular]), ("bold", [.font: Self.bold]), (" word", [.font: Self.regular])])
        let harness = Harness("hello |")
        harness.textView.paste(nil)
        #expect(harness.text == "hello a **bold** word")
        #expect(harness.stored == harness.text, "the page has it")
        #expect(harness.textView.selectedRange == NSRange(location: (harness.text as NSString).length, length: 0))

        harness.editor.undo()
        #expect(harness.text == "hello ", "one undo takes the whole paste")
    }

    @Test("A paste replaces the selection")
    func replacesSelection() throws {
        try Self.putRTF([("new", [.font: Self.bold])])
        let harness = Harness("one old two|")
        harness.textView.selectedRange = NSRange(location: 4, length: 3)
        harness.textView.paste(nil)
        #expect(harness.text == "one **new** two")
    }

    @Test("A colour, a size and a link survive")
    func coloursSizesAndLinks() throws {
        try Self.putRTF([
            ("body ", [.font: Self.regular]),
            ("red", [.font: Self.regular, .foregroundColor: UIColor(red: 0.9, green: 0.28, blue: 0.3, alpha: 1)]),
            (" and ", [.font: Self.regular]),
            ("big", [.font: UIFont(name: "Helvetica", size: 24)!]),
            (" and ", [.font: Self.regular]),
            ("site", [.font: Self.regular, .link: URL(string: "https://example.com")!]),
        ])
        let harness = Harness("|")
        harness.textView.paste(nil)
        #expect(harness.text == "body <span style=\"color:#E6474D\">red</span> and <span style=\"font-size:2em\">big</span> and [site](https://example.com)")
    }

    @Test("A paste into a code block is the text view's own, plain")
    func codeStaysPlain() throws {
        try Self.putRTF([("bold", [.font: Self.bold])])
        let harness = Harness("```cpp\nint x|;\n```\n")
        #expect(!harness.coordinator.richPaste(into: harness.textView))
        let over = Harness("one\n```cpp\nint x;\n```\ntwo|")
        over.textView.selectedRange = NSRange(location: 2, length: 10)
        #expect(!over.coordinator.richPaste(into: over.textView), "a selection reaching into code")
        let after = Harness("```cpp\nint x;\n```\n|")
        #expect(after.coordinator.richPaste(into: after.textView), "the line after a closed block is prose")
        #expect(after.text.hasSuffix("```\n**bold**"))
    }

    @Test("An unclosed block holds the caret to the end of the note")
    func unclosedBlock() throws {
        try Self.putRTF([("bold", [.font: Self.bold])])
        let harness = Harness("```cpp\nint x;|")
        #expect(!harness.coordinator.richPaste(into: harness.textView))
    }

    @Test("Text with nothing in it to keep is left to the text view")
    func nothingToKeep() throws {
        try Self.putRTF([("just words", [.font: Self.regular])])
        let harness = Harness("hello |")
        #expect(!harness.coordinator.richPaste(into: harness.textView))
        #expect(harness.text == "hello ")
    }

    @Test("Text copied from a note is pasted as the Markdown it came as, not read back from RTF")
    func ownCopyIsLeftAlone() throws {
        let source = Harness("|a **bold** word")
        source.textView.selectedRange = NSRange(location: 0, length: source.text.utf16.count)
        source.textView.copy(nil)
        #expect(UIPasteboard.general.contains(pasteboardTypes: [RichPaste.ownType]))
        #expect(RichPaste.attributedString(from: .general) == nil)

        let target = Harness("|")
        #expect(!target.coordinator.richPaste(into: target.textView))
    }

    @Test("A locked note takes no paste")
    func locked() throws {
        try Self.putRTF([("bold", [.font: Self.bold])])
        let harness = Harness("hello |")
        harness.editor.setTextLocked(true)
        #expect(!harness.coordinator.richPaste(into: harness.textView))
        #expect(harness.text == "hello ")
    }

    @Test("Pasted text isn't typed: a typing style is cleared and doesn't write over it")
    func typingStyle() async throws {
        try Self.putRTF([("plain", [.font: Self.regular]), ("bold", [.font: Self.bold])])
        let harness = Harness("hello |")
        harness.editor.toggle(.italic)
        #expect(harness.editor.typingStyle.italic == true)
        harness.textView.paste(nil)
        await harness.nextTap()
        #expect(harness.editor.typingStyle.isEmpty)
        #expect(harness.text == "hello plain**bold**", "the paste is as the source had it")
    }

    @Test("A list pasted at a line's start is a list, and mid-line it is only text")
    func lists() throws {
        try Self.putRTF([("\t•\tOne\n\t•\tTwo", [.font: Self.regular])])
        let start = Harness("|")
        start.textView.paste(nil)
        #expect(start.text == "- One\n- Two")

        let middle = Harness("see |")
        middle.textView.paste(nil)
        #expect(middle.text == "see One\n- Two")
    }

    // MARK: Copy

    static let styled = "# Title\nsome **bold** and *slant* and ~~gone~~ and <span style=\"color:#E5484D\">red</span> and <span style=\"font-size:2em\">big</span>\n"

    @Test("A copy has the Markdown as its text and the page's text as RTF")
    func copiesBoth() throws {
        Self.clearPasteboard()
        let harness = Harness("|" + Self.styled)
        harness.textView.selectedRange = NSRange(location: 0, length: Self.styled.utf16.count)
        harness.textView.copy(nil)

        #expect(UIPasteboard.general.string == Self.styled, "the plain text is the Markdown, as it was")
        #expect(UIPasteboard.general.contains(pasteboardTypes: [RichPaste.ownType]))

        let text = try #require(Self.copiedText())
        #expect(text.string == "Title\nsome bold and slant and gone and red and big\n", "what can be seen, and no marker")
        #expect(Self.traits(of: "bold", in: text).contains(.traitBold))
        #expect(!Self.traits(of: "some", in: text).contains(.traitBold))
        #expect(Self.traits(of: "slant", in: text).contains(.traitItalic))
        #expect((Self.attribute(.strikethroughStyle, of: "gone", in: text) as? Int ?? 0) != 0)
        #expect(Self.attribute(.strikethroughStyle, of: "some", in: text) == nil)

        let body = harness.coordinator.typography.prose.pointSize
        for word in ["Title", "some", "bold", "slant"] {
            let name = (Self.attribute(.font, of: word, in: text) as? UIFont)?.fontName ?? ""
            #expect(name.hasPrefix("HelveticaNeue"), "a face other apps have, not the system font's private name: \(name)")
        }
        #expect(Self.size(of: "some", in: text) == body)
        #expect(Self.size(of: "big", in: text) == body * 2)
        #expect(Self.traits(of: "Title", in: text).contains(.traitBold))
        #expect((Self.size(of: "Title", in: text) ?? 0) > body, "a heading is larger")

        var (red, green, blue, alpha) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        let colour = try #require(Self.attribute(.foregroundColor, of: "red", in: text) as? UIColor)
        colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let drawn = AccentPalette.textHex(for: 0xE5484D, isDark: false)
        #expect(abs(red - CGFloat((drawn >> 16) & 0xFF) / 255) < 0.01 && abs(blue - CGFloat(drawn & 0xFF) / 255) < 0.01,
                "a colour as a light page draws it")
        #expect(Self.attribute(.foregroundColor, of: "some", in: text) == nil)
    }

    @Test("A selection that starts inside a span still has the span's style")
    func selectionInsideASpan() throws {
        Self.clearPasteboard()
        let harness = Harness("a **bol|d** b")
        let start = (harness.text as NSString).range(of: "ld").location
        harness.textView.selectedRange = NSRange(location: start, length: (harness.text as NSString).length - start)
        harness.textView.copy(nil)
        let text = try #require(Self.copiedText())
        #expect(text.string == "ld b")
        #expect(Self.traits(of: "ld", in: text).contains(.traitBold))
        #expect(!Self.traits(of: "b", in: text).contains(.traitBold))
        #expect(UIPasteboard.general.string == "ld** b", "the plain text is what was selected")
    }

    @Test("Code is monospaced text without its fences")
    func code() throws {
        Self.clearPasteboard()
        let source = "before\n```cpp\nint x;\nreturn x;\n```\nafter"
        let harness = Harness("|" + source)
        harness.textView.selectedRange = NSRange(location: 0, length: source.utf16.count)
        harness.textView.copy(nil)
        let text = try #require(Self.copiedText())
        #expect(text.string == "before\nint x;\nreturn x;\nafter")
        #expect(Self.traits(of: "int", in: text).contains(.traitMonoSpace))
        #expect(!Self.traits(of: "before", in: text).contains(.traitMonoSpace))
    }

    @Test("List items keep their markers when the selection reaches them")
    func listItems() throws {
        Self.clearPasteboard()
        let source = "- one\n- [x] **two**\n1. three\n"
        let harness = Harness("|" + source)
        harness.textView.selectedRange = NSRange(location: 0, length: source.utf16.count)
        harness.textView.copy(nil)
        #expect(try #require(Self.copiedText()).string == "•\tone\n☑\ttwo\n1.\tthree\n")

        // Starting after a marker leaves it out.
        harness.textView.selectedRange = NSRange(location: 2, length: 3)
        harness.textView.copy(nil)
        #expect(try #require(Self.copiedText()).string == "one")
    }

    @Test("A cut takes the text out and leaves the same two copies")
    func cut() throws {
        Self.clearPasteboard()
        let harness = Harness("|a **bold** word")
        harness.textView.selectedRange = NSRange(location: 2, length: 8)
        harness.textView.cut(nil)
        #expect(harness.text == "a  word")
        #expect(UIPasteboard.general.string == "**bold**")
        let text = try #require(Self.copiedText())
        #expect(text.string == "bold")
        #expect(Self.traits(of: "bold", in: text).contains(.traitBold))
    }

    @Test("A copy of nothing adds no RTF")
    func nothingSelected() {
        Self.clearPasteboard()
        let harness = Harness("a **bold** word|")
        harness.textView.copy(nil)
        #expect(Self.copiedText() == nil)
    }

    @Test("Markers alone are not visible: a selection of only a marker has no RTF")
    func onlyMarkers() {
        Self.clearPasteboard()
        let harness = Harness("a **bold** word|")
        harness.textView.selectedRange = NSRange(location: 2, length: 2)
        harness.textView.copy(nil)
        #expect(Self.copiedText() == nil, "there is nothing to see in `**`")
        #expect(UIPasteboard.general.string == "**", "the plain text is still what was selected")
    }
}
