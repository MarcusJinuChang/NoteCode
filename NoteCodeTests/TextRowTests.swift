//
//  TextRowTests.swift
//  NoteCodeTests
//
//  Phase 6 of v3: the text options row's controls. Each does what a menu
//  already did, through the same edits, so each undoes like typing.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Text row: link and output edits")
struct TextRowEditTests {

    private func target(_ marked: String, code: [CodeRange] = []) -> (text: String, range: NSRange?) {
        let caret = (marked as NSString).range(of: "|")
        let text = marked.replacingOccurrences(of: "|", with: "")
        return (text, MarkdownFormatting.linkTarget(
            in: text as NSString, selection: NSRange(location: caret.location, length: 0), codeRanges: code
        ))
    }

    @Test("A selection is what a link wraps")
    func selection() {
        let text = "see the notes here" as NSString
        let range = MarkdownFormatting.linkTarget(in: text, selection: NSRange(location: 4, length: 9), codeRanges: [])
        #expect(range == NSRange(location: 4, length: 9))
    }

    @Test("With a caret, the word it is in or against")
    func wordAtCaret() {
        #expect(target("see the no|tes here").range == NSRange(location: 8, length: 5))
        #expect(target("see the notes| here").range == NSRange(location: 8, length: 5), "against the word's end")
        #expect(target("see |the notes").range == NSRange(location: 4, length: 3), "against its start")
        #expect(target("my_var|name").range == NSRange(location: 0, length: 10), "an identifier is one word")
    }

    @Test("With no word, an empty range at the caret, for a placeholder")
    func noWord() {
        #expect(target("a  |  b").range == NSRange(location: 3, length: 0))
        #expect(target("|").range == NSRange(location: 0, length: 0))
    }

    @Test("No link where one can't go: across lines, over brackets, in code, or in a link")
    func refused() {
        let text = "one\ntwo" as NSString
        #expect(MarkdownFormatting.linkTarget(in: text, selection: NSRange(location: 0, length: 7), codeRanges: []) == nil)
        let bracketed = "a [b] c" as NSString
        #expect(MarkdownFormatting.linkTarget(in: bracketed, selection: NSRange(location: 0, length: 5), codeRanges: []) == nil)

        let source = "```cpp\nint x;\n```\n"
        let code = [CodeRange(range: NSRange(location: 0, length: (source as NSString).length), isClosed: true)]
        #expect(MarkdownFormatting.linkTarget(in: source as NSString, selection: NSRange(location: 9, length: 0), codeRanges: code) == nil)

        #expect(target("see [the no|tes](http://a.b) now").range == nil, "already a link")
    }

    @Test("The edit is [text](address), the caret after it, and a placeholder when nothing was selected")
    func linkEdit() {
        let text = "see notes here"
        let edit = MarkdownFormatting.link(address: "https://a.b/c", over: NSRange(location: 4, length: 5), in: text as NSString)
        #expect(edit.applied(to: text) == "see [notes](https://a.b/c) here")
        #expect(edit.selection == NSRange(location: 4 + "[notes](https://a.b/c)".count, length: 0))

        let none = MarkdownFormatting.link(address: "x.org", over: NSRange(location: 3, length: 0), in: text as NSString)
        #expect(none.applied(to: text) == "see[link](x.org) notes here")
    }

    @Test("An address is trimmed, and what would end it early is escaped")
    func address() {
        #expect(MarkdownFormatting.linkAddress(from: "  example.com/a b  ") == "example.com/a%20b")
        #expect(MarkdownFormatting.linkAddress(from: "https://x.org/f_(1)") == "https://x.org/f_%281%29")
        #expect(MarkdownFormatting.linkAddress(from: "   ") == nil)
        #expect(MarkdownFormatting.linkAddress(from: "") == nil)
    }

    @Test("The link the edit makes is a link to the parser, with that address")
    func parsesAsALink() throws {
        let text = "see notes here"
        let edit = MarkdownFormatting.link(address: "https://a.b/c", over: NSRange(location: 4, length: 5), in: text as NSString)
        let result = edit.applied(to: text)
        let block = try #require(DocumentParser.parse(result).first)
        let link = try #require(block.inlines.first { $0.kind == .link })
        #expect(String(result[link.contentRange]) == "notes")
        #expect(link.destination.map { String(result[$0]) } == "https://a.b/c")
    }

