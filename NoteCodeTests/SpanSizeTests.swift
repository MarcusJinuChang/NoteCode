//
//  SpanSizeTests.swift
//  NoteCodeTests
//
//  Size anywhere (step 10): `font-size` in a run's tag, beside its colour.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Sized text")
struct SpanSizeTests {

    static let red = TextColour.red.hex

    static func styles(_ line: String) -> [SpanStyle] {
        (DocumentParser.parse(line).first?.inlines ?? []).compactMap {
            if case .spanOpen(let style) = $0.kind { style } else { nil }
        }
    }

    // MARK: Writing and reading

    @Test("A size is written beside a colour, colour first, in one tag")
    func written() {
        #expect(SpanStyle(size: .large).openTag == "<span style=\"font-size:1.25em\">")
        #expect(SpanStyle(colour: Self.red, size: .small).openTag == "<span style=\"color:#E5484D;font-size:0.85em\">")
        #expect(SpanStyle(size: .larger).openTag == "<span style=\"font-size:1.5em\">")
    }

    @Test("Each written style reads back as itself")
    func roundTrip() {
        for colour in [nil, Self.red] as [Int?] {
            for size in [nil] + SpanSize.allCases.map(Optional.some) {
                let style = SpanStyle(colour: colour, size: size)
                guard !style.isEmpty else { continue }
                #expect(Self.styles("a \(style.openTag)b\(SpanStyle.close) c") == [style])
            }
        }
    }

    @Test("A size from elsewhere snaps to the nearest step, and one near 1em is no size")
    func snaps() {
        #expect(SpanSize.nearest(toEm: 1.2) == .large)
        #expect(SpanSize.nearest(toEm: 2) == .larger)
        #expect(SpanSize.nearest(toEm: 0.9) == .small)
        #expect(SpanSize.nearest(toEm: 0.5) == .small)
        #expect(SpanSize.nearest(toEm: 1.05) == nil)
        #expect(Self.styles("<span style=\"font-size:1.2em\">x</span>") == [SpanStyle(size: .large)])
    }

    @Test("Another order, another unit or a missing separator is text", arguments: [
        "<span style=\"font-size:1.25em;color:#E5484D\">a</span>",
        "<span style=\"font-size:12px\">a</span>",
        "<span style=\"color:#E5484Dfont-size:1.25em\">a</span>",
        "<span style=\"color:#E5484D;\">a</span>",
        "<span style=\"font-size:em\">a</span>",
    ])
    func notASize(line: String) {
        #expect(Self.styles(line).isEmpty, "\(line)")
    }

    // MARK: Editing

    static func size(_ size: SpanSize?, _ text: String, _ selection: NSRange) -> String? {
        MarkdownFormatting.size(size, selection: selection, in: text as NSString, codeRanges: []).map {
            (text as NSString).replacingCharacters(in: $0.range, with: $0.replacement)
        }
    }

    static func colour(_ hex: Int?, _ text: String, _ selection: NSRange) -> String? {
        MarkdownFormatting.colour(hex, selection: selection, in: text as NSString, codeRanges: []).map {
            (text as NSString).replacingCharacters(in: $0.range, with: $0.replacement)
        }
    }

    static func caret(in word: String, of text: String) -> NSRange {
        NSRange(location: (text as NSString).range(of: word).location + 1, length: 0)
    }

    @Test("A size on a word wraps it")
    func sizesAWord() {
        let text = "keep it small"
        #expect(Self.size(.large, text, Self.caret(in: "small", of: text)) == "keep it \(SpanStyle(size: .large).openTag)small</span>")
    }

    @Test("A size on a coloured run keeps its colour, and a colour on a sized one keeps its size")
    func keepsTheOtherSetting() {
        let red = "a \(SpanStyle(colour: Self.red).openTag)word</span> b"
        #expect(Self.size(.larger, red, Self.caret(in: "word", of: red))
                == "a \(SpanStyle(colour: Self.red, size: .larger).openTag)word</span> b")

        let large = "a \(SpanStyle(size: .large).openTag)word</span> b"
        #expect(Self.colour(Self.red, large, Self.caret(in: "word", of: large))
                == "a \(SpanStyle(colour: Self.red, size: .large).openTag)word</span> b")
    }

    @Test("Taking one setting off keeps the other; taking the last off unwraps")
    func takesSettingsOff() {
        let both = "a \(SpanStyle(colour: Self.red, size: .large).openTag)word</span> b"
        #expect(Self.size(nil, both, Self.caret(in: "word", of: both)) == "a \(SpanStyle(colour: Self.red).openTag)word</span> b")
        #expect(Self.colour(nil, both, Self.caret(in: "word", of: both)) == "a \(SpanStyle(size: .large).openTag)word</span> b")

        let large = "a \(SpanStyle(size: .large).openTag)word</span> b"
        #expect(Self.size(nil, large, Self.caret(in: "word", of: large)) == "a word b")
        #expect(Self.size(nil, "plain words", NSRange(location: 2, length: 3)) == nil)
    }

    @Test("The caret's size is the run it is in")
    func caretSize() {
        let text = "a \(SpanStyle(colour: Self.red, size: .small).openTag)word</span> b" as NSString
        let state = MarkdownFormatting.formatting(at: Self.caret(in: "word", of: text as String), in: text, codeRanges: [])
        #expect(state.size == .small)
        #expect(state.colour == Self.red)
        #expect(MarkdownFormatting.formatting(at: NSRange(location: 1, length: 0), in: text, codeRanges: []).size == nil)
    }
}

