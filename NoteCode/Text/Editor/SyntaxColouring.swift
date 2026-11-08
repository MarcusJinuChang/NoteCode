//
//  SyntaxColouring.swift
//  NoteCode
//
//  Syntax colours for a text view's code blocks: which blocks are already
//  coloured, the pass in flight, and the appearance they were coloured
//  for. Pulled out of `DocumentTextView.Coordinator` (2T3); the Coordinator
//  keeps forwarding members for the call sites and tests that already use
//  them.
//

#if canImport(UIKit)

import UIKit

@MainActor
final class SyntaxColouring {

    let highlighter: SyntaxHighlighter = HighlightSwiftHighlighter()
    private var task: Task<Void, Never>?

    /// Bumped on every edit. A highlight result carrying an older number
    /// describes a document that no longer exists, so it gets dropped.
    private var generation = 0

    /// Blocks already coloured, keyed by content. A block whose code hasn't
    /// changed keeps the colours already in the text storage, so only the
    /// block being edited needs re-highlighting.
    private(set) var colouredBlocks: Set<HighlightKey> = []

    /// A block as it was coloured: its code and the language it was
    /// coloured as. The tag is part of it because a retag changes neither
    /// the block's id nor its code, and the colours must still follow.
    struct HighlightKey: Hashable {
        var id: CodeBlockID
        var language: String

        nonisolated init(block: CodeBlock) {
            id = block.id
            language = block.tag.map { $0.lowercased() } ?? ""
        }
    }

    /// The appearance `colouredBlocks` were coloured for.
    ///
    /// Syntax colours are fixed values picked from one theme, not dynamic
    /// colours like `.label`, so a block coloured under dark is not coloured
    /// for light just because its code hasn't changed.
    private var colouredAppearance: HighlightAppearance?

    /// The appearance code is always coloured for, whatever the text
    /// view's traits say. Nil follows the traits, as the editor does.
    ///
    /// Paper is light (`PrintedNote`), and its text view can't say so
    /// itself: a view in no window takes its appearance from the scene,
    /// and an override on the view doesn't change it (measured 16 Oct).
    /// With the device dark, the PDF and thumbnails had the dark theme's
    /// colours on a light panel.
    var pinnedAppearance: HighlightAppearance?

    /// Just enough to coalesce a fast burst of keystrokes.
    ///
    /// This was 200ms, chosen before measuring, which was long enough that
    /// a word stayed uncoloured while it was being typed.
    ///
    /// Colouring one block measures at a ~12.5ms median on an iPad Pro
    /// 13-inch simulator — see HighlighterCostTests. An earlier note here
    /// claimed 3.6–5.2ms; that is not reproducible, and since neither this
    /// file nor HighlightSwift has changed since it was written, it was
    /// most likely measured somewhere other than that test.
    ///
    /// The delay and the work do not compete for the same time. HighlightSwift's
    /// `Highlight` is a non-isolated Sendable class, so awaiting it from the
    /// main actor runs the JavaScript off-main; this delay only decides when
    /// that work starts. They add: colour lands roughly 32ms after typing
    /// stops, which is imperceptible. The one main-actor step is
    /// DocumentStyler.applyColors at the end, and it is small — that is the
    /// part to watch when the drawing layer starts competing for the main
    /// actor.
    private static let delay = Duration.milliseconds(20)

    /// What `delay` is measured on. Tests set one they move by hand; the
    /// app keeps `ContinuousClock`, as `Task.sleep(for:)` uses.
    var clock: any Clock<Duration> = ContinuousClock()

    /// Forgets which blocks are coloured, so the next pass colours them
    /// all. For when the storage is replaced and its colours go with it.
    func forget() {
        colouredBlocks = []
    }