    // MARK: Output

    private func output(_ marked: String) -> (text: String, edit: TextEdit?, ranges: [CodeRange]) {
        let caret = (marked as NSString).range(of: "|")
        let text = marked.replacingOccurrences(of: "|", with: "")
        let source = text.nativeUTF8
        let ranges = CodeBlockAction.targets(in: source, blocks: DocumentParser.parse(source)).map {
            CodeRange(range: $0.range, isClosed: source.contains("\n```\n") || source.hasSuffix("\n```"), isOutput: $0.isOutput, language: $0.language, tag: $0.tag)
        }
        // CodeRange needs the parser's own closed flag; take it from the blocks.
        let blocks = DocumentParser.parse(source)
        let real = blocks.compactMap { block -> CodeRange? in
            guard let code = block.codeBlock else { return nil }
            let range = NSRange(block.range, in: source)
            let terminator = code.isClosed ? source[block.range].last.flatMap { $0.isNewline ? $0.utf16.count : nil } ?? 0 : 0
            return CodeRange(range: range, isClosed: code.isClosed, lastCaret: range.location + range.length - terminator, isOutput: code.isOutput, language: code.language, tag: code.infoString.split(separator: " ").first.map(String.init) ?? "")
        }
        _ = ranges
        return (text, MarkdownFormatting.insertOutputBlock(afterBlockAt: caret.location, in: text as NSString, codeRanges: real), real)
    }

    @Test("An empty output block goes directly under the code block, the caret in it")
    func outputAfterABlock() throws {
        let (text, maybe, _) = output("Intro\n```cpp\nint |x;\n```\nAfter\n")
        let edit = try #require(maybe)
        let result = edit.applied(to: text)
        #expect(result == "Intro\n```cpp\nint x;\n```\n```output\n\n```\nAfter\n")
        #expect((result as NSString).substring(to: edit.selection.location).hasSuffix("```output\n"), "the caret is on the new block's empty line")

        let blocks = DocumentParser.parse(result)
        let kinds = blocks.compactMap(\.codeBlock).map(\.isOutput)
        #expect(kinds == [false, true])
        #expect(blocks.last.map { !$0.isCode } == true || blocks.count >= 4)
    }

    @Test("A closing fence on the note's last line, with no newline, still gets a block after it")
    func outputAtTheEnd() throws {
        let (text, maybe, _) = output("```py\nprint(1)|\n```")
        let result = try #require(maybe).applied(to: text)
        #expect(result == "```py\nprint(1)\n```\n```output\n\n```")
        #expect(DocumentParser.parse(result).compactMap(\.codeBlock).map(\.isOutput) == [false, true])
    }

    @Test("An unclosed block has no place after it, and a caret in prose has no block")
    func outputRefused() {
        #expect(output("```cpp\nint x;|\n").edit == nil)
        #expect(output("pro|se\n```cpp\nx\n```\n").edit == nil)
    }
}

#if canImport(UIKit)

import SwiftUI
import UIKit

@Suite("Text row: the controls' edits", .serialized)
@MainActor
struct TextRowEditorTests {

    @MainActor
    final class Harness {
        var stored: String
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        let textView = DocumentTextView.makeConfiguredTextView()
        let editor = NoteEditor()
        let page: PageView
        var coordinator: DocumentTextView.Coordinator!

