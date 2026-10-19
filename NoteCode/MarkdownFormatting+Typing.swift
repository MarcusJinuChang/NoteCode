//
//  MarkdownFormatting+Typing.swift
//  NoteCode
//
//  Text overhaul, phase 4: what a button does with a collapsed caret, and how
//  text typed under a typing style is written (`TypingStyle`). Pure, like the
//  rest of `MarkdownFormatting`.
//

import Foundation

extension MarkdownFormatting {

    /// What a formatting button does with a collapsed caret.
    enum CaretTarget: Equatable, Sendable {
        /// The caret is strictly inside a word, a word character either side:
        /// the button acts on the word (Word's rule).
        case word
        /// Anywhere else in prose, a word's ends included, between words and
        /// on a blank line: the button sets the typing style, and nothing is
        /// written until text is typed.
        case typing
        /// In code, a code block's lines or a line's marker, or at a link or
        /// inline code that typed text would join: nothing to do.
        case nothing
    }

    /// Where a press with the caret at `caret` goes (decision 5). Ends of a
    /// word are the typing style's, not the word's, so that a word just
    /// typed can be followed by text in the other style: the one place this
    /// can be tuned is here.
    static func caretTarget(at caret: Int, in text: NSString, codeRanges: [CodeRange]) -> CaretTarget {
        guard caret >= 0, caret <= text.length, !isCode(caret, in: codeRanges) else { return .nothing }
        let line = contentLine(containing: caret, in: text)
        guard let styled = StyledLine(text.substring(with: line)) else { return .nothing }
        let local = caret - line.location
        guard local >= styled.content.location else { return .nothing }
        if styled.wordGlyphs(atCaret: local) != nil { return .word }
        return styled.typedStyle(at: local).joinsLinkOrCode ? .nothing : .typing
    }

    /// The edit that writes the text just typed, `run` in `text` as it is
    /// now, with `typing` on: `nil` where the text is already drawn that way,
    /// or where nothing can be done (the run crosses a line, is in code, joins
    /// a link, or can't be written to read as asked).
    ///
    /// - The run is taken out and put back as characters of the line read
    ///   before it was typed, so the line a typed space broke (`**hello **`
    ///   shows its stars) is written again from what it was.
    /// - The run's style is the text around the caret's, then the typing
    ///   style's settings (`TypingStyle.apply`).
    /// - Spaces just before the run, between it and a character drawn the same
    ///   way, are drawn that way too, so a sentence typed in bold is one bold
    ///   and not a bold word, a space and a bold word each time.
    /// - A space can't be at the end of bold, italic or strikethrough, so
    ///   one typed there goes outside it and the caret with it
    ///   (`StyledLine`); the next text typed is written with the style again.
    /// - The selection afterwards is just after the run, inside whatever
    ///   markers close behind it, where typing goes on.
    static func typed(
        _ typing: TypingStyle,
        run: NSRange,
        in text: NSString,
        blockSizes: BlockSizes,
        codeRanges: [CodeRange]
    ) -> TextEdit? {
        guard !typing.isEmpty, run.length > 0, NSMaxRange(run) <= text.length,
              !isCode(run.location, in: codeRanges)
        else { return nil }
        let line = contentLine(containing: run.location, in: text)
        guard NSMaxRange(run) <= NSMaxRange(line) else { return nil }

        let current = text.substring(with: line) as NSString
        let local = NSRange(location: run.location - line.location, length: run.length)
        let before = current.replacingCharacters(in: local, with: "")
        guard let styled = StyledLine(before), local.location >= styled.content.location else { return nil }
        let context = styled.typedStyle(at: local.location)
        guard !context.joinsLinkOrCode else { return nil }

        let typedText = current.substring(with: local) as NSString
        var texts: [String] = []
        var position = 0
        while position < typedText.length {
            let piece = typedText.rangeOfComposedCharacterSequence(at: position)
            texts.append(typedText.substring(with: piece))
            position = NSMaxRange(piece)
        }

        var wanted = context.style
        typing.apply(to: &wanted, headingLevel: styled.headingLevel, blockSizes: blockSizes)

        // Spaces in front of the run, after a character drawn as the run is.
        let index = styled.glyphCount(endingBy: local.location)
        var first = index
        while first > 0, styled.glyphs[first - 1].isSpace { first -= 1 }
        if first == index || first == 0 || styled.glyphs[first - 1].style != wanted { first = index }

        let withSpaces = styled.glyphs[first..<index].map(\.text) + texts
        let styles = [StyledLine.Style](repeating: wanted, count: (index - first) + texts.count)

        // Written as asked, or with no style at all if that can't be read
        // back: either way the line is whole again, never showing stars.
        let unstyled = [StyledLine.Style](repeating: context.style, count: texts.count)
        guard let target = styled.edited(replacing: first..<index, with: withSpaces, styles: styles)
                ?? styled.edited(replacing: index..<index, with: texts, styles: unstyled),
              target.line != (current as String)
        else { return nil }

        let edit = minimalEdit(replacing: line, with: target.line, in: text)
        let caret = line.location + target.earliestPosition(at: index + texts.count)
        return TextEdit(range: edit.range, replacement: edit.replacement, selection: NSRange(location: caret, length: 0))
    }
}
