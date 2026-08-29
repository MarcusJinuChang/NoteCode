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
        let blocks = DocumentParser.parse(textView.text ?? "")
        applyStyling(to: textView, blocks: blocks)
        return blocks
    }

    static func applyStyling(to textView: UITextView, blocks: [BlockNode]) {
        let source = textView.text ?? ""

        // Rewriting attributes mid-composition destroys the marked-text
        // underline and can drop the in-progress character entirely, which
        // breaks Pinyin, Kana, and accent input.
        guard textView.markedTextRange == nil else { return }

        let storage = textView.textStorage
        storage.beginEditing()
        storage.setAttributes(proseAttributes, range: NSRange(location: 0, length: storage.length))

        for block in blocks {
            switch block.kind {
            case .code(let code):
                storage.setAttributes(codeAttributes, range: NSRange(block.range, in: source))
                // The fence lines are markers like any other, so they recede
                // too — the code inside is what should carry the eye.
                for marker in [
                    block.range.lowerBound..<code.contentRange.lowerBound,
                    code.contentRange.upperBound..<block.range.upperBound,
                ] where !marker.isEmpty {
                    storage.addAttribute(.foregroundColor, value: markerColor, range: NSRange(marker, in: source))
                }

            case .paragraph(let inlines):
                apply(inlines, over: proseFont, to: storage, in: source)

            case .heading(let level, let inlines):
                storage.setAttributes(headingAttributes(level: level), range: NSRange(block.range, in: source))
                apply(inlines, over: headingFont(level: level), to: storage, in: source)
                if let marker = block.markerRange {
                    storage.addAttribute(.foregroundColor, value: markerColor, range: NSRange(marker, in: source))
                }
            }
        }

        storage.endEditing()
    }

    /// Applies inline spans over a block whose base font is already set.
    ///
    /// Traits are derived from the block's own font rather than a fixed one, so
    /// bold inside a heading is a bold heading, not bold body text.
    private static func apply(
        _ inlines: [InlineNode],
        over baseFont: UIFont,
        to storage: NSTextStorage,
        in source: String
    ) {
        for inline in inlines where inline.kind != .text {
            let content = NSRange(inline.contentRange, in: source)

            switch inline.kind {
            case .strong:
                storage.addAttribute(.font, value: baseFont.withTraits(.traitBold), range: content)
            case .emphasis:
                storage.addAttribute(.font, value: baseFont.withTraits(.traitItalic), range: content)
            case .inlineCode:
                storage.addAttribute(
                    .font,
                    value: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular),
                    range: content
                )
                // A per-glyph background is right here, unlike a code block —
                // an inline span is short and doesn't need to square off.
                storage.addAttribute(.backgroundColor, value: UIColor.secondarySystemFill, range: content)
            case .text:
                break
            }

            for marker in inline.markerRanges {
                storage.addAttribute(.foregroundColor, value: markerColor, range: NSRange(marker, in: source))
            }
        }
    }

    /// Paints syntax colours over already-styled text.
    ///
    /// Uses `addAttribute` rather than `setAttributes` so the monospace font
    /// and everything else the styling pass established survive. Colours are
    /// always additive and always land after a full restyle has reset
    /// foregrounds back to `.label`.
    static func applyColors(_ runs: [ColorRun], to textView: UITextView) {
        guard textView.markedTextRange == nil else { return }

        let storage = textView.textStorage
        let length = storage.length

        storage.beginEditing()
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
    static func applyTypingAttributes(to textView: UITextView, blocks: [BlockNode]) {
        let source = textView.text ?? ""
        let caret = textView.selectedRange.location

        textView.typingAttributes = switch block(at: caret, in: source, blocks: blocks)?.kind {
        case .code:                  codeAttributes
        case .heading(let level, _): headingAttributes(level: level)
        default:                     proseAttributes
        }
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
