//
//  PageViewTests+AddPage.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

extension PageViewTests {

    @Suite("Adding pages")
    @MainActor
    struct AddPage: PageViewSuite {

        // MARK: Add page, and seamless's buffer (roadmap step 6)

        @Test("A note given more pages than its text needs has them", arguments: PageViewMode.allCases)
        func minimumPagesAreKept(mode: PageViewMode) {
            let harness = PageHarness(text: "One line.", layout: PageLayout(mode: mode))
            #expect(harness.page.pageCount == 1)

            harness.page.minimumPageCount = 4
            harness.layOut()

            let layout = PageLayout(mode: mode)
            #expect(harness.page.pageCount == 4)
            #expect(abs(harness.page.textView.contentSize.height - layout.noteHeight(pageCount: 4)) < 0.5)
        }

        @Test("Add Page adds one at the end and tells the note", arguments: PageViewMode.allCases)
        func addPageAddsOne(mode: PageViewMode) {
            let harness = PageHarness(text: "One line.", layout: PageLayout(mode: mode))
            var told: [Int] = []
            harness.page.onMinimumPageCountChanged = { told.append($0) }

            harness.page.addPage()
            harness.layOut()
            #expect(harness.page.pageCount == 2)
            harness.page.addPage()
            harness.layOut()

            #expect(harness.page.pageCount == 3)
            #expect(told == [2, 3])
        }

        @Test("A page added to a note longer than its minimum is one more than it has now")
        func addPageCountsPagesTheTextMade() {
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: .print))
            let before = harness.page.pageCount
            #expect(before > 2)

            harness.page.addPage()
            harness.layOut()

