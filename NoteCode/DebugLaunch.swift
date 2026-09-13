//
//  DebugLaunch.swift
//  NoteCode
//
//  Launch arguments that open a debug build in a known state, and a report of
//  what ends up on screen. Debug builds only.
//

#if DEBUG

import Foundation
#if canImport(UIKit)
import SwiftData
import UIKit
#endif

// MARK: - Fixtures

/// A note a debug launch can open with.
///
/// Built in, so a check never depends on the pasteboard: on 12 September the
/// simulator synced the Mac's clipboard over a `simctl pbcopy`, and the paste
/// landed someone's own text instead of the test note.
nonisolated enum DebugFixture: String, CaseIterable, Sendable {
    /// About eight portrait pages. Headings, one-line and wrapped paragraphs,
    /// and code blocks, with descenders throughout, so page breaks land
    /// between lines, mid-paragraph and inside code. Every line is numbered,
    /// so a screenshot or report says exactly where it is.
    case pages
    /// Code in each language the run button knows, an untagged block, a line
    /// too long for the panel, and inline spans — for colour and panel checks.
    case code
    case empty

    var text: String {
        switch self {
        case .pages: Self.pagesText
        case .code:  Self.codeText
        case .empty: ""
        }
    }

    private static let pagesText: String = (1...240).flatMap { index -> [String] in
        if index % 30 == 1 {
            return ["## Section \(index / 30 + 1): gjpqy invariants"]
        }
        if index % 30 == 12 {
            return ["```cpp", "int query(gap g) {", "    return g.jump(); // line \(index), descenders: gjpqy", "}", "```"]
        }
        if index % 4 == 0 {
            return ["Line \(index): a longer paragraph that wraps across more than one line on a portrait page, so a page break can land in the middle of it and push only its later lines onto the next page."]
        }
        return ["Line \(index): the loop invariant holds before and after every iteration gjpqy."]
    }.joined(separator: "\n")

    private static let codeText = """
        # Code fixture: gjpqy
        Inline `code`, **bold**, *italic* and ~~struck~~ text.
        ```cpp
        #include <vector>
        int query(const std::vector<int>& gaps, int g) { // descenders: gjpqy
            return gaps.empty() ? -1 : gaps[g % static_cast<int>(gaps.size())];
        }
        ```
        ```java
        public class Main {
            public static void main(String[] args) { System.out.println("gjpqy"); }
        }
        ```
        ```python
        def jump(gaps, g):
            return [q for q in gaps if q > g]  # descenders: gjpqy
        ```
        ```
        untagged block: copy only, no run button
        ```
        A line of code too long for the panel:
        ```cpp
        auto veryLongIdentifierForHorizontalClipping = computeSomethingWithManyArguments(alpha, beta, gamma, delta, epsilon, zeta);
        ```
        """
}

// MARK: - Options

