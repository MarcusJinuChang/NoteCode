//
//  HotbarUITests.swift
//  NoteCodeUITests
//
//  Where the ink options row sits and what its touches reach. Run as the user
//  would see them: through the accessibility tree and real taps, since a unit
//  test can't see a SwiftUI hit test.
//

import XCTest

final class HotbarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The edge the bar is docked to, as `HotbarDock` spells it.
    private enum Dock: String, CaseIterable {
        case bottom, left, right
    }

    /// A note, the dock, and every stored ink setting emptied. An empty value
    /// isn't a palette or a setting, so the app reads its defaults; the
    /// simulator's own saved palettes would otherwise decide what is on screen.
    private static func arguments(dock: Dock) -> [String] {
        ["-debug-note", "empty", "-hotbarDock", dock.rawValue,
         "-inkPalette", "", "-highlighterPalette", "",
         "-penSettings", "", "-highlighterSettings", "", "-eraser", ""]
    }

    @MainActor
    private func launchInInkMode(dock: Dock) -> XCUIApplication {
        let app = XCUIApplication()
        // A launch argument outranks the saved setting, so this is the dock
        // for this launch only.
        app.launchArguments = Self.arguments(dock: dock)
        app.launch()
        app.buttons["Draw"].tap()
        XCTAssertTrue(app.buttons["Medium Pen"].waitForExistence(timeout: 5), "the options row never came out")
        // Past the row's slide in.
        Thread.sleep(forTimeInterval: 0.8)
        return app
    }

    // MARK: Position

    @MainActor
    private func checkRowBesideBar(dock: Dock) {
        let app = launchInInkMode(dock: dock)
        // The bar, and the row's controls. A control's frame is its touch
        // area: 40pt thick as it looks, and 4pt more toward the page.
        let bar = app.otherElements["hotbar"].frame
        let first = app.buttons["Ink"].frame
        let last = app.buttons["Bold Pen"].frame
        let row = first.union(last)

        let gap: CGFloat = 8
        let thickness: CGFloat = 40 + 4

        switch dock {
        case .bottom:
            XCTAssertEqual(bar.minY - row.maxY, gap, accuracy: 1, "gap above the bar")
            XCTAssertEqual(row.midX, bar.midX, accuracy: 1.5, "centred along the bar")
            XCTAssertEqual(row.height, thickness, accuracy: 1, "40pt thick, and 4pt of reach")
        case .left:
            XCTAssertEqual(row.minX - bar.maxX, gap, accuracy: 1, "gap right of the bar")
            XCTAssertEqual(row.midY, bar.midY, accuracy: 1.5, "centred along the bar")
            XCTAssertEqual(row.width, thickness, accuracy: 1, "40pt thick, and 4pt of reach")
        case .right:
            XCTAssertEqual(bar.minX - row.maxX, gap, accuracy: 1, "gap left of the bar")
            XCTAssertEqual(row.midY, bar.midY, accuracy: 1.5, "centred along the bar")
            XCTAssertEqual(row.width, thickness, accuracy: 1, "40pt thick, and 4pt of reach")
        }
        app.terminate()
    }

    @MainActor func testRowBesideBarDockedAtTheBottom() { checkRowBesideBar(dock: .bottom) }
    @MainActor func testRowBesideBarDockedLeft() { checkRowBesideBar(dock: .left) }
    @MainActor func testRowBesideBarDockedRight() { checkRowBesideBar(dock: .right) }

    // MARK: Coming and going

    @MainActor
    func testRowIsOutOnlyInInkModeForAToolWithOptions() {
        let app = XCUIApplication()
        app.launchArguments = Self.arguments(dock: .bottom)
        app.launch()
        XCTAssertFalse(app.buttons["Medium Pen"].exists, "text mode")

        app.buttons["Draw"].tap()
        XCTAssertTrue(app.buttons["Medium Pen"].waitForExistence(timeout: 5), "pen")

        app.buttons["Highlighter"].tap()
        XCTAssertTrue(app.buttons["Medium Highlighter"].waitForExistence(timeout: 5), "highlighter")
        XCTAssertTrue(app.buttons["Yellow"].isSelected, "the highlighter starts on yellow")

        app.buttons["Eraser"].tap()
        XCTAssertTrue(app.buttons["Pixel Eraser"].waitForExistence(timeout: 5), "eraser")

        app.buttons["Lasso"].tap()
        XCTAssertTrue(app.buttons["Pixel Eraser"].waitForNonExistence(timeout: 5), "lasso has no row")
        XCTAssertFalse(app.buttons["Medium Pen"].exists)
        XCTAssertTrue(app.buttons["Lasso"].exists, "the bar itself stays")

        app.buttons["Pen"].tap()
        XCTAssertTrue(app.buttons["Medium Pen"].waitForExistence(timeout: 5), "pen again")
        app.buttons["Text"].tap()
        XCTAssertTrue(app.buttons["Medium Pen"].waitForNonExistence(timeout: 5), "back in text mode")
        app.terminate()
    }

    // MARK: Reach

    /// Taps `point`, in the window's points from its top left.
    @MainActor
    private func tap(_ point: CGPoint, in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y))
            .tap()
    }

    /// The row's controls take touches in the 4pt past the row's edge toward the
    /// page, and none toward the bar, where the 8pt gap is.
    @MainActor
    private func checkReach(dock: Dock) {
        let app = launchInInkMode(dock: dock)
        let blue = app.buttons["Blue"]
        let red = app.buttons["Red"]
        XCTAssertTrue(app.buttons["Ink"].isSelected, "the pen starts on ink")

        // A control's frame is 44pt across: 40 of face, then 4 of reach on the
        // page's side. So the page's edge of the frame is the reach's far edge,
        // and the bar's edge is the face's.
        let frame = blue.frame
        let redFrame = red.frame
        let inReach: CGPoint
        let inGap: CGPoint
        switch dock {
        case .bottom:
            inReach = CGPoint(x: frame.midX, y: frame.minY + 1.5)
            inGap = CGPoint(x: redFrame.midX, y: redFrame.maxY + 2)
        case .left:
            inReach = CGPoint(x: frame.maxX - 1.5, y: frame.midY)
            inGap = CGPoint(x: redFrame.minX - 2, y: redFrame.midY)
        case .right:
            inReach = CGPoint(x: frame.minX + 1.5, y: frame.midY)
            inGap = CGPoint(x: redFrame.maxX + 2, y: redFrame.midY)
        }

        // Toward the bar, past the face: the gap. Nothing there takes it.
        tap(inGap, in: app)
        XCTAssertFalse(red.isSelected, "a touch in the gap toward the bar reached a control")
        XCTAssertTrue(app.buttons["Ink"].isSelected)

        // Toward the page, in the reach: still the control, though it's past
        // where the row is drawn.
        tap(inReach, in: app)
        XCTAssertTrue(blue.waitForExistence(timeout: 2))
        XCTAssertTrue(blue.isSelected, "a touch in the 4pt of reach toward the page missed its control")
        app.terminate()
    }

    @MainActor func testReachDockedAtTheBottom() { checkReach(dock: .bottom) }
    @MainActor func testReachDockedLeft() { checkReach(dock: .left) }
    @MainActor func testReachDockedRight() { checkReach(dock: .right) }
}
