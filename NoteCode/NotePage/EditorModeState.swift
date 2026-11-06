//
//  EditorModeState.swift
//  NoteCode
//
//  The page's mode and the ink tool hand-off.
//

#if canImport(UIKit)

import Observation
import PaperKit
import UIKit

/// The page's mode (text or ink), the ink tool in hand and the Pencil rules
/// around them. `NoteEditor` forwards each member the hotbar, the page and the
/// text view's coordinator use; the views stay the editor's, and this reaches
/// them through it.
@Observable
final class EditorModeState {

    @ObservationIgnored private unowned let editor: NoteEditor

    /// What each layer was doing when the other took the page.
    @ObservationIgnored private var savedSession: TextSession?

    private(set) var mode: EditorMode = .text

    /// Called after the mode changes. The text view's code blocks show or
    /// hide their fences with it (`DocumentTextView.Coordinator`), and no
    /// edit or selection change tells them.
    ///
    /// Not observed state: it is the text view's hook, and hooking it up
    /// must not make the hotbar re-render.
    @ObservationIgnored var modeDidChange: (() -> Void)?

    /// What the pen, highlighter, eraser and Select tool are set to, and
    /// Finger Draws, kept for the device (`InkToolStore`). The editor holds
    /// only the tool in hand.
    let inkTools: InkToolStore

    /// The tool in hand. Not stored: a note opens on the pen.
    private var toolKind = InkToolKind.pen {
        didSet {
            guard toolKind != oldValue else { return }
            previousInkKind = oldValue
            toolDidChange()
            // The selection is the canvas controller's, not the tool's, so it
            // outlived the lasso (reported 21 Oct). Only *leaving* the lasso
            // clears it: `insertIntoInk` selects what it inserted and then
            // switches to the lasso, and that must keep the selection.
            if oldValue == .lasso, toolKind != .lasso {
                editor.canvas?.clearPaperKitSelection()
                editor.page?.selection.clear()
            }
        }
    }

    /// The tool in use before the current one, for the Pencil's double tap
    /// and squeeze to switch back to.
    private(set) var previousInkKind = InkToolKind.pen

    init(editor: NoteEditor, inkTools: InkToolStore) {
        self.editor = editor
        self.inkTools = inkTools
        inkTools.listen(self) { state, change in state.storeDidChange(change) }
    }

    /// The text view and canvas exist: the mode is applied to them.
    func attachViews(_ textView: UITextView, canvas: DrawingCanvas?) {
        savedSession = mode.apply(to: textView, canvas: canvas, saved: nil, textLocked: editor.isTextLocked)
    }

    /// The note was locked or unlocked.
    func textLockDidChange(_ locked: Bool) {
        if let textView = editor.textView {
            savedSession = mode.apply(to: textView, canvas: editor.canvas, saved: savedSession, textLocked: locked)
        }
    }



    /// What ink mode draws with: the tool in hand, and the store's settings.
    /// Kept here rather than in the hotbar so the canvas can take it as it
    /// changes.
    var inkTool: InkToolState {
        get {
            InkToolState(
                kind: toolKind, pen: inkTools.pen, highlighter: inkTools.highlighter,
                eraser: inkTools.eraser, selectionKind: inkTools.selectionKind
            )
        }
        set {
            inkTools.pen = newValue.pen
            inkTools.highlighter = newValue.highlighter
            inkTools.eraser = newValue.eraser
            inkTools.selectionKind = newValue.selectionKind
            toolKind = newValue.kind
        }
    }

    /// The canvas takes the tool, and the Select tool its shape.
    private func toolDidChange() {
        editor.canvas?.tool = inkTool.pencilKitTool
        editor.page?.selection.kind = inkTools.selectionKind
        applySelecting()
    }

    /// The store changed under this note: from its own hotbar, or from
    /// Settings.
    private func storeDidChange(_ change: InkToolStore.Change) {
        switch change {
        case .tool:
            toolDidChange()
        case .fingerDraws:
            editor.canvas?.allowsFingerDrawing = !isPencilOnly
            applySelecting()
            applyScrolling()
        case .returnsToPreviousTool, .palette:
            break
        }
    }

    /// The Select tool's selection, once the page exists.
    var selection: InkSelection? { editor.page?.selection }

