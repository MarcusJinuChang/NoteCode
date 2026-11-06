import PaperKit
import PencilKit
import UIKit

/// What the ink pipeline needs from the page it works for: the canvas it
/// shows ink on, the layout, and a way to tell the page what happened.
@MainActor
protocol PageInkHost: AnyObject {
    var canvas: DrawingCanvas { get }
    var selection: InkSelection { get }
    var pageLayout: PageLayout { get }
    var pageCount: Int { get }
    /// The reader changed the ink; save it (`PageView.onInkChanged`).
    func inkChanged(_ ink: PaperMarkup)
    /// The ink's lowest point moved, so the page count may have.
    func inkChangedPageCount()
    /// A capture was taken in and told onward; the page may grow for it.
    func inkWasTakenIn(drawnEnds: [CGPoint])
}

/// The state of a page's ink on its way in, and the generation that tells a
/// capture its result is stale (docs/refactor/2P-page.md, 2P1, second PR).
///
/// `PageView` owns one. It holds the stored ink (`InkCapture.State`), the
/// newest snapshot not yet taken in, whether a capture is running, the
/// generation, and the lowest point of the ink as shown. Showing, capturing and
/// committing it are here too (third PR); `PageView` forwards. The rules in AGENTS.md › Implementation requirements apply:
/// ink is saved only from `onInkChanged`, anything reading `ink` calls
/// `commitInk()` first, and a result computed from a state replaced since is
/// dropped (`generation`).
@MainActor
final class PageInkPipeline {
    /// The canvas as the reader last left it, not yet taken into `state`,
    /// with the layout and page count it was drawn in.
    struct Snapshot {
        var markup: PaperMarkup
        var layout: PageLayout
        var pageCount: Int
        var serial: Int
    }

    /// The stored ink, and where each element sat on the canvas when it was
    /// last shown or read. See `InkCapture.State`.
    var state: InkCapture.State

    /// The newest snapshot not yet taken in, whether a capture is working on
    /// it or it's waiting for the one before to finish.
    var newestSnapshot: Snapshot?

    /// True while a detached capture is running.
    var isCapturing = false

    /// Bumped whenever `state` is replaced on the main thread, so a capture
    /// that started from the old one drops its result.
    private(set) var generation = 0

    /// The lowest point of the ink as shown, cached so working out the page
    /// count — which every layout pass does — doesn't walk the strokes.
    var bottom: CGFloat?

    private var serial = 0

    /// The page this works for. Weak: the page owns the pipeline.
    weak var host: PageInkHost?

    init(state: InkCapture.State) {
        self.state = state
    }

    /// Replaces the stored ink. Whatever was on its way in belonged to the
    /// ink this replaces.
    func replace(with markup: PaperMarkup) {
        newestSnapshot = nil
        state = InkCapture.State(ink: markup)
    }

    /// A capture or commit that started from the current state is now stale.
    func invalidate() {
        generation += 1
    }

    /// Records the canvas as the newest snapshot, replacing any waiting one.
    func enqueue(markup: PaperMarkup, layout: PageLayout, pageCount: Int) {
        serial += 1
        newestSnapshot = Snapshot(markup: markup, layout: layout, pageCount: pageCount, serial: serial)
    }

    /// Takes the newest snapshot for a commit on the main thread, and makes
    /// any capture still running stale. Nil, and nothing changed, when none
    /// waits.
    func takeForCommit() -> Snapshot? {
        guard let snapshot = newestSnapshot else { return nil }
        newestSnapshot = nil
        invalidate()
        return snapshot
    }

    /// Clears the waiting snapshot after a capture of it finished, unless a
    /// newer one arrived meanwhile.
    func finish(_ snapshot: Snapshot) {
        if newestSnapshot?.serial == snapshot.serial {
            newestSnapshot = nil
        }
    }

    // MARK: Showing, capturing, committing

