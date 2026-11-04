//
//  FormulaEditingTests.swift
//  NoteCodeTests
//
//  LaTeX, step 5: a drawn formula is one place for the caret, Backspace takes
//  all of it, a selection never ends inside one, and a tap lands on it. The
//  pure rules first, then the same through a real text view.
//

import Testing
import Foundation
@testable import NoteCode

@Suite("Formula editing: rules")
struct FormulaEditingRuleTests {

    static func spans(_ text: String) -> [FormulaEditing.Span] {
        FormulaEditing.spans(in: DocumentParser.parse(text), source: text)
    }

    @Test("Drawable formulas are found, inline and block; a broken one and currency are not")
    func finds() {
        let text = "a $x^2$ b and $\\frac{1}{2}$\n$$\nE=mc^2\n$$\ncosts $5 and $10 and $\\bad{$"
        let found = Self.spans(text)
        #expect(found.map(\.tex) == ["x^2", "\\frac{1}{2}", "\nE=mc^2\n"])
        #expect(found.map(\.isBlock) == [false, false, true])
        let ns = text as NSString
        #expect(ns.substring(with: found[0].range) == "$x^2$")
        #expect(ns.substring(with: found[2].range) == "$$\nE=mc^2\n$$")
    }

    @Test("Inside an inline formula the caret goes to the edge it came from, or the nearer one for a tap")
    func caretStops() {
        let text = "ab $xyz$ cd" as NSString
        let spans = Self.spans(text as String)   // 3 ..< 8
        #expect(spans.first?.range == NSRange(location: 3, length: 5))
        #expect(FormulaEditing.caretStop(for: 4, direction: 1, spans: spans, in: text) == 8)
        #expect(FormulaEditing.caretStop(for: 7, direction: -1, spans: spans, in: text) == 3)
        #expect(FormulaEditing.caretStop(for: 4, direction: 0, spans: spans, in: text) == 3)
        #expect(FormulaEditing.caretStop(for: 6, direction: 0, spans: spans, in: text) == 8)
        // Both edges are real places.
        #expect(FormulaEditing.caretStop(for: 3, direction: 0, spans: spans, in: text) == 3)
        #expect(FormulaEditing.caretStop(for: 8, direction: 0, spans: spans, in: text) == 8)
        #expect(FormulaEditing.caretStop(for: 1, direction: 0, spans: spans, in: text) == 1)
    }

    @Test("Inside a block the caret goes to its start, or the line after it")
    func blockStops() {
        let text = "a\n$$\nx\n$$\nb" as NSString
        let spans = Self.spans(text as String)   // 2 ..< 9
        #expect(spans.first?.range == NSRange(location: 2, length: 7))
        #expect(FormulaEditing.caretStop(for: 5, direction: 1, spans: spans, in: text) == 10)
        #expect(FormulaEditing.caretStop(for: 5, direction: -1, spans: spans, in: text) == 2)
        #expect(FormulaEditing.caretStop(for: 9, direction: 0, spans: spans, in: text) == 10)
        #expect(FormulaEditing.caretStop(for: 10, direction: 0, spans: spans, in: text) == 10)
    }

    @Test("Backspace after a formula, or inside it, deletes all of it as one edit")
    func backspace() {
        let text = "ab $xyz$ cd" as NSString
        let spans = Self.spans(text as String)
        for caret in [8, 6, 4] {
            let edit = FormulaEditing.backspace(at: caret, spans: spans, in: text)
            #expect(edit?.applied(to: text as String) == "ab  cd", "caret \(caret)")
            #expect(edit?.selection == NSRange(location: 3, length: 0))
        }
        #expect(FormulaEditing.backspace(at: 3, spans: spans, in: text) == nil)
        #expect(FormulaEditing.backspace(at: 9, spans: spans, in: text) == nil)
    }

    @Test("Backspace at the start of the line below a block takes the block and the break after it")
    func backspaceBelowABlock() {
        let text = "a\n$$\nx\n$$\nb" as NSString
        let spans = Self.spans(text as String)
        let edit = FormulaEditing.backspace(at: 10, spans: spans, in: text)
        #expect(edit?.applied(to: text as String) == "a\nb")
        #expect(edit?.selection == NSRange(location: 2, length: 0))
    }

    @Test("A selection edge inside a formula moves outwards; one outside is left alone")
    func snapping() {
        let text = "ab $xyz$ cd" as NSString
        let spans = Self.spans(text as String)
        #expect(FormulaEditing.snapped(NSRange(location: 0, length: 5), spans: spans, in: text) == NSRange(location: 0, length: 8))
        #expect(FormulaEditing.snapped(NSRange(location: 5, length: 6), spans: spans, in: text) == NSRange(location: 3, length: 8))
        #expect(FormulaEditing.snapped(NSRange(location: 4, length: 2), spans: spans, in: text) == NSRange(location: 3, length: 5))
        #expect(FormulaEditing.snapped(NSRange(location: 0, length: 3), spans: spans, in: text) == NSRange(location: 0, length: 3))
        #expect(FormulaEditing.snapped(NSRange(location: 8, length: 3), spans: spans, in: text) == NSRange(location: 8, length: 3))
    }

