//
//  PageViewTests+Canvas.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

extension PageViewTests {

    @Suite("The canvas and the note's length")
    @MainActor
    struct Canvas: PageViewSuite {

        // MARK: Ink and the note's length

        @Test("The canvas covers what's on screen, and its ink spans every page")
        func canvasCoversScreen() {
            let harness = PageHarness(text: Self.severalPages)
            let page = harness.page
            let width = page.pageLayout.pageSize.width
            let noteHeight = page.pageLayout.noteHeight(pageCount: page.pageCount)

            // Times the render scale — see DrawingCanvas.fitMarkupToNote.
            let scale = page.canvas.renderScale
            #expect(page.canvas.superview === page.textView)
            #expect(page.canvas.noteSize == CGSize(width: width, height: noteHeight))
            #expect(page.canvas.markup.bounds.size == CGSize(width: width * scale, height: noteHeight * scale))
            #expect(page.canvas.noteSize.height >= page.textView.contentSize.height - 0.5)

            for offset in [0, 1800, noteHeight - page.textView.bounds.height] {
                page.textView.contentOffset.y = offset
                harness.layOut()
                let covered = CGRect(x: 0, y: offset, width: width, height: page.textView.bounds.height)
                #expect(Self.close(page.canvas.frame, covered), "canvas at \(page.canvas.frame)")
            }
        }

        @Test("However long the note, the canvas is no taller than the screen")
        func canvasStaysScreenSized() {
            let long = (0..<60).map { _ in Self.severalPages }.joined(separator: "\n")
            let harness = PageHarness(text: long)
            let page = harness.page

            // PencilKit draws a stroke into a buffer its canvas's size, and Metal
            // refuses one past 16,384 pixels. A canvas as tall as a nine-page
            // note crashed on the first stroke (simulator, 23 September).
            // The canvas's own points are screen points — see
            // DrawingCanvas.renderScale — so its buffer is the screen's size.
            #expect(page.pageCount > 40)
            #expect(page.canvas.bounds.height <= page.bounds.height + 0.5)
        }

        @Test("The part of the note on screen stays within the note")
        func visiblePartClamps() {
            let inside = PageBands.visiblePart(ofNoteHeight: 3000, width: 816, scrolledTo: 1000, viewHeight: 800)
            let bouncedAbove = PageBands.visiblePart(ofNoteHeight: 3000, width: 816, scrolledTo: -60, viewHeight: 800)
            let bouncedBelow = PageBands.visiblePart(ofNoteHeight: 3000, width: 816, scrolledTo: 2400, viewHeight: 800)
            let shortNote = PageBands.visiblePart(ofNoteHeight: 500, width: 816, scrolledTo: 0, viewHeight: 800)

            #expect(inside == CGRect(x: 0, y: 1000, width: 816, height: 800))
            #expect(bouncedAbove.minY == 0)
            #expect(bouncedBelow.maxY == 3000)
            #expect(shortNote == CGRect(x: 0, y: 0, width: 816, height: 500))
        }

        @Test("Ink below the last line adds the pages needed to reach it")
        func inkBelowTextAddsPages() {
            let harness = PageHarness(text: "A short note.")
            let layout = harness.page.pageLayout

            harness.setInk(PKDrawing(strokes: [Self.stroke(at: 3000)]))
            let inkBottom = harness.page.canvas.markup.contentsRenderFrame.maxY

            #expect(harness.page.pageCount == layout.pageIndex(atY: inkBottom) + 1)
            #expect(harness.page.pageCount > 1)
            #expect(harness.page.textView.contentSize.height >= inkBottom)
            // The note PaperKit lays out: its bounds are the note's times the
            // render scale — see DrawingCanvas.fitMarkupToNote.
            #expect(harness.page.canvas.markup.bounds.maxY / harness.page.canvas.renderScale >= inkBottom)
        }

        @Test("Deleting text never clips ink")
        func deletingTextKeepsInk() {
            let harness = PageHarness(text: Self.severalPages, area: CGSize(width: 682, height: 900))
            harness.setInk(PKDrawing(strokes: [Self.stroke(at: 3000)]))
            let inkBottom = harness.page.canvas.markup.contentsRenderFrame.maxY

            harness.page.textView.text = "Nearly empty now."
            harness.layOut()

            #expect(harness.page.textView.contentSize.height >= inkBottom)
            // The note PaperKit lays out: its bounds are the note's times the
            // render scale — see DrawingCanvas.fitMarkupToNote.
            #expect(harness.page.canvas.markup.bounds.maxY / harness.page.canvas.renderScale >= inkBottom)
        }

        @Test("Laying out again doesn't grow the note again")
        func layoutIsIdempotent() {
            let harness = PageHarness(text: Self.severalPages)
            harness.setInk(PKDrawing(strokes: [Self.stroke(at: 9000)]))
            let height = harness.page.textView.contentSize.height
            let pages = harness.page.pageCount

            harness.layOut()
            harness.layOut()

            #expect(harness.page.textView.contentSize.height == height)
            #expect(harness.page.pageCount == pages)
        }
    }
}

#endif
