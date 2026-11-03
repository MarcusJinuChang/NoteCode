//
//  LinkTapTests.swift
//  NoteCodeTests
//
//  Where a tap on a link lands, and what else is allowed to take it. Points
//  are found in the same note with its markers deleted, so they don't come
//  from the layout being tested.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Taps on links")
@MainActor
struct LinkTapTests {

    static let note = [
        "[Apple](apple.com)",
        "x [Swift](swift.org) y",
        "[Go](go.dev)",
        "- [Rust](rust-lang.org)",
        "## Read [the docs](docs.swift.org)",
        "Plain words to tap on.",
        "",
    ].joined(separator: "\n")

    /// The middle of `text` on the line that starts with `line`, in the note
    /// with its markers deleted.
    static func middle(of text: String, onLineStarting line: String, in deleted: CodeFenceDisplayTests.Harness) throws -> CGPoint {
        let textView = deleted.textView
        let storage = textView.textStorage.string as NSString
        let lineStart = storage.range(of: line).location
        try #require(lineStart != NSNotFound, "no line starting \(line)")
        let found = storage.range(of: text, range: NSRange(location: lineStart, length: storage.length - lineStart))
        let start = textView.caretRect(for: try #require(textView.position(from: textView.beginningOfDocument, offset: found.location)))
        let end = textView.caretRect(for: try #require(textView.position(from: textView.beginningOfDocument, offset: NSMaxRange(found))))
        return CGPoint(x: (start.minX + end.minX) / 2, y: start.midY)
    }

    @Test("A tap on a link's text finds the link, wherever the link sits on its line", arguments: [
        ("Apple", "Apple", "apple.com"),
        ("x Swift", "Swift", "swift.org"),
        ("Go", "Go", "go.dev"),
        ("Rust", "Rust", "rust-lang.org"),
        ("Read", "the docs", "docs.swift.org"),
    ])
    func tapFindsTheLink(line: String, text: String, destination: String) throws {
        let (rendered, deleted) = MarkdownLayoutTests.pair(Self.note)
        let point = try Self.middle(of: text, onLineStarting: line, in: deleted)
        let target = rendered.coordinator.markerTapTarget(at: point, in: rendered.textView)
        guard case .link(_, let found)? = target else {
            Issue.record("a tap on \(text) at \(point) found \(String(describing: target))")
            return
        }
        #expect(found == destination)
    }

    /// A recogniser that says it is wherever the test puts it.
    final class Placed: UIGestureRecognizer {
        var point = CGPoint.zero
        override func location(in view: UIView?) -> CGPoint { point }
    }

    @Test("On a link the text view refuses its other recognisers, which would place the caret; elsewhere it doesn't")
    func refusesTheTextInteractionOnALink() throws {
        let (rendered, deleted) = MarkdownLayoutTests.pair(Self.note)
        let textView = rendered.textView
        let recognizer = Placed()
        textView.addGestureRecognizer(recognizer)

        recognizer.point = try Self.middle(of: "Apple", onLineStarting: "Apple", in: deleted)
        #expect(!textView.gestureRecognizerShouldBegin(recognizer))

        recognizer.point = try Self.middle(of: "words", onLineStarting: "Plain", in: deleted)
        #expect(textView.gestureRecognizerShouldBegin(recognizer))
    }

    @Test("A selection's end over a link can still be dragged")
    func selectionHandleOverALink() throws {
        let (rendered, _) = MarkdownLayoutTests.pair(Self.note)
        let textView = rendered.textView
        let text = textView.textStorage.string as NSString
        let apple = text.range(of: "Apple")
        textView.selectedRange = NSRange(location: 0, length: apple.location + 3)
        let end = textView.caretRect(for: try #require(textView.selectedTextRange).end)
        let recognizer = Placed()
        textView.addGestureRecognizer(recognizer)
        recognizer.point = CGPoint(x: end.midX, y: end.midY)

        #expect(rendered.coordinator.markerTapTarget(at: recognizer.point, in: textView) != nil, "the point is on the link")
        #expect(textView.gestureRecognizerShouldBegin(recognizer))
    }
}

#endif
