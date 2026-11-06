import PaperKit
import UIKit

/// The state of a page's ink on its way in, and the generation that tells a
/// capture its result is stale (docs/refactor/2P-page.md, 2P1, second PR).
///
/// `PageView` owns one. It holds the stored ink (`InkCapture.State`), the
/// newest snapshot not yet taken in, whether a capture is running, the
/// generation, and the lowest point of the ink as shown. The decisions about
/// when to capture, show and commit are still `PageView`'s; they move here in
/// the next PR. The rules in AGENTS.md › Implementation requirements apply:
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
}
