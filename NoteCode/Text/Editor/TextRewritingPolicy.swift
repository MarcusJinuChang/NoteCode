//
//  TextRewritingPolicy.swift
//  NoteCode
//
//  The single place the keyboard's text-rewriting features get configured,
//  and where in a note each set applies.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Whether the keyboard may rewrite what the user typed.
///
/// Six separate UIKit traits all edit text after the fact, and every one of
/// them corrupts code silently:
///
///     autocorrection       `int lo`  ->  `In too`
///     autocapitalization   `back`    ->  `Back`
///     smart quotes         `"`       ->  `“`
///     smart dashes         `--`      ->  `—`
///     smart insert/delete  adjusts spacing around pasted words
///     inline predictions   the space bar accepts a suggested word
///
/// They're grouped here rather than set individually at the call site so that
/// switching them is one call, not six scattered assignments that can drift
/// apart. Prose gets them and code doesn't: `at(_:in:blocks:)` says which
/// applies where the caret is, and `DocumentTextView` switches as the caret
/// moves.
nonisolated enum TextRewritingPolicy: Equatable, Sendable {
    /// Everything on — correct for prose, ruinous for code.
    case prose
    /// Everything off — correct inside a fenced code block.
    case code
    /// Prose with everything off, for a reader who turned off Settings ›
    /// Writing › Autocorrect. Traits are as in code; it is not code, so the
    /// code-keys row stays away.
    case proseWithoutRewriting

    /// Settings › Writing › Autocorrect: whether prose is autocorrected,
    /// capitalised and given smart punctuation. Per device, on until turned off.
    static let proseDefaultsKey = SettingKeys.Writing.autocorrectInProse.name
    static let proseEnabledByDefault = SettingKeys.Writing.autocorrectInProse.defaultValue

    /// What a new editor starts with, before the caret has been placed.
    ///
    /// Nothing rewrites until the editor knows where typing will go: the
    /// coordinator picks the policy for the caret as editing begins, and
    /// again as it moves.
    static let initial: TextRewritingPolicy = .code

    /// The policy for typing at a UTF-16 offset in `source`, whose blocks are
    /// `blocks`.
    ///
    /// Code is a fenced block's lines, its fences included, and inline code
    /// in a line of prose. An unclosed fence or backtick counts too, since the
    /// closing one is typed last: `int lo` would be corrected before it came.
    /// So does the word just after a closing backtick, until a space ends it.
    ///
    /// - Parameter rewritesProse: Settings › Writing › Autocorrect. Off, prose
    ///   is `.proseWithoutRewriting` and code is still `.code`.
    static func at(
        _ utf16Offset: Int,
        in source: String,
        blocks: [BlockNode],
        rewritesProse: Bool = proseEnabledByDefault
    ) -> TextRewritingPolicy {
        let prose: TextRewritingPolicy = rewritesProse ? .prose : .proseWithoutRewriting
        guard let caret = Range(NSRange(location: utf16Offset, length: 0), in: source)?.lowerBound else {
            return .code
        }

        let block: BlockNode?
        if caret == source.endIndex {
            // The note's last line is the last block's, unless a line break
            // ends that block: then the caret is on a new, empty line. An
            // unclosed code block runs to the end of the note, so the new
            // line is still code.
            if let last = blocks.last,
               last.range.upperBound == source.endIndex,
               source.last?.isNewline != true || last.codeBlock?.isClosed == false {
                block = last
            } else {
                block = nil
            }
        } else {
            // Half-open, so a caret at the start of the line after a closing
            // fence is in that line, not the block above it.
            block = blocks.first { $0.range.contains(caret) }
        }

        guard let block else { return prose }
        if block.isCode { return .code }
        if endsWordTouchingBacktick(caret, in: source) { return .code }
        return isInInlineCode(caret, block: block, source: source) ? .code : prose
    }

    /// Whether the word that ends at `caret` has a backtick in it.
    ///
    /// The keyboard corrects the word before the caret when a space ends it,
    /// and its word runs straight through a backtick: right after inline
    /// code, "use `int lo` " became "use `int lot ", the backtick eaten
    /// (measured 3 Oct). So the word stays code until a space ends it, and
    /// the space is typed with nothing on to correct it.
    private static func endsWordTouchingBacktick(_ caret: String.Index, in source: String) -> Bool {
        source[..<caret].reversed().prefix { !$0.isWhitespace }.contains("`")
    }

    /// Whether replacing `old` with `new` is smart punctuation: a straight
    /// quote made curly, or a hyphen or two made a dash.
    static func isSmartPunctuation(replacing old: String, with new: String) -> Bool {
        switch (old, new) {
        case ("\"", "\u{201C}"), ("\"", "\u{201D}"), ("'", "\u{2018}"), ("'", "\u{2019}"),
             ("-", "\u{2013}"), ("-", "\u{2014}"), ("--", "\u{2013}"), ("--", "\u{2014}"):
            true
        default:
            false
        }
    }

    /// The edit that keeps hyphens where the keyboard is turning them into a
    /// dash at the start of a line, or nil when the dash should be made.
    ///
    /// Smart dashes turn the second hyphen of a typed `---` into a dash, so
    /// the third followed it as "—-". At a line's start, hyphens are a
    /// Markdown rule or a front-matter fence, so the typed hyphen is kept
    /// as one (`range` holds the hyphens already there). A `--` between
    /// words still becomes a dash.
    static func hyphensKept(replacing range: NSRange, with text: String, in source: NSString) -> TextEdit? {
        guard text == "\u{2013}" || text == "\u{2014}",
              range.length == 1 || range.length == 2,
              NSMaxRange(range) <= source.length,
              source.substring(with: range).allSatisfy({ $0 == "-" })
        else { return nil }

        // Only spaces and tabs may come before them on the line.
        var index = range.location
        while index > 0 {
            let before = source.character(at: index - 1)
            if before == UTF16Unit.newline { break }
            guard before == 0x20 || before == 0x09 else { return nil }
            index -= 1
        }
        let hyphens = String(repeating: "-", count: range.length + 1)
        return TextEdit(
            range: range, replacement: hyphens,
            selection: NSRange(location: range.location + hyphens.utf16.count, length: 0)
        )
    }

    /// Whether the keyboard replacing `range` of `source` with `replacement`
    /// would change code.
    ///
    /// The traits can't stop every rewrite. The keyboard also goes back over
    /// words behind the caret: after "use `int lo` now" and a space, it
    /// replaced "lo` now" with "log now", eating the backtick, with the caret
    /// in prose by then (measured 3 Oct). Only what actually differs counts,
    /// so a rewrite that spans inline code but changes only the prose after
    /// it still goes through.
    static func rewriteChangesCode(
        _ range: NSRange,
        with replacement: String,
        in source: String,
        blocks: [BlockNode]
    ) -> Bool {
        guard let replaced = Range(range, in: source) else { return false }
        let old = source[replaced]

        // Trim what the rewrite leaves as it was, from both ends.
        let prefix = zip(old, replacement).prefix { $0 == $1 }.count
        let suffix = min(
            zip(old.reversed(), replacement.reversed()).prefix { $0 == $1 }.count,
            min(old.count, replacement.count) - prefix
        )
        let changed = old.index(old.startIndex, offsetBy: prefix)..<old.index(old.endIndex, offsetBy: -suffix)

        if source[changed].contains("`") { return true }

        return blocks.contains { block in
            guard block.range.overlaps(replaced) || block.range.contains(replaced.lowerBound) else { return false }
            let code = block.isCode
                ? [block.range]
                : InlineSpan.spans(in: block.inlines).filter { $0.markup == .inlineCode }.map(\.range)
            return code.contains { span in
                changed.isEmpty
                    ? span.lowerBound < changed.lowerBound && changed.lowerBound < span.upperBound
                    : span.overlaps(changed)
            }
        }
    }

    /// Whether `caret` is in inline code within a line of prose: between a
    /// span's backticks, or after a backtick nothing closes yet.
    private static func isInInlineCode(_ caret: String.Index, block: BlockNode, source: String) -> Bool {
        // Right after the opening backtick to right before the closing one.
        // After the closing one is prose again. Code can be inside bold.
        for span in InlineSpan.spans(in: block.inlines) where span.markup == .inlineCode {
            if span.range.lowerBound < caret, caret <= span.contentRange.upperBound { return true }
        }
        // The parser leaves a backtick as text when nothing on the line
        // closes it, which is what one being typed looks like.
        for inline in block.inlines where inline.kind == .text {
            guard inline.range.lowerBound < caret else { break }
            let before = inline.range.lowerBound..<min(inline.range.upperBound, caret)
            if source[before].contains("`") { return true }
        }
        return false
    }
}