            #expect(harness.page.pageCount == before + 1)
        }

        @Test("Setting the minimum from the note doesn't tell the note again")
        func followingTheNoteIsSilent() {
            let harness = PageHarness(text: "One line.", layout: PageLayout(mode: .print))
            var told = 0
            harness.page.onMinimumPageCountChanged = { _ in told += 1 }

            harness.page.minimumPageCount = 3
            harness.layOut()

            #expect(told == 0)
        }

        @Test("Seamless keeps a blank page below ink that reaches the last page")
        func seamlessBufferFollowsInk() async {
            let seamless = PageLayout(mode: .seamless)
            let harness = PageHarness(text: "One line.", layout: seamless)
            var told: [Int] = []
            harness.page.onMinimumPageCountChanged = { told.append($0) }
            #expect(harness.page.pageCount == 1)

            Self.draw([Self.stroke(at: seamless.bodyTop(ofPage: 0) + 200)], on: harness)
            #expect(await waitFor { told == [2] })
            harness.layOut()
            #expect(harness.page.pageCount == 2)

            // Ink on the new last page makes another, so there is always one below.
            Self.draw([Self.stroke(at: seamless.bodyTop(ofPage: 1) + 200)], on: harness)
            #expect(await waitFor { told == [2, 3] })
        }

        @Test("Ink above the last page adds nothing in seamless")
        func seamlessBufferWaitsForTheLastPage() async {
            let seamless = PageLayout(mode: .seamless)
            let harness = PageHarness(text: "One line.", layout: seamless)
            harness.page.minimumPageCount = 3
            harness.layOut()
            var told = 0
            harness.page.onMinimumPageCountChanged = { _ in told += 1 }

            Self.draw([Self.stroke(at: seamless.bodyTop(ofPage: 0) + 200)], on: harness)
            _ = await waitFor({ false }, seconds: 0.5)

            #expect(told == 0)
            #expect(harness.page.pageCount == 3)
        }

        @Test("Compressed and print layout add no page of their own for ink", arguments: [PageViewMode.compressed, .print])
        func otherModesHaveNoBuffer(mode: PageViewMode) async {
            let layout = PageLayout(mode: mode)
            let harness = PageHarness(text: "One line.", layout: layout)
            var told = 0
            harness.page.onMinimumPageCountChanged = { _ in told += 1 }

            Self.draw([Self.stroke(at: layout.bodyTop(ofPage: 0) + 200)], on: harness)
            _ = await waitFor({ false }, seconds: 0.5)

            #expect(told == 0)
            #expect(harness.page.pageCount == 1)
        }

        // MARK: Adding pages as the reader draws down

        /// A page's foot, `up` points above its body's bottom.
        private static func foot(of layout: PageLayout, page: Int = 0, up: CGFloat = 20) -> CGFloat {
            layout.bodyTop(ofPage: page) + layout.bodyHeight - up
        }

        @Test("A stroke that ends in the last page's foot adds a page, and saves ink once", arguments: [PageViewMode.compressed, .print])
        func strokeInTheFootAddsAPage(mode: PageViewMode) async {
            let layout = PageLayout(mode: mode)
            let harness = PageHarness(text: "One line.", layout: layout)
            var told: [Int] = []
            var saved = 0
            harness.page.onMinimumPageCountChanged = { told.append($0) }
            harness.page.onInkChanged = { _ in saved += 1 }

            Self.draw([Self.stroke(at: Self.foot(of: layout))], on: harness)

            #expect(await waitFor { told == [2] })
            harness.layOut()
            #expect(harness.page.pageCount == 2)
            // The page it added is the note's minimum, not ink: laying the note
            // out again for it saved nothing more.
            _ = await waitFor({ false }, seconds: 0.5)
            #expect(saved == 1)
        }

        @Test("It is where the stroke ends that counts, not where it began", arguments: [PageViewMode.compressed, .print])
        func strokeEndsInTheFoot(mode: PageViewMode) async {
            let layout = PageLayout(mode: mode)
            let harness = PageHarness(text: "One line.", layout: layout)
            var told: [Int] = []
            harness.page.onMinimumPageCountChanged = { told.append($0) }

            Self.draw([Self.verticalStroke(from: layout.bodyTop(ofPage: 0) + 100, to: Self.foot(of: layout))], on: harness)

            #expect(await waitFor { told == [2] })
        }

        @Test("A stroke above the foot, or on a page that isn't the last, adds nothing", arguments: [PageViewMode.compressed, .print])
        func strokeAboveTheFoot(mode: PageViewMode) async {
            let layout = PageLayout(mode: mode)
            let harness = PageHarness(text: "One line.", layout: layout)
            var told = 0
            harness.page.onMinimumPageCountChanged = { _ in told += 1 }

            let top = layout.growthBandTop(ofPage: 0)
            Self.draw([Self.stroke(at: top - 10)], on: harness)
            _ = await waitFor({ false }, seconds: 0.5)
            #expect(told == 0)
            #expect(harness.page.pageCount == 1)

            // Three pages, a stroke in the first one's foot.
            harness.page.minimumPageCount = 3
            harness.layOut()
            Self.draw([Self.stroke(at: Self.foot(of: layout))], on: harness)
            _ = await waitFor({ false }, seconds: 0.5)
            #expect(told == 0)
            #expect(harness.page.pageCount == 3)
        }

        @Test("Turned off, a stroke in the foot adds nothing", arguments: [PageViewMode.compressed, .print])
        func settingOff(mode: PageViewMode) async {
            let layout = PageLayout(mode: mode)
            let harness = PageHarness(text: "One line.", layout: layout)
            harness.page.addsPagesWhileDrawing = false
            var told = 0
            harness.page.onMinimumPageCountChanged = { _ in told += 1 }

            Self.draw([Self.stroke(at: Self.foot(of: layout))], on: harness)
            _ = await waitFor({ false }, seconds: 0.5)

            #expect(told == 0)
            #expect(harness.page.pageCount == 1)
        }

        @Test("Ink that is loaded or moved into the foot adds nothing: only a stroke drawn now does", arguments: [PageViewMode.compressed, .print])
        func onlyDrawnStrokesAdd(mode: PageViewMode) async throws {
            let layout = PageLayout(mode: mode)
            var told = 0

            // Loaded into the foot.
            let loaded = PageHarness(text: "One line.", layout: layout)
            loaded.page.onMinimumPageCountChanged = { _ in told += 1 }
            loaded.setInk(PKDrawing(strokes: [Self.stroke(at: Self.foot(of: layout))]))
            _ = await waitFor({ false }, seconds: 0.5)
            #expect(told == 0)

            // Drawn above the foot, then moved into it by the lasso.
            let moved = PageHarness(text: "One line.", layout: layout)
            moved.page.onMinimumPageCountChanged = { _ in told += 1 }
            var saved = 0
            moved.page.onInkChanged = { _ in saved += 1 }
            Self.draw([Self.stroke(at: layout.bodyTop(ofPage: 0) + 200)], on: moved)
            #expect(await waitFor { saved == 1 })

            var markup = moved.page.canvas.markup
            var stroke = try #require(markup.subelements.strokes.first)
            stroke.applyTransform(CGAffineTransform(translationX: 0, y: Self.foot(of: layout) - (layout.bodyTop(ofPage: 0) + 200)))
            markup.subelements.updateOrAppend(stroke)
            moved.page.canvas.markup = markup
            moved.page.canvas.onMarkupChanged?()
            #expect(await waitFor { saved == 2 })
            moved.layOut()

            #expect(told == 0)
            #expect(moved.page.pageCount == 1)
        }

        @Test("The setting's key is stable and the feature is on until turned off")
        func growthSettingKey() {
            #expect(SettingKeys.Drawing.addPagesWhileDrawing.name == "addPagesWhileDrawing")
            #expect(SettingKeys.Drawing.addPagesWhileDrawing.defaultValue)
            #expect(PageHarness(text: "x").page.addsPagesWhileDrawing)
        }
    }
}

#endif