    /// Puts the ink on the host.canvas, converted to the current mode.
    ///
    /// Strokes drawn on the host.canvas are converted the other way as they arrive,
    /// each on its own page, rather than by converting the whole host.canvas back —
    /// that round trip is what `ink` exists to avoid.
    func show() {
        guard let host else { return }
        // Strokes still on their way in were drawn in the layout the host.canvas
        // shows until now, and are taken in by it before anything moves.
        commit()
        invalidate()

        let ink = state.ink
        let print = PageLayout(orientation: host.pageLayout.orientation, mode: .print)
        // Compressed and print layout show a stroke across a border only on
        // the page it was started on (`InkPages`); seamless shows it whole.
        let hidesOverflow = host.pageLayout.mode != .seamless
        var shown = host.canvas.markup

        if shown.subelements.isEmpty {
            // Nothing on the host.canvas to reconcile with: hand it the stored ink,
            // converted, in one go.
            let visible = hidesOverflow ? InkMarkupTransforms.withoutOverflow(ink) : ink
            host.canvas.markup = InkMarkupTransforms.convert(visible, from: print, to: host.pageLayout) ?? visible
        } else {
            // The host.canvas has its own copy of these elements, and a markup
            // *merges* what it is given rather than replacing it. A copy made
            // from `ink` branched before the host.canvas's own edits, so assigning
            // it changes nothing — measured on 19 September, when ink stayed
            // where it was drawn through every mode. Moving the host.canvas's own
            // elements, by the distance its stored copy says, is what takes.
            // Walked with `for`, never `map`: see `InkMarkupTransforms.frames(of:)`.
            var stored: [MarkupOrderedSet.ElementID: any Markup] = [:]
            for element in ink.subelements where !(hidesOverflow && InkPages.isOverflow(element)) {
                stored[element.elementID] = element
            }

            // A stroke the host.canvas holds whole but the ink holds cut changes
            // shape, and one shown with specks has a frame that isn't its
            // piece's: each leaves the host.canvas and comes back as stored,
            // below. A changed copy assigned over the host.canvas's own doesn't
            // take, and nor does a new one with its id while the old one is
            // there. Ink undo is cleared here anyway, so nothing loses track.
            // Added and placed a set at a time, never an element at a time:
            // see `convert`. Removed one at a time, which is few: a set
            // without them keeps them, and so does `removeAll(where:)`.
            let reshaped = state.wholeOnCanvas.union(state.specked).filter { stored[$0] != nil }
            for id in Set(shown.subelements.ids) where stored[id] == nil || reshaped.contains(id) {
                shown.subelements.removeElement(for: id)
            }
            let onCanvas = Set(shown.subelements.ids)
            var arriving: [any Markup] = []
            for (id, element) in stored where !onCanvas.contains(id) && !reshaped.contains(id) {
                arriving.append(element)
            }
            if !arriving.isEmpty {
                shown.subelements.append(contentsOf: arriving)
            }

            // Pieces that just replaced a stroke arrive at the end, so they
            // draw above strokes made after it until the note is reopened,
            // which shows the stored order. Assigning the set in the stored
            // order doesn't reorder the host.canvas (unit test, 9 October).
            var elements: [any Markup] = []
            for element in shown.subelements {
                guard let original = stored[element.elementID] else { continue }
                let target = print.convert(y: original.renderFrame.midY, to: host.pageLayout)
                    ?? original.renderFrame.midY
                var element = element
                let delta = target - element.renderFrame.midY
                if abs(delta) > 0.001 {
                    element.applyTransform(CGAffineTransform(translationX: 0, y: delta))
                }
                elements.append(element)
            }
            var placed = MarkupOrderedSet()
            placed.append(contentsOf: elements)
            shown.subelements = placed
            host.canvas.markup = shown

            if !reshaped.isEmpty {
                var returned = host.canvas.markup
                for id in reshaped {
                    guard let element = stored[id] else { continue }
                    let placed = InkCapture.moved(element, from: print, to: host.pageLayout)
                    returned.subelements.append((placed as? PKStroke).map(InkPages.redrawn) ?? placed)
                }
                host.canvas.markup = returned
            }
        }

        // Ink just moved under whatever the undo stack was holding: its
        // actions restore strokes to the mode they were drawn in.
        host.canvas.forgetUndo()
        // Ids and the box belong to the layout that is gone.
        host.selection.clear()

        // The host.canvas holds exactly the stored elements this mode shows now,
        // pieces included, and nothing is left to undo.
        let (frames, contents) = InkMarkupTransforms.frames(of: host.canvas.markup)
        state.shown = frames
        state.contents = contents
        state.wholeOnCanvas = []
        state.specked = []
        state.buried = [:]
        bottom = frames.values.map(\.maxY).max()
        // The page count depends on the ink, and nothing about the text changed.
        host.inkChangedPageCount()
    }


