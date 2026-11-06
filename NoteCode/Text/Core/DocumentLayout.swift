//
//  DocumentLayout.swift
//  NoteCode
//
//  The parser's blocks as UTF-16 ranges, and which of them changed. Pure: no UIKit, no TextKit.
//

#if canImport(UIKit)

import Foundation

extension DocumentStyler {
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
    struct BlockLayout {
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

    /// An inline node as UTF-16 offsets: its kind, its characters, and
    /// what it is drawn with.
    struct InlineLayout {
        var kind: InlineNode.Kind
        var range: NSRange
        var attributes: InlineAttributes

        /// A marker's characters, which a rendered note lays out at no width
        /// (`MarkdownLayout`) and the styler dims; none for text.
        nonisolated var markers: [NSRange] { kind.isMarker ? [range] : [] }
    }

    /// Converts every range in the document to UTF-16 offsets in one forward pass.
    ///
    /// `NSRange(someRange, in: source)` measures the distance from the string's
    /// start index, so it costs O(offset) per call. Calling it once per block
    /// and once per inline span made styling quadratic in document length —
    /// 184ms for a 500-line note, on every keystroke. Blocks are contiguous and
    /// in order, and so are the inline spans inside them, so their lengths can
    /// simply be accumulated instead.
    nonisolated static func layouts(for blocks: [BlockNode], in source: String) -> [BlockLayout] {
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
                inlines.append(InlineLayout(
                    kind: inline.kind,
                    range: NSRange(location: inlineOffset, length: inlineLength),
                    attributes: inline.attributes
                ))
                inlineOffset += inlineLength
            }

            // What the text is drawn with is in it, since a recolour or a
            // change of nesting can keep every length the same.
            var inlineHash = 17
            for inline in inlines {
                inlineHash = inlineHash &* 31 &+ inline.kind.discriminant
                inlineHash = inlineHash &* 31 &+ inline.range.length
                inlineHash = inlineHash &* 31 &+ inline.attributes.signature
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
}

#endif
