//
//  DocumentTextView+Highlighting.swift
//  NoteCode
//
//  The coordinator's syntax colouring: scheduling a pass after a pause in
//  typing, waiting for it, and recolouring when the appearance switches.
//

#if canImport(UIKit)

import UIKit

extension DocumentTextView.Coordinator {

    /// Kicks off syntax colouring after a pause in typing.
    ///
    /// The styling pass above has already reset every foreground to
    /// `.label`, so if this never completes the code simply stays plain
    /// monospace — a working fallback rather than a broken state.
    func scheduleHighlighting(for textView: UITextView, source: String, blocks: [BlockNode]) {
        highlightTask?.cancel()

        highlightGeneration &+= 1
        let generation = highlightGeneration
        let appearance = pinnedAppearance ?? HighlightAppearance(textView.traitCollection)

        // Every block on screen was coloured for the other theme, so none of
        // them can be skipped. A pass still running under that theme is
        // dropped by the generation bump above.
        if appearance != highlightedAppearance {
            highlightedBlocks = []
            highlightedAppearance = appearance
        }

        // Forget blocks that no longer exist, so the set can't grow forever.
        highlightedBlocks.formIntersection(Set(blocks.compactMap { $0.codeBlock.map(HighlightKey.init(block:)) }))

        // Snapshot of what to send, taken before any await. Only blocks
        // whose code changed since the last pass — everything else still
        // holds the right colours, which applyStyling carries across.
        let jobs: [(key: HighlightKey, code: String, tag: String, offset: Int)] = blocks.compactMap { node in
            // Output isn't a language: nothing in it is coloured, and a
            // pass over it would only reset its text to `.label`.
            guard let code = node.codeBlock, !code.isOutput,
                  let tag = code.infoString.split(separator: " ").first,
                  !highlightedBlocks.contains(HighlightKey(block: code))
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

        highlightTask = Task { [weak self, weak textView, highlightClock] in
            try? await highlightClock.sleep(for: Self.highlightDelay)
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
                        color: run.color
                    )
                }
            }

            // The document can move while the JS runs. Painting these runs
            // now would colour text at offsets that have shifted underneath
            // them, so both the generation and the text itself are checked.
            guard generation == self.highlightGeneration,
                  textView.text == source
            else { return }

            let covered = jobs.map { NSRange(location: $0.offset, length: ($0.code as NSString).length) }
            DocumentStyler.applyColors(painted, clearing: covered, to: textView)
            self.highlightedBlocks.formUnion(jobs.map(\.key))
        }
    }

    /// Returns once the colouring pass in flight, if any, has painted.
    ///
    /// Printing waits on this: paper gets no second chance to be coloured.
    func highlightingFinished() async {
        await highlightTask?.value
    }

    /// Re-colours the code when the view switches between light and dark.
    ///
    /// Nothing else would: highlighting only runs after an edit, so a note
    /// left open across the switch keeps the old theme's colours.
    func observeAppearance(of textView: UITextView) {
        textView.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (textView: UITextView, _) in
            guard let self else { return }
            let snapshot = self.snapshot(of: textView)
            scheduleHighlighting(for: textView, source: snapshot.source, blocks: snapshot.blocks)
        }
    }

}

#endif
