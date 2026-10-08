//
//  TextRewritingPolicyTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("Text rewriting policy")
@MainActor
struct TextRewritingPolicyTests {

    // MARK: Traits

    @Test("The code policy disables every rewriting trait")
    func codeDisablesEverything() {
        let textView = UITextView()
        TextRewritingPolicy.code.apply(to: textView)

        #expect(textView.autocorrectionType == .no)
        #expect(textView.autocapitalizationType == .none)
        #expect(textView.smartQuotesType == .no)
        #expect(textView.smartDashesType == .no)
        #expect(textView.smartInsertDeleteType == .no)
        #expect(textView.inlinePredictionType == .no)
        #expect(textView.spellCheckingType == .no)
    }

    @Test("The prose policy enables every rewriting trait, and leaves spell checking off")
    func proseEnablesEverything() {
        let textView = UITextView()
        TextRewritingPolicy.code.apply(to: textView)   // start from off
        TextRewritingPolicy.prose.apply(to: textView)

        #expect(textView.autocorrectionType == .yes)
        #expect(textView.autocapitalizationType == .sentences)
        #expect(textView.smartQuotesType == .yes)
        #expect(textView.smartDashesType == .yes)
        #expect(textView.smartInsertDeleteType == .yes)
        #expect(textView.inlinePredictionType == .default)
        #expect(textView.spellCheckingType == .no)
    }

    @Test("Switching policies round-trips cleanly")
    func policiesRoundTrip() {
        let textView = UITextView()

        TextRewritingPolicy.prose.apply(to: textView)
        TextRewritingPolicy.code.apply(to: textView)

        #expect(textView.autocorrectionType == .no)
        #expect(textView.smartQuotesType == .no)
        #expect(textView.inlinePredictionType == .no)
    }

    @Test("A new editor rewrites nothing until the caret is placed")
    func initialPolicyIsCode() {
        #expect(TextRewritingPolicy.initial == .code)
    }

    // MARK: Where each applies

    /// The policy at the `|` in `marked`, which is taken out first.
    private func policy(_ marked: String) -> TextRewritingPolicy {
        let caret = marked.range(of: "|")!
        let offset = NSRange(caret, in: marked).location
        let source = marked.replacingCharacters(in: caret, with: "")
        return TextRewritingPolicy.at(offset, in: source, blocks: DocumentParser.parse(source))
    }

    @Test("Prose, headings and list items are prose")
    func proseLines() {
        #expect(policy("|") == .prose)                      // an empty note
        #expect(policy("the pointer| holds") == .prose)
        #expect(policy("# Lect|ure") == .prose)
        #expect(policy("- first ite|m\n") == .prose)
        #expect(policy("1. second|") == .prose)
    }

    @Test("A code block's lines and fences are code")
    func codeBlockLines() {
        #expect(policy("Before\n```cpp|\nint lo = 0;\n```\nAfter") == .code)   // opening fence
        #expect(policy("Before\n```cpp\nint lo| = 0;\n```\nAfter") == .code)
        #expect(policy("Before\n```cpp\n|int lo = 0;\n```\nAfter") == .code)   // start of a code line
        #expect(policy("Before\n```cpp\nint lo = 0;\n```|\nAfter") == .code)   // closing fence
        #expect(policy("Before\n```cpp\nint lo = 0;\n```\n|After") == .prose)  // the line after
        #expect(policy("Before|\n```cpp\nint lo = 0;\n```\nAfter") == .prose)  // the line before
    }

    @Test("A fence being typed is code from its first backtick")
    func fenceBeingTyped() {
        #expect(policy("Notes\n`|") == .code)
        #expect(policy("Notes\n``|") == .code)
        #expect(policy("Notes\n```|") == .code)
        #expect(policy("Notes\n```py|") == .code)
        #expect(policy("Notes\n```python\npri|") == .code)
    }

    @Test("The note's last line follows the block it belongs to")
    func lastLine() {
        // A new line after a closed block is prose; still on the closing
        // fence, or anywhere in an unclosed block, is code.
        #expect(policy("```cpp\nx;\n```\n|") == .prose)
        #expect(policy("```cpp\nx;\n```|") == .code)
        #expect(policy("```cpp\nx;\n|") == .code)
        #expect(policy("```cpp\n|") == .code)
        #expect(policy("prose\n|") == .prose)
    }

    @Test("Inline code is code, between its backticks")
    func inlineCode() {
        #expect(policy("use `vec|tor` here") == .code)
        #expect(policy("use `|vector` here") == .code)     // right after the opening backtick
        #expect(policy("use `vector|` here") == .code)     // right before the closing one
        #expect(policy("use `vector` |here") == .prose)    // past the closing one and a space
        #expect(policy("use |`vector` here") == .prose)    // before the opening one
        #expect(policy("use `vector` and `ma|p`") == .code)
        #expect(policy("use `vector` and |`map`") == .prose)
    }

