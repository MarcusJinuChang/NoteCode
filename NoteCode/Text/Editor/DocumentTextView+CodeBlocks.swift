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

    /// Puts a block's code on the pasteboard, with a light tap. One path
    /// for the button, the edit menu and ⇧⌘C.
    func copy(_ target: CodeBlockTarget) {
        UIPasteboard.general.string = target.code
        Haptics.copyBlock()
        editor?.onBlockCopied?()
    }

    /// The code block the caret is in, for the edit menu and ⌘R and ⇧⌘C.
    func target(atCaret caret: Int, in textView: UITextView) -> CodeBlockTarget? {
        let targets = snapshot(of: textView).targets
        return CodeBlockAction.target(atCaret: caret, in: targets, sourceLength: textView.textStorage.length)
    }

    /// ⇧Tab, and whether it has anything to do.
    func outdentListItems(in textView: UITextView) {
        guard let edit = indentEdit(outdent: true, in: textView) else { return }
        apply(edit, to: textView)
    }

    func canOutdentListItems(in textView: UITextView) -> Bool {
        textView.isEditable && indentEdit(outdent: true, in: textView) != nil
    }

    /// One level in or out at the caret: the code lines' rule in a code
    /// block, the list item's elsewhere. Tab, ⇧Tab and the text options
    /// row's ⇥ and ⇤ all ask here.
    func indentEdit(outdent: Bool, in textView: UITextView) -> TextEdit? {
        if let edit = CodeIndent.indentEdit(
            in: textView.textStorage.mutableString,
            selection: textView.selectedRange,
            outdent: outdent,
            codeRanges: codeRanges(in: textView.textStorage),
            width: indentWidth
        ) {
            return edit
        }
        return MarkdownFormatting.indent(
            in: textView.textStorage.mutableString,
            selection: textView.selectedRange,
            outdent: outdent,
            codeRanges: codeRanges(in: textView.textStorage)
        )
    }
}

#endif