        /// - Parameter marked: the note, with `|` where the caret is.
        init(_ marked: String) {
            let caret = (marked as NSString).range(of: "|")
            stored = marked.replacingOccurrences(of: "|", with: "")
            page = PageView(textView: textView)
            coordinator = DocumentTextView.Coordinator(
                text: Binding(get: { [unowned self] in stored }, set: { [unowned self] in stored = $0 })
            )
            coordinator.editor = editor
            textView.delegate = coordinator
            textView.textLayoutManager?.delegate = coordinator
            coordinator.observeEdits(of: textView)
            coordinator.attachOverlay(to: textView)
            coordinator.setRendersMarkdown(true, in: textView)
            textView.text = stored
            coordinator.invalidateStyling()
            coordinator.restyle(textView)
            page.frame = window.bounds
            window.addSubview(page)
            window.makeKeyAndVisible()
            page.layoutIfNeeded()
            editor.attach(textView, canvas: page.canvas, page: page)
            coordinator.connect(editor, to: textView)
            textView.selectedRange = NSRange(location: caret.location, length: 0)
            coordinator.refreshCaretFormatting(in: textView)
        }

        /// Each tap of a chip is its own turn of the run loop in the app, and
        /// so its own undo step: UIKit closes an undo group at the end of the
        /// turn. A test makes its edits back to back, in one turn, and a
        /// single undo would take them all.
        func nextTap() async {
            try? await Task.sleep(for: .milliseconds(30))
        }

        var text: String { textView.text ?? "" }
        var block: MarkdownFormatting.CaretFormatting.Block { editor.caretFormatting.block }
    }

    // MARK: What the row shows

    @Test("The row follows the caret: paragraph, list item, then code with its language")
    func followsTheCaret() {
        let harness = Harness("Prose| here\n- item\n```cpp\nint x;\n```\n```ruby\nx\n```\n")
        #expect(harness.block == .paragraph)

        harness.textView.selectedRange = NSRange(location: 14, length: 0)
        harness.coordinator.refreshCaretFormatting(in: harness.textView)
        #expect(harness.block == .listItem)

        let cpp = (harness.text as NSString).range(of: "int x").location
        harness.textView.selectedRange = NSRange(location: cpp, length: 0)
        harness.coordinator.refreshCaretFormatting(in: harness.textView)
        #expect(harness.block == .code(label: "C++", kind: .language(.cpp), isClosed: true))

        let ruby = (harness.text as NSString).range(of: "x\n```\n", options: .backwards).location
        harness.textView.selectedRange = NSRange(location: ruby, length: 0)
        harness.coordinator.refreshCaretFormatting(in: harness.textView)
        #expect(harness.block == .code(label: "ruby", kind: nil, isClosed: true), "a tag the app doesn't know keeps its own name")
    }

    // MARK: Paragraph and heading

    @Test("Body, H1, H2 and H3 are the Style menu's edits, and one undo takes a chip back")
    func headingChips() async {
        let harness = Harness("Wo|rds here\n")
        harness.editor.setHeading(level: 2)
        #expect(harness.text == "## Words here\n")
        #expect(harness.editor.caretFormatting.headingLevel == 2, "the chip lights for the heading it made")

        await harness.nextTap()
        harness.editor.setHeading(level: 0)
        #expect(harness.text == "Words here\n")

        harness.editor.undo()
        #expect(harness.text == "## Words here\n", "undo after a style chip")
        harness.editor.undo()
        #expect(harness.text == "Words here\n")
    }

    // MARK: Link

    @Test("Link asks for an address, wraps the word, and one undo takes it back")
    func linkFlow() {
        let harness = Harness("see no|tes here\n")
        harness.editor.beginLink()
        #expect(harness.editor.linkTarget == NSRange(location: 4, length: 5))

        harness.editor.finishLink(address: "example.com/a b")

        #expect(harness.text == "see [notes](example.com/a%20b) here\n")
        #expect(harness.stored == harness.text, "the page has it")
        #expect(harness.editor.linkTarget == nil)

        harness.editor.undo()
        #expect(harness.text == "see notes here\n")
    }

    @Test("Cancel, or an empty address, adds nothing")
    func linkCancelled() {
        let harness = Harness("see no|tes here\n")
        harness.editor.beginLink()
        harness.editor.cancelLink()
        #expect(harness.editor.linkTarget == nil)
        #expect(harness.text == "see notes here\n")

        harness.editor.beginLink()
        harness.editor.finishLink(address: "   ")
        #expect(harness.text == "see notes here\n")
        #expect(harness.editor.linkTarget == nil)
    }

