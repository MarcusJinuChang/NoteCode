//
//  PageView+Ink.swift
//  NoteCode
//
//  The page's ink: showing, replacing and inserting it, and the pipeline's host.
//

#if canImport(UIKit)

import PaperKit
import UIKit

extension PageView {

    /// The note's ink, in print layout's coordinates: where each stroke sits
    /// on its sheet, which is also where it prints.
    ///
    /// The canvas shows it converted to the current mode, and every mode
    /// change converts from this rather than from the canvas. Ink in a sheet's
    /// margin has no exact place in a mode with narrower breaks — see
    /// `PageLayout.convert` — so converting what's on screen back and forth
    /// would move it a page on every round trip.
    ///
    /// Strokes the reader made are taken in off the main thread
    /// (`captureInk`), so reading this first finishes any still on their way.
    var ink: PaperMarkup {
        commitInk()
        return inkPipeline.state.ink
    }

    var inkBottom: CGFloat? { inkPipeline.bottom }

    func showInk() {
        inkPipeline.show()
    }

    /// Replaces the note's ink.
    ///
    /// - Parameter drawing: strokes in print layout's coordinates, for this
    ///   note's orientation — the form ink is stored and printed in.
    func setInk(_ markup: PaperMarkup) {
        // Whatever was on its way in belonged to the ink this replaces.
        inkPipeline.replace(with: markup)
        inkPipeline.show()
    }

    /// Runs one of PaperKit's inserts so what it adds lands on the page the
    /// reader is looking at: see `InkInsertion.centre`.
    ///
    /// The insert tells the canvas's delegate, so it is captured, saved and
    /// undone like any other change the reader makes.
    func insertIntoInk(extent: CGSize, _ insert: () -> Void) {
        let centre = InkInsertion.centre(
            in: canvas.coveredPart,
            regions: pageLayout.inkRegions(pageCount: pageCount),
            extent: extent
        )
        canvas.inserting(around: centre, insert)
    }

    /// The tallest a photo is first shown: a share of what is on screen, and
    /// of a page's body, so it fits one page.
    var insertionMaxHeight: CGFloat {
        min(canvas.coveredPart.height, pageLayout.bodyHeight) * InkInsertion.photoWidthShare
    }

    /// Hands touches to the Select tool's overlay, or back to the canvas.
    func setSelecting(_ selecting: Bool, allowsFingers: Bool) {
        selectionOverlay.allowsFingers = allowsFingers
        selectionOverlay.isActive = selecting
    }

    /// Takes in, now and on the main thread, whatever the reader drew that is
    /// still on its way: before ink is shown again, read, printed or saved
    /// for the app leaving the screen (`PageInkPipeline.commit`).
    func commitInk() {
        inkPipeline.commit()
    }

    // MARK: PageInkHost

    func inkChanged(_ ink: PaperMarkup) {
        onInkChanged?(ink)
    }

    func inkChangedPageCount() {
        textView.reapplyContentHeightAdjustment()
        textView.setNeedsLayout()
    }

    func inkWasTakenIn(drawnEnds: [CGPoint]) {
        bands.keepPageBelowInk()
        growPageForStroke(endingAt: drawnEnds)
    }

    /// A stroke the reader just drew that ends in the last page's foot adds a
    /// page, as Add Page does (`PageBands.raiseMinimum`), so they can go on writing.
    ///
    /// Only strokes drawn now count (`InkCapture.Result.drawnEnds`): not ink
    /// that was loaded, moved by the lasso or shown again for a mode switch.
    /// It runs after the stroke has been taken in and told onward, and the
    /// page it adds is the note's minimum, not ink: nothing here calls
    /// `onInkChanged`, so growing never saves ink of its own. Seamless adds
    /// its page from `PageBands.keepPageBelowInk` as soon as ink reaches the last page.
    private func growPageForStroke(endingAt ends: [CGPoint]) {
        guard addsPagesWhileDrawing, pageLayout.mode != .seamless else { return }
        let last = pageCount
        guard ends.contains(where: { pageLayout.endsInGrowthBand(y: $0.y, pageCount: last) }) else { return }
        bands.raiseMinimum(to: last + 1)
    }
}

#endif