    @Test("What the editor writes keeps the formula one that parses")
    func cleaning() {
        #expect(FormulaEditing.cleaned("  a +\n b  ", isBlock: false) == "a + b")
        #expect(FormulaEditing.cleaned("5$ + $x", isBlock: false) == "5\\$ + \\$x")
        #expect(FormulaEditing.cleaned("\\$ ok", isBlock: false) == "\\$ ok")
        #expect(FormulaEditing.cleaned("a\n\n  b \n", isBlock: true) == "a\nb")
        // Whatever it writes still reads back as one formula.
        for (tex, block) in [("5$ + $x", false), (" a \n b ", false), ("x\n\ny", true)] {
            let written = FormulaEditing.cleaned(tex, isBlock: block)
            let note = block ? "$$\n\(written)\n$$" : "q $\(written)$ q"
            #expect(Self.spans(note).count == 1, "\(tex.debugDescription) -> \(note.debugDescription)")
        }
    }

    @Test("Done replaces the TeX and nothing around it, keeping the padding of `$$ x $$`")
    func writeBack() {
        let text = "q $a$ q\n$$ x $$\n" as NSString
        let spans = Self.spans(text as String)
        #expect(spans.count == 2)
        let inline = FormulaEditing.replacing(spans[0], with: "b+c", in: text)
        #expect(inline.applied(to: text as String) == "q $b+c$ q\n$$ x $$\n")
        #expect(inline.selection.location == 7)
        let block = FormulaEditing.replacing(spans[1], with: "y^2", in: text)
        #expect(block.applied(to: text as String) == "q $a$ q\n$$ y^2 $$\n")
    }

    @Test("A new formula is inserted over the selection; a display one on lines of its own")
    func inserting() {
        let text = "ab cd" as NSString
        let inline = FormulaEditing.inserting("x", display: false, over: NSRange(location: 2, length: 1), in: text)
        #expect(inline.applied(to: text as String) == "ab$x$cd")
        #expect(inline.selection == NSRange(location: 5, length: 0))

        let display = FormulaEditing.inserting("x", display: true, over: NSRange(location: 2, length: 1), in: text)
        #expect(display.applied(to: text as String) == "ab\n$$\nx\n$$\ncd")
        let atStart = FormulaEditing.inserting("x", display: true, over: NSRange(location: 0, length: 0), in: "" as NSString)
        #expect(atStart.applied(to: "") == "$$\nx\n$$")
        #expect(Self.spans(display.applied(to: text as String)).count == 1)
    }

    @Test("An unclosed dollar and a formula that can't be drawn leave the caret rules alone")
    func undrawable() {
        for text in ["a $\\bad{$ b", "a $x b", "$$ x"] {
            #expect(Self.spans(text).isEmpty, "\(text)")
        }
        let text = "a $\\bad{$ b" as NSString
        // The dollars of a formula nobody sees drawn aren't hidden markers.
        #expect(MarkdownFormatting.caretStop(for: 3, direction: 0, in: text, codeRanges: []) == 3)
        #expect(MarkdownFormatting.caretStop(for: 4, direction: 0, in: text, codeRanges: []) == 4)
    }
}

#if canImport(UIKit)

import UIKit

@Suite("Formula editing: in a text view")
@MainActor
struct FormulaEditingViewTests {

    static let note = "Intro $x^2$ outro\n\n$$\n\\sum_{i=1}^{n} i\n$$\n\nlast line\n"

    /// The rendered note, with the formulas swapped for attachments.
    static func harness(_ text: String = note) -> CodeFenceDisplayTests.Harness {
        let harness = CodeFenceDisplayTests.Harness(text)
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.layOut()
        return harness
    }

