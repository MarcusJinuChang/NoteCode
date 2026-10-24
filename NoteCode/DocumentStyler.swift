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

    /// The fonts at the default size, which is every note's unless it was
    /// resized (`NoteTypography`). The note body does not follow Dynamic Type
    /// (Phase 9): its size is part of its pagination, and a larger body
    /// re-wraps every line and moves the page breaks while ink stays where it
    /// was drawn. A note's own size is chosen on the note, from the text
    /// options row, and asks first when the note has ink.
    static var proseFont: UIFont { NoteTypography.standard.prose }
    static var codeFont: UIFont { NoteTypography.standard.code }

    static func headingFont(level: Int, typography: NoteTypography = .standard) -> UIFont {
        typography.heading(level: level)
    }

    static func proseAttributes(_ typography: NoteTypography = .standard) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: typography.prose,
            .foregroundColor: UIColor.label,
        ]
        // Only with spacing, so a note with none is styled as it always was.
        if typography.lineSpacing > 0 {
            attributes[.paragraphStyle] = typography.lineStyle(for: typography.prose)
        }
        return attributes
    }

    /// No `.backgroundColor` here on purpose. That attribute paints per glyph,
    /// which leaves the ragged right edge this project started with;
    /// CodeBlockLayoutFragment draws the panel at fragment level instead.
    ///
    /// The paragraph style is a code line's height (`CodeBlockRoom`), here
    /// rather than added after, so a line made by typing Return in a block
    /// is as tall as its neighbours before the restyle reaches it. Its
    /// continuation indent is an unindented line's; `applyCodeLineIndents`
    /// gives each line its own.
    static func codeAttributes(_ typography: NoteTypography = .standard) -> [NSAttributedString.Key: Any] {
        [
            .font: typography.code,
            .foregroundColor: UIColor.label,
            .paragraphStyle: unindentedCodeLine(typography),
        ]
    }

    /// An output block's text: light on its dark panel, in both appearances.
    static func outputAttributes(_ typography: NoteTypography = .standard) -> [NSAttributedString.Key: Any] {
        [
            .font: typography.code,
            .foregroundColor: CodeOutputPanel.textColor,
            .paragraphStyle: unindentedCodeLine(typography),
        ]
    }

    private static func unindentedCodeLine(_ typography: NoteTypography) -> NSParagraphStyle {
        CodeBlockRoom.codeLine(
            height: typography.codeLineHeight,
            continuation: CodeBlockRoom.continuationIndent(leading: 0, advance: CodeBlockRoom.advance(of: typography.code))
        )
    }

    static func headingAttributes(level: Int, typography: NoteTypography = .standard) -> [NSAttributedString.Key: Any] {
        let font = typography.heading(level: level)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
        ]
        if typography.lineSpacing > 0 {
            attributes[.paragraphStyle] = typography.lineStyle(for: font)
        }
        return attributes
    }

    /// Markdown markers stay visible but recede, so the text reads as formatted
    /// without hiding what you'd need to edit. Hiding them only when the caret
    /// is elsewhere is a later refinement.
    static let markerColor = UIColor.tertiaryLabel

    /// Link text: the accent as text, darker on light and lighter on dark
    /// (`AccentPalette.textHex`). Read from the stored accent each time the
    /// colour is resolved, so a new accent shows on the next redraw
    /// (`DocumentUITextView.tintColorDidChange`) with no restyle: the
    /// attribute is this one object either way.
    static let linkColor = UIColor { traits in
        AccentPalette.uiColor(AccentPalette.linkHex(isDark: traits.userInterfaceStyle == .dark))
    }

    /// How far each nesting level indents, on top of the whitespace the user
    /// actually typed.
    static let listIndentPerLevel: CGFloat = 16

    /// Indents a list item and, more importantly, aligns its wrapped lines
    /// under the content rather than under the bullet.
    /// Measuring text is not cheap and list markers repeat constantly — a
    /// document of bullets asks for the width of "- " hundreds of times.
    ///
    /// Keyed by the size too: a marker is wider in a larger body, and notes
    /// of different sizes are styled in one process.
    private static var markerWidths: [String: CGFloat] = [:]

    static func listParagraphStyle(
        for block: BlockNode,
        in source: String,
        rendered: Bool = false,
        typography: NoteTypography = .standard
    ) -> NSParagraphStyle {
        let style = typography.lineStyle(for: typography.prose)
        let depth = block.listDepth ?? 0
        let levelIndent = CGFloat(depth) * listIndentPerLevel

        // Width of the literal marker text, indentation included, so a wrapped
        // line starts exactly where the item's text does.
        let markerWidth: CGFloat = if let marker = block.markerRange {
            width(ofMarker: laidOutMarker(String(source[marker]), of: block, rendered: rendered), typography: typography)
        } else {
            0
        }

        style.firstLineHeadIndent = levelIndent
        style.headIndent = levelIndent + markerWidth
        return style
    }

    /// The marker as TextKit lays it out, so a wrapped line hangs under the
    /// words: a rendered note's `- ` is `• `, and a checkbox item's marker is
    /// the box's em space and the gap after it. Indentation stays as typed.
    private static func laidOutMarker(_ marker: String, of block: BlockNode, rendered: Bool) -> String {
        guard rendered, let kind = block.listMarker else { return marker }
        let indent = marker.prefix { $0 == " " || $0 == "\t" }
        switch kind {
        case .ordered:  return marker
        case .bullet:   return indent + "\(MarkdownLayout.bullet) "
        case .checkbox: return indent + "\(MarkdownLayout.box) "
        }
    }

    private static func width(ofMarker marker: String, typography: NoteTypography) -> CGFloat {
        let key = "\(typography.bodySize)|\(marker)"
        if let cached = markerWidths[key] { return cached }
        let width = (marker as NSString).size(withAttributes: [.font: typography.prose]).width
        markerWidths[key] = width
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
    static func applyStyling(to textView: UITextView, rendered: Bool = false, typography: NoteTypography = .standard) -> [BlockNode] {
        let source = (textView.text ?? "").nativeUTF8
        let blocks = DocumentParser.parse(source)
        applyStyling(to: textView, source: source, blocks: blocks, previousSignatures: [], rendered: rendered, typography: typography)
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
        previousSignatures: [BlockSignature] = [],
        rendered: Bool = false,
        typography: NoteTypography = .standard
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

        // Worked out on a copy, and written only where it differs.
        //
        // Setting attributes is an edit even when they're the ones already
        // there, and with page breaks as exclusion paths TextKit then lays out
        // everything below the edited paragraph again. A keystroke in prose
        // usually leaves its paragraph styled exactly as it was — the typed
        // character takes the typing attributes — so restyling it cost a
        // second full layout of the note below the caret on every keystroke
        // (sampled on the simulator, 25 September).
        let styled = NSMutableAttributedString(attributedString: storage)
        styled.setAttributes(proseAttributes(typography), range: span)

        for layout in touched {
            switch layout.block.kind {
            case .code(let code):
                let output = code.isOutput
                styled.setAttributes(output ? outputAttributes(typography) : codeAttributes(typography), range: layout.range)
                // The fence lines are markers like any other, so they recede
                // too — the code inside is what should carry the eye. On an
                // output block's dark panel the usual marker grey would sink
                // into it, so they take the panel's own label colour.
                for marker in layout.blockMarkers {
                    styled.addAttribute(.foregroundColor, value: output ? CodeOutputPanel.labelColor : markerColor, range: marker)
                }
                // The fences last, so nothing else's style can land on them.
                applyCodeLineIndents(to: styled, code: layout.contentRange, typography: typography)
                applyFenceRoom(to: styled, block: layout.range, isClosed: code.isClosed, font: typography.code)

            case .paragraph:
                apply(layout.inlines, over: typography.prose, to: styled)

            case .listItem(_, let marker, _):
                styled.addAttribute(
                    .paragraphStyle,
                    value: listParagraphStyle(for: layout.block, in: source, rendered: rendered, typography: typography),
                    range: layout.range
                )
                apply(layout.inlines, over: typography.prose, to: styled)
                for range in layout.blockMarkers {
                    styled.addAttribute(.foregroundColor, value: markerColor, range: range)
                }
                // A ticked item is done: struck through, and quieter.
                if marker == .checkbox(checked: true), layout.contentRange.length > 0 {
                    let content = trimmingNewline(layout.contentRange, in: source, of: layout)
                    styled.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: content)
                    styled.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
                }

            case .heading(let level, _):
                styled.setAttributes(headingAttributes(level: level, typography: typography), range: layout.range)
                apply(layout.inlines, over: typography.heading(level: level), to: styled)
                for marker in layout.blockMarkers {
                    styled.addAttribute(.foregroundColor, value: markerColor, range: marker)
                }

            case .blockQuote(let depth, _):
                // Indented past its bar, which its fragment draws. Whole
                // paragraphs, as a list item's style is: the storage makes a
                // paragraph's characters share its first one's.
                styled.addAttribute(.paragraphStyle, value: ProseBlockMetrics.quoteParagraphStyle(depth: depth, typography: typography), range: layout.range)
                apply(layout.inlines, over: typography.prose, to: styled)
                for marker in layout.blockMarkers {
                    styled.addAttribute(.foregroundColor, value: markerColor, range: marker)
                }

            case .rule:
                // An ordinary line of text with its dashes hidden; its
                // fragment draws the line through it.
                for marker in layout.blockMarkers {
                    styled.addAttribute(.foregroundColor, value: markerColor, range: marker)
                }
            }
        }

        // Put the colours back. Newly typed characters aren't covered by any of
        // them and take the block's plain typing attributes, so they show up
        // uncoloured until the next highlight pass rather than inheriting the
        // colour of whatever they were typed after.
        for run in existingColors {
            styled.addAttribute(.foregroundColor, value: run.color, range: run.range)
        }

        let wanted = styled.attributedSubstring(from: span)
        guard !wanted.isEqual(to: storage.attributedSubstring(from: span)) else {
            return signatures
        }

        storage.beginEditing()
        wanted.enumerateAttributes(in: NSRange(location: 0, length: wanted.length)) { attributes, range, _ in
            storage.setAttributes(attributes, range: NSRange(location: span.location + range.location, length: range.length))
        }
        storage.endEditing()

        return signatures
    }

    /// Gives a code block's fence lines their room: the opening fence the gap
    /// above the panel and its header, the closing fence the footer and the
    /// gap below (`CodeBlockRoom`).
    ///
    /// The fences are found as paragraphs, the block's first and, when it is
    /// closed, its last: a paragraph style belongs to a whole paragraph, and
    /// the block's markers end where its code begins rather than at a newline.
    private static func applyFenceRoom(to styled: NSMutableAttributedString, block: NSRange, isClosed: Bool, font: UIFont) {
        guard block.length > 0 else { return }
        let string = styled.string as NSString

        func apply(_ style: CodeBlockRoom.LineStyle, to paragraph: NSRange) {
            styled.addAttribute(.paragraphStyle, value: style.paragraph, range: paragraph)
            styled.addAttribute(.baselineOffset, value: style.baselineOffset, range: paragraph)
        }

        let opening = string.paragraphRange(for: NSRange(location: block.location, length: 0))
        apply(CodeBlockRoom.openingFence(font: font), to: opening)

        guard isClosed else { return }
        let closing = string.paragraphRange(for: NSRange(location: block.location + block.length - 1, length: 0))
        guard closing.location > opening.location else { return }
        apply(CodeBlockRoom.closingFence(font: font), to: closing)
    }

    /// Gives each line of code its own continuation indent: a line that
    /// wraps continues past its own indentation (`CodeBlockRoom`), so the
    /// rest of it never reads as the next line.
    ///
    /// Whole paragraphs, newline included: a paragraph style belongs to a
    /// paragraph, the storage makes every character of one take its first
    /// character's, and a newline left with another would differ from the
    /// storage on every restyle and be written, and laid out, every time.
    private static func applyCodeLineIndents(to styled: NSMutableAttributedString, code: NSRange, typography: NoteTypography) {
        guard code.length > 0 else { return }
        let string = styled.string as NSString
        let advance = CodeBlockRoom.advance(of: typography.code)
        let height = typography.codeLineHeight
        var styles: [CGFloat: NSParagraphStyle] = [:]

        string.enumerateSubstrings(in: string.paragraphRange(for: code), options: .byParagraphs) { line, _, paragraph, _ in
            guard let line else { return }
            let continuation = CodeBlockRoom.continuationIndent(
                leading: CodeBlockRoom.leadingWidth(of: line, advance: advance),
                advance: advance
            )
            let style = styles[continuation] ?? CodeBlockRoom.codeLine(height: height, continuation: continuation)
            styles[continuation] = style
            styled.addAttribute(.paragraphStyle, value: style, range: paragraph)
        }
    }

    // MARK: Colour and size

    /// The font a sized run's text is set in: the font around it, at the
    /// run's size against it, so a heading's run is a larger heading.
    ///
    /// `withSize` keeps the font's leading, scaled with it (measured 18 Oct:
    /// 1.713pt at 17, 2.418 at 24), so a line holding a run is as tall as the
    /// run's own text would make it; a run at the size of the text around it
    /// lays out exactly the lines plain text does.
    static func font(_ base: UIFont, sizedTo size: SpanSize?) -> UIFont {
        guard let size else { return base }
        return base.withSize(size.points(against: base.pointSize))
    }

    /// The colour a coloured run is drawn in: its hex, taken toward black on
    /// a light page and white on a dark one far enough for 4.5:1, as links
    /// are (`AccentPalette.textHex`).
    ///
    /// One object per hex, kept: the styler writes only attributes that
    /// differ from the storage's, and two dynamic colours made from the same
    /// hex aren't equal, so a new one each restyle would rewrite every
    /// coloured run, and lay out the note below it, on every keystroke.
    static func textColour(hex: Int) -> UIColor {
        colourCache.colour(hex: hex)
    }

    private static let colourCache = TextColourCache()

    /// The colour a highlight is drawn in: its hue over the page, translucent
    /// (`HighlightColour.alpha`), a dynamic colour per appearance.
    ///
    /// One object per colour, made once, for the reason `textColour` has: the
    /// styler writes only attributes that differ from the storage's, and two
    /// dynamic colours made alike aren't equal.
    static func highlightColour(_ colour: HighlightColour) -> UIColor {
        highlightColours[colour]!
    }

    private static let highlightColours: [HighlightColour: UIColor] = Dictionary(
        uniqueKeysWithValues: HighlightColour.allCases.map { colour in
            (colour, UIColor { traits in
                let isDark = traits.userInterfaceStyle == .dark
                let hex = isDark ? colour.hex.dark : colour.hex.light
                return AccentPalette.uiColor(hex).withAlphaComponent(HighlightColour.alpha(isDark: isDark))
            })
        }
    )

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
        var markers: [NSRange] { kind.isMarker ? [range] : [] }
    }

    /// Converts every range in the document to UTF-16 offsets in one forward pass.
    ///
    /// `NSRange(someRange, in: source)` measures the distance from the string's
    /// start index, so it costs O(offset) per call. Calling it once per block
    /// and once per inline span made styling quadratic in document length —
    /// 184ms for a 500-line note, on every keystroke. Blocks are contiguous and
    /// in order, and so are the inline spans inside them, so their lengths can
    /// simply be accumulated instead.
    static func layouts(for blocks: [BlockNode], in source: String) -> [BlockLayout] {
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

    /// Snapshots the syntax colours currently inside code blocks.
    ///
    /// Only colours that differ from the default are worth carrying over, and
    /// only inside a code block's content — the dimmed fence lines are markers
    /// and get reapplied from scratch.
    private static func codeColors(in storage: NSTextStorage, layouts: [BlockLayout]) -> [ColorRun] {
        var preserved: [ColorRun] = []
        let defaultColor = UIColor.label

        for layout in layouts where layout.block.isCode && layout.block.codeBlock?.isOutput != true {
            // A block with no language is plain text: its old colours belong to
            // a tag that was just deleted, and no highlight pass will come to
            // take them off, since there is nothing to ask highlight.js for.
            guard layout.block.codeBlock?.hasLanguageTag == true else { continue }
            let range = layout.contentRange
            guard range.location >= 0, range.location + range.length <= storage.length else { continue }

            storage.enumerateAttribute(.foregroundColor, in: range) { value, subrange, _ in
                // An output block's text colour is its default, not a syntax
                // colour: carried into a block just retagged to a language,
                // it would show as pale grey on the page until highlighting
                // caught up.
                guard let color = value as? UIColor, color != defaultColor,
                      color != CodeOutputPanel.textColor
                else { return }
                preserved.append(ColorRun(range: subrange, color: color))
            }
        }

        return preserved
    }

    /// A list item's text without its line terminator, so a strikethrough
    /// doesn't run on into the gap after the line.
    private static func trimmingNewline(_ range: NSRange, in source: String, of layout: BlockLayout) -> NSRange {
        let text = source[layout.block.contentRange]
        guard let last = text.last, last.isNewline else { return range }
        return NSRange(location: range.location, length: max(range.length - last.utf16.count, 0))
    }

    /// Applies inline nodes over a block whose base font is already set.
    ///
    /// One pass: each node is drawn with its own attributes, which hold
    /// every pair it is inside. Fonts are derived from the block's own,
    /// sized first, then given their traits, so bold inside a heading is a
    /// bold heading and bold inside a sized run is bold at the run's size.
    /// A marker keeps the font of the text around its pair and is dimmed.
    private static func apply(_ inlines: [InlineLayout], over blockFont: UIFont, to storage: NSMutableAttributedString) {
        for inline in inlines {
            let attributes = inline.attributes
            if inline.kind.isMarker {
                if attributes != .plain {
                    storage.addAttribute(.font, value: font(for: attributes, over: blockFont), range: inline.range)
                }
                storage.addAttribute(.foregroundColor, value: markerColor, range: inline.range)
                continue
            }
            guard attributes != .plain else { continue }

            if attributes.size != nil || attributes.bold || attributes.italic || attributes.code {
                storage.addAttribute(.font, value: font(for: attributes, over: blockFont), range: inline.range)
            }
            // A link keeps the link colour inside a coloured run.
            if attributes.link {
                storage.addAttribute(.foregroundColor, value: linkColor, range: inline.range)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: inline.range)
            } else if let colour = attributes.colour {
                storage.addAttribute(.foregroundColor, value: textColour(hex: colour), range: inline.range)
            }
            if attributes.code {
                // A per-glyph background is right here, unlike a code block —
                // an inline span is short and doesn't need to square off.
                storage.addAttribute(.backgroundColor, value: UIColor.secondarySystemFill, range: inline.range)
            }
            // After code's, so a highlighted word of code shows the highlight.
            if let highlight = attributes.highlight {
                storage.addAttribute(.backgroundColor, value: highlightColour(highlight), range: inline.range)
            }
            if attributes.strikethrough {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: inline.range)
            }
            if attributes.underline {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: inline.range)
            }
        }
    }

    /// The font text with `attributes` is set in, in a block set in
    /// `blockFont`: sized, then monospaced for code, or given bold and
    /// italic. Code is regular weight unless it is inside bold.
    static func font(for attributes: InlineAttributes, over blockFont: UIFont) -> UIFont {
        let sized = font(blockFont, sizedTo: attributes.size)
        if attributes.code {
            let code = UIFont.monospacedSystemFont(ofSize: sized.pointSize, weight: attributes.bold ? .bold : .regular)
            return attributes.italic ? code.withTraits(.traitItalic) : code
        }
        var traits: UIFontDescriptor.SymbolicTraits = []
        if attributes.bold { traits.insert(.traitBold) }
        if attributes.italic { traits.insert(.traitItalic) }
        return traits.isEmpty ? sized : sized.withTraits(traits)
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
    static func applyTypingAttributes(
        to textView: UITextView,
        source: String,
        blocks: [BlockNode],
        rendered: Bool = false,
        typography: NoteTypography = .standard
    ) {
        let caret = textView.selectedRange.location

        let current = block(at: caret, in: source, blocks: blocks)

        switch current?.kind {
        case .code(let code) where code.isOutput:
            // One colour all the way through: nothing is highlighted.
            textView.typingAttributes = outputAttributes(typography)
        case .code:
            // Carry the neighbouring syntax colour onto whatever is typed next.
            //
            // Highlighting is debounced, so without this the character just
            // typed sits uncoloured for as long as the debounce — you type the
            // `n` of `return` and watch it stay black next to five pink
            // letters. A briefly stale colour reads as stable; a black gap at
            // the caret reads as broken, and the next highlight pass corrects
            // either one.
            var attributes = codeAttributes(typography)
            if let inherited = inheritedCodeColor(at: caret, in: textView.textStorage) {
                attributes[.foregroundColor] = inherited
            }
            textView.typingAttributes = attributes
        case .heading(let level, _):
            textView.typingAttributes = headingAttributes(level: level, typography: typography)
        case .blockQuote(let depth, _):
            // The indent carries, or a quote's new line starts at the margin.
            var attributes = proseAttributes(typography)
            attributes[.paragraphStyle] = ProseBlockMetrics.quoteParagraphStyle(depth: depth, typography: typography)
            textView.typingAttributes = attributes
        case .listItem:
            // Carry the indent, or text typed into a wrapped list line jumps
            // back to the margin.
            var attributes = proseAttributes(typography)
            attributes[.paragraphStyle] = listParagraphStyle(for: current!, in: source, rendered: rendered, typography: typography)
            textView.typingAttributes = attributes
        default:
            textView.typingAttributes = proseAttributes(typography)
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

/// The dynamic colours coloured runs are drawn in, one per hex.
private final class TextColourCache: @unchecked Sendable {
    private var colours: [Int: UIColor] = [:]
    private let lock = NSLock()

    func colour(hex: Int) -> UIColor {
        lock.lock()
        defer { lock.unlock() }
        if let colour = colours[hex] { return colour }
        let colour = UIColor { traits in
            AccentPalette.uiColor(AccentPalette.textHex(for: hex, isDark: traits.userInterfaceStyle == .dark))
        }
        colours[hex] = colour
        return colour
    }
}

#endif
