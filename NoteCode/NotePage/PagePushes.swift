//
//  PagePushes.swift
//  NoteCode
//
//  Page breaks by moving whole paragraphs, not by exclusion paths (F5).
//

#if canImport(UIKit)

import UIKit

extension NSAttributedString.Key {
    /// How far a paragraph was pushed down by `PagePaginator`, on the copy of
    /// the paragraph TextKit lays out. Never in the text storage.
    static let pagePush = NSAttributedString.Key("NoteCode.pagePush")
    /// The part of that push which is the break itself (`PageLayout.gap`),
    /// as opposed to the unused room at the foot of the page before it.
    static let pageGap = NSAttributedString.Key("NoteCode.pageGap")
    /// The page break laid in above one line of a paragraph taller than a
    /// page, on the characters of that line in the copy TextKit lays out
    /// (D9, docs/design/paged-typing-cost.md › C). The same distance is in
    /// the copy's `.baselineOffset` there, which is what moves the glyphs;
    /// this says how much of that offset is the break, for whatever places
    /// things by the offset or by the line's top. Never in the text storage.
    static let pageLineGap = NSAttributedString.Key("NoteCode.pageLineGap")
    /// How far that line's glyphs were moved down: the whole of the offset
    /// laid in, which is the gap plus what the line's minimum height took up
    /// (`PagePaginator.slack(of:in:)`), and the gap alone without line spacing.
    static let pageLineShift = NSAttributedString.Key("NoteCode.pageLineShift")
}

extension NSTextLineFragment {
    /// The page break above this line's glyphs (`.pageLineGap`), 0 on all
    /// but the first line after a break in a paragraph taller than a page.
    ///
    /// On such a line the typographic bounds start that far above the
    /// glyphs, where the line before it ended, and `glyphOrigin` leaves the
    /// gap out, so it reads that much too high (stage 0's finding). The
    /// glyphs' line top is `typographicBounds.minY + pageLineGap`, and their
    /// baseline `typographicBounds.minY + glyphOrigin.y + pageLineShift`.
    var pageLineGap: CGFloat { largest(.pageLineGap) }

    /// How far this line's glyphs were moved down from where `glyphOrigin`
    /// puts them (`.pageLineShift`): the gap, and with line spacing on a
    /// little more.
    var pageLineShift: CGFloat { largest(.pageLineShift) }

    private func largest(_ key: NSAttributedString.Key) -> CGFloat {
        let string = attributedString
        let range = NSIntersectionRange(characterRange, NSRange(location: 0, length: string.length))
        guard range.length > 0 else { return 0 }
        var largest: CGFloat = 0
        string.enumerateAttribute(key, in: range) { value, _, _ in
            if let value = value as? Double { largest = max(largest, CGFloat(value)) }
        }
        return largest
    }
}