/// What a debug launch asked for, parsed from the process's arguments.
///
/// The arguments are the app's own, never the settings keys. Passing
/// `-pageViewMode print` would set the mode with no code at all, but launch
/// arguments outrank saved settings, so choosing a mode from the view menu
/// would then appear to do nothing for the whole session.
nonisolated struct DebugLaunchOptions: Equatable, Sendable {

    enum Note: Equatable, Sendable {
        case fixture(DebugFixture)
        case file(String)
    }

    /// Opens a new note, in a store that lives in memory for this launch.
    var note: Note?
    var mode: PageViewMode?
    /// The seeded note's page orientation.
    var orientation: PageOrientation?
    /// A page to scroll to, counted from 1 as pages are on screen.
    var page: Int?
    /// A view mode to switch to once the page has settled.
    var thenMode: PageViewMode?
    /// Seconds to wait after settling before switching.
    var thenDelay: Double = 1
    /// Writes `DebugStateReport` each time layout settles.
    var writesReport = false

    /// Arguments that couldn't be used. Reported rather than ignored, so a
    /// typo can't pass for a check that ran.
    var problems: [String] = []

    var isActive: Bool {
        note != nil || mode != nil || orientation != nil || page != nil || thenMode != nil || writesReport
    }

    static let current = parse(ProcessInfo.processInfo.arguments)

    static func parse(_ arguments: [String]) -> DebugLaunchOptions {
        var options = DebugLaunchOptions()
        var index = 0

        /// The argument after `flag`, if there is one that isn't another flag.
        func value(for flag: String) -> String? {
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("-") else {
                options.problems.append("\(flag) needs a value")
                return nil
            }
            index += 1
            return arguments[index]
        }

        func choice<T: RawRepresentable & CaseIterable>(_ raw: String?, for flag: String) -> T? where T.RawValue == String {
            guard let raw else { return nil }
            if let parsed = T(rawValue: raw) { return parsed }
            let expected = T.allCases.map(\.rawValue).joined(separator: ", ")
            options.problems.append("\(flag): \"\(raw)\" isn't one of \(expected)")
            return nil
        }

        func setNote(_ note: Note) {
            if options.note != nil {
                options.problems.append("more than one note given; using the last")
            }
            options.note = note
        }

        while index < arguments.count {
            let flag = arguments[index]
            switch flag {
            case "-debug-note":
                if let fixture: DebugFixture = choice(value(for: flag), for: flag) {
                    setNote(.fixture(fixture))
                }
            case "-debug-note-file":
                if let path = value(for: flag) {
                    setNote(.file(path))
                }
            case "-debug-mode":
                options.mode = choice(value(for: flag), for: flag)
            case "-debug-orientation":
                options.orientation = choice(value(for: flag), for: flag)
            case "-debug-page":
                if let raw = value(for: flag) {
                    if let number = Int(raw), number >= 1 {
                        options.page = number
                    } else {
                        options.problems.append("\(flag): \"\(raw)\" isn't a page number from 1")
                    }
                }
            case "-debug-then-mode":
                options.thenMode = choice(value(for: flag), for: flag)
            case "-debug-then-delay":
                if let raw = value(for: flag) {
                    if let seconds = Double(raw), seconds >= 0 {
                        options.thenDelay = seconds
                    } else {
                        options.problems.append("\(flag): \"\(raw)\" isn't a number of seconds")
                    }
                }
            case "-debug-report":
                options.writesReport = true
            default:
                if flag.hasPrefix("-debug-") {
                    options.problems.append("unknown argument \(flag)")
                }
            }
            index += 1
        }

        if options.orientation != nil && options.note == nil {
            options.problems.append("-debug-orientation applies to a seeded note; add -debug-note")
        }
        if arguments.contains("-debug-then-delay") && options.thenMode == nil {
            options.problems.append("-debug-then-delay does nothing without -debug-then-mode")
        }
        return options
    }
}

// MARK: - Report

/// What's on screen once layout settles, written as JSON for a script to read.
///
/// Built from what TextKit has actually laid out, not from page geometry. The
/// view-switch bug of 13 September left the scroll offset exactly right while
/// the lines under it were a page's break out of place; a report of offsets
/// would have said all was well. `topLine.text` and `visibleLinesAcrossBreaks`
/// are the two fields that would have shown it.
nonisolated struct DebugStateReport: Codable, Equatable, Sendable {

    struct TopLine: Codable, Equatable, Sendable {
        /// UTF-16 offset of the line's first character.
        var character: Int
        /// Counted from 1.
        var page: Int
        /// Whether it's the first line of its page.
        var startsPage: Bool
        /// The start of the line, up to 60 characters.
        var text: String
    }

    /// Increases with each report this launch, so a script can tell a fresh one.
    var sequence: Int
    /// `settled`, or `after-then-mode` once the requested switch has happened.
    var event: String
    var mode: String
    var orientation: String
    var pageCount: Int
    var contentOffset: Double
    var displayScale: Double
    var zoom: Double
    /// The first line reaching below the top of the view.
    var topLine: TopLine?
    /// Visible lines lying across a page break. Anything but 0 means TextKit
    /// has lines where the pages say they can't be.
    var visibleLinesAcrossBreaks: Int
    var problems: [String]
}

