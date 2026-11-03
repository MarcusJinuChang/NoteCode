//
//  TextBarLayoutTests.swift
//  NoteCodeTests
//
//  The order of the text options row, how long it may be beside the bar, and
//  how much of the page the bars are allowed to cover above the keyboard
//  (31 Oct review: hotbar layout).
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Text bar layout")
struct TextBarLayoutTests {

    /// Size at the top or left, then the inline styles, then colour.
    @Test func proseRowOrder() {
        #expect(TextRowSection.prose == [.size, .style, .colour, .more])
    }

    /// The text row is no longer than the bar, however much room the page has.
    @Test func textRowIsNoLongerThanTheBar() {
        #expect(RowLimit.length(pageLimit: 1170, barLength: 480, capsToBar: true) == 480)
        #expect(RowLimit.length(pageLimit: 366, barLength: 480, capsToBar: true) == 366)
        #expect(RowLimit.length(pageLimit: nil, barLength: 480, capsToBar: true) == 480)
    }

    /// The pen's row keeps the page's length, and a bar not yet measured
    /// doesn't squash the text row to nothing.
    @Test func inkRowAndUnmeasuredBarKeepThePageLimit() {
        #expect(RowLimit.length(pageLimit: 1170, barLength: 480, capsToBar: false) == 1170)
        #expect(RowLimit.length(pageLimit: 1170, barLength: 0, capsToBar: true) == 1170)
    }

    /// Room is kept for the lines after the caret's, with and without the
    /// row, and only for a bar at the bottom.
    @Test func clearanceKeepsLinesBelowTheCaretClear() {
        let bar = Hotbar.keyboardClearance(dock: .bottom, showsTextRow: false)
        let row = Hotbar.keyboardClearance(dock: .bottom, showsTextRow: true)
        #expect(bar >= Hotbar.barFootprint + Hotbar.linesBelowCaret)
        #expect(row == bar + Hotbar.optionsGap + OptionsRowStyle.thickness + OptionsRowStyle.reachAmount)
        #expect(Hotbar.keyboardClearance(dock: .left, showsTextRow: true) == 0)
        #expect(Hotbar.keyboardClearance(dock: .right, showsTextRow: true) == 0)
    }

    /// On an iPad the row is out whenever text can be formatted; on a phone
    /// only once Format asks for it.
    @Test func phoneTextRowWaitsToBeAskedFor() {
        func shows(compact: Bool, wanted: Bool, text: Bool = true, locked: Bool = false, covered: Bool = false) -> Bool {
            Hotbar.showsTextRow(isText: text, isLocked: locked, isCovered: covered, isCompact: compact, wanted: wanted)
        }
        #expect(shows(compact: false, wanted: false))
        #expect(!shows(compact: true, wanted: false))
        #expect(shows(compact: true, wanted: true))
        #expect(!shows(compact: true, wanted: true, text: false))
        #expect(!shows(compact: true, wanted: true, locked: true))
        #expect(!shows(compact: false, wanted: true, covered: true))
    }

    /// A track fades only the ends that have controls past them.
    @Test func edgesFadeOnlyWhereThereIsMore() {
        #expect(HiddenEdges.of(offset: 0, visible: 300, length: 300) == HiddenEdges())
        #expect(HiddenEdges.of(offset: 0, visible: 300, length: 391) == HiddenEdges(start: false, end: true))
        #expect(HiddenEdges.of(offset: 40, visible: 300, length: 391) == HiddenEdges(start: true, end: true))
        #expect(HiddenEdges.of(offset: 91, visible: 300, length: 391) == HiddenEdges(start: true, end: false))
        #expect(HiddenEdges.of(offset: 0.5, visible: 300, length: 300.5) == HiddenEdges())
    }
}

#endif