    /// Takes what the reader just drew, erased or moved into the stored ink,
    /// off the main thread (`InkCapture`).
    ///
    /// PaperKit says only that the markup changed, so what changed is found
    /// by walking all of it, and every operation on PaperKit's sets costs
    /// time in proportion to the ink: at 5,000 strokes this was 400ms on the
    /// main thread per stroke even walked properly (simulator, 10 October).
    /// Here the main thread only takes a snapshot, which costs nothing
    /// measurable. A burst of strokes is taken in as one: while a capture
    /// runs, only the newest snapshot waits.
    func capture() {
        guard let host else { return }
        enqueue(markup: host.canvas.markup, layout: host.pageLayout, pageCount: host.pageCount)
        startCapture()
    }

    private func startCapture() {
        guard !isCapturing, let snapshot = newestSnapshot else { return }
        isCapturing = true
        let state = state
        let generation = generation
        let (markup, layout, pageCount) = (snapshot.markup, snapshot.layout, snapshot.pageCount)
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                InkCapture.capture(markup, into: state, layout: layout, pageCount: pageCount)
            }.value
            guard let self else { return }
            isCapturing = false
            if generation == self.generation {
                finish(snapshot)
                apply(result)
            }
            startCapture()
        }
    }

    /// Takes in, now and on the main thread, whatever the reader drew that is
    /// still on its way: before ink is shown again, read, printed or saved
    /// for the app leaving the screen.
    func commit() {
        // A capture still running started from the state this replaces.
        guard let snapshot = takeForCommit() else { return }
        apply(InkCapture.capture(snapshot.markup, into: state, layout: snapshot.layout, pageCount: snapshot.pageCount))
    }

    private func apply(_ result: InkCapture.Result) {
        state = result.state
        guard result.changed, let host else { return }
        host.inkChanged(result.state.ink)

        let before = bottom
        bottom = result.inkBottom
        if !result.reshow.isEmpty {
            showOwnPieces(result.reshow, on: host)
        }
        // Ink below the last line makes the note longer, and nothing about
        // the text changed to trigger that on its own. Only a page's worth
        // can change the count, and a layout pass on every stroke cost 8ms.
        let page = { (bottom: CGFloat?) in bottom.map(host.pageLayout.pageIndex(atY:)) }
        if page(before) != page(bottom) {
            host.inkChangedPageCount()
        }
        host.inkWasTakenIn(drawnEnds: result.drawnEnds)
    }

    /// Swaps strokes the host.canvas holds whole for the piece on the page each
    /// was started on, keeping their ids: in compressed and print layout, a
    /// stroke drawn across a border stops at it once the pen lifts.
    ///
    /// The id is kept so PaperKit's undo still finds the stroke, and
    /// assigning the host.canvas registers no undo of its own (probe, 10
    /// October). Taken off and put back, since a changed copy assigned over
    /// the host.canvas's own doesn't take, and with a new path (`InkPages.redrawn`),
    /// or PencilKit goes on drawing it whole.
    private func showOwnPieces(_ pieces: [PKStroke], on host: PageInkHost) {
        var markup = host.canvas.markup
        for piece in pieces {
            let whole = state.shown[piece.elementID] ?? piece.renderFrame
            markup.subelements.updateOrAppend(InkPages.shown(piece, over: whole))
        }
        host.canvas.markup = markup

        // Where PaperKit has them now, which may be rounded from theirs.
        let now = host.canvas.markup.subelements
        for piece in pieces {
            state.shown[piece.elementID] = now[piece.elementID]?.renderFrame
            state.specked.insert(piece.elementID)
        }
        bottom = state.shown.values.map(\.maxY).max()
        // A snapshot waiting to be taken in was taken before this.
        if var waiting = newestSnapshot {
            waiting.markup = host.canvas.markup
            newestSnapshot = waiting
        }
    }

}
