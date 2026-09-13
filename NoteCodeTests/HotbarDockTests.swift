//
//  HotbarDockTests.swift
//  NoteCodeTests
//

import CoreGraphics
import Testing
@testable import NoteCode

@Suite("Hotbar dock")
struct HotbarDockTests {

    /// An iPad Pro 13-inch page area in landscape, below the title.
    private let landscape = CGSize(width: 1376, height: 860)

    /// The same iPad in portrait.
    private let portrait = CGSize(width: 1032, height: 1200)

    @Test("A drop near an edge docks to that edge", arguments: [
        (CGPoint(x: 40, y: 400), HotbarDock.left),
        (CGPoint(x: 1336, y: 400), .right),
        (CGPoint(x: 688, y: 830), .bottom),
    ])
    func nearEdge(point: CGPoint, expected: HotbarDock) {
        #expect(HotbarDock.nearest(to: point, in: landscape) == expected)
    }

    @Test("The top half of a tall page picks a side, since there is no top dock")
    func topPicksSide() {
        #expect(HotbarDock.nearest(to: CGPoint(x: 200, y: 50), in: portrait) == .left)
        #expect(HotbarDock.nearest(to: CGPoint(x: 900, y: 50), in: portrait) == .right)
    }

    @Test("A bottom corner goes to whichever edge is actually closer")
    func corners() {
        #expect(HotbarDock.nearest(to: CGPoint(x: 30, y: 800), in: landscape) == .left)
        #expect(HotbarDock.nearest(to: CGPoint(x: 120, y: 840), in: landscape) == .bottom)
    }

    @Test("A bar flung past an edge still lands on it")
    func flungPastEdge() {
        #expect(HotbarDock.nearest(to: CGPoint(x: 1600, y: 100), in: landscape) == .right)
        #expect(HotbarDock.nearest(to: CGPoint(x: -300, y: 100), in: landscape) == .left)
        #expect(HotbarDock.nearest(to: CGPoint(x: 688, y: 1400), in: landscape) == .bottom)
    }

    @Test("Only the bottom dock lies flat")
    func orientation() {
        #expect(!HotbarDock.bottom.isVertical)
        #expect(HotbarDock.left.isVertical)
        #expect(HotbarDock.right.isVertical)
    }

    @Test("Stored values keep their spelling, or a saved dock is forgotten on update")
    func rawValuesAreStable() {
        #expect(HotbarDock(rawValue: "left") == .left)
        #expect(HotbarDock(rawValue: "bottom") == .bottom)
        #expect(HotbarDock(rawValue: "right") == .right)
    }
}
