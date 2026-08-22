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
    @discardableResult
    static func applyStyling(to textView: UITextView) -> [Region] {
        let source = textView.text ?? ""
        let regions = FenceParser.parse(source)

        // Rewriting attributes mid-composition destroys the marked-text
        // underline and can drop the in-progress character entirely, which
        // breaks Pinyin, Kana, and accent input.
        guard textView.markedTextRange == nil else { return regions }

        let storage = textView.textStorage
        storage.beginEditing()
        storage.setAttributes(proseAttributes, range: NSRange(location: 0, length: storage.length))
        for region in regions where region.isCode {
            storage.setAttributes(codeAttributes, range: NSRange(region.range, in: source))
        }
        storage.endEditing()

        return regions
    }

    /// Sets the attributes newly typed characters will take on.
    ///
    /// Without this, UIKit inherits typing attributes from the character to the
    /// left of the caret — so the first thing typed after a code block comes out
    /// monospaced on a grey background. This is the "attribute bleed" problem;
    /// setting typing attributes from the *parsed* region under the caret is the
    /// fix, rather than letting the text system guess.
    static func applyTypingAttributes(to textView: UITextView, regions: [Region]) {
        let source = textView.text ?? ""
        let caret = textView.selectedRange.location
        let inCode = region(at: caret, in: source, regions: regions)?.isCode ?? false

        textView.typingAttributes = inCode ? codeAttributes : proseAttributes
    }

    /// The region containing a UTF-16 offset, if any.
    ///
    /// Ranges are half-open, so a caret sitting exactly on the boundary between
    /// a code block and the prose after it belongs to the prose — which is what
    /// you want when typing just past a closing fence.
    static func region(at utf16Offset: Int, in source: String, regions: [Region]) -> Region? {
        guard let index = Range(NSRange(location: utf16Offset, length: 0), in: source)?.lowerBound else {
            return nil
        }
        if index == source.endIndex {
            return regions.last
        }
        return regions.first { $0.range.contains(index) }
    }
}

#endif
