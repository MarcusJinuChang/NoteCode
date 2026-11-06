//
//  DocumentTextView+Highlighting.swift
//  NoteCode
//
//  The coordinator's syntax colouring, which `SyntaxColouring` does: these
//  forward to it for the call sites and tests that already use them.
//

#if canImport(UIKit)

import UIKit

extension DocumentTextView.Coordinator {

    /// The appearance code is always coloured for. Nil follows the traits.
    var pinnedAppearance: HighlightAppearance? {
        get { syntaxColouring.pinnedAppearance }
        set { syntaxColouring.pinnedAppearance = newValue }
    }

    /// What the colouring pass waits on. Tests set one they move by hand.
    var highlightClock: any Clock<Duration> {
        get { syntaxColouring.clock }
        set { syntaxColouring.clock = newValue }
    }

    /// Kicks off syntax colouring after a pause in typing.
    func scheduleHighlighting(for textView: UITextView, source: String, blocks: [BlockNode]) {
        syntaxColouring.schedule(for: textView, source: source, blocks: blocks)
    }

    /// Returns once the colouring pass in flight, if any, has painted.
    func highlightingFinished() async {
        await syntaxColouring.finished()
    }

    /// Re-colours the code when the view switches between light and dark.
    func observeAppearance(of textView: UITextView) {
        syntaxColouring.observeAppearance(of: textView) { [weak self] textView in
            self?.snapshot(of: textView)
        }
    }
}

#endif
