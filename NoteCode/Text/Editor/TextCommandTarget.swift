//
//  TextCommandTarget.swift
//  NoteCode
//
//  What the page's editor asks of the text view it fronts. The text view's
//  coordinator conforms and the editor holds it weakly (`NoteEditor.textTarget`),
//  so connecting is one assignment, and the editor asks it instead of calling
//  closure slots the coordinator filled with `[weak self, weak textView]`.
//
//  Callbacks the page sets on the editor (`commitTextSize`, `commitLineSpacing`,
//  `onBlockCopied`) stay closures: they point the other way.
//

#if canImport(UIKit)

import UIKit

@MainActor
protocol TextCommandTarget: AnyObject {

    /// The note's code blocks, for the edits that need to know where one is.
    var codeRanges: [CodeRange] { get }

    /// The code block the caret is in, in text mode; `nil` elsewhere.
    func codeBlockAtCaret() -> CodeBlockTarget?

    /// ⌘R: runs the code block the caret is in, in text mode.
    func runBlockAtCaret()

    /// ⇧⌘C: copies it.
    func copyBlockAtCaret()

    /// Tab and ⇧Tab, and the text options row's ⇥ and ⇤: the list item's or
    /// code lines' rule, whichever the caret is in.
    func indentAtCaret(outdent: Bool)

    /// The language menu's pick for the block at the caret.
    func retagBlockAtCaret(_ kind: CodeBlockKind)

    /// Opens the formula editor for a new formula, inline or display.
    func presentNewFormula(display: Bool)
}

#endif
