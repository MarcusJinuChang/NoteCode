//
//  RichPasteTests.swift
//  NoteCodeTests
//
//  Text overhaul, phase 5: styled text pasted into a note. The conversion
//  from runs to Markdown is pure.
//

import Testing
import Foundation
@testable import NoteCode

@Suite("Rich paste: runs to Markdown")
struct RichPasteTests {

    static let red = 0xE5484D

    /// A run, in a 12pt body unless it says otherwise.
    static func run(
        _ text: String, bold: Bool = false, italic: Bool = false, strike: Bool = false, mono: Bool = false,
        link: String? = nil, colour: Int? = nil, size: Double = 12
    ) -> PastedRun {
        PastedRun(text: text, attributes: PastedAttributes(
            bold: bold, italic: italic, strikethrough: strike, monospaced: mono, link: link, colour: colour, pointSize: size
        ))
    }

    static func markdown(_ runs: PastedRun..., atLineStart: Bool = true) -> String? {
        RichPaste.markdown(from: runs, atLineStart: atLineStart)
    }

    // MARK: Styles

    @Test("Text with nothing styled is left to the text view's own paste")
    func plainIsLeftAlone() {
        #expect(Self.markdown(Self.run("just words, "), Self.run("and more\nand a second line")) == nil)
        #expect(Self.markdown(Self.run("no\u{00A0}break and\r\nline ends")) == nil, "normalising alone isn't a reason to take the paste")
    }

    @Test("A no-break space is a space, and an attachment's placeholder is nothing")
    func oddCharacters() {
        #expect(Self.markdown(Self.run("a\u{00A0}"), Self.run("b", bold: true)) == "a **b**")
        #expect(Self.markdown(Self.run("a\u{FFFC}"), Self.run("b", bold: true)) == "a**b**")
        #expect(Self.markdown(Self.run("a\r\n"), Self.run("b", bold: true)) == "a\n**b**", "a Windows line end is one line end")
    }

    @Test("Bold, italic and strikethrough become their markers")
    func emphasis() {
        #expect(Self.markdown(Self.run("a "), Self.run("bold", bold: true), Self.run(" word")) == "a **bold** word")
        #expect(Self.markdown(Self.run("a "), Self.run("slanted", italic: true), Self.run(" word")) == "a *slanted* word")
        #expect(Self.markdown(Self.run("a "), Self.run("gone", strike: true), Self.run(" word")) == "a ~~gone~~ word")
    }

    @Test("Bold and italic together read back as both")
    func combined() throws {
        let written = try #require(Self.markdown(Self.run("a "), Self.run("both", bold: true, italic: true), Self.run(" b")))
        let line = try #require(StyledLine(written))
        let both = line.glyphs.filter { $0.style.bold && $0.style.italic }.map(\.text).joined()
        #expect(both == "both")
        #expect(line.glyphs.map(\.text).joined() == "a both b")
    }