/// The keyboard's "." shortcut, taken back where the keyboard may not
/// rewrite: in code, and in prose with Settings › Writing › Autocorrect off.
///
/// Two spaces typed quickly on the on-screen keyboard become ". ". No text
/// input trait turns that off (it is the reader's Settings › General ›
/// Keyboard › "." Shortcut), and the delegate can't refuse it: measured 7
/// Nov on the soft keyboard, the second space comes through
/// `shouldChangeTextIn` as an ordinary insert, then the keyboard replaces
/// both spaces with "." and inserts a space, neither through the delegate.
/// So this watches for that sequence after a second space and answers the
/// last step with the edit that puts the two spaces back.
nonisolated struct PeriodShortcut: Equatable, Sendable {
    /// Where the first of the two spaces is, while the sequence may follow.
    private var space: Int?
    /// The note's length with both spaces in.
    private var length = 0

    /// The keyboard is about to replace `range` of `source` with `text`.
    /// A second space typed where nothing may rewrite starts the watch;
    /// anything else ends it.
    mutating func willChange(_ range: NSRange, to text: String, in source: NSString, rewrites: Bool) {
        // The shortcut's own space, if it comes through the delegate.
        if let space, text == " ", range == NSRange(location: space + 1, length: 0),
           source.length == length - 1, source.character(at: space) == UTF16Unit.period {
            return
        }
        if !rewrites, text == " ", range.length == 0, range.location > 0, range.location <= source.length,
           source.character(at: range.location - 1) == UTF16Unit.space {
            space = range.location - 1
            length = source.length + 1
        } else {
            space = nil
        }
    }

    /// The note is now `source`. Returns the edit that turns the shortcut's
    /// ". " back into the two spaces typed, once the keyboard has made it.
    mutating func didChange(_ source: NSString, selection: NSRange) -> TextEdit? {
        guard let space else { return nil }
        let caret = selection.length == 0 ? selection.location : -1
        func at(_ offset: Int) -> unichar { offset < source.length ? source.character(at: offset) : 0 }
        switch (source.length - length, caret - space, at(space), at(space + 1)) {
        case (0, 2, UTF16Unit.space, UTF16Unit.space):
            // The second space is in.
            return nil
        case (-1, 1, UTF16Unit.period, _):
            // The keyboard replaced the two spaces with ".".
            return nil
        case (0, 2, UTF16Unit.period, UTF16Unit.space):
            // And typed its space after it.
            self.space = nil
            return TextEdit(
                range: NSRange(location: space, length: 2), replacement: "  ",
                selection: NSRange(location: space + 2, length: 0)
            )
        default:
            self.space = nil
            return nil
        }
    }
}

