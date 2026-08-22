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

    @Test("The editor is editable and scrolls")
    func editableAndScrollable() {
        let textView = DocumentTextView.makeConfiguredTextView()

        #expect(textView.isEditable)
        #expect(textView.isScrollEnabled)
    }
}

#endif
