//
//  DocumentStyler+Colour.swift
//  NoteCode
//
//  The colour half of DocumentStyler: text and highlight colours, the
//  syntax colours a restyle carries over and the highlighter paints, and
//  the colour typing takes from the character before the caret.
//

#if canImport(UIKit)

import UIKit

extension DocumentStyler {

    // MARK: Colour

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

    /// Snapshots the syntax colours currently inside code blocks.
    ///
    /// Only colours that differ from the default are worth carrying over, and
    /// only inside a code block's content — the dimmed fence lines are markers
    /// and get reapplied from scratch.
    static func codeColors(in storage: NSTextStorage, layouts: [BlockLayout]) -> [ColorRun] {
        var preserved: [ColorRun] = []

        for layout in layouts where layout.block.isCode && layout.block.codeBlock?.isOutput != true {
            // A block with no language is plain text: its old colours belong to
            // a tag that was just deleted, and no highlight pass will come to
            // take them off, since there is nothing to ask highlight.js for.
            guard layout.block.codeBlock?.hasLanguageTag == true else { continue }
            let range = layout.contentRange
            guard range.location >= 0, range.location + range.length <= storage.length else { continue }

            // Only runs the highlighter marked. An output block's text colour
            // is its default, not a syntax colour: carried into a block just
            // retagged to a language, it would show as pale grey on the page
            // until highlighting caught up, and it carries no mark.
            storage.enumerateAttribute(.noteCodeSyntax, in: range) { marked, markedRange, _ in
                guard marked != nil else { return }
                storage.enumerateAttributes(in: markedRange) { attributes, subrange, _ in
                    guard let color = attributes[.foregroundColor] as? UIColor else { return }
                    let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
                    preserved.append(ColorRun(
                        range: subrange, color: color,
                        bold: traits.contains(.traitBold), italic: traits.contains(.traitItalic)
                    ))
                }
            }
        }

        return preserved
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
            storage.removeAttribute(.noteCodeSyntax, range: range)
            // Back to the block's plain face, at the size it already has.
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                guard let font = value as? UIFont,
                      font.fontDescriptor.symbolicTraits.isDisjoint(with: [.traitBold, .traitItalic]) == false
                else { return }
                storage.addAttribute(.font, value: syntaxFont(font, bold: false, italic: false), range: subrange)
            }
        }

        for run in runs {
            // Defensive: an off-by-one here would trap, and the ranges came
            // from a snapshot of the document taken before an await.
            guard run.range.location >= 0,
                  run.range.length >= 0,
                  run.range.location + run.range.length <= length
            else { continue }

            storage.addAttributes(syntaxAttributes(run, over: storage, at: run.range), range: run.range)
        }
        storage.endEditing()
    }

    /// A code font with a token's weight and italic: monospaced, at `base`'s
    /// size, so the token is as wide and as tall as the code around it.
    /// Semibold rather than bold, as the theme asks for 600.
    static func syntaxFont(_ base: UIFont, bold: Bool, italic: Bool) -> UIFont {
        let key = SyntaxFontKey(size: base.pointSize, bold: bold, italic: italic)
        return syntaxFonts.value(for: key) {
            let face = UIFont.monospacedSystemFont(ofSize: key.size, weight: bold ? .semibold : .regular)
            guard bold || italic else { return face }
            // The bold trait is added too, so the weight reads back as bold.
            var traits: UIFontDescriptor.SymbolicTraits = []
            if bold { traits.insert(.traitBold) }
            if italic { traits.insert(.traitItalic) }
            guard let descriptor = face.fontDescriptor.withSymbolicTraits(traits) else { return face }
            return UIFont(descriptor: descriptor, size: key.size)
        } ?? base
    }

    private struct SyntaxFontKey: Hashable {
        var size: CGFloat
        var bold: Bool
        var italic: Bool
    }

    /// Built once per size and style: a run is a font lookup, not a font build.
    private static let syntaxFonts = BoundedCache<SyntaxFontKey, UIFont>(limit: 64)

    /// The attributes a syntax run is drawn with over the code font.
    static func syntaxAttributes(_ run: ColorRun, over base: UIFont) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: run.color, .noteCodeSyntax: true]
        if run.bold || run.italic { attributes[.font] = syntaxFont(base, bold: run.bold, italic: run.italic) }
        return attributes
    }

    private static func syntaxAttributes(_ run: ColorRun, over storage: NSTextStorage, at range: NSRange) -> [NSAttributedString.Key: Any] {
        let base = storage.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont ?? codeFont
        return syntaxAttributes(run, over: base)
    }

    /// The colour of the character before the caret, when it makes sense to
    /// extend it onto the next one.
    ///
    /// Reads the storage directly rather than converting a `Range<String.Index>`
    /// — this runs on every caret move, and that conversion costs O(offset).
    static func inheritedCodeColor(at caret: Int, in storage: NSTextStorage) -> UIColor? {
        guard caret > 0, caret - 1 < storage.length else { return nil }

        // A colour shouldn't carry onto a new line.
        guard storage.mutableString.character(at: caret - 1) != UTF16Unit.newline else { return nil }

        // Only a coloured run: the dimmed or hidden fence line, and plain
        // text, carry no mark.
        guard storage.attribute(.noteCodeSyntax, at: caret - 1, effectiveRange: nil) != nil,
              let color = storage.attribute(.foregroundColor, at: caret - 1, effectiveRange: nil) as? UIColor
        else { return nil }

        return color
    }
}

/// The dynamic colours coloured runs are drawn in, one per hex.
private final class TextColourCache: @unchecked Sendable {
    private let colours = BoundedCache<Int, UIColor>(limit: 2_000)

    func colour(hex: Int) -> UIColor {
        colours.value(for: hex) {
            UIColor { traits in
                AccentPalette.uiColor(AccentPalette.textHex(for: hex, isDark: traits.userInterfaceStyle == .dark))
            }
        }!
    }
}

#endif
