//
//  NoteEditor+Undo.swift
//  NoteCode
//
//  Undo and redo for whichever layer has the page.
//

#if canImport(UIKit)

import Observation
import PaperKit
import SwiftUI
import UIKit

extension NoteEditor {

    // MARK: Undo

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
        switch mode {
        case .text: isTextLocked ? nil : textView?.undoManager
        case .ink:  canvas?.undoManager
        }
    }

    func undo() {
        activeUndoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        activeUndoManager?.redo()
        refreshUndoState()
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
              responder is UITextInput, responder !== textView
        else { return nil }
        return responder.undoManager
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
