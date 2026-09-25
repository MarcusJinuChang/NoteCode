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
    private let portraitWidth = PageLayout(orientation: .portrait).pageSize.width
    private let landscapeWidth = PageLayout(orientation: .landscape).pageSize.width

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
            return CanvasGeometry.fitScale(areaWidth: 834 - insets.left - insets.right, pageWidth: portraitWidth)
        }

        #expect(Set(scales).count == 1)
    }

    @Test("The bottom is reserved only while the bar is there")
    func bottomOnlyWhenDockedThere() {
        #expect(CanvasGeometry.hotbarReserve(dock: .bottom, thickness: reserve).bottom == reserve)
        #expect(CanvasGeometry.hotbarReserve(dock: .left, thickness: reserve).bottom == 0)
        #expect(CanvasGeometry.hotbarReserve(dock: .right, thickness: reserve).bottom == 0)
    }

    // MARK: Fitting

    @Test("A page fits its area's width")
    func fitsWidth() {
        // iPad Pro 13-inch portrait: 1032pt.
        #expect(CanvasGeometry.fitScale(areaWidth: area(screenWidth: 1032), pageWidth: portraitWidth) == 880.0 / 816)
        // iPad Pro 11-inch portrait, landscape page.
        #expect(CanvasGeometry.fitScale(areaWidth: area(screenWidth: 834), pageWidth: landscapeWidth) == 682.0 / 1056)
    }

    @Test("Fitting stops at the ceiling and grows margins instead")
    func capsFit() {
        // iPad Pro 13-inch landscape would otherwise be 1.5x.
        #expect(CanvasGeometry.fitScale(areaWidth: area(screenWidth: 1376), pageWidth: portraitWidth) == CanvasGeometry.maximumFitScale)
    }

    @Test("Print layout fits inside a gutter, so the surround shows either side of a sheet")
    func printGutter() {
        let gutter = CanvasGeometry.gutter(for: .print)
        let scale = CanvasGeometry.fitScale(areaWidth: 872, pageWidth: portraitWidth, gutter: gutter)
        let frame = CanvasGeometry.pageFrame(in: CGSize(width: 872, height: 1000), pageWidth: portraitWidth, scale: scale)

        #expect(gutter > 0)
        #expect(abs(frame.minX - gutter) < 0.001)
        #expect(CanvasGeometry.gutter(for: .seamless) == 0)
        #expect(CanvasGeometry.gutter(for: .compressed) == 0)
    }

    @Test("A zero-width area, before layout, doesn't produce a zero or infinite scale")
    func zeroWidth() {
        #expect(CanvasGeometry.fitScale(areaWidth: 0, pageWidth: portraitWidth) == 1)
    }

    @Test("Zoom multiplies the fit, within its range")
    func zoomMultipliesFit() {
        let fit = CanvasGeometry.fitScale(areaWidth: 880, pageWidth: portraitWidth)

        #expect(CanvasGeometry.displayScale(areaWidth: 880, pageWidth: portraitWidth, zoom: 2) == fit * 2)
        #expect(CanvasGeometry.displayScale(areaWidth: 880, pageWidth: portraitWidth, zoom: 40) == fit * CanvasGeometry.maximumZoom)
        #expect(CanvasGeometry.displayScale(areaWidth: 880, pageWidth: portraitWidth, zoom: 0.01) == fit * CanvasGeometry.minimumZoom)
    }

    @Test("Rendering density follows the scale, up to its cap")
    func renderingCap() {
        #expect(CanvasGeometry.renderingScale(displayScale: 1.25, screenScale: 2) == 2.5)
        #expect(CanvasGeometry.renderingScale(displayScale: 5, screenScale: 2) == CanvasGeometry.maximumRenderingScale * 2)
        // Ink never zooms below 1 — see CanvasGeometry.inkRenderScale.
        #expect(CanvasGeometry.inkRenderScale(displayScale: 0.84) == 1)
        #expect(CanvasGeometry.inkRenderScale(displayScale: 1.25) == 1.25)
        #expect(CanvasGeometry.inkRenderScale(displayScale: 5) == CanvasGeometry.maximumRenderingScale)
    }

    // MARK: Frame

    @Test("A page narrower than its area is centred")
    func centred() {
        let frame = CanvasGeometry.pageFrame(in: CGSize(width: 1224, height: 900), pageWidth: 816, scale: 1.25)

        #expect(frame.width == 1020)
        #expect(frame.minX == 102)
    }

    @Test("A page wider than its area starts at the left edge")
    func overflowPinnedLeft() {
        let frame = CanvasGeometry.pageFrame(in: CGSize(width: 682, height: 900), pageWidth: 816, scale: 2)

        #expect(frame.minX == 0)
        #expect(frame.width == 1632)
    }

    @Test("The page's own bounds are always the page width, and fill the area's height once scaled")
    func bounds() {
        let area = CGSize(width: 682, height: 1000)
        let scale = CanvasGeometry.fitScale(areaWidth: area.width, pageWidth: 816)
        let bounds = CanvasGeometry.pageBounds(in: area, pageWidth: 816, scale: scale)

        #expect(bounds.width == 816)
        #expect(abs(bounds.height * scale - area.height) < 0.001)
    }

    // MARK: Zoom

    private let area = CGSize(width: 880, height: 1100)

    /// The page point under `focus` for a viewport.
    private func pagePoint(under focus: CGPoint, in viewport: CanvasGeometry.Viewport) -> CGPoint {
        let frame = CanvasGeometry.pageFrame(in: area, pageWidth: 816, scale: viewport.scale)
        return CGPoint(
            x: (focus.x + viewport.horizontalOffset - frame.minX) / viewport.scale,
            y: viewport.verticalOffset + focus.y / viewport.scale
        )
    }

    @Test("Zooming keeps the point between the fingers under them", arguments: [
        (CGPoint(x: 440, y: 550), CGFloat(2.5)),
        (CGPoint(x: 120, y: 900), CGFloat(1.8)),
        (CGPoint(x: 700, y: 200), CGFloat(3.2)),
    ])
    func focusStaysPut(focus: CGPoint, scale: CGFloat) {
        let before = CanvasGeometry.Viewport(scale: 1.078, horizontalOffset: 0, verticalOffset: 3000)
        let after = CanvasGeometry.zoom(before, to: scale, about: focus, area: area, pageWidth: 816, noteHeight: 20_000)

        let was = pagePoint(under: focus, in: before)
        let now = pagePoint(under: focus, in: after)
        #expect(abs(was.x - now.x) < 0.001)
        #expect(abs(was.y - now.y) < 0.001)
    }

    @Test("Zooming back out from anywhere recentres the page sideways")
    func zoomOutRecentres() {
        let zoomedIn = CanvasGeometry.Viewport(scale: 3, horizontalOffset: 900, verticalOffset: 3000)
        let after = CanvasGeometry.zoom(zoomedIn, to: 0.8, about: CGPoint(x: 800, y: 500), area: area, pageWidth: 816, noteHeight: 20_000)

        #expect(after.horizontalOffset == 0)
    }

    @Test("Zooming near an edge never scrolls past it")
    func clampsToEdges() {
        let top = CanvasGeometry.Viewport(scale: 1, horizontalOffset: 0, verticalOffset: 0)
        let zoomedOut = CanvasGeometry.zoom(top, to: 0.6, about: CGPoint(x: 10, y: 1000), area: area, pageWidth: 816, noteHeight: 20_000)
        #expect(zoomedOut.verticalOffset == 0)

        let end = CanvasGeometry.Viewport(scale: 2, horizontalOffset: 750, verticalOffset: 19_500)
        let further = CanvasGeometry.zoom(end, to: 4, about: CGPoint(x: 870, y: 1090), area: area, pageWidth: 816, noteHeight: 20_000)
        #expect(further.horizontalOffset <= 816 * 4 - area.width)
        #expect(further.verticalOffset <= 20_000 - area.height / 4)
    }
}