#if canImport(UIKit)

extension DebugStateReport {
    @MainActor
    init(page: PageView, event: String, sequence: Int, problems: [String]) {
        let textView = page.textView
        let layout = page.pageLayout

        self.sequence = sequence
        self.event = event
        self.mode = layout.mode.rawValue
        self.orientation = layout.orientation.rawValue
        self.pageCount = page.pageCount
        self.contentOffset = Double(textView.contentOffset.y)
        self.displayScale = Double(page.displayScale)
        self.zoom = Double(page.zoom)
        self.problems = problems
        self.visibleLinesAcrossBreaks = Self.visibleLinesAcrossBreaks(in: page)

        if let character = page.topLineCharacter(), let top = page.lineTop(atCharacter: character) {
            let index = layout.pageIndex(atY: top)
            let text = (textView.text ?? "") as NSString
            let start = min(character, text.length)
            let newline = text.range(of: "\n", range: NSRange(location: start, length: text.length - start)).location
            let end = newline == NSNotFound ? text.length : newline
            topLine = TopLine(
                character: character,
                page: index + 1,
                startsPage: top - layout.bodyTop(ofPage: index) < 1,
                text: text.substring(with: NSRange(location: start, length: min(end - start, 60)))
            )
        } else {
            topLine = nil
        }
    }

    @MainActor
    private static func visibleLinesAcrossBreaks(in page: PageView) -> Int {
        let textView = page.textView
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager
        else { return 0 }

        let layout = page.pageLayout
        // Where the page geometry puts each break, in note coordinates.
        let breaks = layout.exclusionBands(pageCount: page.pageCount, containerTop: layout.firstBodyTop)
            .map { $0.offsetBy(dx: 0, dy: layout.firstBodyTop) }
        let visibleTop = textView.contentOffset.y
        let visibleBottom = visibleTop + textView.bounds.height

        var count = 0
        let from = manager.textViewportLayoutController.viewportRange?.location ?? content.documentRange.location
        manager.enumerateTextLayoutFragments(from: from, options: []) { fragment in
            for line in fragment.textLineFragments {
                // Where TextKit actually has the line, with the inset it is
                // actually drawn at.
                let top = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + textView.textContainerInset.top
                let bottom = top + line.typographicBounds.height
                if top > visibleBottom { return false }
                guard bottom > visibleTop else { continue }
                if breaks.contains(where: { $0.minY < bottom - 0.25 && $0.maxY > top + 0.25 }) {
                    count += 1
                }
            }
            return true
        }
        return count
    }
}

// MARK: - Launch

@MainActor
enum DebugLaunch {

    /// A store holding one note built from the options, and that note.
    ///
    /// In memory: the simulator's own notes are left alone, and every launch
    /// starts from the same state. Returned as `.persistent` because it opened
    /// as intended — `.ephemeral` would show the storage-failure warning.
    static func seededStorage(_ options: DebugLaunchOptions, session: DebugSession) -> (storage: Storage, page: Page)? {
        guard let note = options.note else { return nil }

        let schema = Schema([Page.self])
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        } catch {
            session.record("couldn't open an in-memory store: \(error.localizedDescription)")
            return nil
        }

        let title: String
        let content: String
        switch note {
        case .fixture(let fixture):
            title = "Debug: \(fixture.rawValue)"
            content = fixture.text
        case .file(let path):
            title = "Debug: \((path as NSString).lastPathComponent)"
            do {
                content = try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                session.record("couldn't read \(path): \(error.localizedDescription)")
                content = ""
            }
        }

