//
//  TextRewritingPolicyTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Text rewriting policy")
@MainActor
struct TextRewritingPolicyTests {

    @Test("The code policy disables every rewriting trait")
    func codeDisablesEverything() {
        let textView = UITextView()
        TextRewritingPolicy.code.apply(to: textView)

        #expect(textView.autocorrectionType == .no)
        #expect(textView.autocapitalizationType == .none)
        #expect(textView.smartQuotesType == .no)
        #expect(textView.smartDashesType == .no)
        #expect(textView.smartInsertDeleteType == .no)
    }

    @Test("The prose policy enables every rewriting trait")
    func proseEnablesEverything() {
        let textView = UITextView()
        TextRewritingPolicy.code.apply(to: textView)   // start from off
        TextRewritingPolicy.prose.apply(to: textView)

        #expect(textView.autocorrectionType == .yes)
        #expect(textView.autocapitalizationType == .sentences)
        #expect(textView.smartQuotesType == .yes)
        #expect(textView.smartDashesType == .yes)
        #expect(textView.smartInsertDeleteType == .yes)
    }

    @Test("Switching policies round-trips cleanly")
    func policiesRoundTrip() {
        let textView = UITextView()

        TextRewritingPolicy.prose.apply(to: textView)
        TextRewritingPolicy.code.apply(to: textView)

        #expect(textView.autocorrectionType == .no)
        #expect(textView.smartQuotesType == .no)
    }

    @Test("Today's policy is code, so nothing rewrites what is typed")
    func currentPolicyIsCode() {
        #expect(TextRewritingPolicy.current == .code)
    }
}

#endif
