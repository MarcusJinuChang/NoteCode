//
//  EditingBehaviorTests.swift
//  NoteCodeTests
//
//  Step 6: the editing edge cases — boundaries, paste, re-parse cost,
//  and structural edits mid-fence.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

// MARK: - Re-parse cost

@Suite("Re-parse cost")
struct DocumentCacheTests {

    @Test("Repeated reads of the same document parse once")
    func repeatedReadsParseOnce() {
        let cache = DocumentCache()
        let source = "prose\n```cpp\nint x;\n```\n"

        for _ in 0..<10 {
            _ = cache.blocks(for: source)
        }

        #expect(cache.parseCount == 1)
    }

    @Test("Each distinct edit costs exactly one parse")
    func eachEditParsesOnce() {
        let cache = DocumentCache()

        // Simulates a keystroke: didChange and didChangeSelection both read.
        for text in ["a", "ab", "abc"] {
            _ = cache.blocks(for: text)   // textViewDidChange
            _ = cache.blocks(for: text)   // textViewDidChangeSelection
        }

        #expect(cache.parseCount == 3)
    }

    @Test("Returning to a previous document re-parses rather than going stale")
    func revertingReparses() {
        let cache = DocumentCache()

        _ = cache.blocks(for: "a")
        _ = cache.blocks(for: "b")
        let back = cache.blocks(for: "a")

        #expect(cache.parseCount == 3)
        #expect(back.count == 1)
    }
}

// MARK: - Paste

@Suite("Paste normalization")
@MainActor
struct PasteTests {

    @Test("Rich text editing is off, so paste arrives plain")
    func richTextEditingDisabled() {
        #expect(DocumentTextView.makeConfiguredTextView().allowsEditingTextAttributes == false)
    }

    @Test("Foreign fonts and backgrounds are overwritten by styling")
    func foreignAttributesNormalized() {
        let textView = DocumentTextView.makeConfiguredTextView()

        let pasted = NSMutableAttributedString(string: "prose\n```cpp\nint x;\n```\n")
        pasted.addAttributes(
            [
                .font: UIFont.systemFont(ofSize: 42),
                .backgroundColor: UIColor.systemRed,
                .foregroundColor: UIColor.systemGreen,
            ],
            range: NSRange(location: 0, length: pasted.length)
        )
        textView.attributedText = pasted

        DocumentStyler.applyStyling(to: textView)

        let storage = textView.textStorage
        let codeOffset = ("prose\n```cpp\n" as NSString).length

        #expect(storage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont == DocumentStyler.proseFont)
        #expect(storage.attribute(.font, at: codeOffset, effectiveRange: nil) as? UIFont == DocumentStyler.codeFont)
        #expect(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
        #expect(storage.attribute(.backgroundColor, at: codeOffset, effectiveRange: nil) == nil)
    }
}

// MARK: - Structural edits

@Suite("Mid-fence edits")
struct MidFenceEditTests {

    @Test("Deleting the closing fence reopens the block to end of document")
    func deletingClosingFence() {
        let closed = DocumentParser.parse("```cpp\nx\n```\nafter")
        let reopened = DocumentParser.parse("```cpp\nx\n\nafter")

        #expect(closed.first?.codeBlock?.isClosed == true)
        #expect(closed.count == 2)

        #expect(reopened.count == 1)
        #expect(reopened.first?.codeBlock?.isClosed == false)
    }

    @Test("The third backtick is what turns prose into a code block")
    func thirdBacktickOpensBlock() {
        #expect(DocumentParser.parse("``").allSatisfy { !$0.isCode })
        #expect(DocumentParser.parse("```").contains { $0.isCode })
    }

    @Test("Typing a language tag onto an open fence keeps the block open")
    func taggingAnOpenFence() {
        for source in ["```", "```c", "```cp", "```cpp"] {
            let blocks = DocumentParser.parse(source)
            #expect(blocks.first?.isCode == true)
            #expect(blocks.first?.codeBlock?.isClosed == false)
        }

        #expect(DocumentParser.parse("```cpp").first?.codeBlock?.language == .cpp)
        #expect(DocumentParser.parse("```cp").first?.codeBlock?.language == nil)
    }

