//
//  KeyboardAndMenuTests.swift
//  NoteCodeTests
//
//  Phase 9: what the shortcuts do, the edit menu, the copy tap, and the note
//  body staying put when the system's text size changes.
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("Shortcuts, the edit menu and Dynamic Type")
@MainActor
struct KeyboardAndMenuTests {

    typealias Harness = CodeFenceDisplayTests.Harness

    private func isolatedDefaults() -> UserDefaults {
        let name = "KeyboardAndMenuTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Every title in a menu, nested ones included, in order.
    private func titles(of menu: UIMenu) -> [String] {
        menu.children.flatMap { element -> [String] in
            if let submenu = element as? UIMenu {
                // Inline groups have no title of their own.
                return (submenu.options.contains(.displayInline) ? [] : [submenu.title]) + titles(of: submenu)
            }
            return [element.title]
        }
    }

    private func allActions(in menu: UIMenu) -> [UIAction] {
        menu.children.flatMap { element -> [UIAction] in
            if let submenu = element as? UIMenu { return allActions(in: submenu) }
            return (element as? UIAction).map { [$0] } ?? []
        }
    }

    private func editMenu(_ harness: Harness, at offset: Int, selecting length: Int = 0) -> UIMenu {
        harness.textView.selectedRange = NSRange(location: offset, length: length)
        return harness.coordinator.textView(
            harness.textView,
            editMenuForTextInRanges: [NSValue(range: NSRange(location: offset, length: length))],
            suggestedActions: []
        )!
    }

    /// Counts the taps a copy makes while the test runs. Call `restore()`
    /// when done: the seam is shared by every test.
    @MainActor
    private final class Taps {
        var count = 0
        private let original = Haptics.copyBlock

        init() {
            Haptics.copyBlock = { [unowned self] in count += 1 }
        }

        func restore() {
            Haptics.copyBlock = original
        }
    }

    // MARK: Tools and width

    @Test("P, H, E and L pick a tool in ink mode, and do nothing in text mode")
    func toolKeys() {
        let editor = NoteEditor()

        editor.selectTool(.eraser)
        #expect(editor.inkTool.kind == .pen)

        editor.setMode(.ink)
        for kind in [InkToolKind.highlighter, .eraser, .lasso, .pen] {
            editor.selectTool(kind)
            #expect(editor.inkTool.kind == kind)
        }
    }

    @Test("[ and ] change the selected tool's width in ink mode only")
    func widthKeys() {
        let editor = NoteEditor()

        editor.stepWidth(by: 1)
        #expect(editor.inkTool.pen.width == .medium)

        editor.setMode(.ink)
        editor.stepWidth(by: 1)
        #expect(editor.inkTool.pen.width == .bold)
        editor.stepWidth(by: -1)
        editor.stepWidth(by: -1)
        #expect(editor.inkTool.pen.width == .fine)
    }

    @Test("⇧⌘D switches between text and draw, both ways")
    func modeKey() {
        let editor = NoteEditor()
        editor.toggleMode()
        #expect(editor.mode == .ink)
        editor.toggleMode()
        #expect(editor.mode == .text)
    }

    // MARK: Code blocks

    @Test("⇧⌘K starts a block in the last language picked, and a pick is remembered")
    func codeBlockKey() async throws {
        let harness = Harness("Notes\n")
        harness.editor.defaults = isolatedDefaults()
        try await harness.caret(at: 6)

        // Never picked: C++.
        harness.editor.insertCodeBlockInLastLanguage()
        #expect(harness.textView.text.contains("```cpp"))

        harness.editor.insertCodeBlock(language: .python)
        harness.editor.insertCodeBlockInLastLanguage()
        #expect(harness.textView.text.components(separatedBy: "```python").count == 3)

        harness.editor.insertCodeBlock(language: nil)
        #expect(LastCodeLanguage.read(from: harness.editor.defaults) == nil)
    }

    @Test("A locked note starts no block and remembers nothing")
    func lockedCodeBlock() {
        let harness = Harness("Notes\n")
        harness.editor.defaults = isolatedDefaults()
        harness.editor.setTextLocked(true)

        harness.editor.insertCodeBlock(language: .java)

        #expect(harness.textView.text == "Notes\n")
        #expect(harness.editor.defaults.string(forKey: LastCodeLanguage.defaultsKey) == nil)
    }

    @Test("⇧⌘C copies the block the caret is in, with a tap, and does nothing in prose")
    func copyKey() async throws {
        let harness = Harness()
        let taps = Taps()
        defer { taps.restore() }

        UIPasteboard.general.string = "before"
        try await harness.caret(at: harness.offset(of: "Prose before"))
        harness.editor.copyBlockAtCaret?()
        #expect(UIPasteboard.general.string == "before")
        #expect(taps.count == 0)

        try await harness.caret(at: harness.offset(of: "int other"))
        harness.editor.copyBlockAtCaret?()
        #expect(UIPasteboard.general.string == "int value = query(gap);\nint other = 2;\n")
        #expect(taps.count == 1)
    }

    @Test("In ink mode, ⌘R and ⇧⌘C leave the pasteboard alone")
    func blockKeysNeedTextMode() async throws {
        let harness = Harness()
        try await harness.caret(at: harness.offset(of: "int other"))
        harness.editor.setMode(.ink)

        UIPasteboard.general.string = "before"
        harness.editor.copyBlockAtCaret?()
        #expect(UIPasteboard.general.string == "before")
    }

    @Test("Copying a block taps, from the button's path too")
    func copyTaps() {
        let harness = Harness()
        let taps = Taps()
        defer { taps.restore() }

        harness.coordinator.overlay?.onCopy?(CodeBlockTarget(
            id: CodeBlockID(ordinal: 0, code: "x"),
            range: NSRange(location: 0, length: 1),
            language: .cpp,
            code: "x"
        ))

        #expect(taps.count == 1)
        #expect(UIPasteboard.general.string == "x")
    }

    @Test("Copying a block tells the page, from the button and from ⇧⌘C, and a failed copy doesn't")
    func copyToasts() async throws {
        let harness = Harness()
        let taps = Taps()
        defer { taps.restore() }
        var told = 0
        harness.editor.onBlockCopied = { told += 1 }

        harness.coordinator.overlay?.onCopy?(CodeBlockTarget(
            id: CodeBlockID(ordinal: 0, code: "x"),
            range: NSRange(location: 0, length: 1),
            language: .cpp,
            code: "x"
        ))
        #expect(told == 1)

        // Prose has no block, so the key copies nothing and says nothing.
        try await harness.caret(at: harness.offset(of: "Prose before"))
        harness.editor.copyBlockAtCaret?()
        #expect(told == 1)

        try await harness.caret(at: harness.offset(of: "int other"))
        harness.editor.copyBlockAtCaret?()
        #expect(told == 2)
    }

    @Test("The caret finds its block, fence lines included, and the end of the note finds the open one")
    func blockAtCaret() {
        let source = "a\n```cpp\nint x;\n```\nb\n```cpp\nint y;"
        let targets = CodeBlockAction.targets(in: source, blocks: DocumentParser.parse(source))
        let length = (source as NSString).length

        #expect(targets.count == 2)
        #expect(CodeBlockAction.target(atCaret: 0, in: targets, sourceLength: length) == nil)
        #expect(CodeBlockAction.target(atCaret: 4, in: targets, sourceLength: length)?.code == "int x;\n")
        #expect(CodeBlockAction.target(atCaret: 12, in: targets, sourceLength: length)?.code == "int x;\n")
        // On the closing fence's line.
        #expect(CodeBlockAction.target(atCaret: 17, in: targets, sourceLength: length)?.code == "int x;\n")
        // In the prose between.
        #expect(CodeBlockAction.target(atCaret: 21, in: targets, sourceLength: length) == nil)
        // At the end of the note, in the block still being typed.
        #expect(CodeBlockAction.target(atCaret: length, in: targets, sourceLength: length)?.code == "int y;")
    }

    // MARK: The edit menu

    @Test("On prose the edit menu has Bold, Italic, Underline, Code and a Format submenu")
    func proseMenu() {
        let harness = Harness()
        let menu = editMenu(harness, at: 0, selecting: 5)

        let all = titles(of: menu)
        #expect(all.starts(with: ["Bold", "Italic", "Underline", "Code", "Format"]))
        for title in ["Strikethrough", "Heading 1", "Heading 2", "Heading 3", "Heading 4", "Heading 5", "Heading 6", "Body"] {
            #expect(all.contains(title), "\(title)")
        }
        #expect(!all.contains("Run Block"))
    }

    @Test("Underline in the edit menu does what the button does, undoably")
    func underlineMenuActs() throws {
        let harness = Harness("a word b")
        let menu = editMenu(harness, at: 2, selecting: 4)

        let underline = try #require(allActions(in: menu).first { $0.title == "Underline" })
        underline.performWithSender(nil, target: nil)

        #expect(harness.textView.text == "a <u>word</u> b")
        harness.editor.undo()
        #expect(harness.textView.text == "a word b")
    }

    @Test("Bold in the edit menu does what the button does, undoably")
    func proseMenuActs() throws {
        let harness = Harness("a word b")
        let menu = editMenu(harness, at: 2, selecting: 4)

        let bold = try #require(allActions(in: menu).first { $0.title == "Bold" })
        bold.performWithSender(nil, target: nil)

        #expect(harness.textView.text == "a **word** b")
        #expect(harness.stored == "a **word** b")
        harness.editor.undo()
        #expect(harness.textView.text == "a word b")
    }

    @Test("In a code block the edit menu has Run Block and Copy Block, not the prose formatting")
    func codeMenu() {
        let harness = Harness()
        let menu = editMenu(harness, at: harness.offset(of: "int other"))

        let all = titles(of: menu)
        #expect(all.starts(with: ["Run Block", "Copy Block"]))
        #expect(!all.contains("Bold"))
        #expect(!all.contains("Format"))
    }

    @Test("A block with no language the app knows has no Run Block")
    func codeMenuWithoutLanguage() {
        let harness = Harness("```\nplain text\n```\n")
        let menu = editMenu(harness, at: 5)

        let all = titles(of: menu)
        #expect(all.contains("Copy Block"))
        #expect(!all.contains("Run Block"))
    }

    @Test("Copy Block in the edit menu copies the block and taps")
    func codeMenuCopies() throws {
        let harness = Harness()
        let taps = Taps()
        defer { taps.restore() }

        let menu = editMenu(harness, at: harness.offset(of: "int other"))
        let copy = try #require(allActions(in: menu).first { $0.title == "Copy Block" })
        copy.performWithSender(nil, target: nil)

        #expect(UIPasteboard.general.string == "int value = query(gap);\nint other = 2;\n")
        #expect(taps.count == 1)
    }

    @Test("A locked note, and ink mode, get no formatting in the edit menu")
    func menuStandsDown() {
        let harness = Harness()
        harness.editor.setTextLocked(true)
        #expect(!titles(of: editMenu(harness, at: 0, selecting: 5)).contains("Bold"))

        harness.editor.setTextLocked(false)
        harness.editor.setMode(.ink)
        #expect(!titles(of: editMenu(harness, at: 0, selecting: 5)).contains("Bold"))
    }

    // MARK: Text input

    @Test("A field with the keyboard turns the bare keys off until it lets go")
    func textInputActivity() {
        let activity = TextInputActivity()
        let first = UITextField()
        let second = UITextView()

        #expect(!activity.isEditing)
        activity.began(first)
        #expect(activity.isEditing)

        // A tap from one field to another begins the second before the first ends.
        activity.began(second)
        activity.ended(first)
        #expect(activity.isEditing)

        activity.ended(second)
        #expect(!activity.isEditing)
    }

    @Test("It follows UIKit's own begin and end notifications")
    func textInputNotifications() async throws {
        let activity = TextInputActivity()
        activity.start()
        let field = UITextField()

        NotificationCenter.default.post(name: UITextField.textDidBeginEditingNotification, object: field)
        try await Task.sleep(for: .milliseconds(50))
        #expect(activity.isEditing)

        NotificationCenter.default.post(name: UITextField.textDidEndEditingNotification, object: field)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!activity.isEditing)
    }

