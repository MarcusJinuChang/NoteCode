//
//  DocumentTextViewTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Editor text view")
@MainActor
struct DocumentTextViewTests {

    @Test("The editor is backed by TextKit 2, not TextKit 1")
    func usesTextKit2() {
        let textView = DocumentTextView.makeConfiguredTextView()

        // If this ever fails, something read the legacy `.layoutManager`
        // property and silently downgraded the view — fence rendering would
        // stop running with no other symptom.
        #expect(textView.textLayoutManager != nil)
    }

    @Test("Nothing that rewrites typed text is enabled")
    func textRewritingDisabled() {
        let textView = DocumentTextView.makeConfiguredTextView()

        // Autocorrect is the dangerous one: it rewrote `int lo` to `In too`
        // when this was first run on the simulator.
        #expect(textView.autocorrectionType == .no)
        #expect(textView.autocapitalizationType == .none)
        #expect(textView.smartQuotesType == .no)
        #expect(textView.smartDashesType == .no)
        #expect(textView.smartInsertDeleteType == .no)
    }

    @Test("Styling does not downgrade the view to TextKit 1")
    func stylingKeepsTextKit2() {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = "prose\n```cpp\nint x;\n```\n"
        DocumentStyler.applyStyling(to: textView)

        #expect(textView.textLayoutManager != nil)
    }

    /// The container reports a width of -16 (zero bounds minus two lots of
    /// line-fragment padding) until the view has a frame. CodeBlockLayoutFragment
    /// resolves its panel width at draw time for exactly this reason — reading
    /// it when the fragment is created produced a negative-width panel.
    @Test("The text container reports a usable width once laid out")
    func containerReportsWidth() {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        textView.layoutIfNeeded()

        let width = textView.textLayoutManager?.textContainer?.size.width
        #expect(width != nil)
        #expect((width ?? 0) > 100)
    }

    @Test("The editor is editable and scrolls")
    func editableAndScrollable() {
        let textView = DocumentTextView.makeConfiguredTextView()

        #expect(textView.isEditable)
        #expect(textView.isScrollEnabled)
    }
}

#endif
