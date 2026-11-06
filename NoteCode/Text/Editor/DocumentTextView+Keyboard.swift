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

    /// Gives prose autocorrect and smart punctuation, and code neither,
    /// by where the caret is.
    ///
    /// Only on crossing from one to the other: reloading the keyboard
    /// redraws its suggestion bar, and this runs on every keystroke.
    func applyRewritingPolicy(to textView: UITextView, source: String, blocks: [BlockNode]) {
        // Mid-composition (Korean, Japanese, Chinese), a keyboard reload
        // could disturb the character being composed. The first caret move
        // after it's committed catches up.
        guard textView.markedTextRange == nil else { return }

        let policy = TextRewritingPolicy.at(
            textView.selectedRange.location, in: source, blocks: blocks, rewritesProse: rewritesProse
        )
        guard policy != rewritingPolicy else {
            // The caret is in the same kind of text, but the row might
            // not have been put there yet: the first tap into a note
            // starts out as code and crosses nothing.
            refreshCodeKeys(in: textView, reloading: true)
            return
        }
        rewritingPolicy = policy
        // The row is chosen before the one reload, so crossing from prose
        // to code changes the traits and the row in a single redraw.
        _ = placeCodeKeys(in: textView)
        policy.apply(to: textView, reloadingInputViews: textView.isFirstResponder)
    }

    /// Settings › Writing › Autocorrect changed: prose takes the new
    /// traits now, in the keyboard already up.
    func setRewritesProse(_ enabled: Bool, in textView: UITextView) {
        guard enabled != rewritesProse else { return }
        rewritesProse = enabled
        let snapshot = self.snapshot(of: textView)
        applyRewritingPolicy(to: textView, source: snapshot.source, blocks: snapshot.blocks)
    }

    // MARK: The code-keys row

    func setCodeKeys(_ enabled: Bool, in textView: UITextView) {
        guard enabled != codeKeysEnabled else { return }
        codeKeysEnabled = enabled
        refreshCodeKeys(in: textView, reloading: true)
    }

    /// Whether the row belongs on the keyboard right now.
    var wantsCodeKeys: Bool {
        CodeKeys.isShown(
            enabled: codeKeysEnabled,
            policy: rewritingPolicy,
            hardwareKeyboard: HardwareKeyboard.isConnected(),
            isEditable: textView?.isEditable ?? false
        )
    }

    /// Puts the row on the text view, or takes it off. Whether the
    /// accessory changed.
    @discardableResult
    func placeCodeKeys(in textView: UITextView) -> Bool {
        let wanted: UIView? = wantsCodeKeys ? codeKeysRow : nil
        guard textView.inputAccessoryView !== wanted else { return false }
        textView.inputAccessoryView = wanted
        return true
    }

    /// `placeCodeKeys`, then the keyboard is redrawn if the row came or
    /// went while it is up.
    func refreshCodeKeys(in textView: UITextView, reloading: Bool) {
        guard placeCodeKeys(in: textView), reloading, textView.isFirstResponder,
              textView.markedTextRange == nil
        else { return }
        textView.reloadInputViews()
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
