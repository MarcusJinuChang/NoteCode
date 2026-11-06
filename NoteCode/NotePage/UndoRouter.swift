//
//  UndoRouter.swift
//  NoteCode
//
//  Undo and redo for whichever layer has the page, and whether there is
//  anything to undo, which the hotbar shows.
//

#if canImport(UIKit)

import Observation
import PaperKit
import SwiftUI
import UIKit

/// Picks the undo stack of the layer taking input, and keeps `canUndo` and
/// `canRedo` for the hotbar. `NoteEditor` forwards to it; the text view's
/// coordinator and the editor tell it (`refresh()`) whenever an edit may have
/// changed what there is to undo.
@Observable
final class UndoRouter {

    @ObservationIgnored private unowned let editor: NoteEditor

    private(set) var canUndo = false
    private(set) var canRedo = false

    init(editor: NoteEditor) {
        self.editor = editor
    }

    /// The undo stack of whichever layer is taking input.
    ///
    /// Two stacks, not one. Left alone they would be one: the canvas's
    /// `undoManager` walks the responder chain into the text view's. Ink and
    /// text are separate kinds of edit, and undoing a stroke by accident while
    /// typing is worse than an arrow that only undoes what the current mode
    /// did, so `DrawingCanvas` vends its own and this picks between them.
    ///
    /// None while the text is locked: undoing typing would change locked
    /// text. Ink keeps its stack, since the lock leaves ink alone.
    private var activeUndoManager: UndoManager? {
        switch editor.mode {
        case .text: editor.isTextLocked ? nil : editor.textView?.undoManager
        case .ink:  editor.canvas?.undoManager
        }
    }

    func undo() {
        activeUndoManager?.undo()
        refresh()
    }

    func redo() {
        activeUndoManager?.redo()
        refresh()
    }

    /// ⌘Z and ⇧⌘Z, from the menu bar.
    ///
    /// The note's own stacks, unless some other text field has the keyboard
    /// (the title being renamed, the list's search): undoing there is for
    /// that field, and the note's typing isn't what was asked for. The
    /// system's Undo command reaches only a first responder that has an undo
    /// manager, and in ink mode nothing on the page is first responder, so
    /// the menu would otherwise be dead exactly when ink has the page.
    func undoFromKeyboard() {
        if let other = otherTextInputUndoManager { other.undo() } else { undo() }
    }

    func redoFromKeyboard() {
        if let other = otherTextInputUndoManager { other.redo() } else { redo() }
    }

    private var otherTextInputUndoManager: UndoManager? {
        guard let responder = UIResponder.currentFirstResponder,
              responder is UITextInput, responder !== editor.textView
        else { return nil }
        return responder.undoManager
    }

    /// Re-reads whether undo and redo have anything to do.
    ///
    /// Assigns only on a real change. This runs on every keystroke, and an
    /// observable property invalidates its readers on any assignment, equal
    /// value or not — the whole hotbar would re-render per character.
    func refresh() {
        let undo = activeUndoManager?.canUndo ?? false
        let redo = activeUndoManager?.canRedo ?? false
        if canUndo != undo { canUndo = undo }
        if canRedo != redo { canRedo = redo }
    }
}

#endif
