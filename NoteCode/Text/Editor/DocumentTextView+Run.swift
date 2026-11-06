//
//  DocumentTextView+Run.swift
//  NoteCode
//
//  The coordinator's Run: a block's Run button, Run Block and ⌘R, a
//  compiler site, and the services a feature is handed (EditorServices).
//

#if canImport(UIKit)

import UIKit

extension DocumentTextView.Coordinator {

    /// Runs a block (`CodeBlockCommands.run`).
    func run(_ target: CodeBlockTarget, from textView: UITextView) {
        codeBlocks.run(target, from: textView, editor: editor)
    }

    /// Opens a block on a compiler site (`CodeBlockCommands.openAtSite`).
    func openAtSite(code: String, language: CodeLanguage, from textView: UITextView?) {
        codeBlocks.openAtSite(code: code, language: language, from: textView)
    }

    /// What this coordinator does for the editor's features, on `textView`.
    func featureServices(for textView: UITextView) -> EditorServices {
        EditorServices(
            text: { [weak self, weak textView] in
                guard let self, let textView else { return "" }
                return snapshot(of: textView).source
            },
            blocks: { [weak self, weak textView] in
                guard let self, let textView else { return [] }
                return snapshot(of: textView).targets
            },
            openAtSite: { [weak self, weak textView] code, language in
                self?.openAtSite(code: code, language: language, from: textView)
            },
            apply: { [weak self, weak textView] edit in
                guard let self, let textView else { return }
                apply(edit, to: textView)
            },
            placeCaret: { [weak textView] offset in
                guard let textView else { return }
                if !textView.isFirstResponder { textView.becomeFirstResponder() }
                textView.selectedRange = NSRange(location: offset, length: 0)
                textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
            }
        )
    }
}

#endif
