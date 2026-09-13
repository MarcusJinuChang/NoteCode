//
//  HotbarDock.swift
//  NoteCode
//
//  Which edge of the page the hotbar sits on.
//

import CoreGraphics

/// The edges the hotbar can dock to. Never the top: that's the title.
nonisolated enum HotbarDock: String, CaseIterable, Sendable {
    case left
    case bottom
    case right

    static let `default` = HotbarDock.bottom

    /// Stored per device, like the default run destination. Where the bar
    /// belongs depends on how this iPad is held and which hand has the Pencil,
    /// not on which note is open.
    static let defaultsKey = "hotbarDock"

    var isVertical: Bool {
        self != .bottom
    }

    /// The edge a bar dropped at `point` snaps to: whichever is closest.
    ///
    /// Distances are signed, so a bar flung past an edge still lands on that
    /// edge. Exact ties go to the bottom, then the left.
    static func nearest(to point: CGPoint, in size: CGSize) -> HotbarDock {
        let distances: [(dock: HotbarDock, distance: CGFloat)] = [
            (.bottom, size.height - point.y),
            (.left, point.x),
            (.right, size.width - point.x),
        ]
        return distances.min { $0.distance < $1.distance }!.dock
    }
}
