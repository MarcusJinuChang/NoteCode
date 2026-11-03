//
//  DocumentTextView+Clipboard.swift
//  NoteCode
//
//  Text overhaul, phase 5: the coordinator's side of copy and paste with
//  formatting. The conversions are `RichCopy` and `RichPaste`.
//

#if canImport(UIKit)

import UIKit

extension DocumentTextView.Coordinator {

    /// Connects the text view's copy, cut and paste to this note's text.
    func installClipboard(on textView: DocumentUITextView) {
        textView.richCopy = { [weak self] textView in
            self?.richCopy(from: textView)
        }
        textView.richPaste = { [weak self] textView in
            self?.richPaste(into: textView) ?? false
        }
    }

    /// The selection as RTF, or `nil` where there is none: nothing selected,
    /// or nothing visible in it.
    func richCopy(from textView: UITextView) -> Data? {
        let selection = textView.selectedRange
        guard selection.length > 0,
              let attributed = RichCopy.attributedString(
                  selection: selection,
                  in: textView.textStorage.mutableString,
                  codeRanges: codeRanges(in: textView.textStorage),
                  typography: typography
              )
        else { return nil }
        return RichCopy.rtf(attributed)
    }

    /// Pastes the pasteboard's styled text as the Markdown that says the same.
    /// Whether it did: not in code, nor over any of it (a paste there is
    /// plain), nor while a composition is going, nor when there is no
    /// formatting in the paste to keep.
    func richPaste(into textView: UITextView) -> Bool {
        guard textView.isEditable, textView.markedTextRange == nil else { return false }
        let selection = textView.selectedRange
        let text = textView.textStorage.mutableString
        guard !Self.touchesCode(selection, in: codeRanges(in: textView.textStorage)) else { return false }

        let atLineStart = selection.location == 0 || text.character(at: selection.location - 1) == 10
        guard let markdown = RichPaste.markdown(from: .general, atLineStart: atLineStart) else { return false }

        // Pasted text isn't typed, so no typing style writes over it.
        editor?.clearTypingStyle()
        apply(
            TextEdit(
                range: selection,
                replacement: markdown,
                selection: NSRange(location: selection.location + (markdown as NSString).length, length: 0)
            ),
            to: textView
        )
        return true
    }

    /// Whether `selection` is in a code block, or reaches into one. An
    /// unclosed block runs to the note's end.
    static func touchesCode(_ selection: NSRange, in blocks: [CodeRange]) -> Bool {
        blocks.contains { block in
            if NSLocationInRange(selection.location, block.range) { return true }
            if selection.length == 0 { return !block.isClosed && selection.location == NSMaxRange(block.range) }
            return NSIntersectionRange(block.range, selection).length > 0
        }
    }
}

#endif
