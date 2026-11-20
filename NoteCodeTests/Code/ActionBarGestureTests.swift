//
//  ActionBarGestureTests.swift
//  NoteCodeTests
//
//  AGENTS.md › Implementation requirements: when one of the text view's own
//  recognisers claims a touch on an action bar, UIKit cancels the button's
//  tracking and it never fires, so `DocumentUITextView` refuses to let them
//  begin there. `sendActions` can't see that conflict, and neither can this:
//  it checks the refusal itself, which a real tap (the iPad checklist) then
//  confirms.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Action bar gestures", .tags(.editor))
@MainActor
struct ActionBarGestureTests {

    /// A recogniser that reports its touch where the test says.
    private final class Touching: UITapGestureRecognizer {
        var point: CGPoint = .zero
        override func location(in view: UIView?) -> CGPoint { point }
    }

    @Test("The text view's recognisers don't begin on an action bar's button, and do elsewhere")
    func recognisersRefuseTheBar() async throws {
        let harness = EditorHarness()
        try await harness.caret(at: 2)
        let button = try #require(harness.languageButton)
        let tap = Touching()

        tap.point = CGPoint(x: button.frame.midX, y: button.frame.midY)
        #expect(!harness.textView.gestureRecognizerShouldBegin(tap), "on the button")

        tap.point = CGPoint(x: button.frame.maxX + 40, y: button.frame.midY)
        #expect(harness.textView.gestureRecognizerShouldBegin(tap), "beside it")
    }
}

#endif
