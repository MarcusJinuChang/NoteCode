//
//  InkSelectionOverlay.swift
//  NoteCode
//
//  The view that owns touches while the Select tool is current, above the
//  canvas, so PaperKit never sees one and has nothing to select
//  (docs/design/object-system.md, decision 3).
//

#if canImport(UIKit)

import UIKit

@MainActor
final class InkSelectionOverlay: UIView {

    let selection: InkSelection

    /// Whether the Select tool is current in ink mode. Off, the view takes no
    /// touch and draws nothing, and the canvas below owns them.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            isUserInteractionEnabled = isActive
            if !isActive { cancelTouch() }
            redraw()
        }
    }

    /// Whether a finger selects, as it draws: off, only the Pencil does and
    /// a finger scrolls the note.
    var allowsFingers = true

    /// Where a touch may start, in note coordinates: the canvas's own rule.
    var takesTouch: ((CGPoint) -> Bool)?

    private enum Gesture {
        case drawing(start: CGPoint)
        case moving(start: CGPoint)
        case scaling(start: CGPoint, corner: CGPoint)
    }

    private var gesture: Gesture?
    private var activeTouch: UITouch?
    private var trail: [CGPoint] = []
    private var lastPreview: TimeInterval = 0

    private let trailLayer = CAShapeLayer()
    private let boxLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    private let textLayer = CAShapeLayer()

    init(selection: InkSelection) {
        self.selection = selection
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isMultipleTouchEnabled = true

        for layer in [textLayer, trailLayer, boxLayer, handleLayer] {
            layer.fillColor = nil
            layer.lineWidth = 1.5
            self.layer.addSublayer(layer)
        }
        trailLayer.lineDashPattern = [6, 4]
        trailLayer.lineJoin = .round
        boxLayer.lineDashPattern = [5, 3]
        handleLayer.lineWidth = 2

        selection.onChange = { [weak self] in self?.redraw() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Covers `visible`, part of the note, in the note's own coordinates:
    /// the bounds' origin is the part's, so a layer path or a touch location
    /// in the text view's content needs no conversion.
    func cover(_ visible: CGRect) {
        if bounds != CGRect(origin: visible.origin, size: visible.size) {
            bounds = CGRect(origin: visible.origin, size: visible.size)
        }
        let middle = CGPoint(x: visible.midX, y: visible.midY)
        if center != middle { center = middle }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isActive, super.point(inside: point, with: event) else { return false }
        return takesTouch?(point) ?? true
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        redraw()
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // A second finger is a scroll (two fingers scroll while a finger
        // draws): let go of what the first started.
        if activeTouch != nil {
            cancelTouch()
            return
        }
        guard let touch = touches.first, allowsFingers || touch.type != .direct else { return }
        activeTouch = touch
        let point = touch.location(in: self)
        switch SelectionTouch.decide(at: point, selection: selection.bounds, canScale: selection.canScale) {
        case .draw:
            hadSelection = !selection.isEmpty
            selection.clear()
            gesture = .drawing(start: point)
            trail = [point]
        case .move:
            gesture = .moving(start: point)
            selection.beginAdjusting()
        case .scale:
            gesture = .scaling(start: point, corner: selection.bounds?.origin ?? point)
            selection.beginAdjusting()
        }
        redraw()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch), let gesture else { return }
        let point = touch.location(in: self)
        switch gesture {
        case .drawing:
            trail.append(point)
            redraw()
        case .moving(let start):
            throttled { self.selection.previewMove(by: CGSize(width: point.x - start.x, height: point.y - start.y)) }
        case .scaling(let start, let corner):
            let from = max(hypot(start.x - corner.x, start.y - corner.y), 1)
            let factor = max(0.1, hypot(point.x - corner.x, point.y - corner.y) / from)
            throttled { self.selection.previewScale(by: factor) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch), let gesture else { return }
        let point = touch.location(in: self)
        switch gesture {
        case .drawing(let start):
            completeDrawing(with: shape(from: start, to: point))
        case .moving(let start):
            // The last position, whatever the throttle skipped.
            selection.previewMove(by: CGSize(width: point.x - start.x, height: point.y - start.y))
            selection.endAdjusting(actionName: "Move")
        case .scaling(let start, let corner):
            let from = max(hypot(start.x - corner.x, start.y - corner.y), 1)
            selection.previewScale(by: max(0.1, hypot(point.x - corner.x, point.y - corner.y) / from))
            selection.endAdjusting(actionName: "Resize")
        }
        finish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        cancelTouch()
    }

    /// The shape a drawing gesture made. A touch that barely moved is a tap:
    /// a small square round it, which picks the one object under it.
    private func shape(from start: CGPoint, to end: CGPoint) -> SelectionShape? {
        if hypot(end.x - start.x, end.y - start.y) < Self.tapDistance && trail.count < 12 || trail.count < 2 {
            return .rectangle(CGRect(x: start.x - Self.tapSize / 2, y: start.y - Self.tapSize / 2, width: Self.tapSize, height: Self.tapSize))
        }
        switch selection.kind {
        case .rectangle:
            return .rectangle(CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
        case .lasso:
            return .lasso(trail)
        }
    }

    private var hadSelection = false

    /// For tests, which can't make a touch: as if one had landed on empty
    /// space with a selection up.
    func beginsDrawingForTest() {
        hadSelection = !selection.isEmpty
        selection.clear()
    }

    /// A drawn shape is done: select what it covers. Where something was
    /// selected and the shape covers nothing, the selection has ended by the
    /// reader's choice (a tap on empty space), which `onEnded` reports.
    func completeDrawing(with shape: SelectionShape?) {
        let covered = shape.map { selection.select($0) } ?? false
        if hadSelection && !covered { selection.onEnded?() }
        hadSelection = false
    }

    static let tapDistance: CGFloat = 8
    static let tapSize: CGFloat = 8

    private func throttled(_ preview: () -> Void) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPreview >= 1.0 / 30 else { return }
        lastPreview = now
        preview()
    }

    private func finish() {
        gesture = nil
        activeTouch = nil
        trail = []
        redraw()
    }

    func cancelTouch() {
        if case .moving = gesture { selection.cancelAdjusting() }
        if case .scaling = gesture { selection.cancelAdjusting() }
        finish()
    }

    // MARK: Drawing

    private func redraw() {
        let tint = (tintColor ?? .systemBlue).cgColor
        trailLayer.strokeColor = tint
        textLayer.fillColor = UIColor(cgColor: tint).withAlphaComponent(0.25).cgColor
        textLayer.strokeColor = nil
        boxLayer.strokeColor = tint
        handleLayer.strokeColor = UIColor.white.cgColor
        handleLayer.fillColor = tint

        guard isActive else {
            trailLayer.path = nil; boxLayer.path = nil; handleLayer.path = nil; textLayer.path = nil
            return
        }

        if case .drawing(let start) = gesture, let last = trail.last {
            let path = UIBezierPath()
            switch selection.kind {
            case .rectangle:
                path.append(UIBezierPath(rect: CGRect(x: min(start.x, last.x), y: min(start.y, last.y), width: abs(last.x - start.x), height: abs(last.y - start.y))))
            case .lasso:
                path.move(to: trail[0])
                trail.dropFirst().forEach { path.addLine(to: $0) }
            }
            trailLayer.path = path.cgPath
        } else {
            trailLayer.path = nil
        }

        let highlight = UIBezierPath()
        for piece in selection.textPieces {
            highlight.append(UIBezierPath(roundedRect: piece.rect, cornerRadius: 3))
        }
        textLayer.path = selection.textPieces.isEmpty ? nil : highlight.cgPath

        if let box = selection.bounds {
            boxLayer.path = UIBezierPath(roundedRect: box.insetBy(dx: -6, dy: -6), cornerRadius: 6).cgPath
            if selection.canScale {
                let corner = CGPoint(x: box.maxX + 6, y: box.maxY + 6)
                handleLayer.path = UIBezierPath(arcCenter: corner, radius: 8, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
            } else {
                handleLayer.path = nil
            }
        } else {
            boxLayer.path = nil
            handleLayer.path = nil
        }
    }
}

#endif
