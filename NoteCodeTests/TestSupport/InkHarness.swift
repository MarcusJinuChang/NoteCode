//
//  InkHarness.swift
//  NoteCodeTests
//
//  The drawing canvas where the page puts it. A test waits for ink, which
//  is taken in off the main thread, with `waitFor` (Waiting.swift).
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

#endif
