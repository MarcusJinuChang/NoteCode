//
//  InkSelection.swift
//  NoteCode
//
//  The Select tool's state and what it does to the canvas. The overlay
//  (InkSelectionOverlay) turns touches into calls on this; nothing here knows
//  about touches. docs/design/object-system.md, decisions 2 and 4.
//

#if canImport(UIKit)

import Observation
import PaperKit
import PencilKit
import UIKit

/// What a touch that lands with the Select tool does, decided from where it
/// lands. Pure, so the rules are tested without a touch.
nonisolated enum SelectionTouch: Equatable, Sendable {
    /// Draw a new shape, letting go of the selection.
    case draw
    /// Move the selection.
    case move
    /// Scale the selection from its top-left corner.
    case scale

    /// How far past the selection's edge a touch still counts as on it, and
    /// the corner handle's reach, in points of the note.
    static let slop: CGFloat = 12
    static let handleReach: CGFloat = 22

    static func decide(at point: CGPoint, selection: CGRect?, canScale: Bool) -> SelectionTouch {
        guard let selection else { return .draw }
        if canScale {
            let handle = CGPoint(x: selection.maxX, y: selection.maxY)
            if hypot(point.x - handle.x, point.y - handle.y) <= handleReach { return .scale }
        }
        return selection.insetBy(dx: -slop, dy: -slop).contains(point) ? .move : .draw
    }
}

@MainActor
@Observable
final class InkSelection {

    typealias ElementID = MarkupOrderedSet.ElementID

    /// Lasso or rectangle. Per device (`InkToolStore`).
    var kind = SelectionKind.lasso

    /// The elements selected: every piece of every object the shape touched.
    private(set) var ids: Set<ElementID> = []

    /// Where they are on the note, for the box drawn round them.
    private(set) var bounds: CGRect?

    /// The text the shape covered, a range per line, with where each is drawn.
    private(set) var textPieces: [TextRegion.Piece] = []

    /// Nothing selected, ink or text.
    var isEmpty: Bool { ids.isEmpty && textPieces.isEmpty }

    /// Whether any ink is selected: what moves, duplicates and deletes.
    var hasInk: Bool { !ids.isEmpty }

    /// Reads the text a shape covers. Set by the page.
    @ObservationIgnored var textPiecesFor: ((SelectionShape) -> [TextRegion.Piece])?

    /// Recolours text ranges (`nil`: takes colour off). Set by the editor,
    /// which owns the text; returns whether it did.
    @ObservationIgnored var recolourText: (([NSRange], Int?) -> Void)?

    @ObservationIgnored weak var canvas: DrawingCanvas?

    /// The canvas as it was when a drag or scale began.
    @ObservationIgnored private var base: PaperMarkup?

    /// Called whenever `ids` or `bounds` change, so the overlay redraws.
    @ObservationIgnored var onChange: (() -> Void)?

    /// Called when a command ends the selection by the reader's choice
    /// (Delete), as opposed to a tool or mode switch. The previous-tool rule
    /// reads this.
    @ObservationIgnored var onEnded: (() -> Void)?

    /// Whether the objects selected can be scaled: only if all sit within one
    /// page's region of ink, since a stroke cut across a break would need its
    /// pieces re-cut (docs/design/object-system.md, risks). Set by the page.
    @ObservationIgnored var regions: [CGRect] = []

    var canScale: Bool {
        guard let bounds else { return false }
        return regions.isEmpty || regions.contains { $0.contains(bounds) }
    }

    // MARK: Choosing

    /// Selects what `shape` touches. A shape that touches nothing is no
    /// selection.
    @discardableResult
    func select(_ shape: SelectionShape) -> Bool {
        guard let canvas else { return false }
        textPieces = textPiecesFor?(shape) ?? []
        set(InkObjects.select(shape, in: canvas.markup))
        return !isEmpty
    }

    /// Whether one shape or image is selected: the case PaperKit's own
    /// selection can finish what the Select tool doesn't.
    var canEditInPaperKit: Bool {
        guard ids.count == 1, let canvas, let id = ids.first else { return false }
        for element in canvas.markup.subelements where element.elementID == id {
            return !(element is PKStroke)
        }
        return false
    }

    private(set) var isEditingInPaperKit = false

    func editInPaperKit() {
        guard canEditInPaperKit, let canvas, let id = ids.first else { return }
        isEditingInPaperKit = true
        canvas.beginPaperKitEdit(id)
        onEditingChange?()
    }

