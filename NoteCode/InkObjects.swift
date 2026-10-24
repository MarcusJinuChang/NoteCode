//
//  InkObjects.swift
//  NoteCode
//
//  Ink objects: what a selection shape touches, and the commands that change a
//  selection. Pure, off the main thread if the caller wants. See
//  docs/design/object-system.md, decisions 1, 2 and 4.
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import UIKit

/// What the reader drags out to select: a rectangle or a free lasso.
nonisolated enum SelectionShape: Equatable, Sendable {
    case rectangle(CGRect)
    /// A closed polygon, the last point joined to the first.
    case lasso([CGPoint])

    var bounds: CGRect {
        switch self {
        case .rectangle(let rect):
            return rect.standardized
        case .lasso(let points):
            guard let first = points.first else { return .null }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for point in points {
                minX = min(minX, point.x); maxX = max(maxX, point.x)
                minY = min(minY, point.y); maxY = max(maxY, point.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        switch self {
        case .rectangle(let rect):
            return rect.standardized.contains(point)
        case .lasso(let points):
            guard points.count >= 3 else { return false }
            // Even-odd, so a lasso that crosses itself leaves its loop out.
            var inside = false
            var previous = points[points.count - 1]
            for current in points {
                if (current.y > point.y) != (previous.y > point.y),
                   point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x {
                    inside.toggle()
                }
                previous = current
            }
            return inside
        }
    }

    /// Whether the shape touches a rectangle, for elements drawn as a frame.
    func touches(_ frame: CGRect) -> Bool {
        guard bounds.intersects(frame) else { return false }
        switch self {
        case .rectangle:
            return true
        case .lasso(let points):
            let corners = [
                CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY),
                CGPoint(x: frame.midX, y: frame.midY),
            ]
            return corners.contains(where: contains) || points.contains(where: frame.contains)
        }
    }
}

nonisolated enum InkObjects {

    typealias ElementID = MarkupOrderedSet.ElementID

    /// What the reader sees as one thing. A stroke across a page break is
    /// several pieces with one family (`InkPages`); anything else is itself.
    enum Key: Hashable, Sendable {
        case stroke(InkPages.Family)
        case element(ElementID)
    }

    static func key(of element: any Markup) -> Key {
        if let stroke = element as? PKStroke {
            return .stroke(InkPages.family(of: stroke.id))
        }
        return .element(element.elementID)
    }

    /// How far apart the path points a stroke is tested at are, in points.
    /// Closer than a pen's width, so a fast line can't slip through a
    /// rectangle's corner between two points.
    static let pathStep: CGFloat = 4

    // MARK: Hit testing

    /// The elements of every object `shape` touches, pieces included.
    ///
    /// Touching, not containing: a handwritten diagram is caught by dragging
    /// roughly around it. A stroke is touched when a point of its visible
    /// path is in the shape; anything else when its frame is.
    ///
    /// Walks the markup once with `for`; see `PageView.frames(of:)`.
    static func select(_ shape: SelectionShape, in markup: PaperMarkup) -> Set<ElementID> {
        let area = shape.bounds
        guard !area.isNull else { return [] }

        var hit: Set<Key> = []
        for element in markup.subelements {
            let frame = element.renderFrame
            guard frame.intersects(area) else { continue }
            let key = key(of: element)
            if hit.contains(key) { continue }
            if let stroke = element as? PKStroke {
                if touches(shape, stroke: stroke) { hit.insert(key) }
            } else if shape.touches(frame) {
                hit.insert(key)
            }
        }
        guard !hit.isEmpty else { return [] }

        // The whole object: a piece the shape missed goes with its family.
        var ids: Set<ElementID> = []
        for element in markup.subelements where hit.contains(key(of: element)) {
            ids.insert(element.elementID)
        }
        return ids
    }

    static func touches(_ shape: SelectionShape, stroke: PKStroke) -> Bool {
        for point in stroke.path.interpolatedPoints(by: .distance(pathStep)) {
            // The mask is in the stroke's own space, before its transform.
            if let mask = stroke.mask, !mask.contains(point.location) { continue }
            if shape.contains(point.location.applying(stroke.transform)) { return true }
        }
        return false
    }
}

// MARK: - Commands

/// The changes the Select tool makes. Each returns a new markup built in one
/// append, with every untouched element as it was and every touched one under
/// its own id.
///
/// **Never per element.** `updateOrAppend` and `removeElement` cost time in
/// proportion to the set's size each, so moving 114 of 5,000 strokes took 1.7s
/// that way against 130ms rebuilt (scripts/spikes/object-system-probe.swift).
/// `InkObjectCommandTests.cost` keeps it.
nonisolated enum InkCommands {

    typealias ElementID = MarkupOrderedSet.ElementID

    static func transformed(_ markup: PaperMarkup, ids: Set<ElementID>, by transform: CGAffineTransform) -> PaperMarkup {
        rebuilt(markup) { element in
            guard ids.contains(element.elementID) else { return element }
            var moved = element
            moved.applyTransform(transform)
            return moved
        }
    }

    static func deleted(_ markup: PaperMarkup, ids: Set<ElementID>) -> PaperMarkup {
        rebuilt(markup) { ids.contains($0.elementID) ? nil : $0 }
    }

    /// Strokes get the colour as ink (same type and width), shapes as their
    /// line and, where they had a fill, their fill. Images have none.
    static func recoloured(_ markup: PaperMarkup, ids: Set<ElementID>, to color: UIColor) -> PaperMarkup {
        rebuilt(markup) { element in
            guard ids.contains(element.elementID) else { return element }
            if let stroke = element as? PKStroke {
                return recoloured(stroke, to: color)
            }
            if var shape = element as? ShapeMarkup {
                shape.strokeColor = color.cgColor
                if shape.fillColor != nil { shape.fillColor = color.withAlphaComponent(0.2).cgColor }
                return shape
            }
            return element
        }
    }

    /// A copy of `stroke` in another colour. Same id, so it is the same
    /// object to the canvas, to `InkCapture` and to undo.
    static func recoloured(_ stroke: PKStroke, to color: UIColor) -> PKStroke {
        var copy = PKStroke(
            ink: PKInk(stroke.ink.inkType, color: color), path: stroke.path,
            transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
        copy.id = stroke.id
        return copy
    }

    /// Copies the objects, moved by `offset`, on top of the markup.
    /// - Returns: the new markup, and the copies' ids.
    static func duplicated(_ markup: PaperMarkup, ids: Set<ElementID>, offset: CGSize) -> (markup: PaperMarkup, copies: Set<ElementID>) {
        let shift = CGAffineTransform(translationX: offset.width, y: offset.height)
        var elements: [any Markup] = []
        var copies: [any Markup] = []
        for element in markup.subelements {
            elements.append(element)
            guard ids.contains(element.elementID), let copy = copied(element) else { continue }
            var moved = copy
            moved.applyTransform(shift)
            copies.append(moved)
        }
        // A stroke's pieces share a family; their copies must too.
        copies = reidentified(copies)
        var result = PaperMarkup(bounds: markup.bounds)
        result.subelements.append(contentsOf: elements + copies)
        return (result, Set(copies.map(\.elementID)))
    }

    // MARK: Building

    private static func rebuilt(_ markup: PaperMarkup, _ change: (any Markup) -> (any Markup)?) -> PaperMarkup {
        var elements: [any Markup] = []
        elements.reserveCapacity(markup.subelements.count)
        for element in markup.subelements {
            if let changed = change(element) { elements.append(changed) }
        }
        var result = PaperMarkup(bounds: markup.bounds)
        result.subelements.append(contentsOf: elements)
        return result
    }

    /// A copy under a new identity: strokes get a fresh id, shapes and images a
    /// fresh `MarkupID`.
    private static func copied(_ element: any Markup) -> (any Markup)? {
        if let stroke = element as? PKStroke {
            var copy = PKStroke(
                ink: stroke.ink, path: stroke.path, transform: stroke.transform,
                mask: stroke.mask, randomSeed: stroke.randomSeed)
            copy.id = stroke.id
            return copy
        }
        if var shape = element as? ShapeMarkup {
            shape.id = MarkupID()
            return shape
        }
        if var image = element as? ImageMarkup {
            image.id = MarkupID()
            return image
        }
        return nil
    }

    /// A random id in `family` that isn't an overflow piece's.
    private static func ownID(in family: InkPages.Family) -> UUID {
        var id = InkPages.overflowID(in: family)
        // `overflowID` carries the mark in bytes 10 to 13; flip one so this
        // one doesn't, and keep the family's ten.
        var bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        bytes[10] ^= 0xFF
        id = bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
        return id
    }

    /// Gives each family among `strokes` a new one, the same new one to all of
    /// its pieces, and an overflow piece an overflow id in it.
    private static func reidentified(_ elements: [any Markup]) -> [any Markup] {
        var families: [InkPages.Family: InkPages.Family] = [:]
        return elements.map { element in
            guard var stroke = element as? PKStroke else { return element }
            let old = InkPages.family(of: stroke.id)
            let new = families[old] ?? InkPages.family(of: UUID())
            families[old] = new
            stroke.id = InkPages.isOverflow(stroke.id) ? InkPages.overflowID(in: new) : ownID(in: new)
            return stroke
        }
    }
}

#endif
