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

    static let `default` = SettingKeys.General.hotbarDock.defaultValue

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