        let page = Page(title: title, content: content)
        if let orientation = options.orientation {
            page.orientation = orientation
        }
        container.mainContext.insert(page)
        return (.persistent(container), page)
    }

    /// Sets the view mode before any view reads it, in the saved setting the
    /// view menu writes to. It stays set after the launch, as a choice made
    /// from the menu would.
    static func applyViewMode(_ options: DebugLaunchOptions) {
        if let mode = options.mode {
            UserDefaults.standard.set(mode.rawValue, forKey: PageViewMode.defaultsKey)
        }
    }

    /// Scrolls to page `number`'s top edge.
    ///
    /// Lays out the text down to that page first, the way scrolling there by
    /// hand would have, so the page count is real rather than an estimate.
    /// Not the whole note: a full layout leaves TextKit in a state a reader
    /// never reaches, and a check run from it could miss what they'd see.
    ///
    /// - Returns: a problem to report, if the note has fewer pages.
    @discardableResult
    static func scroll(_ page: PageView, toPage number: Int) -> String? {
        let textView = page.textView
        let layout = page.pageLayout
        var index = max(number - 1, 0)

        textView.textLayoutManager?.ensureLayout(for: CGRect(
            x: 0,
            y: 0,
            width: layout.textWidth,
            height: layout.scrollTop(forPage: index) + textView.bounds.height
        ))
        textView.setNeedsLayout()
        textView.layoutIfNeeded()

        var problem: String?
        if index >= page.pageCount {
            problem = "page \(number) requested; the note has \(page.pageCount)"
            index = page.pageCount - 1
        }
        let maximum = max(textView.contentSize.height - textView.bounds.height, 0)
        textView.contentOffset.y = min(layout.scrollTop(forPage: index), maximum)
        return problem
    }
}

/// Carries out a debug launch's requests against the page once it's on
/// screen, and writes the report. Does nothing unless a debug argument was
/// passed, which is the case for every test run and every normal launch.
@MainActor
final class DebugSession {

    static let shared = DebugSession(options: .current)

    /// Where the report is written: the app container's `tmp`.
    static var reportURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notecode-debug-state.json")
    }

    let options: DebugLaunchOptions
    private(set) var problems: [String]

    private weak var page: PageView?
    private var hasScrolled = false

    private enum Switch { case pending, scheduled, done }
    private var modeSwitch = Switch.pending

    private var settleWork: DispatchWorkItem?
    private var sequence = 0

    /// Quiet time after the last layout pass before calling the page settled.
    static let settleDelay: TimeInterval = 0.4

    init(options: DebugLaunchOptions) {
        self.options = options
        self.problems = options.problems
    }

    func record(_ problem: String) {
        problems.append(problem)
    }

    /// Called by the page view as it's made. The first one is the one opened.
    func attach(_ page: PageView) {
        guard options.isActive, self.page == nil else { return }
        self.page = page
    }

    /// Called after every layout pass of the attached page's text view.
    func pageDidLayout(_ page: PageView) {
        guard options.isActive, page === self.page, page.textView.bounds.height > 0 else { return }

        if let number = options.page, !hasScrolled {
            hasScrolled = true
            // After this layout pass rather than inside it.
            DispatchQueue.main.async { [weak self, weak page] in
                guard let self, let page else { return }
                if let problem = DebugLaunch.scroll(page, toPage: number) {
                    self.record(problem)
                }
            }
            return
        }
        scheduleSettle()
    }

    private func scheduleSettle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settled() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func settled() {
        guard let page else { return }

        if options.writesReport {
            sequence += 1
            let report = DebugStateReport(
                page: page,
                event: modeSwitch == .done ? "after-then-mode" : "settled",
                sequence: sequence,
                problems: problems
            )
            write(report)
        }

        if let thenMode = options.thenMode, modeSwitch == .pending, options.page == nil || hasScrolled {
            modeSwitch = .scheduled
            DispatchQueue.main.asyncAfter(deadline: .now() + options.thenDelay) { [weak self] in
                self?.modeSwitch = .done
                // Through the saved setting, the path the view menu takes, so
                // the switch runs through the same SwiftUI update a tap does.
                UserDefaults.standard.set(thenMode.rawValue, forKey: PageViewMode.defaultsKey)
            }
        }
    }

    private func write(_ report: DebugStateReport) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(report).write(to: Self.reportURL, options: .atomic)
        } catch {
            print("NoteCode debug report not written: \(error.localizedDescription)")
        }
    }
}

#endif
#endif
