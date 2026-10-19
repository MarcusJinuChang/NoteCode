//
//  TypingStyle.swift
//  NoteCode
//
//  Text overhaul, phase 4 (docs/text-system-overhaul.md, decision 5): what the
//  next text typed will be drawn with, which a button sets when it has no
//  word to act on.
//

import Foundation

/// What a formatting button has set for the text about to be typed: Bold,
/// Italic, Strikethrough, Underline, Code, a colour, a highlight or a size, each on, off or left as
/// the text around the caret has it. Nothing is written until text is typed;
/// then `MarkdownFormatting.typed` writes it with the style on.
///
/// Off is a setting too: at the end of a bold word the next text typed is
/// bold, and Bold pressed there turns that off for it.
nonisolated struct TypingStyle: Equatable, Sendable {

    /// A colour or size set to a value, or taken off.
    enum Setting<Value: Equatable & Sendable>: Equatable, Sendable {
        case set(Value)
        case clear
    }

    var bold: Bool?
    var italic: Bool?
    var strikethrough: Bool?
    var underline: Bool?
    var code: Bool?
    /// `TextColour`'s hex.
    var colour: Setting<Int>?
    var highlight: Setting<HighlightColour>?
    /// A size in points, written against the line's own text when the text
    /// is typed (`SpanSize`), as the size control writes one.
    var points: Setting<Double>?

    static let none = TypingStyle()

    var isEmpty: Bool { self == .none }

    /// The style typed text gets: the text around the caret's `style`, then
    /// each setting here. `headingLevel` and `blockSizes` turn points into a
    /// size against the line's block.
    func apply(to style: inout StyledLine.Style, headingLevel: Int, blockSizes: MarkdownFormatting.BlockSizes) {
        if let bold { style.bold = bold }
        if let italic { style.italic = italic }
        if let strikethrough { style.strikethrough = strikethrough }
        if let underline { style.underline = underline }
        if let code { style.code = code }
        switch colour {
        case .set(let hex)?: style.colour = hex
        case .clear?:        style.colour = nil
        case nil:            break
        }
        switch highlight {
        case .set(let colour)?: style.highlight = colour
        case .clear?:           style.highlight = nil
        case nil:               break
        }
        switch points {
        case .set(let points)?:
            MarkdownFormatting.StyleChange.points(points, blockSizes).apply(to: &style, headingLevel: headingLevel)
        case .clear?:
            style.size = nil
        case nil:
            break
        }
    }

    /// What the bar shows at the caret: `formatting` (what the text says)
    /// with each setting here on top. Size is read by the size control, which
    /// has the note's fonts.
    func shown(over formatting: MarkdownFormatting.CaretFormatting) -> MarkdownFormatting.CaretFormatting {
        var shown = formatting
        if let bold { shown.bold = bold }
        if let italic { shown.italic = italic }
        if let strikethrough { shown.strikethrough = strikethrough }
        if let underline { shown.underline = underline }
        if let code { shown.code = code }
        switch colour {
        case .set(let hex)?: shown.colour = hex
        case .clear?:        shown.colour = nil
        case nil:            break
        }
        switch highlight {
        case .set(let colour)?: shown.highlight = colour
        case .clear?:           shown.highlight = nil
        case nil:               break
        }
        return shown
    }

    /// The setting for `style` turned the other way from how it is `shown`.
    func toggled(_ style: MarkdownFormatting.InlineStyle, shown: Bool) -> TypingStyle {
        var next = self
        switch style {
        case .bold:          next.bold = !shown
        case .italic:        next.italic = !shown
        case .strikethrough: next.strikethrough = !shown
        case .underline:     next.underline = !shown
        case .code:          next.code = !shown
        }
        return next
    }

    /// `hex` as the colour for typed text, or none for `nil`.
    func colouring(_ hex: Int?) -> TypingStyle {
        var next = self
        next.colour = hex.map { .set($0) } ?? .clear
        return next
    }

    /// `colour` as the highlight for typed text, or none for `nil`.
    func highlighting(_ colour: HighlightColour?) -> TypingStyle {
        var next = self
        next.highlight = colour.map { .set($0) } ?? .clear
        return next
    }

    /// `points` as the size for typed text, or the text's own for `nil`.
    func sizing(_ points: Double?) -> TypingStyle {
        var next = self
        next.points = points.map { .set($0) } ?? .clear
        return next
    }
}