    func finishEditingInPaperKit() {
        guard isEditingInPaperKit else { return }
        isEditingInPaperKit = false
        canvas?.endPaperKitEdit()
        refresh()
        onEditingChange?()
    }

    /// Called when PaperKit's editing starts or ends, so the page can give it
    /// the touches and take them back.
    @ObservationIgnored var onEditingChange: (() -> Void)?

    /// Selects these elements, when the app chose them (what Insert added).
    func select(ids new: Set<ElementID>) {
        textPieces = []
        set(new)
    }

    func clear() {
        finishEditingInPaperKit()
        guard !isEmpty else { return }
        textPieces = []
        set([])
    }

    /// Drops ids the canvas no longer holds and refreshes the box: after an
    /// undo, an erase, or a mode switch.
    func refresh() {
        guard let canvas, !ids.isEmpty else { return }
        var present: Set<ElementID> = []
        for element in canvas.markup.subelements where ids.contains(element.elementID) {
            present.insert(element.elementID)
        }
        set(present)
    }

    private func set(_ new: Set<ElementID>) {
        ids = new
        bounds = new.isEmpty ? nil : frame(of: new)
        onChange?()
    }

    private func frame(of ids: Set<ElementID>) -> CGRect? {
        guard let canvas else { return nil }
        var union: CGRect?
        for element in canvas.markup.subelements where ids.contains(element.elementID) {
            union = union.map { $0.union(element.renderFrame) } ?? element.renderFrame
        }
        return union
    }

    // MARK: A drag or a scale in progress

    /// Bumped by every begin and end, so a snapshot that finishes drawing
    /// after its drag is over is not used.
    @ObservationIgnored private var adjustment = 0

    /// Whether a drag or a scale is in progress: the canvas may be showing
    /// the note without the selection, so nothing else should replace its
    /// markup (`PageInkPipeline.isBusy`).
    var isAdjusting: Bool { base != nil }

    /// Whether the canvas still shows `base`, as the drag found it: nothing
    /// was hidden or previewed yet, so ending or cancelling assigns nothing.
    @ObservationIgnored private var showsBase = true

    /// The picture couldn't be drawn (too large), so previews assign the
    /// whole markup, as they did before O2.
    @ObservationIgnored private var previewsWholeMarkup = false

    /// The task drawing the picture, for `settled()`.
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?

    func beginAdjusting() {
        base = canvas?.markup
        startBounds = nil
        startBounds = originalBounds
        adjustment += 1
        showsBase = true
        previewsWholeMarkup = false
        guard let canvas, let base, let area = originalBounds else { return }
        let token = adjustment
        let ids = ids
        // Until the picture is ready only the box moves. Assigning the whole
        // markup per preview, as this did before the picture was up, had
        // PaperKit redraw the page 30 times a second, and it flashed.
        snapshotTask = Task { @MainActor [weak self, weak canvas] in
            let selected = InkCommands.only(base, ids: ids)
            let isCurrent = { () -> Bool in
                guard let self else { return false }
                return self.adjustment == token && self.base != nil
            }
            guard let canvas else { return }
            let shown = await canvas.showSnapshot(
                of: selected, over: area.insetBy(dx: -24, dy: -24),
                isCurrent: isCurrent,
                remaining: InkCommands.deleted(base, ids: ids))
            // A drag that ended while the picture was drawing has already
            // put the canvas right; touching it now would hide the selection
            // with nothing to bring it back, and the next capture would store
            // the note without it (Marcus, 21 Nov: moved ink disappearing).
            guard let self, isCurrent() else { return }
            if shown {
                self.showsBase = false
                // Catch up with where the drag got to while it was drawing.
                if let pending = self.pending { canvas.transformSnapshot(pending) }
            } else {
                self.previewsWholeMarkup = true
                if let pending = self.pending { self.preview(pending) }
            }
        }
    }

    /// Returns once the picture for the drag begun last is up, or given up.
    /// For tests.
    func settled() async {
        await snapshotTask?.value
    }

    /// Shows the selection moved by `translation`. Quiet: nothing is told
    /// until `endAdjusting`.
    func previewMove(by translation: CGSize) {
        preview(CGAffineTransform(translationX: translation.width, y: translation.height))
    }

    /// Shows the selection scaled by `factor` about its top-left corner.
    func previewScale(by factor: CGFloat) {
        guard let origin = originalBounds?.origin else { return }
        let transform = CGAffineTransform(translationX: origin.x, y: origin.y)
            .scaledBy(x: factor, y: factor)
            .translatedBy(x: -origin.x, y: -origin.y)
        preview(transform)
    }

