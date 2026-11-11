//
//  PageViewTests+Ink.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

extension PageViewTests {

    @Suite("Ink across modes, drawing and saving")
    @MainActor
    struct Ink: PageViewSuite {

        // MARK: Ink across modes

        @Test("Ink is shown on the same place on its page in every mode", arguments: PageViewMode.allCases)
        func inkShownOnItsPage(mode: PageViewMode) {
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: mode))
            let printedAt = Self.printPortrait.bodyTop(ofPage: 2) + 50

            harness.setInk(PKDrawing(strokes: [Self.stroke(at: printedAt)]))

            #expect(abs((harness.shownInkY ?? 0) - (PageLayout(mode: mode).bodyTop(ofPage: 2) + 50)) < 0.5)
        }

        @Test("Ink follows its page as the mode changes")
        func inkFollowsModeChanges() {
            let harness = PageHarness(text: Self.severalPages)
            harness.setInk(PKDrawing(strokes: [Self.stroke(at: Self.printPortrait.bodyTop(ofPage: 2) + 50)]))

            for mode in [PageViewMode.print, .compressed, .seamless, .print] {
                harness.switchTo(PageLayout(mode: mode))
                #expect(abs((harness.shownInkY ?? 0) - (PageLayout(mode: mode).bodyTop(ofPage: 2) + 50)) < 0.5)
            }
        }

        @Test("Ink in a sheet's margin is back in the margin after a trip through seamless")
        func marginInkSurvivesRoundTrip() {
            let print = Self.printPortrait
            let harness = PageHarness(text: Self.severalPages, layout: print)
            let inMargin = print.bodyTop(ofPage: 2) + print.bodyHeight + 30
            harness.setInk(PKDrawing(strokes: [Self.stroke(at: inMargin)]))

            harness.switchTo(PageLayout(mode: .seamless))
            harness.switchTo(print)

            // Converting what was on screen back from seamless would put this on
            // page 3, 168 points lower. Kept in print coordinates, it can't move.
            #expect(abs((harness.shownInkY ?? 0) - inMargin) < 0.5)
        }

        @Test("Ink keeps its printed position when the orientation changes")
        func inkKeptOnOrientationChange() {
            let harness = PageHarness(text: Self.severalPages)
            harness.setInk(PKDrawing(strokes: [Self.stroke(at: 1500)]))
            let before = harness.page.ink.subelements.strokes.first?.renderBounds

            harness.switchTo(PageLayout(orientation: .landscape))

            #expect(harness.page.ink.subelements.strokes.first?.renderBounds == before)
        }

        // MARK: Ink drawn on the canvas

        @Test("A stroke drawn in any mode is stored where it prints", arguments: PageViewMode.allCases)
        func drawnStrokeIsStoredInPrintCoordinates(mode: PageViewMode) {
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: mode))
            let drawnAt = PageLayout(mode: mode).bodyTop(ofPage: 2) + 50

            Self.draw([Self.stroke(at: drawnAt)], on: harness)

            let stored = harness.page.ink.subelements.strokes.first?.renderBounds.midY
            #expect(abs((stored ?? 0) - (Self.printPortrait.bodyTop(ofPage: 2) + 50)) < 0.5)
        }

        @Test("A stroke drawn in seamless is on the same words in every other mode")
        func drawnStrokeFollowsTheModes() {
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: .seamless))
            let drawnAt = PageLayout(mode: .seamless).bodyTop(ofPage: 2) + 50

            Self.draw([Self.stroke(at: drawnAt)], on: harness)

            for mode in [PageViewMode.print, .compressed, .seamless] {
                harness.switchTo(PageLayout(mode: mode))
                #expect(abs((harness.shownInkY ?? 0) - (PageLayout(mode: mode).bodyTop(ofPage: 2) + 50)) < 0.5)
            }
        }

        // MARK: Saving ink

        @Test("Drawing hands the ink over to be saved, in print coordinates")
        func drawingReportsInk() async {
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: .seamless))
            var reported: [PaperMarkup] = []
            harness.page.onInkChanged = { reported.append($0) }

            Self.draw([Self.stroke(at: PageLayout(mode: .seamless).bodyTop(ofPage: 2) + 50)], on: harness)

            #expect(await waitFor { !reported.isEmpty })
            #expect(reported.count == 1)
            let saved = reported.last?.subelements.strokes.first?.renderBounds.midY
            #expect(abs((saved ?? 0) - (Self.printPortrait.bodyTop(ofPage: 2) + 50)) < 0.5)
        }

        /// Every operation on PaperKit's sets costs time in proportion to the
        /// ink, so working out what a stroke changed on the main thread made
        /// writing in a long note stutter.
        @Test("A stroke is taken into the ink off the main thread")
        func captureIsOffTheMainThread() async {
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: .seamless))
            var reported = 0
            harness.page.onInkChanged = { _ in reported += 1 }

            Self.draw([Self.stroke(at: 400)], on: harness)
            // Nothing has turned the run loop since the stroke landed.
            #expect(reported == 0)

            #expect(await waitFor { reported == 1 })
        }

        @Test("A mode switch takes in strokes still on their way, where they were drawn", arguments: [PageViewMode.print, .compressed])
        func switchTakesInPendingStrokes(to mode: PageViewMode) async {
            let seamless = PageLayout(mode: .seamless)
            let harness = PageHarness(text: Self.severalPages, layout: seamless)
            let drawnAt = seamless.bodyTop(ofPage: 2) + 50
            var reported = 0
            harness.page.onInkChanged = { _ in reported += 1 }

            Self.draw([Self.stroke(at: drawnAt)], on: harness)
            harness.switchTo(PageLayout(mode: mode))
            // Let the capture that was running finish; its result is stale.
            await harness.page.inkSettled()

            let stored = harness.page.ink.subelements.strokes
            #expect(stored.count == 1)
            #expect(abs((stored.first?.renderBounds.midY ?? 0) - (Self.printPortrait.bodyTop(ofPage: 2) + 50)) < 0.5)
            #expect(abs((harness.shownInkY ?? 0) - (PageLayout(mode: mode).bodyTop(ofPage: 2) + 50)) < 0.5)
            #expect(reported == 1)
        }

        @Test("Leaving a note takes in strokes still on their way, for the save")
        func commitTakesInPendingStrokes() {
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: .seamless))
            var reported: [PaperMarkup] = []
            harness.page.onInkChanged = { reported.append($0) }

            Self.draw([Self.stroke(at: 400), Self.stroke(at: 600)], on: harness)
            harness.page.commitInk()

            #expect(reported.count == 1)
            #expect(reported.last?.subelements.strokes.count == 2)
        }

        /// A save bumps the note to the top of the list, so one that only
        /// looked at ink would reorder the list for opening a note.
        @Test("Showing ink, on opening or for a mode switch, hands nothing over")
        func showingInkReportsNothing() {
            let harness = PageHarness(text: Self.severalPages)
            var reports = 0
            harness.page.onInkChanged = { _ in reports += 1 }

            harness.setInk(PKDrawing(strokes: [Self.stroke(at: 1500)]))
            for mode in [PageViewMode.print, .compressed, .seamless] {
                harness.switchTo(PageLayout(mode: mode))
            }
            // PaperKit also calls its delegate when nothing the reader did
            // changed anything.
            harness.page.canvas.onMarkupChanged?()

            #expect(reports == 0)
        }

        /// Opened the way the app opens a note: a fresh page, given the note's
        /// layout, then its stored ink. Checked against the words under the
        /// stroke when it was drawn, not against page geometry.
        @Test(
            "Saved ink reopens on the same words",
            arguments: PageOrientation.allCases, PageViewMode.allCases
        )
        func savedInkReopensOnItsWords(orientation: PageOrientation, mode: PageViewMode) async throws {
            let drawnIn = PageLayout(orientation: orientation, mode: .seamless)
            let drawn = PageHarness(text: Self.severalPages, layout: drawnIn)
            let drawnAt = drawnIn.bodyTop(ofPage: 2) + 40
            let words = try #require(drawn.lines.first { $0.frame.minY <= drawnAt && drawnAt < $0.frame.maxY }?.range)
            Self.draw([Self.stroke(at: drawnAt)], on: drawn)

            let data = try await DrawingCodec.encode(drawn.page.ink)
            guard case .ink(let stored) = DrawingCodec.decode(data) else {
                Issue.record("saved ink didn't read back")
                return
            }

            let reopened = PageHarness(text: Self.severalPages, layout: PageLayout(orientation: orientation, mode: mode))
            reopened.page.setInk(stored)
            reopened.layOut()

            let line = try #require(reopened.lines.first { $0.range == words }?.frame)
            let shown = try #require(reopened.shownInkY)
            #expect(line.minY <= shown && shown < line.maxY, "stroke at \(shown), its words at \(line.minY)–\(line.maxY)")
        }
    }
}

#endif
