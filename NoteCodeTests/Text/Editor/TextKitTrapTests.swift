//
//  TextKitTrapTests.swift
//  NoteCodeTests
//
//  AGENTS.md › Implementation requirements: reading `.layoutManager` anywhere
//  on the text view silently downgrades it to TextKit 1. T8 of the refactor
//  plan: these fail when something does.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("TextKit 2 trap", .tags(.editor))
@MainActor
struct TextKitTrapTests {

    /// The premise. If UIKit stops downgrading, the trap is gone and so is the
    /// reason for `lint-traps.sh` rule 1.
    @Test("Reading .layoutManager on a TextKit 2 text view leaves textLayoutManager nil")
    func readingLayoutManagerDowngrades() {
        let textView = UITextView(usingTextLayoutManager: true)
        #expect(textView.textLayoutManager != nil)

        _ = textView.layoutManager  // the trap, on purpose, on a scratch view

        #expect(textView.textLayoutManager == nil)
    }

    @Test("The editor still has its TextKit 2 layout manager after styling, layout and typing")
    func editorStaysOnTextKit2() {
        let harness = EditorHarness("Intro\n\n```cpp\nint x = 1;\n```\n\nTail")
        harness.layOut()
        #expect(harness.textView.textLayoutManager != nil, "after opening")

        harness.type("\n```py\nprint(1)\n```\n", at: harness.source.length)
        harness.layOut()
        #expect(harness.textView.textLayoutManager != nil, "after typing a fence")
    }
}

#endif
