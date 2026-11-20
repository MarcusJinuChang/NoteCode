//
//  ColoursLandingTests.swift
//  NoteCodeTests
//
//  Syntax colours land a moment after a note is put somewhere: opened at a
//  page, scrolled to a search result, re-wrapped at a new text size. When
//  they land on code above the screen, the reader stays where they were put.
//

#if canImport(UIKit) && DEBUG

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

/// DEBUG for its note, the debug launch's fixture.
///
/// The colours are held on a clock the test moves, so each test reads the
/// place before they land and again after, with nothing racing.
///
/// What is read is `PageView.topLineCharacter`, which starts from TextKit's
/// viewport: the lines the reader sees. `PageSettlingTests.characterAtTop`
/// asks for the fragment at the top edge's point instead, and that kept
/// answering the right line while the screen showed one 30 lines on, so the
/// reopening and text size tests never saw this.
@Suite("Colours landing above the screen keep the reader's place", .serialized, .tags(.layout), .timeLimit(.minutes(1)))
@MainActor
struct ColoursLandingTests {

    /// About eight portrait pages, a tagged C++ block on each: the device
    /// pass's note (`-debug-note pages`).
    static let note = TestFixtures.seedNote(.pages)

    struct Opened {
        let window: UIWindow
        let coordinator: DocumentTextView.Coordinator
        let box: PageSettlingTests.Box
        let page: PageView
        let clock: ManualClock
    }

    /// Opened the way `ReopenTests.open` opens a note, with the first
    /// colouring pass waiting on `clock`.
    static func open(layout: PageLayout, before: (PageView) -> Void = { _ in }) async -> Opened {
        let box = PageSettlingTests.Box()
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let clock = ManualClock()
        coordinator.highlightClock = clock
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.delegate = coordinator
        textView.textLayoutManager?.delegate = coordinator
        coordinator.attachOverlay(to: textView)
        coordinator.observeAppearance(of: textView)
        textView.text = note
        coordinator.invalidateStyling()
        coordinator.restyle(textView)

        let page = PageView(textView: textView)
        page.pageLayout = layout
        before(page)
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 1366))
        page.frame = CGRect(x: 76, y: 137, width: 872, height: 1100)
        window.addSubview(page)
        window.makeKeyAndVisible()
        await ReopenTests.layOut(page)
        return Opened(window: window, coordinator: coordinator, box: box, page: page, clock: clock)
    }

    /// Lets the colouring pass waiting on the clock paint, then lays out.
    static func colour(_ opened: Opened) async {
        await opened.clock.untilSleeping()
        opened.clock.advance(by: .seconds(1))
        await opened.coordinator.highlightingFinished()
        await ReopenTests.layOut(opened.page)
    }

    /// Page `index`'s first character in the note opened at its top and laid
    /// out to the end.
    static func pageStart(_ index: Int, layout: PageLayout) async throws -> Int {
        let control = await open(layout: layout)
        await colour(control)
        let textView = control.page.textView
        if let manager = textView.textLayoutManager { manager.ensureLayout(for: manager.documentRange) }
        control.page.paginate()
        if let manager = textView.textLayoutManager { manager.ensureLayout(for: manager.documentRange) }
        let start = try #require(PageSettlingTests.firstCharacter(onPage: index, of: textView, layout: layout))
        control.window.isHidden = true
        withExtendedLifetime(control) {}
        return start
    }

    static func snippet(_ at: Int?) -> String {
        guard let at else { return "nothing" }
        let text = note as NSString
        return "\(at) \"\(text.substring(with: NSRange(location: at, length: min(16, text.length - at))))\""
    }

    @Test("A note opened at page 5 still shows page 5 once its colours land (pages-18)", arguments: PageViewMode.allCases)
    func openedDeep(mode: PageViewMode) async throws {
        let layout = PageLayout(mode: mode)
        let expected = try await Self.pageStart(4, layout: layout)
        let opened = await Self.open(layout: layout) { $0.restore(toPage: 4) }
        let before = opened.page.topLineCharacter()
        try #require(before == expected, "\(mode): opened at \(Self.snippet(before)); page 5 starts \(Self.snippet(expected))")

        await Self.colour(opened)
        let after = opened.page.topLineCharacter()
        #expect(after == expected, "\(mode): page 5 starts \(Self.snippet(expected)); with the colours in, the top is \(Self.snippet(after))")
        withExtendedLifetime(opened) {}
    }

    @Test("A search result deep in a note stays where it was shown once the colours land (pages-5)", arguments: PageViewMode.allCases)
    func searchResult(mode: PageViewMode) async throws {
        let match = try #require(NoteSearch("150:").matches(in: Self.note).first)
        let opened = await Self.open(layout: PageLayout(mode: mode)) { $0.reveal(match, highlighting: [match]) }
        let textView = opened.page.textView
        let before = opened.page.topLineCharacter()
        let matchBefore = try #require(opened.page.lineTop(atCharacter: match.location)) - textView.contentOffset.y
        try #require((0..<textView.bounds.height / 2).contains(matchBefore), "\(mode): the match is shown \(matchBefore)pt down")

        await Self.colour(opened)
        let after = opened.page.topLineCharacter()
        #expect(after == before, "\(mode): the result opened with \(Self.snippet(before)) at the top; with the colours in, \(Self.snippet(after))")
        withExtendedLifetime(opened) {}
    }

    @Test("A new text size deep in a note keeps the reader's line at the top once the colours land (pages-2)", arguments: [PageViewMode.print, .seamless], [21, 14])
    func textSize(mode: PageViewMode, size: Int) async throws {
        let layout = PageLayout(mode: mode)
        let opened = await Self.open(layout: layout) { $0.restore(toPage: 4) }
        await Self.colour(opened)
        let reading = try #require(opened.page.topLineCharacter())

        // The re-wrap puts the reader's line at the top (TextSizeReflowTests);
        // the colours it asks for land after.
        opened.page.reflow { opened.coordinator.setTypography(NoteTypography(bodySize: size), in: opened.page.textView) }
        let reflowed = try #require(opened.page.topLineCharacter())
        try #require(reflowed == reading, "\(mode), \(size)pt: the size change put \(Self.snippet(reflowed)) at the top, not \(Self.snippet(reading))")

        await Self.colour(opened)
        let after = opened.page.topLineCharacter()
        #expect(after == reading, "\(mode), \(size)pt: the reader was on \(Self.snippet(reading)); with the colours in, the top is \(Self.snippet(after))")
        withExtendedLifetime(opened) {}
    }
}

#endif