/// Where a paragraph falls against the pages, as a pure function.
///
/// A paragraph is never split: if its last line would end below its page's
/// body it starts the next page, whatever its first lines would have fitted.
/// (Page breaks used to be exclusion paths, which push single lines; they
/// made TextKit lay out everything below an edit — docs/design/pages.md ›
/// Cost.) A paragraph taller than a page's body can't start a page and fit
/// it, so it stays where it is and its lines are pushed one at a time.
nonisolated enum PageBreakRule {

    enum Placement: Equatable {
        /// Stays where it is.
        case fits
        /// Moves down this far, to the top of the next page's body.
        case push(CGFloat)
        /// Taller than a body: stays, and its lines are pushed (`linePlacement`).
        case tall
    }

    /// Slack for float error: a paragraph ending 0.01pt over the body fits.
    static let tolerance: CGFloat = 0.01

    /// - Parameters:
    ///   - top: the paragraph's top, in note coordinates, before any push.
    ///   - lastLineBottom: the bottom of its last line, same coordinates.
    static func placement(top: CGFloat, lastLineBottom: CGFloat, layout: PageLayout) -> Placement {
        let offset = top - layout.firstBodyTop
        guard offset > -tolerance else { return .fits }
        let page = (offset / layout.pitch).rounded(.down)
        let into = offset - page * layout.pitch
        let height = lastLineBottom - top
        // Starting in a break: the next page, however tall it is.
        if into >= layout.bodyHeight - tolerance && height > tolerance {
            return .push(layout.pitch - into)
        }
        if into + height <= layout.bodyHeight + tolerance { return .fits }
        if height > layout.bodyHeight + tolerance { return .tall }
        return .push(layout.pitch - into)
    }

    /// Where a tall paragraph's lines end up when each is pushed past the
    /// breaks it would cross, from the paragraph's top.
    ///
    /// - Returns: the bottom of the last line; the gap laid in above each
    ///   line that is pushed, by the line's index: the distance from where it
    ///   would start to the top of the next page's body; and the pages whose
    ///   breaks the paragraph crosses.
    static func linePlacement(top: CGFloat, lineHeights: [CGFloat], layout: PageLayout) -> (bottom: CGFloat, gaps: [Int: CGFloat], pages: [Int]) {
        var y = top
        var gaps: [Int: CGFloat] = [:]
        var pages: [Int] = []
        for (index, height) in lineHeights.enumerated() {
            let offset = y - layout.firstBodyTop
            let page = (offset / layout.pitch).rounded(.down)
            let into = offset - page * layout.pitch
            if into >= layout.bodyHeight - tolerance
                || (into + height > layout.bodyHeight + tolerance && height <= layout.bodyHeight) {
                gaps[index] = layout.pitch - into
                pages.append(Int(page))
                y += layout.pitch - into
            }
            y += height
        }
        return (y, gaps, pages)
    }
}

/// One line's page break, in `PagePushTable`: the line's length, the gap
/// above it, and the baseline offset that makes the line grow by the gap.
struct PageLineGap: Equatable {
    var length: Int
    var gap: CGFloat
    /// The offset laid in: the gap, and with line spacing on a little more,
    /// since the paragraph's minimum line height takes up part of an offset
    /// before the line grows (`PagePaginator.LineMeasure`).
    var shift: CGFloat

    /// How far a measured shift may be from the one laid in before the
    /// paragraph is laid out again: the measurement comes from font metrics
    /// where the line did not grow, a few hundredths of a point out.
    static let shiftTolerance: CGFloat = 0.25

    func matches(_ other: PageLineGap) -> Bool {
        length == other.length && abs(gap - other.gap) <= PageBreakRule.tolerance
            && abs(shift - other.shift) <= Self.shiftTolerance
    }
}

/// The pushes in force, by the offset each paragraph starts at, and how far
/// down the note they are known to be right.
///
/// Offsets are kept true across edits by watching the text storage, so a
/// paragraph keeps its push when text is typed above it.
final class PagePushTable: NSObject {

    /// Paragraph start (UTF-16) to the push it is laid out with.
    private(set) var pushes: [Int: CGFloat] = [:]

    /// Line start (UTF-16) to the break laid in above that line, for the
    /// paragraphs taller than a page (`PageBreakRule.linePlacement`). A
    /// handful in a note that has any, and none in most.
    private(set) var gaps: [Int: PageLineGap] = [:]

    /// Paragraph start to the pages whose breaks run through it, for the
    /// paragraphs taller than a page whose lines are a fixed height: a code
    /// line or a display formula's source that wraps past a page. A baseline
    /// offset moves a fixed-height line's glyphs without making it taller, so
    /// a gap can't break them, and these keep the exclusion paths (with
    /// their cost) that every tall paragraph had before D9.
    private(set) var tall: [Int: [Int]] = [:]

    /// Everything before this offset is known to be paginated. `Int.max`: the
    /// whole note.
    var through = 0

    /// The layout the pushes belong to; a different one starts again.
    var layout: PageLayout?

    /// Passes in a row that changed something, so a layout that will not
    /// settle gives up instead of looping.
    var changingPasses = 0

    /// True while the paginator edits the storage to lay a paragraph out
    /// again, which is no change of text.
    var isApplying = false

    func push(at offset: Int) -> CGFloat { pushes[offset] ?? 0 }

