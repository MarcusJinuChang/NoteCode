//
//  InkHarness.swift
//  NoteCodeTests
//
//  The drawing canvas where the page puts it, and how a test waits for ink
//  that is taken in off the main thread.
//

#if canImport(UIKit)

import Foundation
import UIKit
@testable import NoteCode

/// The canvas inside a text view's content, in a window, so the responder
/// chain is the real one.
@MainActor
final class InkHarness {
    let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let textView = DocumentTextView.makeConfiguredTextView()
    let canvas: DrawingCanvas

    /// - Parameter covering: a band of the note, in note coordinates, for
    ///   the canvas to cover, as it does where the page has scrolled; the
    ///   note is then `pageSize` tall.
    init(
        _ text: String = "binary search invariant",
        pageSize: CGSize = CGSize(width: 816, height: 1056),
        covering: CGRect? = nil
    ) {
        canvas = DrawingCanvas(pageSize: pageSize)
        textView.frame = window.bounds
        textView.text = text
        window.addSubview(textView)
        textView.addSubview(canvas)
        window.makeKeyAndVisible()
        if let covering {
            canvas.noteSize = pageSize
            canvas.cover(covering)
        }
        window.layoutIfNeeded()
    }
}

/// Waits for `condition`, up to `seconds`: for ink, which a page takes in on a
/// detached task (`InkCapture`), so it reaches `onInkChanged` a moment after
/// the stroke. False if it never did.
///
/// By suspending, not by turning the run loop: the work comes back to
/// the main actor, and a test turning the run loop is still holding it
/// (AGENTS.md › Implementation requirements, `PageViewTests.waitFor`).
@MainActor
func waitFor(_ condition: () -> Bool, seconds: TimeInterval = 3) async -> Bool {
    let end = Date(timeIntervalSinceNow: seconds)
    while !condition() && Date() < end {
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

#endif