    @Test("The word after inline code stays code until a space ends it")
    func wordTouchingInlineCode() {
        // The keyboard corrects the word a space ends, and its word runs
        // through a backtick: "use `int lo` " became "use `int lot " (3 Oct).
        #expect(policy("use `int lo`|") == .code)
        #expect(policy("use `vector`s|") == .code)
        #expect(policy("use `vector`| here") == .code)
        #expect(policy("use `vector` |") == .prose)
        #expect(policy("use `vector` teh|") == .prose)
        #expect(policy("use `vector`\n|") == .prose)       // a new line
    }

    @Test("Inline code being typed is code before its closing backtick")
    func inlineCodeBeingTyped() {
        #expect(policy("use `int lo|") == .code)
        #expect(policy("use `vector` then `int lo|") == .code)
        #expect(policy("use `|`") == .code)                // between an empty pair
    }

    @Test("Backticks inside a code block don't change anything")
    func backticksInCode() {
        #expect(policy("```sh\necho `date`|\n```") == .code)
    }

    @Test("Windows line endings put the caret on the right line")
    func crlf() {
        #expect(policy("```cpp\r\nint lo;\r\n```\r\n|After") == .prose)
        #expect(policy("```cpp\r\nint lo|;\r\n```\r\nAfter") == .code)
    }

    // MARK: Rewrites behind the caret

    /// Whether the keyboard replacing the «marked» text with `replacement`
    /// would change code.
    private func rewrite(_ marked: String, to replacement: String) -> Bool {
        let open = marked.range(of: "«")!, close = marked.range(of: "»")!
        let range = NSRange(
            location: NSRange(open, in: marked).location,
            length: NSRange(open.upperBound..<close.lowerBound, in: marked).length
        )
        let source = marked.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
        return TextRewritingPolicy.rewriteChangesCode(range, with: replacement, in: source, blocks: DocumentParser.parse(source))
    }

    @Test("The keyboard can't rewrite code behind the caret")
    func rewritesOfCode() {
        // A space after "now" turned "lo` now" into "log now" (3 Oct).
        #expect(rewrite("use `int «lo` now»", to: "log now"))
        #expect(rewrite("use `int «lo`»", to: "lot"))
        #expect(rewrite("use `«int» lo` now", to: "Int"))                // inside the span
        #expect(rewrite("```cpp\nint «lo»\n```\nAfter", to: "log"))       // inside a block
    }

    @Test("The keyboard can still rewrite prose, beside code or not")
    func rewritesOfProse() {
        #expect(!rewrite("«teh» cat", to: "the"))
        #expect(!rewrite("use `int «lo` nwo»", to: "lo` now"))             // only the prose word differs
        #expect(!rewrite("```cpp\nint lo\n```\n«teh»", to: "the"))
    }

    // MARK: The editor

    @Test("The editor switches as the caret crosses into code and back")
    func editorSwitches() {
        final class Box { var value = "" }
        let box = Box()
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.delegate = coordinator
        textView.text = "Lecture notes\n```cpp\nint lo = 0;\n```\nMore notes"

        textView.selectedRange = NSRange(location: 5, length: 0)
        coordinator.textViewDidChangeSelection(textView)
        #expect(coordinator.rewritingPolicy == .prose)
        #expect(textView.autocorrectionType == .yes)

        textView.selectedRange = NSRange(location: 24, length: 0)   // in `int lo`
        coordinator.textViewDidChangeSelection(textView)
        #expect(coordinator.rewritingPolicy == .code)
        #expect(textView.autocorrectionType == .no)
        #expect(textView.smartQuotesType == .no)

        textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)
        coordinator.textViewDidChangeSelection(textView)
        #expect(coordinator.rewritingPolicy == .prose)
        #expect(textView.autocapitalizationType == .sentences)
    }

    @Test("The editor turns away the keyboard's rewrites of code, and only those")
    func editorFiltersRewrites() {
        final class Box { var value = "" }
        let box = Box()
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.delegate = coordinator
        textView.text = "use `int lo` nwo"
        textView.selectedRange = NSRange(location: 16, length: 0)

        func allows(_ location: Int, _ length: Int, _ replacement: String) -> Bool {
            coordinator.textView(textView, shouldChangeTextIn: NSRange(location: location, length: length), replacementText: replacement)
        }

        #expect(!allows(9, 7, "log now"))   // going back over the span
        #expect(allows(13, 3, "now"))       // correcting the prose word after it
        #expect(allows(16, 0, " "))         // typing
        #expect(allows(15, 1, ""))          // deleting

        textView.selectedRange = NSRange(location: 4, length: 8)
        #expect(allows(4, 8, "x"))          // typing over a selected span
    }

    @Test("Starting to type in an empty note is prose, though the caret never moved")
    func editorBeginsInEmptyNote() {
        // A tap into an empty note leaves the caret where it was, so no
        // selection change says where typing will go.
        final class Box { var value = "" }
        let box = Box()
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.delegate = coordinator

        #expect(coordinator.textViewShouldBeginEditing(textView))
        #expect(coordinator.rewritingPolicy == .prose)
        #expect(textView.autocapitalizationType == .sentences)
    }
}

#endif
