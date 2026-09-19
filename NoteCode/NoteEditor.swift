//
//  NoteEditor.swift
//  NoteCode
//
//  What the hotbar talks to: the page's mode, its ink tool, and its text view.
//

#if canImport(UIKit)

import Observation
import UIKit

/// A note page's editing state, shared by the hotbar and the editor.
///
/// SwiftUI owns the hotbar and UIKit owns the text view, and neither can reach
/// the other. This sits between them: the hotbar reads and changes state here,
/// and the text view registers itself so that edits have somewhere to land.
@Observable
final class NoteEditor {

    private(set) var mode: EditorMode = .text

    /// What ink mode draws with. Kept here rather than in the hotbar so the
    /// canvas can take it as it changes.
    var inkTool = InkToolState() {
        didSet {
            guard inkTool != oldValue else { return }
            canvas?.tool = inkTool.pencilKitTool
        }
    }

    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored private weak var textView: UITextView?
    @ObservationIgnored private weak var canvas: DrawingCanvas?
    @ObservationIgnored private var savedSession: TextSession?

    /// Called by `DocumentTextView` once the page, and so the canvas, exists.
    func attach(_ textView: UITextView, canvas: DrawingCanvas? = nil) {
        self.textView = textView
        self.canvas = canvas
        canvas?.tool = inkTool.pencilKitTool
        savedSession = mode.apply(to: textView, canvas: canvas, saved: nil)
        refreshUndoState()
    }

    func setMode(_ newMode: EditorMode) {
        guard newMode != mode else { return }
        mode = newMode
        if let textView {
            savedSession = newMode.apply(to: textView, canvas: canvas, saved: savedSession)
        }
        refreshUndoState()
    }

    // MARK: Formatting

    func toggle(_ style: MarkdownFormatting.InlineStyle) {
        perform { MarkdownFormatting.toggle(style, in: $0, selection: $1) }
    }

    func setHeading(level: Int) {
        perform { MarkdownFormatting.setHeading(level: level, in: $0, selection: $1) }
    }

    func toggleBullet() {
        perform { MarkdownFormatting.toggleBullet(in: $0, selection: $1) }
    }

    func insertCodeBlock(language: CodeLanguage?) {
        perform { MarkdownFormatting.insertCodeBlock(language: language, in: $0, selection: $1) }
    }

    /// Makes an edit through the text view rather than around it.
    ///
    /// `replace(_:withText:)` is the path typing takes, so the edit lands on
    /// the undo stack and the delegate restyles it and writes it back to the
    /// page, exactly as if it had been typed. Assigning `.text` would do
    /// neither, and would throw away the selection besides.
    private func perform(_ makeEdit: (String, NSRange) -> TextEdit) {
        guard mode == .text, let textView else { return }

        let edit = makeEdit(textView.text ?? "", textView.selectedRange)

        guard let start = textView.position(from: textView.beginningOfDocument, offset: edit.range.location),
              let end = textView.position(from: start, offset: edit.range.length),
              let range = textView.textRange(from: start, to: end)
        else { return }

        // Formatting is a prelude to typing, so the keyboard comes up for it.
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        textView.replace(range, withText: edit.replacement)
        textView.selectedRange = edit.selection
        refreshUndoState()
    }

    // MARK: Undo

    /// The undo stack of whichever layer is taking input.
    ///
    /// Two stacks, not one. Left alone they would be one: the canvas's
    /// `undoManager` walks the responder chain into the text view's. Ink and
    /// text are separate kinds of edit, and undoing a stroke by accident while
    /// typing is worse than an arrow that only undoes what the current mode
    /// did, so `DrawingCanvas` vends its own and this picks between them.
    private var activeUndoManager: UndoManager? {
        mode == .text ? textView?.undoManager : canvas?.undoManager
    }

    func undo() {
        activeUndoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        activeUndoManager?.redo()
        refreshUndoState()
    }

    /// Re-reads whether undo and redo have anything to do.
    ///
    /// Assigns only on a real change. This runs on every keystroke, and an
    /// observable property invalidates its readers on any assignment, equal
    /// value or not — the whole hotbar would re-render per character.
    func refreshUndoState() {
        let undo = activeUndoManager?.canUndo ?? false
        let redo = activeUndoManager?.canRedo ?? false
        if canUndo != undo { canUndo = undo }
        if canRedo != redo { canRedo = redo }
    }
}

#endif