    @Test("A colour is kept and black, white and greys are not")
    func colours() {
        #expect(Self.markdown(Self.run("a "), Self.run("red", colour: Self.red), Self.run(" b"))
            == "a <span style=\"color:#E5484D\">red</span> b")
        #expect(Self.markdown(Self.run("black ", colour: 0x000000), Self.run("grey ", colour: 0x666666), Self.run("white", colour: 0xFFFFFF)) == nil)
        #expect(Self.markdown(Self.run("slate", colour: 0x4A5568)) == nil, "within 15% of grey is the source's text colour")
    }

    @Test("A size is against the paste's own body, not the note's")
    func sizes() {
        // 12pt Pages body with a 24pt word: twice the text around it.
        #expect(Self.markdown(Self.run("a "), Self.run("big", size: 24), Self.run(" word"))
            == "a <span style=\"font-size:2em\">big</span> word")
        // Safari's 16px body is the body, not 0.94em of the note's 17.
        #expect(Self.markdown(Self.run("all of it", size: 16)) == nil)
        #expect(Self.markdown(Self.run("body text ", size: 16), Self.run("small", size: 12))
            == "body text <span style=\"font-size:0.75em\">small</span>")
    }

    @Test("Sizes within 4% of the body are the body")
    func sizeTolerance() {
        #expect(Self.markdown(Self.run("body text "), Self.run("close", size: 12.4)) == nil)
        #expect(Self.markdown(Self.run("body text "), Self.run("further", size: 13)) != nil)
    }

    @Test("A heading from elsewhere is bold at a larger size")
    func headingFromElsewhere() throws {
        let written = try #require(Self.markdown(
            Self.run("Title", bold: true, size: 24), Self.run("\nsome body text that outweighs the title\n")
        ))
        let first = try #require(StyledLine(String(written.prefix { $0 != "\n" })))
        #expect(first.glyphs.allSatisfy { $0.style.bold && $0.style.size == SpanSize(em: 2) })
    }

    @Test("A link is kept, with its address escaped")
    func links() {
        #expect(Self.markdown(Self.run("see "), Self.run("the notes", link: "https://example.com/notes"))
            == "see [the notes](https://example.com/notes)")
        #expect(Self.markdown(Self.run("see "), Self.run("the notes", link: "https://example.com/a b(c)"))
            == "see [the notes](https://example.com/a%20b%28c%29)")
    }

    @Test("A link the app wouldn't open is only its text")
    func linksThatDontOpen() {
        #expect(Self.markdown(Self.run("a "), Self.run("script", link: "javascript:alert(1)")) == nil)
        #expect(Self.markdown(Self.run("a "), Self.run("file", link: "file:///etc/passwd")) == nil)
    }

    @Test("A bold link is one bold holding one link, and two links stay two")
    func boldLinks() throws {
        let written = try #require(Self.markdown(
            Self.run("a ", bold: true), Self.run("one", bold: true, link: "https://a.io"),
            Self.run("two", bold: true, link: "https://b.io")
        ))
        let line = try #require(StyledLine(written))
        #expect(line.glyphs.allSatisfy { $0.style.bold })
        let links = Set(line.glyphs.compactMap(\.style.link?.address))
        #expect(links == ["https://a.io", "https://b.io"])
    }

    // MARK: Code

    @Test("A line of code is plain, and code among words is a span")
    func code() {
        #expect(Self.markdown(Self.run("int x = 1;\nreturn x;", mono: true, size: 10)) == nil)
        #expect(Self.markdown(Self.run("call "), Self.run("foo()", mono: true, size: 10), Self.run(" first")) == "call `foo()` first")
    }

    @Test("Code isn't coloured or bold: a code span can't hold a marker")
    func codeHasNoMarkers() {
        #expect(Self.markdown(Self.run("call "), Self.run("foo()", bold: true, mono: true, colour: Self.red), Self.run(" now"))
            == "call `foo()` now")
    }

    @Test("Code lines among prose lines stay plain")
    func codeLines() throws {
        let written = try #require(Self.markdown(
            Self.run("Some ", bold: true), Self.run("prose\n"), Self.run("int x = 1;\n", mono: true, size: 10), Self.run("more")
        ))
        #expect(written == "**Some** prose\nint x = 1;\nmore")
    }

    // MARK: Lists

    @Test("Bullets and numbers drawn with a tab become list items, nested by their tabs")
    func lists() {
        #expect(Self.markdown(Self.run("\t•\tOne\n\t•\tTwo\n\t\t◦\tNested\n")) == "- One\n- Two\n  - Nested\n")
        #expect(Self.markdown(Self.run("\t1.\tFirst\n\t2.\tSecond")) == "1. First\n2. Second")
        #expect(Self.markdown(Self.run("•\tNo tabs before")) == "- No tabs before")
    }

    @Test("A dash or star with a tab is only a list after a tab of nesting")
    func dashes() {
        #expect(Self.markdown(Self.run("-\tnot a list")) == nil)
        #expect(Self.markdown(Self.run("\t-\ta list")) == "- a list")
    }

    @Test("List items keep their styles")
    func styledListItem() throws {
        let written = try #require(Self.markdown(Self.run("\t•\t"), Self.run("Bold", bold: true), Self.run(" item")))
        #expect(written == "- **Bold** item")
    }

    @Test("A list item pasted mid-line has no place to start a list")
    func listMidLine() {
        #expect(Self.markdown(Self.run("\t•\tOne\n\t•\tTwo"), atLineStart: false) == "One\n- Two")
    }

    // MARK: Never a line that shows its markers

    @Test("Literal markers in the pasted text are plain, as a plain paste has them")
    func literalMarkers() {
        #expect(Self.markdown(Self.run("2 * 3 * 4 = 24")) == nil)
        let written = Self.markdown(Self.run("2 * 3 ", bold: false), Self.run("* 4", bold: true))
        let line = written.flatMap { StyledLine($0) }
        #expect(line?.glyphs.map(\.text).joined() == "2 * 3 * 4", "bold on a text that holds a star still reads as the text pasted")
    }

    @Test("A paste too long for the writer is left to the text view")
    func tooLong() {
        let long = String(repeating: "a", count: RichPaste.maxCharacters + 1)
        #expect(Self.markdown(Self.run(long, bold: true)) == nil)
    }

    @Test("Random pastes keep their characters, or are plain")
    func property() {
        var random = Seeded(state: 0x5EED)
        let words = ["alpha", "beta", " ", "  ", "x", "*", "_", "~~", "`", "[", "](", "<span", "é", "👩‍💻", "https://x.io", "(", ")"]
        let sizes: [Double] = [10, 12, 12, 12, 12, 18, 24]
        let colours: [Int?] = [nil, nil, nil, Self.red, 0x000000, 0x3B82F6]
        let links: [String?] = [nil, nil, nil, nil, "https://example.com/a", "https://b.io"]
        var styled = 0

        for _ in 0..<3_000 {
            var runs: [PastedRun] = []
            for _ in 0..<Int.random(in: 1...6, using: &random) {
                let text = (0..<Int.random(in: 1...3, using: &random)).map { _ in words.randomElement(using: &random)! }.joined()
                runs.append(Self.run(
                    text + (Bool.random(using: &random) && Int.random(in: 0..<6, using: &random) == 0 ? "\n" : ""),
                    bold: Bool.random(using: &random), italic: Bool.random(using: &random),
                    strike: Int.random(in: 0..<4, using: &random) == 0, mono: Int.random(in: 0..<8, using: &random) == 0,
                    link: links.randomElement(using: &random)!, colour: colours.randomElement(using: &random)!,
                    size: sizes.randomElement(using: &random)!
                ))
            }
            let input = RichPaste.glyphs(of: runs).map(\.text).joined()
            guard let written = RichPaste.markdown(from: runs) else { continue }
            styled += 1
            let inputLines = input.components(separatedBy: "\n")
            let writtenLines = written.components(separatedBy: "\n")
            #expect(inputLines.count == writtenLines.count, "lines are kept: \(runs.map(\.text))")
            for (before, after) in zip(inputLines, writtenLines) {
                let visible = StyledLine(after)?.glyphs.map(\.text).joined()
                #expect(after == before || visible == before, "\(before.debugDescription) came out as \(after.debugDescription)")
            }
        }
        #expect(styled > 1_500, "the generator should style most pastes")
    }

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
}