    /// Kicks off syntax colouring after a pause in typing.
    ///
    /// The styling pass has already reset every foreground to `.label`, so
    /// if this never completes the code simply stays plain monospace — a
    /// working fallback rather than a broken state.
    func schedule(for textView: UITextView, source: String, blocks: [BlockNode]) {
        task?.cancel()

        generation &+= 1
        let generation = generation
        let appearance = pinnedAppearance ?? HighlightAppearance(textView.traitCollection)

        // Every block on screen was coloured for the other theme, so none of
        // them can be skipped. A pass still running under that theme is
        // dropped by the generation bump above.
        if appearance != colouredAppearance {
            colouredBlocks = []
            colouredAppearance = appearance
        }

        // Forget blocks that no longer exist, so the set can't grow forever.
        colouredBlocks.formIntersection(Set(blocks.compactMap { $0.codeBlock.map(HighlightKey.init(block:)) }))

        // Snapshot of what to send, taken before any await. Only blocks
        // whose code changed since the last pass — everything else still
        // holds the right colours, which applyStyling carries across.
        let jobs: [(key: HighlightKey, code: String, tag: String, offset: Int)] = blocks.compactMap { node in
            // Output isn't a language: nothing in it is coloured, and a
            // pass over it would only reset its text to `.label`.
            guard let code = node.codeBlock, !code.isOutput,
                  let tag = code.tag,
                  !colouredBlocks.contains(HighlightKey(block: code))
            else { return nil }
            return (
                HighlightKey(block: code),
                String(source[code.contentRange]),
                // The name highlight.js knows the language by, for a
                // language the app knows; what was typed otherwise, so
                // any of its other languages still colours.
                code.language?.highlightName ?? String(tag),
                NSRange(code.contentRange, in: source).location
            )
        }
        guard !jobs.isEmpty else { return }

        task = Task { [weak self, weak textView, clock] in
            try? await clock.sleep(for: Self.delay)
            guard !Task.isCancelled, let self, let textView else { return }

            var painted: [ColorRun] = []
            for job in jobs {
                let runs = await highlighter.colorRuns(
                    for: job.code,
                    languageTag: job.tag,
                    appearance: appearance
                )
                guard !Task.isCancelled else { return }

                painted += runs.map { run in
                    ColorRun(
                        range: NSRange(location: job.offset + run.range.location, length: run.range.length),
                        color: run.color,
                        bold: run.bold,
                        italic: run.italic
                    )
                }
            }

            // The document can move while the JS runs. Painting these runs
            // now would colour text at offsets that have shifted underneath
            // them, so both the generation and the text itself are checked.
            guard generation == self.generation,
                  textView.text == source
            else { return }

            let covered = jobs.map { NSRange(location: $0.offset, length: ($0.code as NSString).length) }
            let paint = { DocumentStyler.applyColors(painted, clearing: covered, to: textView) }
            // Colours above the screen move the lines on it. The edit
            // invalidates every paragraph it spans, and TextKit 2 lays the
            // screen's lines out again a page break's worth higher for every
            // page above, under an offset that never moved, while the
            // fragments above keep their old frames (measured 7 Nov,
            // ColoursLandingTests). A note opened at page 5, a search result
            // and a new text size all landed 17 to 58 lines past where they
            // were put, out of step with the sheets. So the page puts the
            // reader back on their line, as a new text size does. Only for
            // a block that starts above the screen. Typing in a block that
            // starts on it colours that block alone, and nothing above it
            // moves. Typing in a long block whose opening fence has scrolled
            // off takes this path at every pause too, since that edit also
            // spans paragraphs above the screen: the page lays out down to
            // the top line again and sets the offset back to where it was.
            if let keep = (textView as? DocumentUITextView)?.keepingReadingPlace,
               let first = covered.map(\.location).min(),
               first < Self.screenStart(of: textView) {
                keep(paint)
            } else {
                paint()
            }
            self.colouredBlocks.formUnion(jobs.map(\.key))
        }
    }

    /// The character TextKit's viewport starts at; 0 before it has laid out.
    private static func screenStart(of textView: UITextView) -> Int {
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager,
              let start = manager.textViewportLayoutController.viewportRange?.location
        else { return 0 }
        return content.offset(from: content.documentRange.location, to: start)
    }

    /// Returns once the colouring pass in flight, if any, has painted.
    ///
    /// Printing waits on this: paper gets no second chance to be coloured.
    func finished() async {
        await task?.value
    }

    /// Re-colours the code when the view switches between light and dark.
    ///
    /// Nothing else would: highlighting only runs after an edit, so a note
    /// left open across the switch keeps the old theme's colours.
    /// - Parameter snapshot: the note as it stands, from the Coordinator.
    func observeAppearance(of textView: UITextView, snapshot: @escaping @MainActor (UITextView) -> DocumentSnapshot?) {
        textView.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (textView: UITextView, _) in
            guard let self else { return }
            guard let snapshot = snapshot(textView) else { return }
            schedule(for: textView, source: snapshot.source, blocks: snapshot.blocks)
        }
    }
}

#endif