    /// The middle of the characters at `range`, in the text view.
    static func middle(of range: NSRange, in textView: UITextView) throws -> CGPoint {
        let start = try #require(textView.position(from: textView.beginningOfDocument, offset: range.location))
        let end = try #require(textView.position(from: start, offset: range.length))
        let rect = textView.firstRect(for: try #require(textView.textRange(from: start, to: end)))
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    @Test("A tap on an inline formula, and on a block's line, finds that formula; a tap on plain words doesn't")
    func tapFinds() throws {
        let harness = Self.harness()
        let textView = harness.textView
        let text = textView.textStorage.string as NSString
        let inline = text.range(of: "$x^2$")
        let block = text.range(of: "$$\n\\sum")
        try #require(inline.location != NSNotFound && block.location != NSNotFound)

        let onInline = harness.coordinator.markerTapTarget(
            at: try Self.middle(of: NSRange(location: inline.location, length: 1), in: textView), in: textView
        )
        guard case .formula(let span)? = onInline else {
            Issue.record("a tap on the inline formula found \(String(describing: onInline))")
            return
        }
        #expect(span.tex == "x^2" && !span.isBlock)

        let onBlock = harness.coordinator.markerTapTarget(
            at: try Self.middle(of: NSRange(location: block.location, length: 1), in: textView), in: textView
        )
        guard case .formula(let blockSpan)? = onBlock else {
            Issue.record("a tap on the block found \(String(describing: onBlock))")
            return
        }
        #expect(blockSpan.isBlock)

        let word = text.range(of: "last")
        #expect(harness.coordinator.markerTapTarget(at: try Self.middle(of: word, in: textView), in: textView) == nil)
        let intro = text.range(of: "Intro")
        #expect(harness.coordinator.markerTapTarget(at: try Self.middle(of: intro, in: textView), in: textView) == nil)
    }

    @Test("A formula is found in a locked note too, so its editor can open read-only")
    func lockedTap() throws {
        let harness = Self.harness()
        harness.textView.isEditable = false
        let text = harness.textView.textStorage.string as NSString
        let inline = text.range(of: "$x^2$")
        let target = harness.coordinator.markerTapTarget(
            at: try Self.middle(of: NSRange(location: inline.location, length: 1), in: harness.textView),
            in: harness.textView
        )
        guard case .formula? = target else {
            Issue.record("found \(String(describing: target))")
            return
        }
    }

    @Test("Backspace after a formula deletes it whole, and undo brings it back in one step")
    func backspaceAndUndo() async throws {
        let harness = Self.harness()
        let textView = harness.textView
        textView.becomeFirstResponder()
        let text = textView.textStorage.string as NSString
        let inline = text.range(of: "$x^2$")
        let caret = NSMaxRange(inline)
        textView.selectedRange = NSRange(location: caret, length: 0)
        let before = textView.text

        // What the delegate is asked when Backspace is pressed there.
        let last = NSRange(location: caret - 1, length: 1)
        let allowed = harness.coordinator.textView(textView, shouldChangeTextIn: last, replacementText: "")
        #expect(!allowed, "the coordinator makes the edit itself")
        #expect(textView.text == "Intro  outro\n\n$$\n\\sum_{i=1}^{n} i\n$$\n\nlast line\n")
        #expect(textView.selectedRange == NSRange(location: inline.location, length: 0))

        // A turn of the run loop later, as a reader's next action would be.
        try await Task.sleep(for: .milliseconds(50))
        let undo = try #require(textView.undoManager)
        undo.undo()
        #expect(textView.text == before, "one undo step puts the whole formula back")
        undo.redo()
        #expect(textView.text.contains("Intro  outro"))
    }

    @Test("Backspace on the line below a block deletes the block, and undo returns it")
    func backspaceBelowBlock() async throws {
        let harness = Self.harness("a\n$$\nx^2\n$$\nb")
        let textView = harness.textView
        textView.becomeFirstResponder()
        let before = textView.text
        let caret = (before! as NSString).range(of: "b").location
        textView.selectedRange = NSRange(location: caret, length: 0)
        let allowed = harness.coordinator.textView(textView, shouldChangeTextIn: NSRange(location: caret - 1, length: 1), replacementText: "")
        #expect(!allowed)
        #expect(textView.text == "a\nb")
        try await Task.sleep(for: .milliseconds(50))
        textView.undoManager?.undo()
        #expect(textView.text == before)
    }

    @Test("The caret tapped into a formula stands beside it, and a selection ending inside one takes it whole")
    func snapsInTheView() {
        let harness = Self.harness()
        let textView = harness.textView
        let text = textView.textStorage.string as NSString
        let inline = text.range(of: "$x^2$")

        textView.selectedRange = NSRange(location: inline.location + 2, length: 0)
        harness.coordinator.textViewDidChangeSelection(textView)
        #expect(textView.selectedRange.location == inline.location || textView.selectedRange.location == NSMaxRange(inline))

        textView.selectedRange = NSRange(location: 0, length: inline.location + 2)
        harness.coordinator.textViewDidChangeSelection(textView)
        #expect(textView.selectedRange == NSRange(location: 0, length: NSMaxRange(inline)))
    }

    @Test("Done writes the new TeX back as one undo step")
    func doneIsOneStep() async throws {
        let harness = Self.harness()
        let textView = harness.textView
        textView.becomeFirstResponder()
        let before = textView.text
        let spans = harness.coordinator.formulaSpans(in: textView)
        let edit = FormulaEditing.replacing(spans[0], with: "y^3", in: textView.textStorage.mutableString)
        harness.coordinator.apply(edit, to: textView)
        #expect(textView.text.contains("$y^3$"))
        try await Task.sleep(for: .milliseconds(50))
        textView.undoManager?.undo()
        #expect(textView.text == before)
    }
}

#endif
