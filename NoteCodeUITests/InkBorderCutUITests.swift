//
//  InkBorderCutUITests.swift
//  NoteCodeUITests
//
//  A stroke drawn across a page border, in compressed and print layout,
//  stops at the border on screen once the pen lifts (docs/design/pages.md,
//  "When the pen lifts"), and one undo takes it.
//
//  On screen, not in the canvas's markup: the markup held only the piece on
//  its own page, but the overflow went on showing in the next page's body
//  (simulator, 7 November). The stroke was cut while PaperKit was still
//  drawing it for the first time, and a unit test's window doesn't draw it
//  the way the app's does. What changed on screen is found by comparing
//  screenshots before and after.
//

import XCTest

final class InkBorderCutUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A screenshot's pixels, RGBA, at the screen's scale.
    private struct Pixels {
        let data: [UInt8]
        let width: Int
        let height: Int
        let scale: CGFloat

        init(_ screenshot: XCUIScreenshot) {
            let image = screenshot.image
            let cg = image.cgImage!
            width = cg.width
            height = cg.height
            scale = CGFloat(cg.width) / image.size.width
            var data = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            self.data = data
        }

        /// Pixels differing from `other` within `area`, in points.
        func changed(from other: Pixels, in area: CGRect) -> Int {
            let x0 = Int(area.minX * scale), x1 = min(Int(area.maxX * scale), width)
            let y0 = Int(area.minY * scale), y1 = min(Int(area.maxY * scale), height)
            var count = 0
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let i = (y * width + x) * 4
                    if (0..<3).contains(where: { abs(Int(data[i + $0]) - Int(other.data[i + $0])) > 60 }) {
                        count += 1
                    }
                }
            }
            return count
        }
    }

    private func point(_ app: XCUIApplication, _ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    /// The seeded note, scrolled so the border between pages 2 and 3 is on
    /// screen, in draw mode.
    @MainActor
    private func open(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-debug-note", "pages", "-debug-mode", mode, "-debug-page", "3",
                               "-inkPalette", "", "-highlighterPalette", "",
                               "-penSettings", "", "-highlighterSettings", "", "-eraser", ""]
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15), "the note never opened")
        Thread.sleep(forTimeInterval: 1.5)
        point(app, 1000, 300).press(forDuration: 0.3, thenDragTo: point(app, 1000, 700), withVelocity: 250, thenHoldForDuration: 1.0)
        Thread.sleep(forTimeInterval: 1.5)
        let toggle = app.buttons["modeToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) != "Draw mode" { toggle.tap() }
        XCTAssertTrue(app.buttons["Pen"].waitForExistence(timeout: 5), "no ink tools")
        Thread.sleep(forTimeInterval: 1)
        return app
    }

    @MainActor
    func testStrokeAcrossABorderStopsAtItOnScreen() throws {
        for mode in ["compressed", "print"] {
            let app = open(mode)
            let before = Pixels(XCUIScreen.main.screenshot())

            // From high on page 2 to low on page 3.
            point(app, 420, 150).press(forDuration: 0.02, thenDragTo: point(app, 460, 1150), withVelocity: 600, thenHoldForDuration: 0)
            Thread.sleep(forTimeInterval: 2)
            let after = Pixels(XCUIScreen.main.screenshot())
            let onPage2 = CGRect(x: 380, y: 170, width: 120, height: 200)
            let onPage3 = CGRect(x: 380, y: 750, width: 120, height: 350)
            XCTAssertGreaterThan(after.changed(from: before, in: onPage2), 50, "in \(mode): no stroke was drawn")
            XCTAssertEqual(after.changed(from: before, in: onPage3), 0, "in \(mode): the stroke still shows in page 3's body")

            app.buttons["Undo"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 1.5)
            let undone = Pixels(XCUIScreen.main.screenshot())
            XCTAssertEqual(undone.changed(from: before, in: onPage2), 0, "in \(mode): one undo left the stroke")
            app.terminate()
        }
    }
}
