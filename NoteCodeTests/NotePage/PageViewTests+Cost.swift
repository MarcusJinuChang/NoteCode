//
//  PageViewTests+Cost.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

extension PageViewTests {

    @Suite("Cost")
    @MainActor
    struct Cost: PageViewSuite {

        // MARK: Cost

        /// Page breaks are exclusion paths, and once any exist TextKit 2 lays out
        /// everything below an edit. Measured on an iPad Pro 13-inch simulator on
        /// 12 September 2026: a 250-line note went from 5.5ms a keystroke near its
        /// top to 34ms. Loose on purpose, like StylingPerformanceTests — this is
        /// here to catch the cost doubling, not to police noise.
        @Test("Typing near the top of a paged note stays within budget")
        func typingCost() {
            let harness = PageHarness(text: StylingPerformanceTests.document(lines: 250))
            let textView = harness.page.textView

            var times: [TimeInterval] = []
            for index in 0..<9 {
                let position = textView.position(from: textView.beginningOfDocument, offset: 120 + index)!
                let start = Date()
                textView.replace(textView.textRange(from: position, to: position)!, withText: "z")
                textView.layoutIfNeeded()
                times.append(Date().timeIntervalSince(start))
            }

            let median = times.sorted()[4]
            #expect(median < 0.1, "keystroke near the top took \(median)s")
        }

        /// F5. The median of nine one-character edits near the top of a note, as
        /// `typingCost` takes it.
        private func keystrokeMedian(in textView: UITextView) -> TimeInterval {
            var times: [TimeInterval] = []
            for index in 0..<9 {
                let position = textView.position(from: textView.beginningOfDocument, offset: 120 + index)!
                let start = Date()
                textView.replace(textView.textRange(from: position, to: position)!, withText: "z")
                textView.layoutIfNeeded()
                times.append(Date().timeIntervalSince(start))
            }
            return times.sorted()[4]
        }

        /// The same keystroke on a 40-page note. With every page break below the
        /// edit an exclusion path it was 92-100ms (simulator, 6 Nov), against
        /// 15-18ms on 250 lines: the cost grew with the note. With the breaks as
        /// pushed paragraphs (F5) it is about 4ms, and no longer grows with it.
        @Test("Typing near the top of a 40-page note stays within budget", .tags(.perf))
        func typingCostLongNote() {
            let harness = PageHarness(text: StylingPerformanceTests.document(lines: 1500))
            #expect(harness.page.pageCount >= 40)

            let median = keystrokeMedian(in: harness.page.textView)
            reportPerf("PageViewTests/typingCostLongNote", seconds: median)
            #expect(median < 0.03, "keystroke near the top of a 40-page note took \(median)s")
        }

        /// F5's finding, kept as the guard: the cost was the exclusion paths. The
        /// same text in the same configured view costs 1ms a keystroke without
        /// them and about 100ms with them, because TextKit 2 lays out everything
        /// below an edit once line positions depend on where they fall. Page breaks
        /// are now paragraphs pushed down, so the paged note has none and costs
        /// what the plain one does. `PageView` puts a note's paths back only for a
        /// paragraph taller than a page, so this uses a view of its own for them.
        @Test("A 40-page note has no exclusion paths, and costs a keystroke what unpaged text does", .tags(.perf))
        func exclusionPathsAreTheCost() {
            let harness = PageHarness(text: StylingPerformanceTests.document(lines: 1500))
            #expect(harness.page.textView.textContainer.exclusionPaths.isEmpty)
            let layout = harness.page.pageLayout
            let paged = keystrokeMedian(in: harness.page.textView)

            let plain = DocumentTextView.makeConfiguredTextView()
            plain.frame = CGRect(x: 0, y: 0, width: 700, height: 900)
            harness.window.addSubview(plain)
            plain.text = StylingPerformanceTests.document(lines: 1500)
            plain.layoutIfNeeded()
            let without = keystrokeMedian(in: plain)

            // What it was: the same view with a break after every page as a path.
            let bands = layout.exclusionBands(pageCount: 45, containerTop: plain.textContainerInset.top)
            plain.textContainer.exclusionPaths = bands.map { UIBezierPath(rect: $0) }
            plain.layoutIfNeeded()
            let with = keystrokeMedian(in: plain)
            plain.removeFromSuperview()

            reportPerf("PageViewTests/exclusionPathsAreTheCost.paged", seconds: paged)
            reportPerf("PageViewTests/exclusionPathsAreTheCost.without", seconds: without)
            reportPerf("PageViewTests/exclusionPathsAreTheCost.with", seconds: with)
            #expect(with > without * 5, "with \(with)s, without \(without)s")
            #expect(paged < with / 2, "paged \(paged)s, as exclusion paths \(with)s")
        }

        /// A set built an element at a time costs what its `count` does per
        /// element, so opening a note grew with the square of its strokes: 1.5s
        /// at 2,000 strokes, 7s at 5,000, against 141ms now (simulator, 10
        /// October). Loose on purpose, like `typingCost`: this catches the slow
        /// way coming back, not noise.
        @Test("Opening and switching a note of 2,000 strokes stays within budget", .tags(.perf))
        func openingCost() {
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: .seamless))
            let ink = Self.handwriting(2000)

            let opening = Date()
            harness.page.setInk(ink)
            let opened = Date().timeIntervalSince(opening)
            harness.layOut()

            let switching = Date()
            harness.switchTo(PageLayout(mode: .print))
            let switched = Date().timeIntervalSince(switching)

            reportPerf("PageViewTests/openingCost.open", seconds: opened)
            reportPerf("PageViewTests/openingCost.switch", seconds: switched)
            #expect(harness.page.canvas.markup.subelements.strokes.count == 2000)
            #expect(opened < 0.6, "opening took \(opened)s")
            #expect(switched < 0.9, "switching to print layout took \(switched)s")
        }

        /// A stroke cut at a border is drawn again a few times after the pen
        /// lifts (`PageInkPipeline.redrawTimes`), each a lookup, a replacement
        /// and an assignment of the canvas on the main thread.
        @Test("Drawing a cut stroke again in a note of 5,000 strokes stays within budget", .tags(.perf))
        func redrawCost() async throws {
            let layout = PageLayout(mode: .compressed)
            let harness = PageHarness(text: Self.severalPages, layout: layout)
            harness.page.setInk(Self.handwriting(5000))
            harness.layOut()
            var reported = 0
            harness.page.onInkChanged = { _ in reported += 1 }
            let bottom = layout.bodyTop(ofPage: 1) + layout.bodyHeight
            Self.draw([Self.verticalStroke(x: 760, from: bottom - 60, to: layout.bodyTop(ofPage: 2) + 60)], on: harness)
            #expect(await waitFor({ reported == 1 }, seconds: 10))

            var times: [TimeInterval] = []
            for run in 0..<5 {
                let start = Date()
                let drawn = harness.page.inkPipeline.redrawCutPieces(spanning: run.isMultiple(of: 2), on: harness.page)
                times.append(Date().timeIntervalSince(start))
                try #require(drawn == 1, "nothing waited to be drawn again")
            }
            let median = times.sorted()[2]
            reportPerf("PageViewTests/redrawCost", seconds: median)
            #expect(harness.page.canvas.markup.subelements.strokes.count == 5001)
            #expect(median < 0.3, "drawing the piece again took \(median)s")
        }
    }
}

#endif
