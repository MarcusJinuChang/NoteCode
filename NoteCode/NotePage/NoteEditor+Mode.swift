//
//  NoteEditor+Mode.swift
//  NoteCode
//
//  The page's mode and the ink tool hand-off.
//

#if canImport(UIKit)

import Observation
import PaperKit
import SwiftUI
import UIKit

extension NoteEditor {


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
    func toolDidChange() {
        canvas?.tool = inkTool.pencilKitTool
        page?.selection.kind = inkTools.selectionKind
        applySelecting()
    }

    /// The store changed under this note: from its own hotbar, or from
    /// Settings.
    func storeDidChange(_ change: InkToolStore.Change) {
        switch change {
        case .tool:
            toolDidChange()
        case .fingerDraws:
            canvas?.allowsFingerDrawing = !isPencilOnly
            applySelecting()
            applyScrolling()
        case .returnsToPreviousTool, .palette:
            break
        }
    }

    /// The Select tool's selection, once the page exists.
    var selection: InkSelection? { page?.selection }

    /// Gives touches to the Select tool's overlay while it is the tool in ink
    /// mode, and to the canvas otherwise.
    func applySelecting() {
        let selecting = mode == .ink && inkTool.kind == .lasso
        // PaperKit gets no touches while the Select tool has the page, except
        // for one object the reader chose to Edit.
        let editing = page?.selection.isEditingInPaperKit ?? false
        canvas?.suspendsPaperKitInput = selecting
        page?.setSelecting(selecting && !editing, allowsFingers: !isPencilOnly)
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
}

#endif
