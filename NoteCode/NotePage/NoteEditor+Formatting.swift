//
//  NoteEditor+Formatting.swift
//  NoteCode
//
//  The editor's text commands: inline styles, headings, lists, quotes,
//  rules, formulas, code blocks, indenting, colour and highlight, all made
//  as edits through the text view (`perform`).
//

#if canImport(UIKit)

import UIKit

extension NoteEditor {

    // MARK: Formatting

    /// Bold, Italic, Strikethrough, Underline and Code. A selection, or a caret inside a
    /// word, is an edit; a caret anywhere else in prose sets the typing style
    /// (`TypingStyle`) and writes nothing.
    func toggle(_ style: MarkdownFormatting.InlineStyle) {
        if let textView, mode == .text, !isTextLocked, typing.isTypingCaret(in: textView) {
            let shown = formattingShown
            let lit = switch style {
            case .bold:          shown.bold
            case .italic:        shown.italic
            case .strikethrough: shown.strikethrough
            case .underline:     shown.underline
            case .code:          shown.code
            }
            typing.set(typing.typingStyle.toggled(style, shown: lit))
            return
        }
        perform { [textTarget] text, selection in
            MarkdownFormatting.toggle(style, in: text, selection: selection, codeRanges: textTarget?.codeRanges ?? [])
        }
    }

    func setHeading(level: Int) {
        perform { MarkdownFormatting.setHeading(level: level, in: $0, selection: $1) }
    }

    func toggleBullet() {
        toggleList(.bullet)
    }

    /// Makes the lines at the caret a quote, or takes the quote off them.
    func toggleQuote() {
        perform { MarkdownFormatting.toggleQuote(in: $0, selection: $1) }
    }

    /// Style ▾ › Inline Formula and Display Formula.
    func insertFormula(display: Bool) {
        guard mode == .text, !isTextLocked else { return }
        textTarget?.presentNewFormula(display: display)
    }

    /// A horizontal rule below the caret's line.
    func insertRule() {
        perform { [textTarget] text, selection in
            MarkdownFormatting.insertRule(in: text, selection: selection, codeRanges: textTarget?.codeRanges ?? [])
        }
    }

    func toggleList(_ style: MarkdownFormatting.ListStyle) {
        perform { MarkdownFormatting.toggleList(style, in: $0, selection: $1) }
    }

    /// What the bar shows at the caret: the text's own formatting with the
    /// typing style on top, so Bold lit means the next text typed is bold.
    var formattingShown: MarkdownFormatting.CaretFormatting {
        typing.typingStyle.shown(over: caretFormatting)
    }

    /// Starts a code block, and remembers its language for
    /// `insertCodeBlockInLastLanguage`.
    func insertCodeBlock(language: CodeLanguage?) {
        guard mode == .text, !isTextLocked else { return }
        LastCodeLanguage.store(language, in: defaults)
        perform { MarkdownFormatting.insertCodeBlock(language: language, in: $0, selection: $1) }
    }

    /// Code Block ▾'s choice. Output isn't a language, so it leaves the one
    /// ⇧⌘K remembers alone: a student who writes a program and then its
    /// output wants the next block in the program's language.
    func insertCodeBlock(kind: CodeBlockKind) {
        switch kind {
        case .language(let language): insertCodeBlock(language: language)
        case .plain:                  insertCodeBlock(language: nil)
        case .output:
            guard mode == .text, !isTextLocked else { return }
            perform { MarkdownFormatting.insertCodeBlock(kind: .output, in: $0, selection: $1) }
        }
    }

    /// ⇧⌘K: a code block in whichever language the last one was.
    func insertCodeBlockInLastLanguage() {
        insertCodeBlock(language: LastCodeLanguage.read(from: defaults))
    }

