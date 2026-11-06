//
//  KeyboardPolicyController.swift
//  NoteCode
//
//  What the keyboard is set up as for where the caret is: prose or code
//  traits, and the code-keys row above it. Pulled out of
//  `DocumentTextView.Coordinator` (2T5); the Coordinator keeps forwarding
//  members for the call sites and tests that already use them.
//

#if canImport(UIKit)

import UIKit

@MainActor
final class KeyboardPolicyController {

    /// The keyboard traits the text view has now: prose or code.
    private(set) var rewritingPolicy = TextRewritingPolicy.initial
    private(set) var rewritesProse = TextRewritingPolicy.proseEnabledByDefault

    /// Settings › Code › Code Keys, and the row it turns on.
    private(set) var codeKeysEnabled = CodeKeys.enabledByDefault

    /// A tap on the row. Set by the Coordinator, which edits the text.
    var onKey: ((CodeKey) -> Void)?

    /// The text view served, for whether it is editable and for a hardware
    /// keyboard coming or going.
    weak var textView: UITextView?

    private lazy var codeKeysRow: CodeKeysRow = {
        let row = CodeKeysRow()
        row.onKey = { [weak self] key in self?.onKey?(key) }
        return row
    }()
    private var hardwareKeyboardObservers: [NSObjectProtocol] = []

    init() {
        // A keyboard attached or taken away changes whether the row is
        // wanted, with the caret where it was.
        hardwareKeyboardObservers = HardwareKeyboard.observe { [weak self] in
            guard let self, let textView else { return }
            refreshCodeKeys(in: textView, reloading: true)
        }
    }

    deinit {
        hardwareKeyboardObservers.forEach(NotificationCenter.default.removeObserver)
    }

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

    /// Settings › Writing › Autocorrect: whether it changed. The caller then
    /// applies the policy to the keyboard already up.
    func setRewritesProse(_ enabled: Bool) -> Bool {
        guard enabled != rewritesProse else { return false }
        rewritesProse = enabled
        return true
    }

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
}

#endif