#if canImport(UIKit)

@MainActor
extension TextRewritingPolicy {
    /// Applies this policy's traits to `textView`.
    ///
    /// Spell checking stays off for both. Its underlines aren't confined to
    /// the part the caret is in: on in prose, it marks every word typed this
    /// session anywhere in the note, so an identifier typed in a code block
    /// turned red as soon as the caret moved back to prose (measured 3 Oct).
    ///
    /// - Parameter reloadingInputViews: pass `true` when switching policy while
    ///   the keyboard is already on screen. UIKit reads these traits when it
    ///   builds the keyboard, so without the reload the change appears to do
    ///   nothing until the keyboard is dismissed and shown again.
    func apply(to textView: UITextView, reloadingInputViews: Bool = false) {
        let rewritingAllowed = (self == .prose)

        textView.autocorrectionType = rewritingAllowed ? .yes : .no
        textView.autocapitalizationType = rewritingAllowed ? .sentences : .none
        textView.smartQuotesType = rewritingAllowed ? .yes : .no
        textView.smartDashesType = rewritingAllowed ? .yes : .no
        textView.smartInsertDeleteType = rewritingAllowed ? .yes : .no
        // The reader's keyboard setting decides in prose, as it does in Notes.
        textView.inlinePredictionType = rewritingAllowed ? .default : .no
        textView.spellCheckingType = .no

        if reloadingInputViews {
            textView.reloadInputViews()
        }
    }
}

#endif
