//
//  DebugLaunchTests.swift
//  NoteCodeTests
//

#if DEBUG

import Foundation
import Testing
@testable import NoteCode

@Suite("Debug launch options")
struct DebugLaunchOptionsTests {

    private let app = "/path/to/NoteCode.app/NoteCode"

    @Test("A full set of arguments parses")
    func fullSet() {
        let options = DebugLaunchOptions.parse([
            app,
            "-debug-note", "pages",
            "-debug-mode", "print",
            "-debug-orientation", "landscape",
            "-debug-page", "4",
            "-debug-then-mode", "seamless",
            "-debug-then-delay", "1.5",
            "-debug-report",
        ])

        #expect(options.note == .fixture(.pages))
        #expect(options.mode == .print)
        #expect(options.orientation == .landscape)
        #expect(options.page == 4)
        #expect(options.thenMode == .seamless)
        #expect(options.thenDelay == 1.5)
        #expect(options.writesReport)
        #expect(options.problems.isEmpty)
        #expect(options.isActive)
    }

    @Test("A normal launch, or a test run, is inactive and has nothing to report")
    func noDebugArguments() {
        let options = DebugLaunchOptions.parse([app, "-NSDoubleLocalizedStrings", "YES", "-ApplePersistenceIgnoreState", "YES"])

        #expect(!options.isActive)
        #expect(options.problems.isEmpty)
    }

    @Test("A file path is a note")
    func notePath() {
        let options = DebugLaunchOptions.parse([app, "-debug-note-file", "/tmp/note.md"])
        #expect(options.note == .file("/tmp/note.md"))
    }

    @Test("Values that don't exist are reported, not silently ignored", arguments: [
        ["-debug-note", "novel"],
        ["-debug-mode", "carousel"],
        ["-debug-note", "pages", "-debug-orientation", "sideways"],
        ["-debug-page", "0"],
        ["-debug-page", "four"],
        ["-debug-then-mode", "seamless", "-debug-then-delay", "soon"],
    ])
    func badValues(arguments: [String]) {
        let options = DebugLaunchOptions.parse([app] + arguments)
        #expect(!options.problems.isEmpty, "\(arguments)")
    }

    @Test("A flag missing its value doesn't swallow the next flag")
    func missingValue() {
        let options = DebugLaunchOptions.parse([app, "-debug-mode", "-debug-report"])

        #expect(options.mode == nil)
        #expect(options.writesReport)
        #expect(options.problems.contains { $0.contains("-debug-mode") })
    }

    @Test("A misspelt debug argument is reported")
    func unknownArgument() {
        let options = DebugLaunchOptions.parse([app, "-debug-pgae", "4"])
        #expect(options.problems.contains { $0.contains("-debug-pgae") })
    }

    @Test("Orientation without a seeded note is reported, since orientation belongs to a note")
    func orientationNeedsNote() {
        let options = DebugLaunchOptions.parse([app, "-debug-orientation", "landscape"])
        #expect(options.problems.contains { $0.contains("-debug-note") })
    }

    @Test("Two notes are reported, and the last is used")
    func twoNotes() {
        let options = DebugLaunchOptions.parse([app, "-debug-note", "code", "-debug-note", "pages"])

        #expect(options.note == .fixture(.pages))
        #expect(!options.problems.isEmpty)
    }
}

#if canImport(UIKit)

import UIKit

@Suite("Debug fixtures and report")
@MainActor
struct DebugReportTests {

