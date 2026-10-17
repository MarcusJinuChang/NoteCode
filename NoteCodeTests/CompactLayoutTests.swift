//
//  CompactLayoutTests.swift
//  NoteCodeTests
//

import CoreGraphics
import Testing
@testable import NoteCode

/// An iPhone and a folded Duo (roadmap step 11): the page fitted by its text
/// column, and a stack of Home, the list and a note in place of the split view.
@Suite("Compact width")
struct CompactLayoutTests {

    private let portrait = PageLayout(orientation: .portrait)
    private let landscape = PageLayout(orientation: .landscape)

    private func column(_ layout: PageLayout) -> CGFloat {
        CanvasGeometry.columnWidth(textWidth: layout.textWidth)
    }

    // MARK: Fitting the column

    @Test("A phone in portrait fits the text column and the panels' reach, not the page")
    func phoneFitsTheColumn() {
        // iPhone 17: 402pt.
        let scale = CanvasGeometry.fitScale(areaWidth: 402, pageWidth: portrait.pageSize.width, columnWidth: column(portrait))
        // 672 of text and 14 either side for the panels.
        #expect(column(portrait) == 700)
        #expect(scale == 402.0 / 700)
        #expect(scale > CanvasGeometry.fitScale(areaWidth: 402, pageWidth: portrait.pageSize.width))
    }

    @Test("A phone on its side is wide enough for the page, and fits the page")
    func sidewaysFitsThePage() {
        // iPhone 17 in landscape: 874pt.
        let page = CanvasGeometry.fitScale(areaWidth: 874, pageWidth: portrait.pageSize.width)
        #expect(page >= 1)
        #expect(CanvasGeometry.fitScale(areaWidth: 874, pageWidth: portrait.pageSize.width, columnWidth: column(portrait)) == page)
    }

    @Test("Without a column, which only a compact width offers, nothing changes")
    func regularIsUnchanged() {
        for width: CGFloat in [402, 628, 744, 1032] {
            for layout in [portrait, landscape] {
                let fitted = CanvasGeometry.fitScale(areaWidth: width, pageWidth: layout.pageSize.width)
                #expect(fitted == min(width / layout.pageSize.width, CanvasGeometry.maximumFitScale))
            }
        }
    }

    @Test("The column fit is drawn larger, and pinch zoom still multiplies it")
    func zoomMultipliesTheColumnFit() {
        let fit = CanvasGeometry.fitScale(areaWidth: 402, pageWidth: portrait.pageSize.width, columnWidth: column(portrait))
        let zoomed = CanvasGeometry.displayScale(areaWidth: 402, pageWidth: portrait.pageSize.width, columnWidth: column(portrait), zoom: 2)
        #expect(zoomed == fit * 2)
    }

    @Test("A page wider than its area is scrolled to show its middle: the margins cut evenly")
    func centred() {
        let scale = 402.0 / 700
        let offset = CanvasGeometry.centredOffset(areaWidth: 402, pageWidth: 816, scale: scale)
        let frame = CanvasGeometry.pageFrame(in: CGSize(width: 402, height: 800), pageWidth: 816, scale: scale)
        // The column's left edge, less the panels' reach, sits at the screen's.
        let columnLeft = frame.minX + (PageLayout.margin - CodeBlockRoom.outset) * scale - offset
        #expect(abs(columnLeft) < 0.001)
        #expect(CanvasGeometry.centredOffset(areaWidth: 1032, pageWidth: 816, scale: 1) == 0)
    }

    // MARK: The stack

    @Test("Opening a note pushes it on what is showing; closing it goes back there")
    func noteFollowsSelection() {
        #expect(CompactScreen.path([], noteOpen: true) == [.note])
        #expect(CompactScreen.path([.list], noteOpen: true) == [.list, .note])
        // Another note opened over a note replaces it rather than stacking.
        #expect(CompactScreen.path([.list, .note], noteOpen: true) == [.list, .note])
        #expect(CompactScreen.path([.list, .note], noteOpen: false) == [.list])
        #expect(CompactScreen.path([.note], noteOpen: false) == [])
        #expect(CompactScreen.path([.list], noteOpen: false) == [.list])
    }

    @Test("Folding and unfolding keep what was showing", arguments: [
        (false, false), (true, false), (false, true), (true, true),
    ])
    func foldingKeepsThePlace(listShowing: Bool, noteOpen: Bool) {
        let path = CompactScreen.path(listShowing: listShowing, noteOpen: noteOpen)
        #expect(path.contains(.note) == noteOpen)
        #expect(path.last != .note || noteOpen)
        // Unfolded again, the list is over the page only if it was on top.
        #expect(CompactScreen.listShowing(in: path) == (listShowing && !noteOpen))
    }
}
