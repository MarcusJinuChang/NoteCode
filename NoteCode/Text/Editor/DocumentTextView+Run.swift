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

    /// Runs a block: the editor's features are asked first (Pro's Run: the
    /// paywall, or the panel); with none that takes it, the block opens on a
    /// compiler site.
    ///
    /// Nothing is executed on the device: the panel sends the block to our
    /// run service. Only a build without one hands it to a site instead.
    func run(_ target: CodeBlockTarget, from textView: UITextView) {
        guard let language = target.language, language.canRun else { return }

        // A feature that takes it does its own gate (R4) and resigns the
        // keyboard when it runs.
        if editor?.features.contains(where: { $0.run(target, from: textView) }) == true {
            return
        }

        openAtSite(code: target.code, language: language, from: textView)
    }

    /// Opens a block on a site (`CodeDestination.request(for:language:)`):
    /// the panel's way out when a run can't happen, and Run itself in a
    /// build without a service. Where the code travels in the link the
    /// student lands on a finished run; where it can't, it goes on the
    /// pasteboard and they paste it on arrival.
    func openAtSite(code: String, language: CodeLanguage, from textView: UITextView?) {
        let request = CodeDestination.request(for: code, language: language)

        if let code = request.pasteboardCode {
            UIPasteboard.general.string = code
        }

        // Dismiss the keyboard first. Leaving for Safari with it up means
        // coming back to a view that has to re-lay-out under it.
        textView?.resignFirstResponder()
        openURL(request.url)
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
