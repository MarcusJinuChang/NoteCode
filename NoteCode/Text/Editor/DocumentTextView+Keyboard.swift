//
//  DocumentTextView+Keyboard.swift
//  NoteCode
//
//  The coordinator's keyboard: prose or code traits by where the caret is,
//  and the code-keys row above the keyboard.
//

#if canImport(UIKit)

import UIKit

extension DocumentTextView.Coordinator {

    /// The keyboard traits the text view has now: prose or code.
    var rewritingPolicy: TextRewritingPolicy { keyboard.rewritingPolicy }
    var rewritesProse: Bool { keyboard.rewritesProse }

    /// Settings › Code › Code Keys.
    var codeKeysEnabled: Bool { keyboard.codeKeysEnabled }

    /// Whether the row belongs on the keyboard right now.
    var wantsCodeKeys: Bool { keyboard.wantsCodeKeys }

    func applyRewritingPolicy(to textView: UITextView, source: String, blocks: [BlockNode]) {
        keyboard.applyRewritingPolicy(to: textView, source: source, blocks: blocks)
    }

    /// Settings › Writing › Autocorrect changed: prose takes the new
    /// traits now, in the keyboard already up.
    func setRewritesProse(_ enabled: Bool, in textView: UITextView) {
        guard keyboard.setRewritesProse(enabled) else { return }
        let snapshot = self.snapshot(of: textView)
        applyRewritingPolicy(to: textView, source: snapshot.source, blocks: snapshot.blocks)
    }

    func setCodeKeys(_ enabled: Bool, in textView: UITextView) {
        keyboard.setCodeKeys(enabled, in: textView)
    }

    func refreshCodeKeys(in textView: UITextView, reloading: Bool) {
        keyboard.refreshCodeKeys(in: textView, reloading: reloading)
    }

    /// A tap on the row.
    func perform(_ key: CodeKey) {
        guard let textView, textView.isEditable else { return }
        let selection = textView.selectedRange
        let text = textView.textStorage.mutableString

        switch key {
        case .insert(let characters):
            guard let range = textView.selectedTextRange else { return }
            textView.replace(range, withText: characters)
        case .indent, .outdent:
            guard let edit = CodeIndent.indentEdit(
                in: text, selection: selection, outdent: key == .outdent,
                codeRanges: codeRanges(in: textView.textStorage), width: indentWidth
            ) else { return }
            apply(edit, to: textView)
        case .left, .right:
            // A selection collapses to the edge the arrow points at, as
            // the system's arrows do; otherwise one character.
            var target = key == .left ? selection.location : NSMaxRange(selection)
            if selection.length == 0 {
                if key == .left, target > 0 {
                    target = text.rangeOfComposedCharacterSequence(at: target - 1).location
                } else if key == .right, target < text.length {
                    target = NSMaxRange(text.rangeOfComposedCharacterSequence(at: target))
                }
            }
            textView.selectedRange = NSRange(location: target, length: 0)
            textView.scrollRangeToVisible(textView.selectedRange)
        }
    }
}

#endif
