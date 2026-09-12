//
//  DocumentStyler.swift
//  NoteCode
//
//  Turns FenceParser's regions into visible styling on the text view.
//

#if canImport(UIKit)

import UIKit

enum DocumentStyler {

    // MARK: Attributes

    /// Body text. Tracks Dynamic Type because it's derived from the preferred
    /// body font rather than a hardcoded size.
    static var proseFont: UIFont {
        UIFont.preferredFont(forTextStyle: .body)
    }

    /// Monospaced at whatever size body currently is, so code scales with
    /// Dynamic Type alongside prose instead of staying fixed.
    static var codeFont: UIFont {
        UIFont.monospacedSystemFont(ofSize: proseFont.pointSize, weight: .regular)
    }

    static var proseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: proseFont,
            .foregroundColor: UIColor.label,
        ]
    }

    /// No `.backgroundColor` here on purpose. That attribute paints per glyph,
    /// which leaves the ragged right edge this project started with;
    /// CodeBlockLayoutFragment draws the panel at fragment level instead.
    static var codeAttributes: [NSAttributedString.Key: Any] {
        [
            .font: codeFont,
            .foregroundColor: UIColor.label,
        ]
    }

    /// Headings scale with Dynamic Type by mapping onto real text styles
    /// rather than hardcoded sizes.
    static func headingFont(level: Int) -> UIFont {
        let style: UIFont.TextStyle = switch level {
        case 1:  .largeTitle
        case 2:  .title1
        case 3:  .title2
        case 4:  .title3
        case 5:  .headline
        default: .subheadline
        }
        return UIFont.preferredFont(forTextStyle: style).withTraits(.traitBold)
    }

    static func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        [
            .font: headingFont(level: level),
            .foregroundColor: UIColor.label,
        ]
    }

    /// Markdown markers stay visible but recede, so the text reads as formatted
    /// without hiding what you'd need to edit. Hiding them only when the caret
    /// is elsewhere is a later refinement.
    static let markerColor = UIColor.tertiaryLabel

    /// How far each nesting level indents, on top of the whitespace the user
    /// actually typed.
    static let listIndentPerLevel: CGFloat = 16

    /// Indents a list item and, more importantly, aligns its wrapped lines
    /// under the content rather than under the bullet.
    /// Measuring text is not cheap and list markers repeat constantly — a
    /// document of bullets asks for the width of "- " hundreds of times.
    private static var markerWidths: [String: CGFloat] = [:]

    static func listParagraphStyle(for block: BlockNode, in source: String) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let depth = block.listDepth ?? 0
        let levelIndent = CGFloat(depth) * listIndentPerLevel

        // Width of the literal marker text, indentation included, so a wrapped
        // line starts exactly where the item's text does.
        let markerWidth: CGFloat = if let marker = block.markerRange {
            width(ofMarker: String(source[marker]))
        } else {
            0
        }

        style.firstLineHeadIndent = levelIndent
        style.headIndent = levelIndent + markerWidth
        return style
    }

    private static func width(ofMarker marker: String) -> CGFloat {
        if let cached = markerWidths[marker] { return cached }
        let width = (marker as NSString).size(withAttributes: [.font: proseFont]).width
        markerWidths[marker] = width
        return width
    }

    // MARK: Applying

    /// Re-styles the whole document from scratch.
    ///
    /// Deliberately not incremental. Fence detection is a single linear scan
    /// and a page of class notes is a few thousand characters, so the simple
    /// version is fast enough — and incremental re-styling is where this kind
    /// of editor usually goes to die. Revisit only if Instruments says to.
    ///
    /// Returns the regions it used, so callers don't have to parse twice.
    /// Convenience for callers without a cache of their own (tests, previews).
    /// The editor goes through the `regions:` variant so it parses once per edit.
    @discardableResult
    static func applyStyling(to textView: UITextView) -> [BlockNode] {
        let source = textView.text ?? ""
        let blocks = DocumentParser.parse(source)
        applyStyling(to: textView, source: source, blocks: blocks, previousSignatures: [])
        return blocks
    }

    /// - Parameter previousSignatures: what the document looked like last time
    ///   this ran. Only the blocks that differ get restyled; pass an empty array
    ///   to restyle everything.
    /// - Returns: signatures to hand back on the next call.
    @discardableResult
    /// - Parameter source: the exact string `blocks` were parsed from.
    ///
    ///   It must be the same String *instance*, not merely an equal one.
    ///   `UITextView.text` hands back a freshly bridged NSString-backed String
    ///   on every access, and using `String.Index` values across instances with
    ///   different backing storage forces index reconciliation on each use —
    ///   which turned a single restyle of a 500-line note into 600ms.
    static func applyStyling(
        to textView: UITextView,
        source: String,
        blocks: [BlockNode],
        previousSignatures: [BlockSignature] = []
    ) -> [BlockSignature] {
        // Rewriting attributes mid-composition destroys the marked-text
        // underline and can drop the in-progress character entirely, which
        // breaks Pinyin, Kana, and accent input.
        guard textView.markedTextRange == nil else { return previousSignatures }

        let storage = textView.textStorage
        let layouts = layouts(for: blocks, in: source)
        let signatures = layouts.map(\.signature)

        guard let changed = changedIndices(from: previousSignatures, to: signatures) else {
            return signatures
        }

        let touched = Array(layouts[changed])
        guard let first = touched.first, let last = touched.last else { return signatures }
        let span = NSRange(
            location: first.range.location,
            length: last.range.location + last.range.length - first.range.location
        )

        // Syntax colours already on screen, captured before the wipe below.
        //
        // `setAttributes` replaces rather than merges, so restyling blanks every
        // colour in the document. Highlighting is async and debounced, so that
        // left code with no colour at all for as long as the user kept typing —
        // in every block, not just the one being edited. NSTextStorage has
        // already migrated these ranges across the edit, so they are still
        // correct where the text didn't change.
        let existingColors = codeColors(in: storage, layouts: touched)

        storage.beginEditing()
        storage.setAttributes(proseAttributes, range: span)

        for layout in touched {
            switch layout.block.kind {
            case .code:
                storage.setAttributes(codeAttributes, range: layout.range)
                // The fence lines are markers like any other, so they recede
                // too — the code inside is what should carry the eye.
                for marker in layout.blockMarkers {
                    storage.addAttribute(.foregroundColor, value: markerColor, range: marker)
                }

            case .paragraph:
                apply(layout.inlines, over: proseFont, to: storage)

            case .listItem:
                storage.addAttribute(
                    .paragraphStyle,
                    value: listParagraphStyle(for: layout.block, in: source),
                    range: layout.range
                )
                apply(layout.inlines, over: proseFont, to: storage)
                for marker in layout.blockMarkers {
                    storage.addAttribute(.foregroundColor, value: markerColor, range: marker)
                }

            case .heading(let level, _):
                storage.setAttributes(headingAttributes(level: level), range: layout.range)
                apply(layout.inlines, over: headingFont(level: level), to: storage)
                for marker in layout.blockMarkers {
                    storage.addAttribute(.foregroundColor, value: markerColor, range: marker)
                }
            }
        }

        // Put the colours back. Newly typed characters aren't covered by any of
        // them and take the block's plain typing attributes, so they show up
        // uncoloured until the next highlight pass rather than inheriting the
        // colour of whatever they were typed after.
        for run in existingColors {
            storage.addAttribute(.foregroundColor, value: run.color, range: run.range)
        }

        storage.endEditing()

        return signatures
    }

    // MARK: Incremental restyling

    /// A cheap summary of a block — enough to tell whether its existing styling
    /// can be left alone.
    ///
    /// Length and kind catch most edits. `inlineHash` catches the ones they
    /// miss: replacing `xxbolxx` with `**bold**` keeps the block's kind and
    /// length identical while completely changing what it should look like.
    struct BlockSignature: Equatable {
        var kind: Int
        var length: Int
        var detail: Int
        var inlineHash: Int
    }

    /// Which blocks need restyling, as indices into the new list.
    ///
    /// Blocks are compared from both ends, so an edit in the middle of a
    /// document leaves the untouched blocks at either side alone. `nil` means
    /// nothing changed. NSTextStorage migrates attributes across text edits on
    /// its own, so blocks outside this range are already correct even though
    /// their offsets have moved.
    static func changedIndices(from old: [BlockSignature], to new: [BlockSignature]) -> Range<Int>? {
        guard !old.isEmpty else { return new.isEmpty ? nil : 0..<new.count }

        let overlap = min(old.count, new.count)

        var prefix = 0
        while prefix < overlap, old[prefix] == new[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < overlap - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }

        let lower = prefix
        let upper = new.count - suffix
        return lower < upper ? lower..<upper : nil
    }

    // MARK: Offsets

    /// A block and its spans, as UTF-16 ranges ready to hand to NSTextStorage.
    private struct BlockLayout {
        var block: BlockNode
        var range: NSRange
        var contentRange: NSRange
        var inlines: [InlineLayout]
        var signature: BlockSignature

        /// The block-level markers: a heading's hashes, a list bullet, or a
        /// code block's two fence lines.
        var blockMarkers: [NSRange] {
            var markers: [NSRange] = []

            let leadingLength = contentRange.location - range.location
            if leadingLength > 0 {
                markers.append(NSRange(location: range.location, length: leadingLength))
            }

            let trailingStart = contentRange.location + contentRange.length
            let trailingLength = range.location + range.length - trailingStart
            if trailingLength > 0 {
                markers.append(NSRange(location: trailingStart, length: trailingLength))
            }

            return markers
        }
    }

    private struct InlineLayout {
        var kind: InlineNode.Kind
        var contentRange: NSRange
        var markers: [NSRange]
    }

    /// Converts every range in the document to UTF-16 offsets in one forward pass.
    ///
    /// `NSRange(someRange, in: source)` measures the distance from the string's
    /// start index, so it costs O(offset) per call. Calling it once per block
    /// and once per inline span made styling quadratic in document length —
    /// 184ms for a 500-line note, on every keystroke. Blocks are contiguous and
    /// in order, and so are the inline spans inside them, so their lengths can
    /// simply be accumulated instead.
    private static func layouts(for blocks: [BlockNode], in source: String) -> [BlockLayout] {
        var layouts: [BlockLayout] = []
        layouts.reserveCapacity(blocks.count)

        var offset = 0

        for block in blocks {
            let blockLength = source[block.range].utf16.count
            let leadingLength = source[block.range.lowerBound..<block.contentRange.lowerBound].utf16.count
            let contentLength = source[block.contentRange].utf16.count

            let contentStart = offset + leadingLength
            var inlineOffset = contentStart
            var inlines: [InlineLayout] = []
            inlines.reserveCapacity(block.inlines.count)

            for inline in block.inlines {
                let inlineLength = source[inline.range].utf16.count
                let inlineLeading = source[inline.range.lowerBound..<inline.contentRange.lowerBound].utf16.count
                let inlineContent = source[inline.contentRange].utf16.count

                let content = NSRange(location: inlineOffset + inlineLeading, length: inlineContent)
                var markers: [NSRange] = []
                if inlineLeading > 0 {
                    markers.append(NSRange(location: inlineOffset, length: inlineLeading))
                }
                let trailingStart = content.location + content.length
                let trailingLength = inlineOffset + inlineLength - trailingStart
                if trailingLength > 0 {
                    markers.append(NSRange(location: trailingStart, length: trailingLength))
                }

                inlines.append(InlineLayout(kind: inline.kind, contentRange: content, markers: markers))
                inlineOffset += inlineLength
            }

            var inlineHash = 17
            for inline in inlines {
                inlineHash = inlineHash &* 31 &+ inline.kind.discriminant
                inlineHash = inlineHash &* 31 &+ inline.contentRange.length
            }

            layouts.append(
                BlockLayout(
                    block: block,
                    range: NSRange(location: offset, length: blockLength),
                    contentRange: NSRange(location: contentStart, length: contentLength),
                    inlines: inlines,
                    signature: BlockSignature(
                        kind: block.kindDiscriminant,
                        length: blockLength,
                        detail: block.styleDetail,
                        inlineHash: inlineHash
                    )
                )
            )

            offset += blockLength
        }

        return layouts
    }

    /// Snapshots the syntax colours currently inside code blocks.
    ///
    /// Only colours that differ from the default are worth carrying over, and
    /// only inside a code block's content — the dimmed fence lines are markers
    /// and get reapplied from scratch.
    private static func codeColors(in storage: NSTextStorage, layouts: [BlockLayout]) -> [ColorRun] {
        var preserved: [ColorRun] = []
        let defaultColor = UIColor.label

        for layout in layouts where layout.block.isCode {
            let range = layout.contentRange
            guard range.location >= 0, range.location + range.length <= storage.length else { continue }

            storage.enumerateAttribute(.foregroundColor, in: range) { value, subrange, _ in
                guard let color = value as? UIColor, color != defaultColor else { return }
                preserved.append(ColorRun(range: subrange, color: color))
            }
        }

        return preserved
    }

    /// Applies inline spans over a block whose base font is already set.
    ///
    /// Traits are derived from the block's own font rather than a fixed one, so
    /// bold inside a heading is a bold heading, not bold body text.
    private static func apply(_ inlines: [InlineLayout], over baseFont: UIFont, to storage: NSTextStorage) {
        for inline in inlines where inline.kind != .text {
            switch inline.kind {
            case .strong:
                storage.addAttribute(.font, value: baseFont.withTraits(.traitBold), range: inline.contentRange)
            case .emphasis:
                storage.addAttribute(.font, value: baseFont.withTraits(.traitItalic), range: inline.contentRange)
            case .inlineCode:
                storage.addAttribute(
                    .font,
                    value: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular),
                    range: inline.contentRange
                )
                // A per-glyph background is right here, unlike a code block —
                // an inline span is short and doesn't need to square off.
                storage.addAttribute(.backgroundColor, value: UIColor.secondarySystemFill, range: inline.contentRange)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: inline.contentRange)
            case .text:
                break
            }

            for marker in inline.markers {
                storage.addAttribute(.foregroundColor, value: markerColor, range: marker)
            }
        }
    }


    /// Paints syntax colours over already-styled text.
    ///
    /// Uses `addAttribute` rather than `setAttributes` so the monospace font
    /// and everything else the styling pass established survive. Colours are
    /// always additive and always land after a full restyle has reset
    /// foregrounds back to `.label`.
    /// - Parameter clearing: the code ranges these runs describe. Reset first,
    ///   in the same transaction, so a block that now produces fewer runs than
    ///   before — a changed language tag, say — doesn't keep stale colours on
    ///   the characters the new pass didn't cover.
    static func applyColors(_ runs: [ColorRun], clearing ranges: [NSRange], to textView: UITextView) {
        guard textView.markedTextRange == nil else { return }

        let storage = textView.textStorage
        let length = storage.length

        storage.beginEditing()

        for range in ranges where range.location >= 0 && range.location + range.length <= length {
            storage.addAttribute(.foregroundColor, value: UIColor.label, range: range)
        }

        for run in runs {
            // Defensive: an off-by-one here would trap, and the ranges came
            // from a snapshot of the document taken before an await.
            guard run.range.location >= 0,
                  run.range.length >= 0,
                  run.range.location + run.range.length <= length
            else { continue }

            storage.addAttribute(.foregroundColor, value: run.color, range: run.range)
        }
        storage.endEditing()
    }

    /// Sets the attributes newly typed characters will take on.
    ///
    /// Without this, UIKit inherits typing attributes from the character to the
    /// left of the caret — so the first thing typed after a code block comes out
    /// monospaced on a grey background. This is the "attribute bleed" problem;
    /// setting typing attributes from the *parsed* region under the caret is the
    /// fix, rather than letting the text system guess.
    static func applyTypingAttributes(to textView: UITextView, source: String, blocks: [BlockNode]) {
        let caret = textView.selectedRange.location

        let current = block(at: caret, in: source, blocks: blocks)

        switch current?.kind {
        case .code:
            // Carry the neighbouring syntax colour onto whatever is typed next.
            //
            // Highlighting is debounced, so without this the character just
            // typed sits uncoloured for as long as the debounce — you type the
            // `n` of `return` and watch it stay black next to five pink
            // letters. A briefly stale colour reads as stable; a black gap at
            // the caret reads as broken, and the next highlight pass corrects
            // either one.
            var attributes = codeAttributes
            if let inherited = inheritedCodeColor(at: caret, in: textView.textStorage) {
                attributes[.foregroundColor] = inherited
            }
            textView.typingAttributes = attributes
        case .heading(let level, _):
            textView.typingAttributes = headingAttributes(level: level)
        case .listItem:
            // Carry the indent, or text typed into a wrapped list line jumps
            // back to the margin.
            var attributes = proseAttributes
            attributes[.paragraphStyle] = listParagraphStyle(for: current!, in: source)
            textView.typingAttributes = attributes
        default:
            textView.typingAttributes = proseAttributes
        }
    }

    /// The colour of the character before the caret, when it makes sense to
    /// extend it onto the next one.
    ///
    /// Reads the storage directly rather than converting a `Range<String.Index>`
    /// — this runs on every caret move, and that conversion costs O(offset).
    private static func inheritedCodeColor(at caret: Int, in storage: NSTextStorage) -> UIColor? {
        guard caret > 0, caret - 1 < storage.length else { return nil }

        // A colour shouldn't carry onto a new line.
        guard storage.mutableString.character(at: caret - 1) != 0x0A else { return nil }

        guard let color = storage.attribute(.foregroundColor, at: caret - 1, effectiveRange: nil) as? UIColor,
              color != markerColor   // don't pick up a dimmed fence line
        else { return nil }

        return color
    }

    /// The block containing a UTF-16 offset, if any.
    ///
    /// Ranges are half-open, so a caret sitting exactly on the boundary between
    /// a code block and the prose after it belongs to the prose — which is what
    /// you want when typing just past a closing fence.
    static func block(at utf16Offset: Int, in source: String, blocks: [BlockNode]) -> BlockNode? {
        guard let index = Range(NSRange(location: utf16Offset, length: 0), in: source)?.lowerBound else {
            return nil
        }
        if index == source.endIndex {
            return blocks.last
        }
        return blocks.first { $0.range.contains(index) }
    }
}

private extension UIFont {
    /// Adds symbolic traits while keeping everything else about the font,
    /// including the Dynamic Type size it was resolved at.
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

#endif
