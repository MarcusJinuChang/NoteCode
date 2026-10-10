//
//  CodeFenceDisplay.swift
//  NoteCode
//
//  Showing a code block's backticks only while it is being edited.
//

#if canImport(UIKit)

import UIKit

/// Why this is drawn and never laid out: a fence line that disappears from
/// the text, or collapses to nothing, moves every line below it. That
/// re-breaks pages and leaves ink over the wrong words, and any change to the
/// text storage lays out everything below it again, on every caret move
/// (AGENTS.md, "Pages › Cost"). So an away block's fence lines keep their
/// height and their place, and `CodeBlockLayoutFragment` skips drawing their
/// glyphs. The language name that stands in for the opening fence is a view
/// (`CodeBlockLanguageButton`).
///
/// **Not a rendering attribute** (`NSTextLayoutManager.setRenderingAttributes`
/// with a clear foreground), which the first choice would have been. Measured
/// on the simulator (10 Oct, `CodeFenceDisplayTests.renderingAttribute`), it
/// does hide the glyphs and lay nothing out. But it follows an edit around
/// its range and not one inside it: the language menu replacing a tag drew the
/// new text, as did typing at the range's end. It would need setting again
/// after every edit that touches an away fence. The fragment asks at draw
/// time and keeps nothing to go stale, and printing and the ring use the same
/// answer.
extension DocumentTextView.Coordinator {

    /// Hands the coordinator the page's editor, and has it follow the editor's
    /// mode: ink mode takes every block's fences away, and nothing about the
    /// selection changes when it does.
    func connect(_ editor: NoteEditor?, to textView: UITextView) {
        self.editor = editor
        editor?.modeDidChange = { [weak self, weak textView] in
            guard let self, let textView else { return }
            refreshFenceVisibility(in: textView)
        }
        refreshFenceVisibility(in: textView)
    }

    /// Works out which blocks are being edited and redraws the ones that
    /// changed. Called on every selection change and edit, so the common
    /// case, a caret that stays in the same block or in prose, compares two
    /// small values and returns.
    ///
    /// - Parameter repositioning: whether to move the language buttons now.
    ///   `restyle` passes false and repositions through its own `update`.
    func refreshFenceVisibility(in textView: UITextView, repositioning: Bool = true) {
        let ranges = codeRanges(in: textView.textStorage)
        let wanted = FenceVisibility.at(
            selection: textView.selectedRange,
            in: ranges,
            mode: showMarkdown,
            isInk: editor?.mode == .ink
        )
        guard wanted != fenceVisibility else { return }

        let old = fenceVisibility
        fenceVisibility = wanted
        overlay?.fenceVisibility = wanted

        let changed: Set<Int> = wanted.showsEveryFence == old.showsEveryFence
            ? old.editing.symmetricDifference(wanted.editing)
            : Set(ranges.indices)
        redrawFences(ofBlocks: changed, ranges: ranges, in: textView)
        if repositioning {
            overlay?.reposition()
        }
    }

    /// How a fragment of the block it is in should be drawn, now.
    ///
    /// Asked at draw time and not when the fragment is made: the answer
    /// changes with the caret while the fragment isn't laid out again. The
    /// block is found from the fragment's place in the note as it is now,
    /// since an edit above it moves it without touching the fragment.
    func fenceDisplay(for fragment: NSTextLayoutFragment, in storage: NSTextStorage) -> FenceDisplay {
        guard let contentManager = fragment.textLayoutManager?.textContentManager else {
            return FenceDisplay(showsFences: true, isEditing: false)
        }
        let offset = contentManager.offset(
            from: contentManager.documentRange.location,
            to: fragment.rangeInElement.location
        )
        guard let block = FenceVisibility.blockIndex(containing: offset, in: codeRanges(in: storage)) else {
            return FenceDisplay(showsFences: true, isEditing: false)
        }
        return FenceDisplay(
            showsFences: fenceVisibility.showsFences(ofBlock: block),
            isEditing: fenceVisibility.isEditing(block: block)
        )
    }

    /// Marks the on-screen fragment views of `blocks` as needing display.
    ///
    /// Drawing only, as `updateCodeSelectionHighlight` does it: a fragment
    /// view keeps what it drew until told otherwise, and
    /// `invalidateRenderingAttributes` never tells it. Only fragments TextKit
    /// has laid out in the viewport are looked at, so a caret move forces no
    /// layout; a block scrolled out of view draws its state when it comes
    /// back, since the fragment asks at draw time.
    private func redrawFences(ofBlocks blocks: Set<Int>, ranges: [CodeRange], in textView: UITextView) {
        guard !blocks.isEmpty,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange
        else { return }

        var dirty: [Int: CGRect] = [:]
        let documentStart = contentManager.documentRange.location
        layoutManager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
            let start = fragment.rangeInElement.location
            guard start.compare(viewport.endLocation) != .orderedDescending else { return false }

            let offset = contentManager.offset(from: documentStart, to: start)
            if let block = FenceVisibility.blockIndex(containing: offset, in: ranges), blocks.contains(block) {
                let frame = fragment.layoutFragmentFrame
                let drawn = fragment.renderingSurfaceBounds.offsetBy(dx: frame.minX, dy: frame.minY)
                dirty[block] = (dirty[block] ?? .null).union(frame.union(drawn))
            }
            return true
        }

        // Container coordinates to the text view's.
        let inset = textView.textContainerInset
        for rect in dirty.values {
            Self.redraw(
                fragmentViewsIn: textView,
                intersecting: rect.offsetBy(dx: inset.left, dy: inset.top).insetBy(dx: -2, dy: -2)
            )
        }
    }

    // MARK: Language

    /// Points a block's opening fence at `language`, `nil` for plain text.
    ///
    /// Through `replace(_:withText:)`, the path typing takes, so it is
    /// undoable and the text restyles; the block's Run follows, since its
    /// language is read from the text again.
    func setLanguage(_ language: CodeLanguage?, of target: CodeBlockTarget, in textView: UITextView) {
        guard textView.isEditable else { return }

        let text = textView.textStorage.string as NSString
        guard target.range.location < text.length else { return }
        let line = text.lineRange(for: NSRange(location: target.range.location, length: 0))

        guard let edit = FenceTag.retag(line: text.substring(with: line), as: language),
              let start = textView.position(from: textView.beginningOfDocument, offset: line.location + edit.range.location),
              let end = textView.position(from: start, offset: edit.range.length),
              let range = textView.textRange(from: start, to: end)
        else { return }

        // The replacement leaves the caret at its end, inside the fence, which
        // would put the block in editing and show the fence the pick was
        // made from. The edit is a menu pick, not typing: the caret stays
        // where it was, moved by what the edit added or took away.
        let editAt = line.location + edit.range.location
        let delta = (edit.replacement as NSString).length - edit.range.length
        var selection = textView.selectedRange
        if selection.location >= editAt + edit.range.length {
            selection.location += delta
        } else if NSMaxRange(selection) > editAt + edit.range.length {
            selection.length += delta
        }

        isRetagging = true
        textView.replace(range, withText: edit.replacement)
        isRetagging = false
        textView.selectedRange = selection
    }
}

#endif