    private func open(_ text: String, layout: PageLayout) -> (UIWindow, PageView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 1366))
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = text
        let page = PageView(textView: textView)
        page.pageLayout = layout
        page.frame = CGRect(x: 76, y: 137, width: 872, height: 1100)
        window.addSubview(page)
        window.makeKeyAndVisible()
        layOut(page)
        return (window, page)
    }

    private func layOut(_ page: PageView) {
        for _ in 0..<3 {
            page.setNeedsLayout()
            page.layoutIfNeeded()
            page.textView.setNeedsLayout()
            page.textView.layoutIfNeeded()
        }
    }

    @Test("The pages fixture runs across several portrait pages")
    func pagesFixtureIsLong() {
        let (window, page) = open(DebugFixture.pages.text, layout: PageLayout())
        if let manager = page.textView.textLayoutManager {
            manager.ensureLayout(for: manager.documentRange)
        }
        layOut(page)

        #expect(page.pageCount >= 6)
        withExtendedLifetime(window) {}
    }

    @Test("The code fixture has a block for each run language, and an untagged one")
    func codeFixtureLanguages() {
        let tags = DocumentParser.parse(DebugFixture.code.text).compactMap(\.codeBlock).map(\.infoString)

        #expect(Set(tags).isSuperset(of: ["cpp", "java", "python", ""]))
    }

    @Test("After scrolling to a page, the report's top line is that page's first line", arguments: PageViewMode.allCases)
    func reportMatchesFreshLayout(mode: PageViewMode) throws {
        let layout = PageLayout(mode: mode)
        let (window, page) = open(DebugFixture.pages.text, layout: layout)

        #expect(DebugLaunch.scroll(page, toPage: 4) == nil)
        layOut(page)
        let report = DebugStateReport(page: page, event: "test", sequence: 1, problems: [])

        // The truth, from a full layout taken after the report.
        let truth = try #require(PageSettlingTests.firstCharacter(onPage: 3, of: page.textView, layout: layout))
        let top = try #require(report.topLine)
        #expect(top.page == 4)
        #expect(top.startsPage)
        #expect(top.character == truth)
        #expect(!top.text.isEmpty)
        #expect(report.visibleLinesAcrossBreaks == 0)
        #expect(report.mode == mode.rawValue)
        withExtendedLifetime(window) {}
    }

    @Test("Asking for a page past the end is reported and lands on the last page")
    func pagePastTheEnd() {
        let (window, page) = open("One short line.", layout: PageLayout())

        let problem = DebugLaunch.scroll(page, toPage: 9)

        #expect(problem != nil)
        #expect(page.textView.contentOffset.y == 0)
        withExtendedLifetime(window) {}
    }

    @Test("The report counts lines lying across a page break, so it can show text out of place")
    func reportSeesLinesOutOfPlace() throws {
        let layout = PageLayout(mode: .print)
        let (window, page) = open(DebugFixture.pages.text, layout: layout)
        DebugLaunch.scroll(page, toPage: 2)
        layOut(page)
        #expect(DebugStateReport(page: page, event: "test", sequence: 1, problems: []).visibleLinesAcrossBreaks == 0)

        // Move every line 30pt down without moving the pages, which is what
        // the stale-layout bug did: each sheet's last line now reaches into
        // the break below it. Less than a line, so the page count — and with
        // it where PageView puts the breaks — can't change underneath.
        let pagesBefore = page.pageCount
        page.textView.textContainerInset.top += 30
        page.textView.layoutIfNeeded()
        try #require(page.pageCount == pagesBefore, "the shift added a page, so the breaks moved with the text")

        #expect(DebugStateReport(page: page, event: "test", sequence: 2, problems: []).visibleLinesAcrossBreaks > 0)
        withExtendedLifetime(window) {}
    }

    @Test("The report round-trips through JSON")
    func reportCodable() throws {
        let report = DebugStateReport(
            sequence: 3, event: "settled", mode: "print", orientation: "landscape", pageCount: 6,
            contentOffset: 2579, displayScale: 0.78, zoom: 1,
            topLine: .init(character: 6140, page: 4, startsPage: true, text: "Line 64: a longer paragraph"),
            visibleLinesAcrossBreaks: 0, problems: []
        )

        let decoded = try JSONDecoder().decode(DebugStateReport.self, from: JSONEncoder().encode(report))
        #expect(decoded == report)
    }
}

#endif
#endif
