//
//  CodeKeysTests.swift
//  NoteCodeTests
//
//  v3 phase 4: the row of code keys, and Return and Tab in a real text view.
//

#if canImport(UIKit)

import GameController
import Testing
import UIKit
@testable import NoteCode

// MARK: - What the row holds, and where it shows

@Suite("Code keys")
struct CodeKeysTests {

    @Test("The row holds the design's keys, in the design's order")
    func keys() {
        #expect(CodeKey.all.map(\.title).joined(separator: " ") == "⇥ ⇤ { } ( ) [ ] < > ; = \" ' : / \\ | & * # ← →")
        #expect(CodeKey.all.count == 23)
        #expect(Set(CodeKey.all).count == CodeKey.all.count)
    }

    @Test("Every key says something VoiceOver can read")
    func labels() {
        for key in CodeKey.all {
            #expect(!key.accessibilityLabel.isEmpty)
            if case .insert = key {
                #expect(key.accessibilityLabel != key.title, "\(key.title) is read as a word")
            }
        }
    }

    @Test("The row's keys follow where the caret is: all in code, none in prose", arguments: [
        ("Prose with a caret here", "Prose with a caret here".count, 0),
        ("```cpp\nint x;\n```\n", 10, CodeKey.all.count),
        ("```cpp\nint x;\n```\n", 3, CodeKey.all.count),       // the opening fence
        ("```cpp\nint x;\n```\n", 16, CodeKey.all.count),      // the closing fence
        ("```cpp\nint x;\n```\nAfter\n", 22, 0),               // prose after the block
        ("Use `std::move` here", 10, CodeKey.all.count),       // inline code
        ("Use `std::move` here", 18, 0),                       // past it
        ("An unclosed ` tick", 13, CodeKey.all.count),         // one still being typed
        ("```cpp\nint x;", 13, CodeKey.all.count),             // an unclosed block
        ("```\nplain text block\n```", 8, CodeKey.all.count),  // no language
    ])
    func byRegion(source: String, caret: Int, count: Int) {
        let policy = TextRewritingPolicy.at(caret, in: source, blocks: DocumentParser.parse(source))
        #expect(CodeKeys.keys(for: policy).count == count)
    }

    @Test("The row is shown only for code, set on, editable and with no hardware keyboard")
    func isShown() {
        func shown(enabled: Bool = true, policy: TextRewritingPolicy = .code, hardware: Bool = false, editable: Bool = true) -> Bool {
            CodeKeys.isShown(enabled: enabled, policy: policy, hardwareKeyboard: hardware, isEditable: editable)
        }
        #expect(shown())
        #expect(!shown(enabled: false))
        #expect(!shown(policy: .prose))
        #expect(!shown(hardware: true))
        #expect(!shown(editable: false))
        #expect(CodeKeys.enabledByDefault)
        #expect(CodeKeys.enabledKey == "codeKeys")
    }

    @MainActor
    @Test("The row's buttons are the keys, and a tap sends its key")
    func rowButtons() {
        let row = CodeKeysRow()
        var tapped: [CodeKey] = []
        row.onKey = { tapped.append($0) }

        #expect(row.buttons.map { $0.configuration?.title } == CodeKey.all.map(\.title))
        #expect(row.buttons.map(\.accessibilityLabel) == CodeKey.all.map(\.accessibilityLabel))
        for button in row.buttons { button.sendActions(for: .primaryActionTriggered) }
        #expect(tapped == CodeKey.all)
    }

    @MainActor
    @Test("The row is the options row's size: 40pt keys in a 52pt row")
    func rowSize() {
        let row = CodeKeysRow()
        #expect(row.intrinsicContentSize.height == 52)
        row.frame = CGRect(x: 0, y: 0, width: 1024, height: 52)
        row.layoutIfNeeded()
        let sizes = Set(row.buttons.map { $0.bounds.size })
        #expect(sizes == [CGSize(width: OptionsRowStyle.pitch, height: OptionsRowStyle.thickness)])
        #expect(OptionsRowStyle.thickness == CodeKeysRow.keyHeight)
        #expect(OptionsRowStyle.pitch == CodeKeysRow.keyWidth)
    }
}

