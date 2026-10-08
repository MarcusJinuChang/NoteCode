//
//  KeyboardInsetTests.swift
//  NoteCodeTests
//

import CoreGraphics
import Testing
@testable import NoteCode

/// The keyboard covers the page without resizing it, so the text view insets
/// itself by what's covered. This is the arithmetic.
@Suite("Keyboard inset")
struct KeyboardInsetTests {

    private let screenWidth: CGFloat = 1032
    /// A page area from just under the header to near the screen's bottom.
    private let area = CGRect(x: 76, y: 100, width: 880, height: 1200)

    private func inset(
        keyboard: CGRect,
        area: CGRect? = nil,
        scale: CGFloat = 1,
        clearance: CGFloat = 0
    ) -> CGFloat {
        CanvasGeometry.keyboardInset(
            keyboard: keyboard,
            area: area ?? self.area,
            screenWidth: screenWidth,
            displayScale: scale,
            clearance: clearance
        )
    }

    @Test("A keyboard that isn't up covers nothing")
    func hidden() {
        // Dismissed, its end frame is below the screen.
        #expect(inset(keyboard: CGRect(x: 0, y: 1376, width: screenWidth, height: 400)) == 0)
    }

    @Test("A docked keyboard covers from its top edge to the bottom of the page")
    func docked() {
        // Keyboard top at 1000, page bottom at 1300.
        #expect(inset(keyboard: CGRect(x: 0, y: 1000, width: screenWidth, height: 376)) == 300)
    }

    @Test("The inset is in the text view's points, which the display scale shrinks")
    func scaled() {
        #expect(inset(keyboard: CGRect(x: 0, y: 1000, width: screenWidth, height: 376), scale: 1.25) == 240)
        #expect(inset(keyboard: CGRect(x: 0, y: 1000, width: screenWidth, height: 376), scale: 0.5) == 600)
    }

    @Test("A floating keyboard says nothing about the page's bottom")
    func floating() {
        #expect(inset(keyboard: CGRect(x: 300, y: 900, width: 320, height: 260)) == 0)
    }

    @Test("A keyboard that ends below the page covers none of it")
    func belowPage() {
        let short = CGRect(x: 76, y: 100, width: 880, height: 600)
        #expect(inset(keyboard: CGRect(x: 0, y: 800, width: screenWidth, height: 376), area: short) == 0)
    }

    @Test("A keyboard taller than the page can't inset more than the page")
    func clamped() {
        #expect(inset(keyboard: CGRect(x: 0, y: 0, width: screenWidth, height: 1376)) == area.height)
    }

    @Test("Clearance raises the line the text keeps clear, for a hotbar riding above the keyboard")
    func clearance() {
        #expect(inset(keyboard: CGRect(x: 0, y: 1000, width: screenWidth, height: 376), clearance: 80) == 380)
    }

    @Test("Clearance doesn't inset a page the keyboard isn't up over")
    func clearanceWithoutKeyboard() {
        #expect(inset(keyboard: CGRect(x: 0, y: 1376, width: screenWidth, height: 0), clearance: 80) == 0)
    }

    @Test("A zero display scale insets nothing rather than dividing by it")
    func zeroScale() {
        #expect(inset(keyboard: CGRect(x: 0, y: 1000, width: screenWidth, height: 376), scale: 0) == 0)
    }
}
