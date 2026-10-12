//
//  InkWidthStepTests.swift
//  NoteCodeTests
//
//  [ and ]: one width thinner or thicker.
//

import Testing
@testable import NoteCode

@Suite("Stepping an ink tool's width")
struct InkWidthStepTests {

    @Test("The pen steps through fine, medium and bold, and stops at the ends")
    func penSteps() {
        var state = InkToolState()
        state.kind = .pen
        #expect(state.pen.width == .medium)

        state.stepWidth(by: 1)
        #expect(state.pen.width == .bold)
        state.stepWidth(by: 1)
        #expect(state.pen.width == .bold)

        state.stepWidth(by: -1)
        state.stepWidth(by: -1)
        #expect(state.pen.width == .fine)
        state.stepWidth(by: -1)
        #expect(state.pen.width == .fine)
    }

    @Test("The highlighter steps its own width and leaves the pen's")
    func highlighterIsSeparate() {
        var state = InkToolState()
        state.kind = .highlighter
        state.stepWidth(by: -1)
        #expect(state.highlighter.width == .fine)
        #expect(state.pen.width == .medium)
    }

    @Test("The eraser steps through its sizes")
    func eraserSteps() {
        var state = InkToolState()
        state.kind = .eraser
        #expect(state.eraser.size == .small)

        state.stepWidth(by: 1)
        #expect(state.eraser.size == .medium)
        state.stepWidth(by: 1)
        #expect(state.eraser.size == .large)
        state.stepWidth(by: 1)
        #expect(state.eraser.size == .large)
        state.stepWidth(by: -1)
        #expect(state.eraser.size == .medium)
    }

    @Test("From a custom eraser size a key goes to the nearest preset that way")
    func customEraser() {
        var state = InkToolState()
        state.kind = .eraser
        state.eraser.size = .custom
        state.eraser.customWidth = 40

        state.stepWidth(by: 1)
        #expect(state.eraser.size == .large)

        state.eraser.size = .custom
        state.stepWidth(by: -1)
        #expect(state.eraser.size == .medium)

        // Wider than every preset: thicker has nowhere to go but the largest.
        state.eraser.size = .custom
        state.eraser.customWidth = 70
        state.stepWidth(by: 1)
        #expect(state.eraser.size == .large)
    }

    @Test("The lasso has no width to step")
    func lasso() {
        var state = InkToolState()
        state.kind = .lasso
        let before = state
        state.stepWidth(by: 1)
        #expect(state == before)
    }
}
