//
//  DocumentTextView+Run.swift
//  NoteCode
//
//  The coordinator's Run: a block's Run button, Run Block and ⌘R, a
//  compiler site, and what the panel writes back into the note.
//

#if canImport(UIKit)

import UIKit

extension DocumentTextView.Coordinator {

    /// Runs a block: in the panel for Pro, the paywall for everyone else.
    ///
    /// Nothing is executed on the device: the panel sends the block to our
    /// run service. Only a build without one hands it to a site instead.
    func run(_ target: CodeBlockTarget, from textView: UITextView) {
        guard let language = target.language, language.canRun else { return }

        // The gate comes first (R4): a free reader's Run opens the paywall
        // and does nothing else. Without a service none of this exists.
        switch RunRoute.route(
            hasRunner: editor?.run.isAvailable == true,
            isPro: ProGate.isPro
        ) {
        case .paywall:
            editor?.onRunNeedsPro?()
            return
        case .inApp:
            textView.resignFirstResponder()
            editor?.runInApp(target)
            return
        case .redirect:
            break
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
        UIApplication.shared.open(request.url)
    }


    /// Keep in Note: the run's output as an ```` ```output ```` block under
    /// the code, or in place of the one already there. One `replace`, so one
    /// undo step. Not in a locked note.
    func keepInNote(_ output: String, forBlockAt ordinal: Int, in textView: UITextView) {
        guard editor?.isTextLocked != true else { return }
        let source = (textView.text ?? "").nativeUTF8
        let targets = CodeBlockAction.targets(in: source, blocks: documentCache.blocks(for: source))
        guard let edit = KeepInNote.edit(output: output, forBlockAt: ordinal, in: source, targets: targets) else { return }
        apply(edit, to: textView)
    }

    /// A compile-error link: the caret on that line of the block, in view.
    func showLine(_ line: Int, ofBlockAt ordinal: Int, in textView: UITextView) {
        guard editor?.mode == .text else { return }
        let source = (textView.text ?? "").nativeUTF8
        let targets = CodeBlockAction.targets(in: source, blocks: documentCache.blocks(for: source))
        guard let target = targets.first(where: { $0.id.ordinal == ordinal && !$0.isOutput }),
              let offset = KeepInNote.caretOffset(line: line, in: target, source: source)
        else { return }
        if !textView.isFirstResponder { textView.becomeFirstResponder() }
        textView.selectedRange = NSRange(location: offset, length: 0)
        textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
    }
}

#endif