#if canImport(UIKit)

import PencilKit
import PaperKit
import UIKit

@Suite("Sized text, laid out")
@MainActor
struct SpanSizeLayoutTests {

    static func font(_ textView: UITextView, at word: String) -> UIFont? {
        let offset = (textView.text as NSString).range(of: word).location
        return textView.textStorage.attribute(.font, at: offset, effectiveRange: nil) as? UIFont
    }

    static func styled(_ text: String) -> UITextView {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = text
        DocumentStyler.applyStyling(to: textView)
        return textView
    }

    /// Spelled out, not asked of the styler's own function: 17pt body,
    /// 34pt H1, each step's em, to the half point.
    @Test("A run is set at its size against the text around it, bold and all")
    func fonts() throws {
        let large = SpanStyle(size: .large).openTag
        let small = SpanStyle(size: .small).openTag
        let textView = Self.styled("# A \(large)big\(SpanStyle.close) title\nplain \(large)larger **bold**\(SpanStyle.close) and \(small)tiny\(SpanStyle.close)\n")

        #expect(Self.font(textView, at: "plain")?.pointSize == 17)
        #expect(Self.font(textView, at: "larger")?.pointSize == 21.5)
        #expect(Self.font(textView, at: "tiny")?.pointSize == 14.5)
        #expect(Self.font(textView, at: "big")?.pointSize == 42.5)
        // A heading's run is a larger heading: still bold, as the heading is.
        #expect(Self.font(textView, at: "big")?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect(Self.font(textView, at: "big")?.fontName == Self.font(textView, at: "title")?.fontName)

        let bold = try #require(Self.font(textView, at: "bold"))
        #expect(bold.pointSize == 21.5)
        #expect(bold.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    @Test("Restyling sized text that's already styled leaves the storage alone")
    func restyleIsNotAnEdit() {
        let textView = Self.styled("plain \(SpanStyle(colour: TextColour.red.hex, size: .large).openTag)larger\(SpanStyle.close) text\n")
        var edits = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: textView.textStorage, queue: nil
        ) { _ in edits += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        DocumentStyler.applyStyling(to: textView)
        #expect(edits == 0)
    }

    // MARK: Ink

    @Test("Without ink, a size goes on at once")
    func noInk() {
        let harness = TextSizeEditorTests.Harness(withInk: false)
        harness.textView.selectedRange = NSRange(location: (harness.textView.text as NSString).range(of: "words").location + 2, length: 0)
        harness.editor.setSpanSize(.large)

        #expect(harness.editor.spanSizeAwaitingConfirmation == nil)
        #expect(harness.textView.text.contains("\(SpanStyle(size: .large).openTag)words</span>"))
    }

    @Test("With ink, a size waits for Change, then goes on where it was asked for")
    func inkAsks() {
        let harness = TextSizeEditorTests.Harness(withInk: true)
        let caret = NSRange(location: (harness.textView.text as NSString).range(of: "words").location + 2, length: 0)
        harness.textView.selectedRange = caret
        harness.editor.setSpanSize(.large)

        #expect(harness.editor.spanSizeAwaitingConfirmation == NoteEditor.SpanSizeRequest(size: .large, selection: caret))
        #expect(!harness.textView.text.contains("<span"), "nothing changes until the reader says so")

        // The alert took the keyboard; the selection it was asked for holds.
        harness.textView.selectedRange = NSRange(location: 0, length: 0)
        harness.editor.confirmSpanSize()
        #expect(harness.textView.text.contains("\(SpanStyle(size: .large).openTag)words</span>"))

        // One yes covers the note until it is next opened.
        harness.textView.selectedRange = NSRange(location: (harness.textView.text as NSString).range(of: "Title").location + 1, length: 0)
        harness.editor.setSpanSize(.small)
        #expect(harness.editor.spanSizeAwaitingConfirmation == nil)
        #expect(harness.textView.text.contains("\(SpanStyle(size: .small).openTag)Title</span>"))
    }

    @Test("Cancel changes nothing")
    func inkCancel() {
        let harness = TextSizeEditorTests.Harness(withInk: true)
        harness.textView.selectedRange = NSRange(location: (harness.textView.text as NSString).range(of: "words").location + 2, length: 0)
        harness.editor.setSpanSize(.large)
        harness.editor.cancelSpanSize()

        #expect(harness.editor.spanSizeAwaitingConfirmation == nil)
        #expect(!harness.textView.text.contains("<span"))
    }
}

#endif
