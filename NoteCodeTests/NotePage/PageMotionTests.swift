//
//  PageMotionTests.swift
//  NoteCodeTests
//
//  The page moves with the hotbar when the bar docks at another edge,
//  rather than jumping to its new area while the bar slides.
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("The page follows the hotbar", .tags(.layout))
@MainActor
struct PageMotionTests {

    /// A page in a container, as SwiftUI hosts it: a bar docked at a side
    /// moves the container and narrows the page.
    @MainActor
    final class Fixture {
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 1032, height: 1270))
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1032, height: 1270))
        let page: PageView

        init() {
            let textView = DocumentTextView.makeConfiguredTextView()
            textView.text = (0..<40).map { "Line \($0) of a note long enough to fill the page." }.joined(separator: "\n")
            page = PageView(textView: textView)
            page.frame = container.bounds
            container.addSubview(page)
            window.addSubview(container)
            window.makeKeyAndVisible()
            layOut()
        }

        func layOut() {
            for _ in 0..<3 {
                page.setNeedsLayout()
                page.layoutIfNeeded()
                page.textView.setNeedsLayout()
                page.textView.layoutIfNeeded()
            }
        }

        /// What SwiftUI does when the bar docks at the left: tells the page,
        /// then lays the narrower area out further right.
        func dockLeft(animation: Animation?) {
            page.areaWillChange(to: UIEdgeInsets(top: 0, left: 116, bottom: 0, right: 0), animation: animation)
            container.frame = CGRect(x: 116, y: 0, width: 916, height: 1270)
            page.frame = container.bounds
            page.layoutIfNeeded()
        }

        /// The page stops clipping only while it slides to its new area.
        /// (A SwiftUI animation run by UIKit leaves no Core Animation keys
        /// on the layer to look for.)
        var isMoving: Bool {
            !page.clipsToBounds
        }

        var pageOnScreen: CGRect {
            page.textView.convert(page.textView.bounds, to: window)
        }
    }

    @Test("Docking at a side animates the page to where the new area puts it")
    func animates() {
        let fixture = Fixture()
        let still = Fixture()
        fixture.dockLeft(animation: .linear(duration: 10))
        still.dockLeft(animation: nil)

        #expect(fixture.isMoving)
        // Where it is going is where it would have gone at once.
        #expect(fixture.page.displayScale == still.page.displayScale)
        #expect(fixture.page.textView.center == still.page.textView.center)
        #expect(fixture.page.textView.bounds.size == still.page.textView.bounds.size)
    }

    @Test("Leaving a side, the page's edge moves with the page rather than at once")
    func edgeMovesWithThePage() {
        let fixture = Fixture()
        fixture.dockLeft(animation: nil)
        let edge = fixture.page.pageEdge
        let before = edge.convert(edge.bounds, to: fixture.window)

        // Every place the edge is put while the bar goes back to the bottom.
        // An animation set by UIKit leaves the model at its end, so the
        // start can only be seen as it is set.
        var placed: [CGRect] = []
        let record = { placed.append(edge.convert(edge.bounds, to: fixture.window)) }
        let watchers = [
            edge.layer.observe(\.bounds) { _, _ in MainActor.assumeIsolated { record() } },
            edge.layer.observe(\.position) { _, _ in MainActor.assumeIsolated { record() } },
        ]
        fixture.page.areaWillChange(to: .zero, animation: .linear(duration: 10))
        fixture.container.frame = fixture.window.bounds
        fixture.page.frame = fixture.container.bounds
        fixture.page.layoutIfNeeded()
        watchers.forEach { $0.invalidate() }

        #expect(fixture.isMoving)
        // The page colour behind the text was put at the page's full new
        // width at once, while the text view slid there: in seamless mode
        // the page snapped wide on leaving a side (device pass, 7 Nov).
        #expect(placed.contains(before), "the edge never started where the page was")
        #expect(edge.frame == fixture.page.textView.frame, "and it ends with the page")
    }

    @Test("With no animation, the page goes there at once")
    func noAnimation() {
        let fixture = Fixture()
        let before = fixture.pageOnScreen
        fixture.dockLeft(animation: nil)

        #expect(!fixture.isMoving)
        #expect(fixture.pageOnScreen != before)
    }

    @Test("An animated update that leaves the area alone moves nothing")
    func sameArea() {
        let fixture = Fixture()
        fixture.page.areaWillChange(to: .zero, animation: .linear(duration: 10))
        fixture.page.setNeedsLayout()
        fixture.page.layoutIfNeeded()

        #expect(!fixture.isMoving)
    }
}

#endif
