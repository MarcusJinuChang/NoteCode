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
        for block in blocks where block.isCode {
            storage.setAttributes(codeAttributes, range: NSRange(block.range, in: source))
        }
        storage.endEditing()
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
        let inCode = block(at: caret, in: source, blocks: blocks)?.isCode ?? false

        textView.typingAttributes = inCode ? codeAttributes : proseAttributes
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

#endif