    @Test("Removing the language tag leaves the block intact, without a language")
    func untagging() {
        let tagged = DocumentParser.parse("```cpp\nx\n```")
        let untagged = DocumentParser.parse("```\nx\n```")

        #expect(tagged.first?.codeBlock?.language == .cpp)
        #expect(untagged.first?.isCode == true)
        #expect(untagged.first?.codeBlock?.language == nil)
    }
}

// MARK: - Caret boundaries

@Suite("Caret boundaries")
@MainActor
struct CaretBoundaryTests {

    private static let source = "prose\n```cpp\nint x;\n```\nafter"

    private func typingFont(caretAt offset: Int, in source: String = CaretBoundaryTests.source) -> UIFont? {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = source
        let blocks = DocumentParser.parse(source)
        DocumentStyler.applyStyling(to: textView, blocks: blocks)

        textView.selectedRange = NSRange(location: offset, length: 0)
        DocumentStyler.applyTypingAttributes(to: textView, blocks: blocks)

        return textView.typingAttributes[.font] as? UIFont
    }

    @Test("The caret on the opening fence line types code")
    func caretOnOpeningFence() {
        #expect(typingFont(caretAt: ("prose\n" as NSString).length) == DocumentStyler.codeFont)
    }

    @Test("The caret at the end of the last code line types code")
    func caretAtEndOfCodeLine() {
        #expect(typingFont(caretAt: ("prose\n```cpp\nint x;" as NSString).length) == DocumentStyler.codeFont)
    }

    @Test("The caret immediately after the closing fence types prose")
    func caretAfterClosingFence() {
        #expect(typingFont(caretAt: ("prose\n```cpp\nint x;\n```\n" as NSString).length) == DocumentStyler.proseFont)
    }

    @Test("The caret at the very start of the document types prose")
    func caretAtStart() {
        #expect(typingFont(caretAt: 0) == DocumentStyler.proseFont)
    }

    @Test("The caret at the end of an unclosed block still types code")
    func caretAtEndOfUnclosedBlock() {
        let source = "prose\n```py\nprint(1)"
        #expect(typingFont(caretAt: (source as NSString).length, in: source) == DocumentStyler.codeFont)
    }

    @Test("The caret in an empty document types prose")
    func caretInEmptyDocument() {
        #expect(typingFont(caretAt: 0, in: "") == DocumentStyler.proseFont)
    }
}

// MARK: - Undo

@Suite("Undo")
@MainActor
struct UndoTests {

    /// Puts the editor in a real window and makes it first responder, which is
    /// what the text input system needs before it will register undo entries.
    private func hostedTextView() -> (UIWindow, UITextView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.frame = window.bounds
        window.addSubview(textView)
        window.makeKeyAndVisible()
        textView.becomeFirstResponder()
        return (window, textView)
    }

    @Test("Typed text can be undone")
    func undoRestoresText() throws {
        let (window, textView) = hostedTextView()
        defer { window.isHidden = true }

        textView.text = "notes"
        textView.selectedRange = NSRange(location: 5, length: 0)
        textView.insertText(" more")

        #expect(textView.text == "notes more")

        let undoManager = try #require(textView.undoManager)
        try #require(undoManager.canUndo)
        undoManager.undo()

        #expect(textView.text == "notes")
    }

    @Test("Styling after an undo reflects the restored text")
    func stylingFollowsUndo() throws {
        let (window, textView) = hostedTextView()
        defer { window.isHidden = true }

        textView.text = "prose\n```cpp\nint x;\n"
        textView.selectedRange = NSRange(location: (textView.text as NSString).length, length: 0)
        textView.insertText("```")

        DocumentStyler.applyStyling(to: textView)
        #expect(DocumentParser.parse(textView.text).first(where: \.isCode)?.codeBlock?.isClosed == true)

        let undoManager = try #require(textView.undoManager)
        try #require(undoManager.canUndo)
        undoManager.undo()

        DocumentStyler.applyStyling(to: textView)
        #expect(DocumentParser.parse(textView.text).first(where: \.isCode)?.codeBlock?.isClosed == false)
    }
}

#endif
