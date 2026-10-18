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

#if canImport(UIKit)
import SwiftUI
import UIKit

/// The options rows on a phone narrower than they are long.
@Suite("Options rows on a narrow phone", .serialized)
@MainActor
struct NarrowOptionsRowTests {

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? [] + view.subviews.flatMap(scrollViews(in:))
    }

    /// The pen's row, in ink mode at the bottom, given `limit` along the bar.
    private func penRow(limit: CGFloat?) -> UIScrollView? {
        let editor = NoteEditor()
        editor.setMode(.ink)
        editor.inkTool.kind = .pen
        let host = UIHostingController(rootView: Hotbar(
            editor: editor,
            dock: .constant(.bottom),
            onDrop: { _ in },
            maxRowLength: limit
        ))
        let window = HotbarLayoutTests.makeWindow()
        window.rootViewController = host
        window.makeKeyAndVisible()
        let end = Date(timeIntervalSinceNow: 0.8)
        repeat {
            window.layoutIfNeeded()
            CATransaction.flush()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        } while Date() < end
        // The bar's own tools are shorter than the pen's seven colours, Add
        // Colour and three widths, about 391pt.
        return scrollViews(in: host.view).first { $0.contentSize.width > 350 }
    }

    @Test("Given less room than it needs, the pen's row is that long and scrolls")
    func rowScrollsWhenLonger() throws {
        let row = try #require(penRow(limit: 300))
        #expect(row.bounds.width <= 300.5)
        #expect(row.contentSize.width > row.bounds.width + 50)
    }

    @Test("Given room, or no limit, the row is its own length and doesn't scroll")
    func rowHugsWhenItFits() throws {
        for limit: CGFloat? in [nil, 600] {
            let row = try #require(penRow(limit: limit))
            #expect(abs(row.bounds.width - row.contentSize.width) < 1, "limit \(String(describing: limit))")
        }
    }
}
#endif

/// The hotbar and a Duo's fold.
@Suite("The Duo's fold")
struct FoldAvoidanceTests {

    /// The Duo unfolded and held sideways, as the 27.1 simulator reports it:
    /// a 951 by 669pt window with the fold a 40pt band down the middle.
    private let area = CGSize(width: 951, height: 669)
    private let downTheMiddle = CGRect(x: 455.5, y: 0, width: 40, height: 669)
    private let acrossTheMiddle = CGRect(x: 0, y: 314.5, width: 951, height: 40)
    private let band = Hotbar.footprint

    @Test("A fold down the screen moves a bottom bar to the left, and leaves a side bar alone")
    func foldDownTheScreen() {
        #expect(FoldAvoidance.dock(.bottom, avoiding: [downTheMiddle], in: area, band: band) == .left)
        #expect(FoldAvoidance.dock(.left, avoiding: [downTheMiddle], in: area, band: band) == .left)
        #expect(FoldAvoidance.dock(.right, avoiding: [downTheMiddle], in: area, band: band) == .right)
    }

    @Test("A fold across the screen moves a side bar to the bottom, and leaves a bottom bar alone")
    func foldAcrossTheScreen() {
        #expect(FoldAvoidance.dock(.left, avoiding: [acrossTheMiddle], in: area, band: band) == .bottom)
        #expect(FoldAvoidance.dock(.right, avoiding: [acrossTheMiddle], in: area, band: band) == .bottom)
        #expect(FoldAvoidance.dock(.bottom, avoiding: [acrossTheMiddle], in: area, band: band) == .bottom)
    }

    @Test("No fold, or one the bar's band doesn't reach, changes nothing", arguments: HotbarDock.allCases)
    func nothingInTheWay(dock: HotbarDock) {
        #expect(FoldAvoidance.dock(dock, avoiding: [], in: area, band: band) == dock)
        // A fold down the top half only, clear of the bottom band.
        let short = CGRect(x: 455.5, y: 0, width: 40, height: 300)
        #expect(FoldAvoidance.dock(dock, avoiding: [short], in: area, band: band) == dock)
        // Before the area has been measured.
        #expect(FoldAvoidance.dock(dock, avoiding: [downTheMiddle, acrossTheMiddle], in: .zero, band: band) == dock)
    }
}
