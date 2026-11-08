//
//  RunDockCollapseUITests.swift
//  NoteCodeUITests
//
//  The Run dock's collapse chevron, at the top of the handle on the dock's
//  left edge. It was a 6×10pt target over the handle's width drag, and no
//  tap ever collapsed the dock; now it is the handle's top 44pt and the
//  strip's empty padding beside it. Pro: `-debug-pro` and the Run disclosure's
//  setting are in Pro/, so the open-source build deletes this folder.
//

import XCTest

final class RunDockCollapseUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 120
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// The code note in landscape (a regular width, so Run is the dock),
    /// with the dock open.
    @MainActor
    private func openDock() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-debug-note", "code", "-debug-pro", "on",
                               "-runDisclosureAccepted", "YES", "-debug-run-stub", "ok"]
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15), "the note never opened")
        let run = app.buttons.matching(NSPredicate(format: "label == 'Run'"))
            .allElementsBoundByIndex.first { $0.frame.minY < 90 }
        XCTAssertNotNil(run, "no Run in the top bar")
        run?.tap()
        XCTAssertTrue(app.buttons["runPanelRun"].firstMatch.waitForExistence(timeout: 5), "the dock never opened")
        return app
    }

    /// Taps `point` and expects the dock to collapse to its edge tab, then
    /// opens it again from the tab.
    @MainActor
    private func expectCollapse(_ app: XCUIApplication, at point: CGPoint, _ what: String) {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        let tab = app.buttons["Show Run panel"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 3), "a tap \(what) didn't collapse the dock")
        tab.tap()
        XCTAssertTrue(app.buttons["Collapse Run panel"].firstMatch.waitForExistence(timeout: 3),
                      "the edge tab didn't bring the dock back")
    }

    @MainActor
    func testChevronCollapsesTheDock() throws {
        let app = openDock()
        let chevron = app.buttons["Collapse Run panel"].firstMatch
        XCTAssertTrue(chevron.waitForExistence(timeout: 3), "no collapse chevron")
        let target = chevron.frame
        XCTAssertGreaterThanOrEqual(target.width, 30, "the chevron's target is \(target.size)")
        XCTAssertGreaterThanOrEqual(target.height, 44, "the chevron's target is \(target.size)")

        expectCollapse(app, at: CGPoint(x: target.midX, y: target.midY), "at the chevron")
        // The target's corners, beside the handle and below the glyph.
        expectCollapse(app, at: CGPoint(x: target.maxX - 3, y: target.maxY - 3), "at the target's lower right")
        expectCollapse(app, at: CGPoint(x: target.minX + 3, y: target.maxY - 3), "at the target's lower left")

        // The first block chip, just past the target, is still the chip's.
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '1 · '")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 3), "no first block chip")
        XCTAssertGreaterThanOrEqual(chip.frame.minX, target.maxX - 1, "the chevron's target covers the chip")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: chip.frame.minX + 3, dy: chip.frame.midY)).tap()
        XCTAssertFalse(app.buttons["Show Run panel"].waitForExistence(timeout: 1.5), "a tap on the chip collapsed the dock")
    }

    /// The rest of the handle still drags the width, and a drag doesn't
    /// collapse.
    @MainActor
    func testHandleBelowTheChevronStillDrags() throws {
        let app = openDock()
        let chevron = app.buttons["Collapse Run panel"].firstMatch
        XCTAssertTrue(chevron.waitForExistence(timeout: 3), "no collapse chevron")
        let before = chevron.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: before.midX, dy: before.maxY + 200))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: -100, dy: 0)))
        let after = app.buttons["Collapse Run panel"].firstMatch.frame
        XCTAssertEqual(after.midX, before.midX - 100, accuracy: 4, "the handle didn't drag the width")
        XCTAssertFalse(app.buttons["Show Run panel"].exists, "a drag collapsed the dock")
    }
}