    func set(push: CGFloat, at offset: Int) {
        if push > 0 { pushes[offset] = push } else { pushes[offset] = nil }
    }

    /// The gaps of the lines starting in `range`.
    func gaps(in range: NSRange) -> [Int: PageLineGap] {
        guard !gaps.isEmpty else { return [:] }
        return gaps.filter { NSLocationInRange($0.key, range) }
    }

    /// Whether the gaps of the lines starting in `range` are `wanted`.
    func gaps(in range: NSRange, match wanted: [Int: PageLineGap]) -> Bool {
        let current = gaps(in: range)
        guard current.count == wanted.count else { return false }
        return wanted.allSatisfy { offset, gap in current[offset]?.matches(gap) == true }
    }

    /// The pages a paragraph's breaks run through, for the paragraph in
    /// `range`: any other entry inside it is one an edit left there (a join),
    /// and goes.
    func set(tall pages: [Int]?, inParagraph range: NSRange) {
        if !tall.isEmpty {
            for offset in tall.keys where NSLocationInRange(offset, range) && offset != range.location {
                tall[offset] = nil
            }
        }
        tall[range.location] = pages
    }

    /// Drops the `tall` entries `isStale` says no longer start a paragraph.
    func dropTall(where isStale: (Int) -> Bool) {
        guard !tall.isEmpty else { return }
        for offset in tall.keys where isStale(offset) { tall[offset] = nil }
    }

    /// Replaces the gaps of the lines starting in `range`.
    func set(gaps wanted: [Int: PageLineGap], in range: NSRange) {
        for offset in gaps(in: range).keys { gaps[offset] = nil }
        for (offset, gap) in wanted { gaps[offset] = gap }
    }

    func restart() {
        through = 0
        changingPasses = 0
    }

    /// Forgets every push and starts again from the top.
    func reset() {
        pushes = [:]
        gaps = [:]
        tall = [:]
        layout = nil
        restart()
    }

    func observe(_ storage: NSTextStorage) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storageDidProcessEditing),
            name: NSTextStorage.didProcessEditingNotification,
            object: storage
        )
    }

    @objc private func storageDidProcessEditing(_ notification: Notification) {
        guard !isApplying, let storage = notification.object as? NSTextStorage else { return }
        edited(storage.editedRange, changeInLength: storage.changeInLength)
    }

    /// Keeps the offsets true after an edit. `range` is the edited range as
    /// it is now, `delta` the change in length. An edit that changes no
    /// length (attributes, say) moves nothing, but what is below it may have
    /// changed height, so it is paginated again.
    func edited(_ range: NSRange, changeInLength delta: Int) {
        through = min(through, range.location)
        changingPasses = 0
        guard delta != 0 else { return }
        let oldEnd = range.location + range.length - delta
        // What starts at the old end of the edited range, or past it, is
        // intact and moves with the text; only what started inside the range
        // is gone. When a deletion brings an entry at the old end onto one at
        // the edit, the moved one wins: what starts there now is what
        // started at the old end.
        func moved<T>(_ table: [Int: T]) -> [Int: T] {
            var result: [Int: T] = [:]
            for (offset, value) in table where offset <= range.location {
                result[offset] = value
            }
            for (offset, value) in table where offset > range.location && offset >= oldEnd {
                result[offset + delta] = value
            }
            return result
        }
        pushes = moved(pushes)
        tall = moved(tall)
        guard !gaps.isEmpty else { return }
        // A line's gap covers its characters, so a line the edit is inside
        // grows or shrinks with it. The paginator puts the gaps right once
        // the paragraph is laid out again, if its lines wrap differently.
        var result: [Int: PageLineGap] = [:]
        for (offset, var gap) in gaps where offset <= range.location {
            if offset + gap.length >= range.location {
                gap.length = max(min(gap.length, range.location - offset) + range.length
                                 + max(offset + gap.length - oldEnd, 0), 0)
            }
            result[offset] = gap
        }
        for (offset, gap) in gaps where offset > range.location && offset >= oldEnd {
            result[offset + delta] = gap
        }
        gaps = result
    }
}

#endif