    /// Where the selection was when the drag began, found once: walking the
    /// whole markup for it on every preview cost what the note's size does.
    @ObservationIgnored private var startBounds: CGRect?

    private var originalBounds: CGRect? {
        guard let base else { return bounds }
        if let startBounds { return startBounds }
        var union: CGRect?
        for element in base.subelements where ids.contains(element.elementID) {
            union = union.map { $0.union(element.renderFrame) } ?? element.renderFrame
        }
        return union
    }

    private var pending: CGAffineTransform?

    private func preview(_ transform: CGAffineTransform) {
        guard let canvas, let base else { return }
        pending = transform
        if canvas.isShowingSnapshot {
            canvas.transformSnapshot(transform)
        } else if previewsWholeMarkup {
            canvas.showPreview(InkCommands.transformed(base, ids: ids, by: transform))
            showsBase = false
        }
        // The box follows what it surrounds.
        bounds = originalBounds?.applying(transform)
        onChange?()
    }

    /// Makes what the preview showed the reader's change: one capture, one
    /// undo step. A drag that went nowhere changes nothing.
    func endAdjusting(actionName: String) {
        defer { finishAdjusting() }
        guard let canvas, let base else { return }
        guard let transform = pending, transform != .identity else {
            putBack(base, on: canvas)
            return
        }
        // Back to where it was, quietly, so the canvas's delegate sees the
        // one change from there to the end rather than two. The picture
        // stays up a moment over the canvas while PaperKit redraws, so the
        // moved ink doesn't blink out on release.
        let after = InkCommands.transformed(base, ids: ids, by: transform)
        if canvas.isShowingSnapshot {
            canvas.releaseSnapshot()
        } else if !showsBase {
            canvas.holdStill()
        }
        if !showsBase { canvas.showPreview(base) }
        canvas.replaceMarkup(with: after, actionName: actionName)
        set(ids)
    }

    /// Puts the canvas back as the drag found it.
    func cancelAdjusting() {
        defer { finishAdjusting() }
        guard let canvas, let base else { return }
        putBack(base, on: canvas)
    }

    private func putBack(_ base: PaperMarkup, on canvas: DrawingCanvas) {
        if canvas.isShowingSnapshot {
            // The picture goes back to where the ink is and stays a moment,
            // over the canvas redrawing it there.
            canvas.transformSnapshot(.identity)
            canvas.releaseSnapshot()
        }
        // Nothing to assign when nothing was hidden or moved: a tap on the
        // selection, or a drag that ended before its picture was drawn.
        if !showsBase { canvas.showPreview(base) }
        set(ids)
    }

    private func finishAdjusting() {
        base = nil
        pending = nil
        startBounds = nil
        showsBase = true
        previewsWholeMarkup = false
        adjustment += 1
    }

    // MARK: Commands

    func move(by translation: CGSize) {
        guard let canvas, !ids.isEmpty else { return }
        let after = InkCommands.transformed(canvas.markup, ids: ids, by: CGAffineTransform(translationX: translation.width, y: translation.height))
        canvas.replaceMarkup(with: after, actionName: "Move")
        set(ids)
    }

    /// Recolours the ink as `color` and the text as the nearest text colour
    /// (none for a grey): one control for both.
    func recolour(to color: UIColor) {
        if let canvas, !ids.isEmpty {
            canvas.replaceMarkup(with: InkCommands.recoloured(canvas.markup, ids: ids, to: color), actionName: "Colour")
            set(ids)
        }
        if !textPieces.isEmpty {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            recolourText?(textPieces.map(\.range), TextColour.nearest(red: r, green: g, blue: b)?.hex)
        }
    }

    func delete() {
        guard let canvas, !ids.isEmpty else { return }
        textPieces = []
        canvas.replaceMarkup(with: InkCommands.deleted(canvas.markup, ids: ids), actionName: "Delete")
        set([])
        onEnded?()
    }

    /// Copies the selection a little down and right, and selects the copies.
    func duplicate(offset: CGSize = CGSize(width: 24, height: 24)) {
        guard let canvas, !ids.isEmpty else { return }
        let (after, copies) = InkCommands.duplicated(canvas.markup, ids: ids, offset: offset)
        canvas.replaceMarkup(with: after, actionName: "Duplicate")
        set(copies)
    }
}

#endif