    // MARK: Undo from the keyboard

    @Test("⌘Z and ⇧⌘Z undo and redo the note's own edits when no other field is typing")
    func undoRouting() {
        let harness = Harness("a word b")
        harness.textView.selectedRange = NSRange(location: 2, length: 4)
        harness.editor.toggle(.bold)
        #expect(harness.textView.text == "a **word** b")

        harness.editor.undoFromKeyboard()
        #expect(harness.textView.text == "a word b")
        harness.editor.redoFromKeyboard()
        #expect(harness.textView.text == "a **word** b")
    }

    // MARK: Dynamic Type

    @Test("The note body doesn't follow Dynamic Type, so a larger system text size can't re-wrap it")
    func bodyIgnoresTextSize() {
        let harness = Harness("A long enough line of prose to wrap at least once or twice when the page is narrow enough to need it.\n")
        let before = harness.textView.contentSize.height
        let beforeFont = harness.textView.font?.pointSize

        harness.window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        harness.textView.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        harness.coordinator.restyle(harness.textView)
        harness.layOut()

        #expect(!harness.textView.adjustsFontForContentSizeCategory)
        #expect(harness.textView.font?.pointSize == beforeFont)
        #expect(beforeFont == 17)
        #expect(harness.textView.contentSize.height == before)

        let attributes = harness.textView.textStorage.attributes(at: 0, effectiveRange: nil)
        #expect((attributes[.font] as? UIFont)?.pointSize == 17)
    }

    @Test("Headings and code are fixed too, at the sizes the default setting gives")
    func headingsAndCodeAreFixed() {
        #expect(DocumentStyler.proseFont.pointSize == 17)
        // Code is smaller than the body since step 10 (`NoteTypography.code`).
        #expect(DocumentStyler.codeFont.pointSize == 15)
        // The system's own body font has leading (1.71pt); a plain system font
        // of the same size has none, and every line came out shorter, which
        // moved the page breaks of existing notes off their ink.
        #expect(DocumentStyler.proseFont.leading > 1.5)
        let sizes = (1...6).map { DocumentStyler.headingFont(level: $0).pointSize }
        #expect(sizes == [34, 28, 22, 20, 17, 15])
        for level in 1...6 {
            #expect(DocumentStyler.headingFont(level: level).fontDescriptor.symbolicTraits.contains(.traitBold))
        }
    }
}

#endif
