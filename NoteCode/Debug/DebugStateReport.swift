//
//  DebugStateReport.swift
//  NoteCode
//
//  What's on screen once layout settles, written by `DebugSession` for a
//  debug launch's `-debug-report`. Debug builds only.
//

#if DEBUG

import Foundation
#if canImport(UIKit)
import UIKit
#endif

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
    /// The point size of the text at the top of the view, as laid out: what a
    /// note's text size comes to on screen (a heading is larger).
    var topLinePoints: Double?
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

    /// Where the window is laid out, for the iPhone and the Duo (roadmap step
    /// 11): `compact` or `regular`, the window's size in points, and how far
    /// the page is scrolled sideways (a page fitted by its text column is
    /// centred).
    var sizeClass: String?
    var windowSize: [Double]?
    var horizontalOffset: Double?

    /// A fold the window reports (iOS 27.1, `reservedRegions(kind:
    /// .division)`), in window points, inactive ones included.
    struct Fold: Codable, Equatable, Sendable {
        var frame: [Double]
        var isActive: Bool
    }
    var folds: [Fold]?
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
        self.sizeClass = page.traitCollection.horizontalSizeClass == .compact ? "compact" : "regular"
        self.horizontalOffset = Double(page.contentOffset.x)
        if let window = page.window {
            self.windowSize = [Double(window.bounds.width), Double(window.bounds.height)]
            if #available(iOS 27.1, *) {
                self.folds = window.reservedRegions(kind: .division, options: .includeInactive).map {
                    Fold(
                        frame: [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height].map(Double.init),
                        isActive: $0.isActive
                    )
                }
            }
        }

        if let character = page.topLineCharacter(), let top = page.lineTop(atCharacter: character) {
            let index = layout.pageIndex(atY: top)
            let text = (textView.text ?? "") as NSString
            let start = min(character, text.length)
            let newline = text.range(of: "\n", range: NSRange(location: start, length: text.length - start)).location
            let end = newline == NSNotFound ? text.length : newline
            topLinePoints = start < text.length
                ? (textView.textStorage.attribute(.font, at: start, effectiveRange: nil) as? UIFont).map { Double($0.pointSize) }
                : nil
            topLine = TopLine(
                character: character,
                page: index + 1,
                startsPage: top - layout.bodyTop(ofPage: index) < 1,
                text: text.substring(with: NSRange(location: start, length: min(end - start, 60)))
            )
        } else {
            topLine = nil
            topLinePoints = nil
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
                // The glyphs' line, without a tall paragraph's gap above it.
                let top = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + line.pageLineGap + textView.textContainerInset.top
                let bottom = fragment.layoutFragmentFrame.minY + line.typographicBounds.maxY + textView.textContainerInset.top
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

#endif
#endif