    /// Gives touches to the Select tool's overlay while it is the tool in ink
    /// mode, and to the canvas otherwise.
    func applySelecting() {
        let selecting = mode == .ink && inkTool.kind == .lasso
        // PaperKit gets no touches while the Select tool has the page, except
        // for one object the reader chose to Edit.
        let editing = editor.page?.selection.isEditingInPaperKit ?? false
        editor.canvas?.suspendsPaperKitInput = selecting
        editor.page?.setSelecting(selecting && !editing, allowsFingers: !isPencilOnly)
    }

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

    /// The Pencil's double tap or squeeze while the text has the page: goes to
    /// ink mode so the gesture has something to act on, then does what the
    /// reader set it to. Nothing when the setting is off or a shortcut the
    /// system runs itself, since switching mode for a gesture that then does
    /// nothing would only surprise. Whether the mode changed.
    @discardableResult
    func enterInkForPencil(_ response: PencilResponse) -> Bool {
        guard mode == .text, response != .nothing else { return false }
        setMode(.ink)
        return true
    }

    /// Picks a tool from the keyboard (P, H, E, L). Ink mode only: in text
    /// mode these are letters.
    func selectTool(_ kind: InkToolKind) {
        guard mode == .ink else { return }
        inkTool.kind = kind
    }

    /// `[` and `]`: the selected tool one width thinner or thicker.
    func stepWidth(by direction: Int) {
        guard mode == .ink else { return }
        inkTool.stepWidth(by: direction)
    }

    /// ⇧⌘D, and the same switch as the hotbar's text and draw buttons.
    func toggleMode() {
        setMode(mode == .text ? .ink : .text)
    }

    /// Whether only the Pencil draws.
    ///
    /// Off by default. The page already has a hard toggle between typing and
    /// drawing, so a finger in ink mode means to draw; there is no need to
    /// make people reach for the Pencil to leave a mark. On, a finger scrolls
    /// and selects instead — what you want with the Pencil in hand and a palm
    /// resting on the page. After the first change it is whatever the reader
    /// last chose on this device (`fingerDrawsKey`).
    var isPencilOnly: Bool {
        get { !inkTools.fingerDraws }
        set { inkTools.fingerDraws = !newValue }
    }

    /// The same switch as `isPencilOnly`, said the way the hotbar's hand
    /// button says it: on, a finger draws.
    var fingerDraws: Bool {
        get { !isPencilOnly }
        set { isPencilOnly = !newValue }
    }

    /// Whether the selection ending sends the reader back to their tool.
    /// Per device (`InkToolStore`).
    var returnsToPreviousTool: Bool {
        get { inkTools.returnsToPreviousTool }
        set { inkTools.returnsToPreviousTool = newValue }
    }

    /// The Select tool's selection ended because the reader let go of it:
    /// Delete, or a tap on empty space. Never a tool or mode switch (they
    /// chose a tool) and never a move, recolour or duplicate (they often
    /// do two in a row). Goes back to the tool before Select, if asked to.
    func selectionEnded() {
        guard returnsToPreviousTool, mode == .ink, inkTool.kind == .lasso, previousInkKind != .lasso else { return }
        inkTool.kind = previousInkKind
    }


    func setMode(_ newMode: EditorMode) {
        guard newMode != mode else { return }
        mode = newMode
        editor.typing.clear()
        if let textView = editor.textView {
            savedSession = newMode.apply(to: textView, canvas: editor.canvas, saved: savedSession, textLocked: editor.isTextLocked)
        }
        applyScrolling()
        if newMode != .ink { editor.page?.selection.clear() }
        applySelecting()
        editor.undoRouter.refresh()
        modeDidChange?()
    }


    /// Hands the page's pans whatever the mode and the Pencil lock leave them.
    ///
    /// Through the page when there is one: it picks between this rule and
    /// one finger as each touch lands, by whether the canvas takes it.
    func applyScrolling() {
        let scrolling = mode.scrolling(fingerDraws: !isPencilOnly)
        if let page = editor.page {
            page.scrolling = scrolling
        } else if let textView = editor.textView {
            scrolling.apply(to: textView.panGestureRecognizer)
        }
    }
}

#endif
