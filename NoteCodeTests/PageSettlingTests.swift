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

    /// The case PageViewTests.sheetTopOpensPageStart covers, the way the app
    /// meets it: layout left to happen on its own, not forced, and the text
    /// view not editing. On the simulator the forced-pass test passed while
    /// the app, switched from a landscape sheet's top margin, opened about
    /// ten lines above the page.
    @Test("From a sheet's top margin, switching to seamless shows that page from its top edge once layout settles", arguments: PageOrientation.allCases)
    func sheetTopSurvivesSettling(orientation: PageOrientation) async throws {
        let print = PageLayout(orientation: orientation, mode: .print)
        let seamless = PageLayout(orientation: orientation, mode: .seamless)
        let (window, coordinator, page) = await Self.openNote(layout: print)
        let textView = page.textView
        textView.resignFirstResponder()
        await Self.settle(0.5)
        try #require(page.pageCount > 3)

        // Inside the third sheet's top margin, above its first line. Checked
        // before switching: set straight after opening, the offset was taken
        // back to the note's end, and the switch then had nothing to test.
        let intended = print.sheet(ofPage: 2).minY + 20
        textView.contentOffset.y = intended
        await Self.settle(0.5)
        let before = textView.contentOffset.y
        try #require(abs(before - intended) < 1, "\(orientation): setup scrolled to \(before), not \(intended)")

        page.pageLayout = seamless
        await Self.settle(1)

        let expected = seamless.scrollTop(forPage: 2)
        #expect(abs(textView.contentOffset.y - expected) < 0.5,
                "\(orientation): scrolled to \(before) in print, now \(textView.contentOffset.y) in seamless, expected \(expected)")

        // What the reader sees, not the offset. On the simulator the offset
        // was exactly the page's top edge while the screen showed fifteen
        // lines of the page before it: text above the view hadn't been laid
        // out, so lines sat at estimated positions that page geometry knows
        // nothing about. Checking the offset against that geometry passed.
        let shownAtTop = try #require(Self.characterAtTop(of: textView))
        if let manager = textView.textLayoutManager {
            manager.ensureLayout(for: manager.documentRange)
        }
        let pageStart = try #require(Self.firstCharacter(onPage: 2, of: textView, layout: seamless))
        #expect(shownAtTop == pageStart, "\(orientation): line at the top starts at \(shownAtTop); page 3 starts at \(pageStart)")
        withExtendedLifetime((window, coordinator)) {}
    }

    /// The app's path to the bug, step for step: a note opened at its top,
    /// scrolled down to a sheet deep in it, and switched to seamless. On the
    /// simulator that put "Line 54" at the top of the view where page 4's
    /// first line, "Line 64", belonged — TextKit had the text above the view
    /// at estimated positions, so lines sat on the wrong pages.
    @Test("Deep in a note scrolled to by hand, switching to seamless shows the page's own first line at the top", arguments: PageOrientation.allCases)
    func deepSheetTopShowsPagesFirstLine(orientation: PageOrientation) async throws {
        let print = PageLayout(orientation: orientation, mode: .print)
        let seamless = PageLayout(orientation: orientation, mode: .seamless)
        let longNote = Self.note + "\n" + Self.note.replacingOccurrences(of: "Line ", with: "More ")

        let box = Box()
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.delegate = coordinator
        textView.textLayoutManager?.delegate = coordinator
        coordinator.attachOverlay(to: textView)
        coordinator.observeAppearance(of: textView)
        textView.text = longNote
        coordinator.invalidateStyling()
        coordinator.restyle(textView)

        let page = PageView(textView: textView)
        page.pageLayout = print
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 1366))
        page.frame = CGRect(x: 76, y: 137, width: 872, height: 1100)
        window.addSubview(page)
        window.makeKeyAndVisible()
        await Self.settle(0.5)

        // Down to the fourth sheet's top margin in steps, the way a finger gets there.
        let target = print.sheet(ofPage: 3).minY + 30
        var y: CGFloat = 0
        while y < target {
            y = min(y + 400, target)
            textView.contentOffset.y = y
            await Self.settle(0.05)
        }
        await Self.settle(0.5)
        try #require(abs(textView.contentOffset.y - target) < 1, "\(orientation): setup scrolled to \(textView.contentOffset.y), not \(target)")

        page.pageLayout = seamless
        await Self.settle(1)

        let shownAtTop = try #require(Self.characterAtTop(of: textView))
        if let manager = textView.textLayoutManager {
            manager.ensureLayout(for: manager.documentRange)
        }
        let pageStart = try #require(Self.firstCharacter(onPage: 3, of: textView, layout: seamless))
        let text = textView.text as NSString
        func snippet(_ at: Int) -> String { text.substring(with: NSRange(location: at, length: min(12, text.length - at))) }
        #expect(shownAtTop == pageStart,
                "\(orientation): top shows \"\(snippet(shownAtTop))\" (\(shownAtTop)); page 4 starts \"\(snippet(pageStart))\" (\(pageStart))")
        withExtendedLifetime((window, coordinator, box)) {}
    }

    /// The app's exact history before the bug showed: the note opened in
    /// seamless, switched to print layout, scrolled down to a deep sheet, and
    /// switched back. Logged on the simulator, the lines on screen kept their
    /// print-layout positions after the second switch, running across
    /// seamless's page breaks — TextKit reused layout it had already done.
    @Test("Seamless, then print, scrolled deep, then seamless again: the page's own first line is at the top", arguments: PageOrientation.allCases)
    func roundTripDeepShowsPagesFirstLine(orientation: PageOrientation) async throws {
        let print = PageLayout(orientation: orientation, mode: .print)
        let seamless = PageLayout(orientation: orientation, mode: .seamless)
        let longNote = Self.note + "\n" + Self.note.replacingOccurrences(of: "Line ", with: "More ")

        let box = Box()
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.delegate = coordinator
        textView.textLayoutManager?.delegate = coordinator
        coordinator.attachOverlay(to: textView)
        coordinator.observeAppearance(of: textView)
        textView.text = longNote
        coordinator.invalidateStyling()
        coordinator.restyle(textView)

        let page = PageView(textView: textView)
        page.pageLayout = seamless
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 1366))
        page.frame = CGRect(x: 76, y: 137, width: 872, height: 1100)
        window.addSubview(page)
        window.makeKeyAndVisible()
        await Self.settle(0.5)

        page.pageLayout = print
        await Self.settle(0.5)

        let target = print.sheet(ofPage: 3).minY + 30
        var y = textView.contentOffset.y
        while y < target {
            y = min(y + 400, target)
            textView.contentOffset.y = y
            await Self.settle(0.05)
        }
        await Self.settle(0.5)
        try #require(abs(textView.contentOffset.y - target) < 1, "\(orientation): setup scrolled to \(textView.contentOffset.y), not \(target)")

        page.pageLayout = seamless
        await Self.settle(1)

        let shownAtTop = try #require(Self.characterAtTop(of: textView))
        if let manager = textView.textLayoutManager {
            manager.ensureLayout(for: manager.documentRange)
        }
        let pageStart = try #require(Self.firstCharacter(onPage: 3, of: textView, layout: seamless))
        let text = textView.text as NSString
        func snippet(_ at: Int) -> String { text.substring(with: NSRange(location: at, length: min(12, text.length - at))) }
        #expect(shownAtTop == pageStart,
                "\(orientation): top shows \"\(snippet(shownAtTop))\" (\(shownAtTop)); page 4 starts \"\(snippet(pageStart))\" (\(pageStart))")
        withExtendedLifetime((window, coordinator, box)) {}
    }

    /// The character starting the first line whose bottom is below the top
    /// of the view, as TextKit has the text laid out right now.
    static func characterAtTop(of textView: UITextView) -> Int? {
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager
        else { return nil }
        let edge = textView.contentOffset.y - textView.textContainerInset.top
        guard let fragment = manager.textLayoutFragment(for: CGPoint(x: 1, y: max(edge, 0))) else { return nil }
        let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let frame = fragment.layoutFragmentFrame
        let line = fragment.textLineFragments.first { frame.minY + $0.typographicBounds.maxY > edge }
        return line.map { start + $0.characterRange.location } ?? start
    }

    /// The character starting page `index`'s first line, from a full layout.
    static func firstCharacter(onPage index: Int, of textView: UITextView, layout: PageLayout) -> Int? {
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager
        else { return nil }
        let documentStart = content.documentRange.location
        var found: Int?
        manager.enumerateTextLayoutFragments(from: documentStart, options: [.ensuresLayout]) { fragment in
            let start = content.offset(from: documentStart, to: fragment.rangeInElement.location)
            let frame = fragment.layoutFragmentFrame
            for line in fragment.textLineFragments {
                let top = frame.minY + line.typographicBounds.minY + textView.textContainerInset.top
                if layout.pageIndex(atY: top) >= index {
                    found = start + line.characterRange.location
                    return false
                }
            }
            return true
        }
        return found
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