// MARK: - In a text view

@Suite("Code keys and indentation in the editor", .serialized)
@MainActor
struct CodeEditingInTheEditorTests {

    private static let note = "Some prose here\n```cpp\nint main() {\n    int x = 1;\n}\n```\nMore prose\n"

    private typealias Harness = CodeFenceDisplayTests.Harness

    /// A keystroke the way UIKit offers it to the delegate: `false` means the
    /// coordinator made the edit itself, `true` that the text view goes on to
    /// insert it.
    @discardableResult
    private func key(_ harness: Harness, _ text: String) -> Bool {
        harness.coordinator.textView(
            harness.textView, shouldChangeTextIn: harness.textView.selectedRange, replacementText: text
        )
    }

    private func row(of harness: Harness) -> CodeKeysRow? {
        harness.textView.inputAccessoryView as? CodeKeysRow
    }

    // MARK: Where the row is

    @Test("The row is on the keyboard in code and off it in prose")
    func crossing() async throws {
        let harness = Harness(Self.note)
        try await harness.caret(at: 3)
        #expect(row(of: harness) == nil, "prose")

        try await harness.caret(at: harness.offset(of: "int x"))
        #expect(row(of: harness) != nil, "code")

        try await harness.caret(at: harness.offset(of: "More"))
        #expect(row(of: harness) == nil, "prose again")

        try await harness.caret(at: harness.offset(of: "```cpp") + 3)
        #expect(row(of: harness) != nil, "a fence line is code")
    }

    @Test("A first tap straight into code has the row, with no prose before it to cross from")
    func firstTapIntoCode() async throws {
        // The editor starts out in the code policy, so nothing is crossed.
        let harness = Harness(Self.note)
        try await harness.caret(at: harness.offset(of: "int x"))
        #expect(row(of: harness) != nil)
    }

    @Test("Settings › Code › Code Keys turns it off, and on again")
    func setting() async throws {
        let harness = Harness(Self.note)
        try await harness.caret(at: harness.offset(of: "int x"))
        #expect(row(of: harness) != nil)

        harness.coordinator.setCodeKeys(false, in: harness.textView)
        #expect(row(of: harness) == nil)
        try await harness.caret(at: harness.offset(of: "int main"))
        #expect(row(of: harness) == nil, "stays off while the caret moves in code")

        harness.coordinator.setCodeKeys(true, in: harness.textView)
        #expect(row(of: harness) != nil)
    }