    /// Makes an edit through the text view rather than around it.
    ///
    /// `replace(_:withText:)` is the path typing takes, so the edit lands on
    /// the undo stack and the delegate restyles it and writes it back to the
    /// page, exactly as if it had been typed. Assigning `.text` would do
    /// neither, and would throw away the selection besides.
    private func perform(_ makeEdit: (String, NSRange) -> TextEdit) {
        perform { Optional(makeEdit($0, $1)) }
    }

    /// `perform` for an edit that may have nothing to do.
    func perform(_ makeEdit: (String, NSRange) -> TextEdit?) {
        guard mode == .text, !isTextLocked, let textView else { return }

        guard let edit = makeEdit(textView.text ?? "", textView.selectedRange) else { return }

        guard let range = textView.textRange(for: edit.range) else { return }

        // Formatting is a prelude to typing, so the keyboard comes up for it.
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        editGuard.perform(as: .formatting) {
            textView.replace(range, withText: edit.replacement)
        }
        textView.selectedRange = edit.selection
        undoRouter.refresh()
    }

    // MARK: The text options row

    /// The code blocks, for the edits that need to know where one is. The
    /// text view's coordinator owns the parse.
    var codeRanges: [CodeRange] { textTarget?.codeRanges ?? [] }

    /// ⇥ and ⇤. Text mode, unlocked.
    func indent(outdent: Bool) {
        guard mode == .text, !isTextLocked else { return }
        textTarget?.indentAtCaret(outdent: outdent)
        undoRouter.refresh()
    }

    /// The language menu's pick for the block the caret is in.
    func setCodeBlockKind(_ kind: CodeBlockKind) {
        guard mode == .text, !isTextLocked else { return }
        textTarget?.retagBlockAtCaret(kind)
        undoRouter.refresh()
    }

    /// + Output: an empty output block under the code block the caret is in.
    func addOutputBlock() {
        perform { text, selection in
            MarkdownFormatting.insertOutputBlock(
                afterBlockAt: selection.location, in: text as NSString, codeRanges: codeRanges
            )
        }
    }

    /// Colour (`TextColour`): sets `hex` on the selection, the coloured run
    /// at the caret or the word there; `nil` takes colour off.
    func setColour(_ hex: Int?) {
        guard mode == .text, !isTextLocked, let textView else { return }
        if typing.isTypingCaret(in: textView) {
            typing.set(typing.typingStyle.colouring(hex))
            return
        }
        perform { [textTarget] text, selection in
            MarkdownFormatting.colour(hex, selection: selection, in: text as NSString, codeRanges: textTarget?.codeRanges ?? [])
        }
    }

    /// Colours text ranges, one per line, for the Select tool. Works in ink
    /// mode, where the text view isn't editable and has no keyboard:
    /// `replace(_:withText:)` doesn't care (scripts/spikes/text-edit-while-ink-probe.swift).
    /// All in one turn of the run loop, so one undo step; bottom up, so the
    /// lines an edit rewrites can't move a range not yet done.
    func recolourText(_ ranges: [NSRange], to hex: Int?) {
        guard !isTextLocked, let textView else { return }
        defer { undoRouter.refresh() }
        editGuard.perform(as: .formatting) {
            for range in ranges.sorted(by: { $0.location > $1.location }) {
                let text = textView.text ?? ""
                guard let edit = MarkdownFormatting.colour(hex, selection: range, in: text as NSString, codeRanges: textTarget?.codeRanges ?? []),
                      let textRange = textView.textRange(for: edit.range)
                else { continue }
                textView.replace(textRange, withText: edit.replacement)
            }
        }
    }

    /// Highlight (`HighlightColour`): the same, with a background; `nil`
    /// takes the highlight off.
    func setHighlight(_ colour: HighlightColour?) {
        guard mode == .text, !isTextLocked, let textView else { return }
        if typing.isTypingCaret(in: textView) {
            typing.set(typing.typingStyle.highlighting(colour))
            return
        }
        perform { [textTarget] text, selection in
            MarkdownFormatting.highlight(colour, selection: selection, in: text as NSString, codeRanges: textTarget?.codeRanges ?? [])
        }
    }
}

#endif
