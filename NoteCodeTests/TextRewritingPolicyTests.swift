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
        #expect(policy("use `vector`| here") == .prose)    // after the closing one
        #expect(policy("use |`vector` here") == .prose)    // before the opening one
        #expect(policy("use `vector` and `ma|p`") == .code)
        #expect(policy("use `vector` and |`map`") == .prose)
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
}

#endif
