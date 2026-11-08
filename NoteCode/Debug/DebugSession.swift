//
//  DebugSession.swift
//  NoteCode
//
//  Carries out a debug launch's requests once the page is on screen: the view
//  mode, scrolling to a page, the later mode switch, and writing the report.
//  Debug builds only.
//

#if DEBUG

import Foundation
#if canImport(UIKit)
import UIKit

extension DebugLaunch {

    /// Sets the view mode before any view reads it, in the saved setting the
    /// view menu writes to. It stays set after the launch, as a choice made
    /// from the menu would.
    static func applyViewMode(_ options: DebugLaunchOptions) {
        if let mode = options.mode {
            UserDefaults.standard.set(mode.rawValue, forKey: SettingKeys.Notes.viewMode.name)
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
                UserDefaults.standard.set(thenMode.rawValue, forKey: SettingKeys.Notes.viewMode.name)
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
