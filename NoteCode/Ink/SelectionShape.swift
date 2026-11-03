//
//  SelectionShape.swift
//  NoteCode
//
//  The shape the Select tool drags out. Pure geometry, so the text side
//  (TextRegionSelection) and the macOS build can use it without UIKit.
//  See docs/design/object-system.md.
//

import CoreGraphics
import Foundation

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
