//
//  CodeFenceCostTests.swift
//  NoteCodeTests
//
//  Showing and hiding a block's backticks must cost a redraw and nothing
//  more: no layout, and no edit to the text storage.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Code fence cost")
@MainActor
struct CodeFenceCostTests {

    private static func fragmentIDs(_ textView: UITextView) -> [ObjectIdentifier] {
        guard let manager = textView.textLayoutManager else { return [] }
        var ids: [ObjectIdentifier] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: []) { fragment in
            ids.append(ObjectIdentifier(fragment))
            return true
        }
        return ids
    }

    private static func median(_ times: [TimeInterval]) -> TimeInterval {
        times.sorted()[times.count / 2]
    }

    /// `PageViewTests.typingCost`'s method on a 500-line note: a change near
    /// the top, where TextKit has the most below it to lay out again, timed
    /// through the layout it causes. Seamless layout, so the page-break
    /// bands are exclusion paths and a layout below an edit is what it costs.
    @Test("A caret move into and out of a block costs no layout, on a 500-line note")
    func caretMoveCost() async throws {
        let text = StylingPerformanceTests.document(lines: 500)
        let harness = CodeFenceDisplayTests.Harness(text)
        let textView = harness.textView
        // Let the syntax colouring pass finish: it edits the storage, once,
        // whatever the caret does.
        try await harness.settle()
        let inside = 10   // in the first block, lines 0 to 2
        let outside = 120 // in the prose after it

        let fragments = Self.fragmentIDs(textView)
        var viewportLayouts = 0
        textView.addViewportLayoutObserver { viewportLayouts += 1 }
        let storageEdits = StorageEditCounter(textView.textStorage)

        var into: [TimeInterval] = []
        var out: [TimeInterval] = []
        for _ in 0..<9 {
            textView.selectedRange = NSRange(location: outside, length: 0)
            harness.coordinator.textViewDidChangeSelection(textView)
            textView.layoutIfNeeded()

            var start = Date()
            textView.selectedRange = NSRange(location: inside, length: 0)
            harness.coordinator.textViewDidChangeSelection(textView)
            textView.layoutIfNeeded()
            into.append(Date().timeIntervalSince(start))
            #expect(harness.coordinator.fenceVisibility.editing == [0])

            start = Date()
            textView.selectedRange = NSRange(location: outside, length: 0)
            harness.coordinator.textViewDidChangeSelection(textView)
            textView.layoutIfNeeded()
            out.append(Date().timeIntervalSince(start))
            #expect(harness.coordinator.fenceVisibility.editing.isEmpty)
        }

        let editsByMoves = storageEdits.count

        // A keystroke at the same place, for scale.
        var typing: [TimeInterval] = []
        for index in 0..<9 {
            let position = textView.position(from: textView.beginningOfDocument, offset: outside + index)!
            let start = Date()
            textView.replace(textView.textRange(from: position, to: position)!, withText: "z")
            textView.layoutIfNeeded()
            typing.append(Date().timeIntervalSince(start))
        }
        let typingMedian = Self.median(typing)

        print("FENCECOST caret into a block: \(Self.median(into) * 1000)ms, out: \(Self.median(out) * 1000)ms; a keystroke there: \(typingMedian * 1000)ms")
        #expect(Self.median(into) < 0.1, "a caret move into a block took \(Self.median(into))s")
        #expect(Self.median(out) < 0.1, "a caret move out of a block took \(Self.median(out))s")
        #expect(editsByMoves == 0, "caret moves edited the text storage \(editsByMoves) times")
        print("FENCECOST viewport layouts during the caret moves: \(viewportLayouts)")
        _ = fragments
    }

    @Test("A caret move into a block lays nothing out and edits nothing: the same fragments, the same text storage")
    func caretMoveLaysNothingOut() async throws {
        let harness = CodeFenceDisplayTests.Harness(StylingPerformanceTests.document(lines: 500))
        let textView = harness.textView
        try await harness.settle()
        try await harness.caret(at: 120)
        let storageEdits = StorageEditCounter(textView.textStorage)

        let counter = FragmentCounter(forwardingTo: harness.coordinator)
        textView.textLayoutManager?.delegate = counter
        defer { textView.textLayoutManager?.delegate = harness.coordinator }

        let before = Self.fragmentIDs(textView)
        #expect(before.count > 30)
        try await harness.caret(at: 10)
        #expect(harness.coordinator.fenceVisibility.editing == [0])
        #expect(Self.fragmentIDs(textView) == before, "moving the caret into the block laid out new fragments")
        try await harness.caret(at: 120)
        #expect(harness.coordinator.fenceVisibility.editing.isEmpty)
        #expect(Self.fragmentIDs(textView) == before, "moving the caret out of the block laid out new fragments")
        #expect(counter.count == 0, "caret moves made \(counter.count) fragments")
        #expect(storageEdits.count == 0, "a caret move edited the text storage \(storageEdits.count) times")
    }

    // MARK: A block split by a page break

    @Test("A block that runs over a page break keeps every line where it was, away or being edited")
    func acrossAPageBreak() async throws {
        let filler = (0..<34).map { "Prose line \($0) before the block." }.joined(separator: "\n")
        let code = (0..<12).map { "int value\($0) = \($0);" }.joined(separator: "\n")
        let text = filler + "\n```cpp\n" + code + "\n```\n" + (0..<10).map { "Prose after \($0)." }.joined(separator: "\n")
        let harness = CodeFenceDisplayTests.Harness(text, layout: PageLayout(mode: .print))
        harness.layOut()

        let open = (text as NSString).range(of: "```cpp").location
        let close = (text as NSString).range(of: "```\n", options: .backwards).location
        let layout = harness.page.pageLayout
        let top = try #require(harness.page.lineTop(atCharacter: open))
        let bottom = try #require(harness.page.lineTop(atCharacter: close))
        #expect(layout.pageIndex(atY: top) != layout.pageIndex(atY: bottom), "the block should straddle a break: \(top), \(bottom)")

        try await harness.caret(at: 2)
        let away = CodeFenceDisplayTests.lineFrames(of: harness.textView)
        try await harness.caret(at: (text as NSString).range(of: "value5").location)
        #expect(harness.coordinator.fenceVisibility.editing == [0])
        let editing = CodeFenceDisplayTests.lineFrames(of: harness.textView)
        #expect(away == editing)
    }
}

/// Stands between TextKit and the coordinator and counts the paragraphs
/// TextKit asks it to lay out: one call is one fragment made.
@MainActor
final class FragmentCounter: NSObject, NSTextLayoutManagerDelegate {
    private let coordinator: DocumentTextView.Coordinator
    private(set) var count = 0

    init(forwardingTo coordinator: DocumentTextView.Coordinator) {
        self.coordinator = coordinator
    }

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        count += 1
        return coordinator.textLayoutManager(textLayoutManager, textLayoutFragmentFor: location, in: textElement)
    }
}

/// Counts the edits a text storage processes.
@MainActor
final class StorageEditCounter {
    private(set) var count = 0
    private var observer: NSObjectProtocol?

    init(_ storage: NSTextStorage) {
        observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.count += 1 }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

#endif
