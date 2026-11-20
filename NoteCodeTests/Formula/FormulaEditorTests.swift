//
//  FormulaEditorTests.swift
//  NoteCodeTests
//
//  T5, before 2T5: the formula popover as it behaves today. A tap on a
//  formula opens it on the formula's source; Done writes the source back,
//  Remove takes the formula out and Cancel changes nothing. Style ▾ opens it
//  for a new formula over the selection. The tests press the popover's
//  buttons the way its view does: Done hands over `model.cleaned`.
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("The formula editor", .tags(.editor))
@MainActor
struct FormulaEditorTests {

    /// A note open in a window that can present, as the app's can.
    private func open(_ text: String) -> EditorHarness {
        let harness = EditorHarness(text)
        harness.window.rootViewController = UIViewController()
        return harness
    }

    private func presented(in harness: EditorHarness) -> UIHostingController<FormulaEditor>? {
        harness.window.rootViewController?.presentedViewController as? UIHostingController<FormulaEditor>
    }

    /// Whether the popover goes. It was presented animated, so it leaves
    /// once its presentation has finished, not at once.
    private func closes(in harness: EditorHarness) async -> Bool {
        await waitFor { presented(in: harness) == nil }
    }

    /// The popover's model, after a tap on the formula at `index`.
    private func tapFormula(_ index: Int = 0, in harness: EditorHarness) throws -> FormulaEditorModel {
        let text = harness.text
        let span = try #require(FormulaEditing.spans(in: DocumentParser.parse(text), source: text).dropFirst(index).first)
        harness.coordinator.handleMarkerTap(.formula(span), in: harness.textView)
        return try #require(presented(in: harness)).rootView.model
    }

    @Test("A tap on an inline formula opens the editor on its source")
    func opensOnTheSource() throws {
        let harness = open("Area $x^2$ here\n")
        let model = try tapFormula(in: harness)

        #expect(model.tex == "x^2")
        #expect(!model.display)
        #expect(!model.isBlock)
        #expect(!model.isNew)
        #expect(!model.isReadOnly)
    }

    @Test("Done writes the edited source into the note, and closes the editor")
    func doneWrites() async throws {
        let harness = open("Area $x^2$ here\n")
        let model = try tapFormula(in: harness)

        model.tex = "y^3"
        model.onDone(model.cleaned)

        #expect(harness.text == "Area $y^3$ here\n")
        #expect(harness.stored == harness.text, "the note's stored text has it too")
        #expect(await closes(in: harness))
    }

    @Test("Cancel leaves the note as it was, whatever was typed")
    func cancelLeavesTheText() async throws {
        let harness = open("Area $x^2$ here\n")
        let model = try tapFormula(in: harness)

        model.tex = "y^3"
        model.onCancel()

        #expect(harness.text == "Area $x^2$ here\n")
        #expect(await closes(in: harness))
    }

    @Test("Remove takes the formula and its dollars out")
    func removeTakesItOut() throws {
        let harness = open("Area $x^2$ here\n")
        let model = try tapFormula(in: harness)

        model.onRemove()

        #expect(harness.text == "Area  here\n")
    }

    @Test("A display formula opens as one, and Done keeps it a block")
    func displayFormula() throws {
        let harness = open("Energy\n$$\nE=mc^2\n$$\nafter\n")
        let model = try tapFormula(in: harness)
        #expect(model.tex == "E=mc^2")
        #expect(model.display)
        #expect(model.isBlock)

        model.tex = "a+b"
        model.onDone(model.cleaned)

        #expect(harness.text == "Energy\n$$\na+b\n$$\nafter\n")
    }

    @Test("The second formula on a line opens on its own source")
    func secondFormula() throws {
        let harness = open("Both $a$ and $b+c$ here\n")
        let model = try tapFormula(1, in: harness)
        #expect(model.tex == "b+c")

        model.tex = "d"
        model.onDone(model.cleaned)
        #expect(harness.text == "Both $a$ and $d$ here\n")
    }

    @Test("In a locked note the editor opens read-only")
    func lockedIsReadOnly() throws {
        let harness = open("Area $x^2$ here\n")
        harness.editor.setTextLocked(true)
        try #require(!harness.textView.isEditable)

        let model = try tapFormula(in: harness)

        #expect(model.isReadOnly)
        #expect(model.tex == "x^2")
    }

    @Test("A new formula starts from the selection, and Done puts it in dollars over it")
    func newOverTheSelection() throws {
        let harness = open("Sum x+1 end\n")
        harness.textView.selectedRange = harness.source.range(of: "x+1")

        harness.coordinator.presentNewFormulaEditor(display: false, in: harness.textView)
        let model = try #require(presented(in: harness)).rootView.model
        #expect(model.isNew)
        #expect(model.tex == "x+1")

        model.onDone(model.cleaned)
        #expect(harness.text == "Sum $x+1$ end\n")
    }

    @Test("A new formula has no Done while it is empty: its source is empty and cleaned to nothing")
    func newFromNothing() throws {
        let harness = open("Sum end\n")
        harness.textView.selectedRange = NSRange(location: 4, length: 0)

        harness.coordinator.presentNewFormulaEditor(display: false, in: harness.textView)
        let model = try #require(presented(in: harness)).rootView.model

        #expect(model.tex.isEmpty)
        // The view disables Done on this.
        #expect(model.cleaned.isEmpty)
    }

    @Test("No new formula opens inside a code block, or in a locked note")
    func newRefused() throws {
        let code = open("```cpp\nint x = 1;\n```\n")
        code.textView.selectedRange = NSRange(location: code.offset(of: "int"), length: 0)
        code.coordinator.presentNewFormulaEditor(display: false, in: code.textView)
        #expect(presented(in: code) == nil)

        let locked = open("Sum end\n")
        locked.editor.setTextLocked(true)
        locked.coordinator.presentNewFormulaEditor(display: false, in: locked.textView)
        #expect(presented(in: locked) == nil)
    }
}

#endif
