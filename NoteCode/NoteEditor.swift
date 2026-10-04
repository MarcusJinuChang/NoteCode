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
            if inkTool.kind != oldValue.kind {
                previousInkKind = oldValue.kind
            }
            canvas?.tool = inkTool.pencilKitTool
        }
    }

    /// The tool in use before the current one, for the Pencil's double tap
    /// and squeeze to switch back to.
    private(set) var previousInkKind = InkToolKind.pen

    /// Swaps between the current tool and the eraser: the Pencil's double
    /// tap, as the system sets it up out of the box.
    func toggleEraser() {
        if inkTool.kind == .eraser {
            inkTool.kind = previousInkKind == .eraser ? .pen : previousInkKind
        } else {
            inkTool.kind = .eraser
        }
    }

    /// Swaps between the current tool and the one before it.
    func switchToPreviousTool() {
        inkTool.kind = previousInkKind
    }

    /// Whether only the Pencil draws.
    ///
    /// Off by default. The page already has a hard toggle between typing and
    /// drawing, so a finger in ink mode means to draw; there is no need to
    /// make people reach for the Pencil to leave a mark. On, a finger scrolls
    /// and selects instead — what you want with the Pencil in hand and a palm
    /// resting on the page.
    var isPencilOnly = false {
        didSet {
            guard isPencilOnly != oldValue else { return }
            canvas?.allowsFingerDrawing = !isPencilOnly
            applyScrolling()
        }
    }

    /// Whether the note's text is locked (`Page.isTextLocked`), so text mode
    /// reads rather than edits: no keyboard, no formatting, no undo. The page
    /// holds the setting; this is the copy the text view and the hotbar
    /// follow, set by `setTextLocked(_:)`.
    private(set) var isTextLocked = false

    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored private weak var textView: UITextView?
    @ObservationIgnored private weak var canvas: DrawingCanvas?
    @ObservationIgnored private weak var page: PageView?
    @ObservationIgnored private var savedSession: TextSession?

    /// How many pages the open note runs to, for its info. Read when asked
    /// rather than observed: the count changes as the note is typed, and
    /// nothing on screen shows it.
    var pageCount: Int? {
        page?.pageCount
    }

    /// Called by `DocumentTextView` once the page, and so the canvas, exists.
    ///
    /// - Parameter page: the page around the text view, if any.
    func attach(_ textView: UITextView, canvas: DrawingCanvas? = nil, page: PageView? = nil) {
        self.textView = textView
        self.canvas = canvas
        self.page = page
        canvas?.tool = inkTool.pencilKitTool
        canvas?.allowsFingerDrawing = !isPencilOnly
        canvas?.onUndoDidChange = { [weak self] in self?.refreshUndoState() }
        savedSession = mode.apply(to: textView, canvas: canvas, saved: nil, textLocked: isTextLocked)
        applyScrolling()
        refreshUndoState()
    }

    func setMode(_ newMode: EditorMode) {
        guard newMode != mode else { return }
        mode = newMode
        if let textView {
            savedSession = newMode.apply(to: textView, canvas: canvas, saved: savedSession, textLocked: isTextLocked)
        }
        applyScrolling()
        refreshUndoState()
    }

    /// Locks or unlocks the note's text.
    ///
    /// Locking puts the keyboard away. Unlocking doesn't bring it back: the
    /// reader was reading, and a tap is all it takes to start typing. In ink
    /// mode nothing changes until text mode comes back, and a keyboard that
    /// was up before ink only returns then if the text is unlocked by then.
    /// Works before the text view exists too, and `attach` applies it.
    func setTextLocked(_ locked: Bool) {
        guard locked != isTextLocked else { return }
        isTextLocked = locked
        if let textView {
            savedSession = mode.apply(to: textView, canvas: canvas, saved: savedSession, textLocked: locked)
        }
        refreshUndoState()
    }

    /// Hands the page's pans whatever the mode and the Pencil lock leave them.
    ///
    /// Through the page when there is one: it picks between this rule and
    /// one finger as each touch lands, by whether the canvas takes it.
    private func applyScrolling() {
        let scrolling = mode.scrolling(fingerDraws: !isPencilOnly)
        if let page {
            page.scrolling = scrolling
        } else if let textView {
            scrolling.apply(to: textView.panGestureRecognizer)
        }
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
        guard mode == .text, !isTextLocked, let textView else { return }

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
