//
//  PageSettlingTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

/// What the page looks like once layout settles on its own, the way it does
/// in the app — no layout passes forced by the test.
///
/// Waits with `Task.sleep`, never by running the run loop by hand. A test that
/// spins the main run loop holds the main actor for as long as it spins, and
/// other suites' main-actor tests that poll against a deadline time out.
@Suite("Page settling", .serialized)
@MainActor
struct PageSettlingTests {

    final class Box { var value = "" }

    /// About five portrait pages: prose, wrapped paragraphs, headings, code.
    static let note: String = (1...120).flatMap { index -> [String] in
        if index % 25 == 1 { return ["## Lecture section \(index / 25 + 1): gjpqy invariants"] }
        if index % 25 == 9 { return ["```cpp", "int query(gap g) {", "    return g.jump(); // descenders: gjpqy", "}", "```"] }
        if index % 4 == 0 {
            return ["Line \(index): a longer paragraph that wraps across more than one line on a portrait page, so a page break can land in the middle of it and push only its later lines onto the next page."]
        }
        return ["Line \(index): the loop invariant holds before and after every iteration gjpqy."]
    }.joined(separator: "\n")

    static func settle(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Wired the way DocumentTextView wires it, editing at the note's end —
    /// where a paste leaves the caret.
    static func openNote(_ text: String = note, layout: PageLayout) async -> (UIWindow, DocumentTextView.Coordinator, PageView) {
        let box = Box()
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.delegate = coordinator
        textView.textLayoutManager?.delegate = coordinator
        coordinator.attachOverlay(to: textView)
        coordinator.observeAppearance(of: textView)
        textView.text = text
        coordinator.invalidateStyling()
        coordinator.restyle(textView)

        let page = PageView(textView: textView)
        page.pageLayout = layout
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 1366))
        page.frame = CGRect(x: 76, y: 137, width: 872, height: 1100)
        window.addSubview(page)
        window.makeKeyAndVisible()
        await settle(0.3)

        textView.becomeFirstResponder()
        textView.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        textView.scrollRangeToVisible(textView.selectedRange)
        await settle(0.3)
        return (window, coordinator, page)
    }

    @Test("After a mode switch the note settles at whole pages, with nothing forcing layout", arguments: PageViewMode.allCases)
    func settlesAtWholePages(target: PageViewMode) async {
        for start in PageViewMode.allCases where start != target {
            let (window, coordinator, page) = await Self.openNote(layout: PageLayout(mode: start))

            page.pageLayout = PageLayout(mode: target)
            await Self.settle(1)

            let expected = page.pageLayout.noteHeight(pageCount: page.pageCount)
            #expect(abs(page.textView.contentSize.height - expected) < 0.5,
                    "\(start) → \(target): height \(page.textView.contentSize.height), \(page.pageCount) pages should be \(expected)")
            withExtendedLifetime((window, coordinator)) {}
        }
    }

    @Test("A note's page count matches its text once laid out to the end", arguments: PageViewMode.allCases)
    func pageCountMatchesText(mode: PageViewMode) async {
        let (window, coordinator, page) = await Self.openNote(layout: PageLayout(mode: mode))
        let textView = page.textView

        if let manager = textView.textLayoutManager {
            manager.ensureLayout(for: manager.documentRange)
        }
        // Laying out through TextKit directly doesn't tell the text view its
        // height changed; its own layout pass does, and in the app that pass
        // is where TextKit's layout happens in the first place.
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        await Self.settle(0.5)

        // The last line's bottom, from TextKit's own layout rather than from
        // anything PageView worked out.
        var lastLineBottom: CGFloat = 0
        if let manager = textView.textLayoutManager, let content = manager.textContentManager {
            manager.enumerateTextLayoutFragments(from: content.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { fragment in
                lastLineBottom = fragment.layoutFragmentFrame.maxY + textView.textContainerInset.top
                return false
            }
        }

        #expect(page.pageCount == page.pageLayout.pageIndex(atY: lastLineBottom) + 1,
                "\(mode): last line ends at \(lastLineBottom)")
        #expect(abs(textView.contentSize.height - page.pageLayout.noteHeight(pageCount: page.pageCount)) < 0.5)
        withExtendedLifetime((window, coordinator)) {}
    }
}

#endif
