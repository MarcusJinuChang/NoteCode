//
//  PageViewTests+Window.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

extension PageViewTests {

    @Suite("The note window")
    @MainActor
    struct Window: PageViewSuite {

        // MARK: The note window (W2)

        @Test("The note never scrolls above its top, whatever sets the offset")
        func topClamp() {
            let harness = PageHarness(text: Self.severalPages)
            let textView = harness.page.textView
            textView.contentOffset.y = 400
            textView.contentOffset.y = -80
            #expect(textView.contentOffset.y == -textView.contentInset.top)
            textView.setContentOffset(CGPoint(x: 0, y: -300), animated: false)
            #expect(textView.contentOffset.y == -textView.contentInset.top)
        }

        @Test("The text view's pan is on the page, which has none of its own")
        func panOwner() {
            let harness = PageHarness(text: Self.severalPages)
            let page = harness.page
            let pan = page.textView.panGestureRecognizer
            #expect(pan.view === page)
            #expect(page.isScrollEnabled == false)
            // A mode change re-applies the rule to the pan, which stays on the page.
            page.touchWillLand(on: page.textView)
            #expect(pan.view === page)
        }

        @Test("A touch beside the page goes to the text view, so its pan scrolls the note")
        func panStartedBesidePage() {
            let harness = PageHarness(text: Self.severalPages, area: CGSize(width: 1400, height: 1100))
            let page = harness.page
            let beside = CGPoint(x: 2, y: 300)
            #expect(page.textView.frame.minX > beside.x)
            #expect(page.hitTest(beside, with: nil) === page.textView)
            #expect(page.textView.panGestureRecognizer.view === page)
            // The pan covers the whole view, so it can begin where the text view isn't.
            #expect(page.bounds.contains(beside))
        }

        @Test("The indicator runs at the window's edge and tracks the offset")
        func indicatorFrame() throws {
            let area = CGSize(width: 880, height: 1000)
            let top = try #require(PageScrollIndicator.frame(offset: 0, content: 4000, area: area, scale: 1, sideways: 0))
            let bottom = try #require(PageScrollIndicator.frame(offset: 3000, content: 4000, area: area, scale: 1, sideways: 0))
            #expect(top.maxX < area.width)
            #expect(top.maxX > area.width - 10)
            #expect(top.minY == 0)
            #expect(abs(bottom.maxY - area.height) < 0.5)
            #expect(PageScrollIndicator.frame(offset: 0, content: 900, area: area, scale: 1, sideways: 0) == nil)
            // Panned sideways, it stays at the right edge of what is shown.
            let panned = try #require(PageScrollIndicator.frame(offset: 0, content: 4000, area: area, scale: 1, sideways: 120))
            #expect(panned.minX == top.minX + 120)
        }

        @Test("The text view's own indicator is off, so only the one at the window's edge shows")
        func noIndicatorInsideThePage() {
            let page = PageHarness(text: Self.severalPages).page
            #expect(page.showsVerticalScrollIndicator == false)
            #expect(page.textView.showsVerticalScrollIndicator == false)
        }

        @Test("A sideways fling decays and covers a finite distance")
        func flingDecay() {
            let a = SidewaysFling.decayed(1000, over: 0.1)
            let b = SidewaysFling.decayed(1000, over: 5)
            #expect(a.velocity < 1000 && a.velocity > 0)
            #expect(a.distance > 0 && a.distance < 100)
            #expect(b.velocity < SidewaysFling.minimumSpeed)
            #expect(b.distance > a.distance)
            #expect(SidewaysFling.decayed(-1000, over: 0.1).distance < 0)
        }

        @Test("The page's edge follows the text view and goes in print layout")
        func pageEdge() {
            let harness = PageHarness(text: Self.severalPages)
            let page = harness.page
            func edge() -> UIView? { page.subviews.first { $0 is PageEdgeView } }
            let view = edge()
            #expect(view != nil)
            #expect(view?.frame == page.textView.frame)
            #expect(view?.isHidden == false)
            harness.switchTo(PageLayout(orientation: page.pageLayout.orientation, mode: .print))
            #expect(edge()?.isHidden == true)
        }
    }
}

#endif
