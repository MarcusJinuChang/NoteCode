//
//  PageView+Settling.swift
//  NoteCode
//
//  What tests await instead of sleeping: the page's layout and ink settling.
//

#if canImport(UIKit)

import UIKit

extension PageView {

    /// no layout pass of this view or its text view and no change to where
    /// the note sits (the text view's offset and height, this view's
    /// offset). The offsets count because an animated scroll, such as the
    /// one to the caret, moves them in a window with no scene
    /// (`makeSceneLessTestWindow`) without a layout pass. Polled every 16ms
    /// by suspending (`Task.sleep`), so the run loop turns and Core
    /// Animation commits in between; nothing is laid out by force. A pass asked for runs at the next
    /// commit, well inside `quiet`, so a pending one isn't checked for: in a
    /// window with no scene it would never run. False if layout was still
    /// moving after `limit`. For tests, which await this rather than sleep
    /// (lint rule 9).
    @discardableResult
    func layoutSettled(quiet: Duration = .milliseconds(100), limit: Duration = .seconds(3)) async -> Bool {
        let clock = ContinuousClock()
        let end = clock.now + limit
        func place() -> [CGFloat] {
            [CGFloat(layoutPasses), textView.contentOffset.y, textView.contentSize.height, contentOffset.x, contentOffset.y]
        }
        var seen = place()
        var quietSince = clock.now
        while clock.now < end {
            try? await Task.sleep(for: .milliseconds(16))
            if place() != seen {
                seen = place()
                quietSince = clock.now
            } else if clock.now - quietSince >= quiet {
                return true
            }
        }
        return false
    }

    /// Returns once the ink the reader drew has been taken in and told
    /// onward (`PageInkPipeline.settled`). For tests.
    func inkSettled() async {
        await inkPipeline.settled()
    }
}

#endif