    @Test("Link has nothing to do in code")
    func noLinkInCode() {
        let harness = Harness("```cpp\nint |x;\n```\n")
        harness.editor.beginLink()
        #expect(harness.editor.linkTarget == nil)
    }

    // MARK: Lists

    @Test("In a list item the chips convert the list and nest it, and undo takes each back")
    func listChips() async {
        let harness = Harness("- ite|m\n")
        harness.editor.toggleList(.numbered)
        #expect(harness.text == "1. item\n")
        await harness.nextTap()
        harness.editor.toggleList(.checklist)
        #expect(harness.text == "- [ ] item\n")
        await harness.nextTap()
        harness.editor.toggleList(.checklist)
        #expect(harness.text == "item\n", "the current kind takes the list off, as the List menu does")
        await harness.nextTap()
        harness.editor.undo()
        #expect(harness.text == "- [ ] item\n")
    }

    @Test("⇥ and ⇤ nest a list item two spaces, and take them back")
    func listIndent() async {
        let harness = Harness("- one\n- tw|o\n")
        harness.editor.indent(outdent: false)
        #expect(harness.text == "- one\n  - two\n")
        await harness.nextTap()
        harness.editor.indent(outdent: true)
        #expect(harness.text == "- one\n- two\n")
        await harness.nextTap()
        harness.editor.undo()
        #expect(harness.text == "- one\n  - two\n")
    }

    // MARK: Code

    @Test("⇥ and ⇤ indent the code line by the indent width, and ⇤ takes it back")
    func codeIndent() {
        let harness = Harness("```cpp\nint| x;\n```\n")
        harness.editor.indent(outdent: false)
        #expect(harness.text == "```cpp\n    int x;\n```\n")
        harness.editor.indent(outdent: true)
        #expect(harness.text == "```cpp\nint x;\n```\n")
    }

    @Test("The language menu points the block at another language, as the block's own button does")
    func codeLanguage() async {
        let harness = Harness("```cpp\nint| x;\n```\n")
        harness.editor.setCodeBlockKind(.language(.python))
        #expect(harness.text == "```python\nint x;\n```\n")
        await harness.nextTap()
        harness.editor.setCodeBlockKind(.output)
        #expect(harness.text == "```output\nint x;\n```\n")
        await harness.nextTap()
        harness.editor.setCodeBlockKind(.plain)
        #expect(harness.text == "```\nint x;\n```\n")
        await harness.nextTap()
        harness.editor.undo()
        #expect(harness.text == "```output\nint x;\n```\n", "undo after a retag, which the keyboard-rewrite guard once turned away")
    }

    @Test("+ Output adds an empty output block under the code block, with the caret in it")
    func addOutput() {
        let harness = Harness("```cpp\nint| x;\n```\nAfter\n")
        harness.editor.addOutputBlock()

        #expect(harness.text == "```cpp\nint x;\n```\n```output\n\n```\nAfter\n")
        #expect(harness.stored == harness.text)
        #expect(harness.textView.selectedRange.location == ("```cpp\nint x;\n```\n```output\n" as NSString).length)
        if case .code(_, let kind, _) = harness.block { #expect(kind == .output) } else { Issue.record("the caret should be in the output block") }

        harness.editor.undo()
        #expect(harness.text == "```cpp\nint x;\n```\nAfter\n")
    }

    // MARK: Locked, and ink

    @Test("A locked note's text isn't changed by any of them")
    func lockedNote() {
        let harness = Harness("- ite|m\n")
        harness.editor.setTextLocked(true)
        harness.editor.indent(outdent: false)
        harness.editor.toggleList(.numbered)
        harness.editor.beginLink()
        harness.editor.setCodeBlockKind(.plain)
        harness.editor.addOutputBlock()
        #expect(harness.text == "- item\n")
        #expect(harness.editor.linkTarget == nil)
    }

    @Test("In ink mode they do nothing either")
    func inkMode() {
        let harness = Harness("- ite|m\n")
        harness.editor.setMode(.ink)
        harness.editor.indent(outdent: false)
        harness.editor.setCodeBlockKind(.plain)
        #expect(harness.text == "- item\n")
    }
}

#endif
