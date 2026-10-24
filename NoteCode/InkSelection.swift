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

    /// Lasso or rectangle. Per device (`InkToolPersistence`).
    var kind = SelectionKind.lasso

    /// The elements selected: every piece of every object the shape touched.
    private(set) var ids: Set<ElementID> = []

    /// Where they are on the note, for the box drawn round them.
    private(set) var bounds: CGRect?

    var isEmpty: Bool { ids.isEmpty }

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
        set(InkObjects.select(shape, in: canvas.markup))
        return !ids.isEmpty
    }

    func clear() {
        guard !ids.isEmpty else { return }
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

    func beginAdjusting() {
        base = canvas?.markup
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

    private var originalBounds: CGRect? {
        guard let base else { return bounds }
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
        canvas.showPreview(InkCommands.transformed(base, ids: ids, by: transform))
        // The box follows what it surrounds.
        bounds = originalBounds?.applying(transform)
        onChange?()
    }

    /// Makes what the preview showed the reader's change: one capture, one
    /// undo step. A drag that went nowhere changes nothing.
    func endAdjusting(actionName: String) {
        defer { base = nil; pending = nil }
        guard let canvas, let base else { return }
        guard let transform = pending, transform != .identity else {
            canvas.showPreview(base)
            return
        }
        // Back to where it was, quietly, so the canvas's delegate sees the
        // one change from there to the end rather than two.
        let after = InkCommands.transformed(base, ids: ids, by: transform)
        canvas.showPreview(base)
        canvas.replaceMarkup(with: after, actionName: actionName)
        set(ids)
    }

    /// Puts the canvas back as the drag found it.
    func cancelAdjusting() {
        defer { base = nil; pending = nil }
        guard let canvas, let base else { return }
        canvas.showPreview(base)
        set(ids)
    }

    // MARK: Commands

    func move(by translation: CGSize) {
        guard let canvas, !ids.isEmpty else { return }
        let after = InkCommands.transformed(canvas.markup, ids: ids, by: CGAffineTransform(translationX: translation.width, y: translation.height))
        canvas.replaceMarkup(with: after, actionName: "Move")
        set(ids)
    }

    func recolour(to color: UIColor) {
        guard let canvas, !ids.isEmpty else { return }
        canvas.replaceMarkup(with: InkCommands.recoloured(canvas.markup, ids: ids, to: color), actionName: "Colour")
        set(ids)
    }

    func delete() {
        guard let canvas, !ids.isEmpty else { return }
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