    @Test("A hardware keyboard takes the row away, and taking it off brings it back")
    func hardwareKeyboard() async throws {
        let original = HardwareKeyboard.isConnected
        defer { HardwareKeyboard.isConnected = original }

        let harness = Harness(Self.note)
        try await harness.caret(at: harness.offset(of: "int x"))
        #expect(row(of: harness) != nil)

        HardwareKeyboard.isConnected = { true }
        NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(row(of: harness) == nil, "attached")

        // And a caret move in code with it attached doesn't put it back.
        try await harness.caret(at: harness.offset(of: "int main"))
        #expect(row(of: harness) == nil)

        HardwareKeyboard.isConnected = { false }
        NotificationCenter.default.post(name: .GCKeyboardDidDisconnect, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(row(of: harness) != nil, "detached")
    }

    @Test("A locked note has no keyboard, so no row")
    func locked() async throws {
        let harness = Harness(Self.note)
        harness.editor.setTextLocked(true)
        try await harness.caret(at: harness.offset(of: "int x"))
        harness.coordinator.setCodeKeys(false, in: harness.textView)
        harness.coordinator.setCodeKeys(true, in: harness.textView)
        #expect(row(of: harness) == nil)
    }

    // MARK: The keys

    @Test("A symbol key types at the caret, as typing does: one undo takes it back")
    func symbol() async throws {
        let harness = Harness(Self.note)
        try await harness.caret(at: harness.offset(of: "int x = 1;") + 10)
        let row = try #require(row(of: harness))

        row.buttons.first { $0.accessibilityLabel == "Semicolon" }?.sendActions(for: .primaryActionTriggered)
        #expect(harness.textView.text.contains("int x = 1;;"))
        #expect(harness.stored.contains("int x = 1;;"), "written back to the page")
        #expect(harness.textView.selectedRange.location == harness.offset(of: "int x = 1;;") + 11)

        harness.textView.undoManager?.undo()
        #expect(harness.textView.text == Self.note)
    }

    @Test("A symbol key replaces the selection")
    func symbolOverSelection() async throws {
        let harness = Harness(Self.note)
        try await harness.select(NSRange(location: harness.offset(of: "1;"), length: 1))
        row(of: harness)?.buttons.first { $0.accessibilityLabel == "Left parenthesis" }?.sendActions(for: .primaryActionTriggered)
        #expect(harness.textView.text.contains("int x = (;"))
    }

    @Test("The arrows move the caret a character, and collapse a selection to its edge")
    func arrows() async throws {
        let harness = Harness(Self.note)
        let start = harness.offset(of: "int x")
        try await harness.caret(at: start)
        let row = try #require(row(of: harness))
        func tap(_ label: String) { row.buttons.first { $0.accessibilityLabel == label }?.sendActions(for: .primaryActionTriggered) }

        tap("Move right"); tap("Move right")
        #expect(harness.textView.selectedRange == NSRange(location: start + 2, length: 0))
        tap("Move left")
        #expect(harness.textView.selectedRange == NSRange(location: start + 1, length: 0))

        try await harness.select(NSRange(location: start, length: 5))
        tap("Move right")
        #expect(harness.textView.selectedRange == NSRange(location: start + 5, length: 0))
        try await harness.select(NSRange(location: start, length: 5))
        tap("Move left")
        #expect(harness.textView.selectedRange == NSRange(location: start, length: 0))

        try await harness.caret(at: 0)
        tap("Move left")
        #expect(harness.textView.selectedRange.location == 0, "nothing before the start")
    }

    @Test("⇥ and ⇤ indent and outdent the lines, through the same edit as Tab")
    func indentKeys() async throws {
        let harness = Harness(Self.note)
        try await harness.caret(at: harness.offset(of: "int x = 1;") + 10)
        let row = try #require(row(of: harness))

        row.buttons.first { $0.accessibilityLabel == "Indent" }?.sendActions(for: .primaryActionTriggered)
        #expect(harness.textView.text.contains("\n        int x = 1;\n"))
        row.buttons.first { $0.accessibilityLabel == "Outdent" }?.sendActions(for: .primaryActionTriggered)
        #expect(harness.textView.text == Self.note)
        row.buttons.first { $0.accessibilityLabel == "Indent" }?.sendActions(for: .primaryActionTriggered)
        harness.textView.undoManager?.undo()
        #expect(harness.textView.text == Self.note, "one undo")
    }

    // MARK: Return and Tab

    @Test("Return in code keeps the indent, and one undo takes the line back")
    func returnKeepsIndent() async throws {
        let harness = Harness(Self.note)
        try await harness.caret(at: harness.offset(of: "int x = 1;") + 10)
        #expect(key(harness, "\n") == false)
        #expect(harness.textView.text.contains("    int x = 1;\n    \n}"))
        #expect(harness.textView.selectedRange.location == harness.offset(of: "int x = 1;\n    ") + 15)
        #expect(harness.stored == harness.textView.text)

        harness.textView.undoManager?.undo()
        #expect(harness.textView.text == Self.note)
    }

    @Test("Return after a brace goes deeper, and between braces opens them")
    func returnAfterBrace() async throws {
        let harness = Harness(Self.note)
        try await harness.caret(at: harness.offset(of: "int main() {") + 12)
        #expect(key(harness, "\n") == false)
        #expect(harness.textView.text.contains("int main() {\n    \n    int x = 1;"))

        let split = Harness("```cpp\nfor (;;) {}\n```\n")
        try await split.caret(at: split.offset(of: "{}") + 1)
        #expect(key(split, "\n") == false)
        #expect(split.textView.text == "```cpp\nfor (;;) {\n    \n}\n```\n")
        #expect(split.textView.selectedRange.location == 7 + "for (;;) {\n    ".count)
    }

    @Test("Return in prose is a plain newline")
    func returnInProse() async throws {
        let harness = Harness("    indented prose\n```cpp\nx\n```\n")
        try await harness.caret(at: 18)
        #expect(key(harness, "\n") == true, "the keyboard's own newline")
        #expect(harness.textView.text == "    indented prose\n```cpp\nx\n```\n", "nothing was made for it")
    }

    @Test("Return on a Python colon goes deeper, and elsewhere a colon does not")
    func returnPython() async throws {
        let python = Harness("```python\ndef f(x):\n```\n")
        try await python.caret(at: python.offset(of: "def f(x):") + 9)
        #expect(key(python, "\n") == false)
        #expect(python.textView.text == "```python\ndef f(x):\n    \n```\n")

        let cpp = Harness("```cpp\ncase 1:\n```\n")
        try await cpp.caret(at: cpp.offset(of: "case 1:") + 7)
        #expect(key(cpp, "\n") == true, "a colon in C++ is a plain newline")
        #expect(cpp.textView.text == "```cpp\ncase 1:\n```\n")
    }

    @Test("The indent width setting is used")
    func width() async throws {
        let harness = Harness("```cpp\nif (x) {\n```\n")
        harness.coordinator.indentWidth = 2
        try await harness.caret(at: harness.offset(of: "if (x) {") + 8)
        #expect(key(harness, "\n") == false)
        #expect(harness.textView.text == "```cpp\nif (x) {\n  \n```\n")
    }

    @Test("Tab in code indents the line, not the caret; in a list it nests; in prose it is a tab")
    func tab() async throws {
        let code = Harness(Self.note)
        try await code.caret(at: code.offset(of: "int x = 1;") + 4)
        #expect(key(code, "\t") == false)
        #expect(code.textView.text.contains("\n        int x = 1;\n"))
        #expect(code.textView.selectedRange.location == code.offset(of: "int x = 1;") + 4)

        let list = Harness("- one\n- two\n```cpp\nx\n```\n")
        try await list.caret(at: list.offset(of: "two") + 3)
        #expect(key(list, "\t") == false)
        #expect(list.textView.text.hasPrefix("- one\n  - two\n"))

        let prose = Harness("plain prose\n```cpp\nx\n```\n")
        try await prose.caret(at: 5)
        #expect(key(prose, "\t") == true, "in prose, Tab is the keyboard's own")
    }

    @Test("⇧Tab outdents code, and is given back when there is nothing to take off")
    func shiftTab() async throws {
        let harness = Harness(Self.note)
        try await harness.caret(at: harness.offset(of: "int x = 1;") + 3)
        #expect(harness.textView.canPerformAction(#selector(DocumentUITextView.outdentListItem), withSender: nil))
        harness.textView.outdentListItem()
        #expect(harness.textView.text.contains("\nint x = 1;\n"))
        #expect(!harness.textView.canPerformAction(#selector(DocumentUITextView.outdentListItem), withSender: nil), "no indent left")
    }

    @Test("Return and Tab do nothing special in an output block")
    func output() async throws {
        let harness = Harness("```output\n    ok {\n```\n")
        try await harness.caret(at: harness.offset(of: "ok {") + 4)
        #expect(key(harness, "\n") == true, "a plain newline")
        try await harness.caret(at: harness.offset(of: "ok {"))
        #expect(key(harness, "\t") == true, "and a plain tab")
    }
}

#endif
