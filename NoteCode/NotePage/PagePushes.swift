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
    /// - Returns: the bottom of the last line, and the pages whose breaks it
    ///   crosses.
    static func linePlacement(top: CGFloat, lineHeights: [CGFloat], layout: PageLayout) -> (bottom: CGFloat, pages: [Int]) {
        var y = top
        var pages: [Int] = []
        for height in lineHeights {
            let offset = y - layout.firstBodyTop
            let page = (offset / layout.pitch).rounded(.down)
            let into = offset - page * layout.pitch
            if into >= layout.bodyHeight - tolerance
                || (into + height > layout.bodyHeight + tolerance && height <= layout.bodyHeight) {
                y += layout.pitch - into
                pages.append(Int(page))
            }
            y += height
        }
        return (y, pages)
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

    /// Paragraph start to the pages whose breaks run through it: the
    /// paragraphs taller than a page, which need exclusion paths.
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

    func set(tall pages: [Int]?, at offset: Int) {
        tall[offset] = pages
    }

    func restart() {
        through = 0
        changingPasses = 0
    }

    /// Forgets every push and starts again from the top.
    func reset() {
        pushes = [:]
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
        func moved<T>(_ table: [Int: T]) -> [Int: T] {
            var result: [Int: T] = [:]
            for (offset, value) in table {
                if offset <= range.location {
                    result[offset] = value
                } else if offset > oldEnd {
                    result[offset + delta] = value
                }
            }
            return result
        }
        pushes = moved(pushes)
        tall = moved(tall)
    }
}

#endif
