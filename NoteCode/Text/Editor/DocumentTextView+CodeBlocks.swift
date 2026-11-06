//
//  DocumentTextView+CodeBlocks.swift
//  NoteCode
//
//  The coordinator's commands on a code block: copying one, finding the one
//  the caret is in, and the indent rule the Tab key and the options row share.
//

#if canImport(UIKit)

import UIKit

extension DocumentTextView.Coordinator {

    /// Puts a block's code on the pasteboard (`CodeBlockCommands.copy`).
    func copy(_ target: CodeBlockTarget) {
        codeBlocks.copy(target, told: editor)
    }

    /// The code block the caret is in, for the edit menu and ⌘R and ⇧⌘C.
    func target(atCaret caret: Int, in textView: UITextView) -> CodeBlockTarget? {
        codeBlocks.target(atCaret: caret, in: snapshot(of: textView), sourceLength: textView.textStorage.length)
    }

    /// ⇧Tab, and whether it has anything to do.
    func outdentListItems(in textView: UITextView) {
        guard let edit = indentEdit(outdent: true, in: textView) else { return }
        apply(edit, to: textView)
    }

    func canOutdentListItems(in textView: UITextView) -> Bool {
        textView.isEditable && indentEdit(outdent: true, in: textView) != nil
    }

    /// One level in or out at the caret. Tab, ⇧Tab and the text options
    /// row's ⇥ and ⇤ all ask here.
    func indentEdit(outdent: Bool, in textView: UITextView) -> TextEdit? {
        codeBlocks.indentEdit(
            outdent: outdent, in: textView, codeRanges: codeRanges(in: textView.textStorage), width: indentWidth
        )
    }
}

// MARK: - What the editor asks of the text view

extension DocumentTextView.Coordinator: TextCommandTarget {

    var codeRanges: [CodeRange] {
        textView.map { codeRanges(in: $0.textStorage) } ?? []
    }

    func codeBlockAtCaret() -> CodeBlockTarget? {
        guard let textView, editor?.mode == .text else { return nil }
        return target(atCaret: textView.selectedRange.location, in: textView)
    }

    func runBlockAtCaret() {
        guard let textView, let target = codeBlockAtCaret() else { return }
        run(target, from: textView)
    }

    func copyBlockAtCaret() {
        guard let target = codeBlockAtCaret() else { return }
        copy(target)
    }

    func indentAtCaret(outdent: Bool) {
        guard let textView, textView.isEditable, let edit = indentEdit(outdent: outdent, in: textView) else { return }
        apply(edit, to: textView)
    }

    func retagBlockAtCaret(_ kind: CodeBlockKind) {
        guard let textView, let target = codeBlockAtCaret() else { return }
        setKind(kind, of: target, in: textView)
    }

    func presentNewFormula(display: Bool) {
        guard let textView else { return }
        presentNewFormulaEditor(display: display, in: textView)
    }
}

#endif
