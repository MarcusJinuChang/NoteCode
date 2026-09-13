//
//  CanvasGeometryTests.swift
//  NoteCodeTests
//

import CoreGraphics
import Testing
@testable import NoteCode

@Suite("Canvas geometry")
struct CanvasGeometryTests {

    private let reserve: CGFloat = 76

    /// Page areas once both side reserves come off, in points.
    private func area(screenWidth: CGFloat) -> CGFloat {
        screenWidth - reserve * 2
    }

    // MARK: Hotbar reserve

    @Test("Both sides are reserved wherever the bar is docked", arguments: HotbarDock.allCases)
    func bothSidesAlways(dock: HotbarDock) {
        let insets = CanvasGeometry.hotbarReserve(dock: dock, thickness: reserve)

        #expect(insets.left == reserve)
        #expect(insets.right == reserve)
    }

    @Test("Moving the bar never changes the scale")
    func dockDoesNotChangeScale() {
        let scales = HotbarDock.allCases.map { dock in
            let insets = CanvasGeometry.hotbarReserve(dock: dock, thickness: reserve)
            return CanvasGeometry.displayScale(forAreaWidth: 834 - insets.left - insets.right)
        }

        #expect(Set(scales).count == 1)
    }

    @Test("The bottom is reserved only while the bar is there")
    func bottomOnlyWhenDockedThere() {
        #expect(CanvasGeometry.hotbarReserve(dock: .bottom, thickness: reserve).bottom == reserve)
        #expect(CanvasGeometry.hotbarReserve(dock: .left, thickness: reserve).bottom == 0)
        #expect(CanvasGeometry.hotbarReserve(dock: .right, thickness: reserve).bottom == 0)
    }

    // MARK: Scale

    @Test("An area narrower than the page draws it smaller, down to the floor")
    func scalesDown() {
        // iPad Pro 11-inch portrait: 834pt.
        #expect(CanvasGeometry.displayScale(forAreaWidth: area(screenWidth: 834)) == 682.0 / 700)
        // iPad mini portrait: 744pt.
        #expect(CanvasGeometry.displayScale(forAreaWidth: area(screenWidth: 744)) == 592.0 / 700)
        // A narrow Split View.
        #expect(CanvasGeometry.displayScale(forAreaWidth: 300) == CanvasGeometry.minimumScale)
    }

    @Test("Wide areas stop at the ceiling and grow margins instead")
    func capsScale() {
        // iPad Pro 13-inch landscape would otherwise be 1.75x.
        #expect(CanvasGeometry.displayScale(forAreaWidth: area(screenWidth: 1376)) == CanvasGeometry.maximumScale)
    }

    @Test("A zero-width area, before layout, doesn't produce a zero or infinite scale")
    func zeroWidth() {
        #expect(CanvasGeometry.displayScale(forAreaWidth: 0) == 1)
    }

    // MARK: Frame

    @Test("A page narrower than its area is centred")
    func centred() {
        let frame = CanvasGeometry.pageFrame(in: CGSize(width: 1224, height: 900), scale: 1.25)

        #expect(frame.width == 875)
        #expect(frame.minX == 174.5)
    }

    @Test("A page wider than its area starts at the left edge")
    func overflowPinnedLeft() {
        let frame = CanvasGeometry.pageFrame(in: CGSize(width: 300, height: 900), scale: 0.75)

        #expect(frame.minX == 0)
        #expect(frame.width == 525)
    }

    @Test("The page's own bounds are always the page width, and fill the area's height once scaled")
    func bounds() {
        let area = CGSize(width: 682, height: 1000)
        let scale = CanvasGeometry.displayScale(forAreaWidth: area.width)
        let bounds = CanvasGeometry.pageBounds(in: area, scale: scale)

        #expect(bounds.width == CanvasGeometry.pageWidth)
        #expect(abs(bounds.height * scale - area.height) < 0.001)
    }

    // MARK: Bottom inset

    @Test("With no ink, the bottom inset is the minimum")
    func noInk() {
        #expect(CanvasGeometry.bottomInset(textHeight: 400, inkBottom: nil, minimum: 12, room: 200) == 12)
    }

    @Test("Ink below the last line extends the page to reach it")
    func inkBelowText() {
        let inset = CanvasGeometry.bottomInset(textHeight: 400, inkBottom: 3000, minimum: 12, room: 200)

        #expect(400 + inset == 3200)
    }

    @Test("Ink within the text leaves the minimum alone")
    func inkWithinText() {
        #expect(CanvasGeometry.bottomInset(textHeight: 4000, inkBottom: 300, minimum: 12, room: 200) == 12)
    }

    @Test("Deleting text never clips ink")
    func deletingTextKeepsInk() {
        for textHeight in stride(from: 5000, through: 0, by: -250) {
            let inset = CanvasGeometry.bottomInset(
                textHeight: CGFloat(textHeight), inkBottom: 3000, minimum: 12, room: 200
            )
            #expect(CGFloat(textHeight) + inset >= 3000)
        }
    }
}
