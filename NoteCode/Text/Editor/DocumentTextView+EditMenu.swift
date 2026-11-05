//
//  DocumentTextView+EditMenu.swift
//  NoteCode
//
//  The coordinator's edit menu: a code block's actions, and the prose
//  formatting.
//

#if canImport(UIKit)

import UIKit

extension DocumentTextView.Coordinator {


    /// The edit menu: Run Block, Copy Block and Share for the code block
    /// under the caret, and Bold, Italic, Code and Format › in prose.
    ///
    /// The edit menu is the right home for this: no new chrome, no overlay
    /// to position, and it appears exactly where a selection already is.
    ///
    /// Mind the label. This is iOS 26's plural method, and Swift keeps
    /// "Ranges" in its name because the argument is `[NSValue]`, where the
    /// deprecated singular loses "Range" to its `NSRange` argument. Spelt
    /// `editMenuForTextIn ranges:`, it matches no requirement and UIKit
    /// never calls it, with only a "nearly matches" warning to say so.
    ///
    /// There is deliberately no singular fallback. The deployment target
    /// is 27.0, so UIKit always has this one to call, and a fallback is
    /// what once hid this method's wrong label: the menu kept working.
    func textView(
        _ textView: UITextView,
        editMenuForTextInRanges ranges: [NSValue],
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        let caret = ranges.first?.rangeValue.location ?? textView.selectedRange.location
        return menu(for: textView, at: caret, suggestedActions: suggestedActions)
    }

    private func menu(
        for textView: UITextView,
        at caret: Int,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        if let target = target(atCaret: caret, in: textView) {
            // An empty block has nothing to run or copy.
            guard !target.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return UIMenu(children: suggestedActions)
            }
            return UIMenu(children: EditMenuOrder.order(
                ours: [codeBlockMenu(for: target, in: textView)], system: suggestedActions
            ))
        }

        // Formatting changes the text, and ink mode and a locked note
        // leave it alone (`NoteEditor.perform` would do nothing).
        guard let editor, editor.mode == .text, !editor.isTextLocked else {
            return UIMenu(children: suggestedActions)
        }
        return UIMenu(children: EditMenuOrder.order(ours: [proseMenu(editor)], system: suggestedActions))
    }

    /// Run Block and Copy Block, then Share, which was here first.
    ///
    /// Run is left out for a block with no language the app knows, as the
    /// action bar leaves out its play button: there's nowhere to send it.
    private func codeBlockMenu(for target: CodeBlockTarget, in textView: UITextView) -> UIMenu {
        var actions: [UIMenuElement] = []

        if target.canRun {
            actions.append(UIAction(title: "Run Block", image: UIImage(systemName: "play")) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                run(target, from: textView)
            })
        }

        actions.append(UIAction(title: "Copy Block", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
            self?.copy(target)
        })

        actions.append(UIAction(title: "Share Block", image: UIImage(systemName: "square.and.arrow.up")) { [weak textView] _ in
            guard let textView else { return }
            Self.share(target.code, from: textView)
        })

        // The on-device assistant. Left out when it is switched off or
        // this iPad can never run it; otherwise the sheet says why not.
        if let editor, editor.ai.offersFeatures, !target.isOutput {
            actions.append(UIAction(title: editor.ai.isPro() ? "Explain Block" : "Explain Block (Pro)", image: UIImage(systemName: AIAction.explainBlock.systemImage)) { [weak editor] _ in
                editor?.explain(target)
            })
        }

        return UIMenu(options: .displayInline, children: actions)
    }

    /// Bold, Italic and Code, then a Format submenu for the rest.
    ///
    /// The same edits the hotbar's buttons make, through the editor, so
    /// they land on the undo stack and are styled like typed text.
    private func proseMenu(_ editor: NoteEditor) -> UIMenu {
        let inline = UIMenu(options: .displayInline, children: [
            UIAction(title: "Bold", image: UIImage(systemName: "bold")) { _ in editor.toggle(.bold) },
            UIAction(title: "Italic", image: UIImage(systemName: "italic")) { _ in editor.toggle(.italic) },
            UIAction(title: "Underline", image: UIImage(systemName: "underline")) { _ in editor.toggle(.underline) },
            UIAction(title: "Code", image: UIImage(systemName: "chevron.left.forwardslash.chevron.right")) { _ in
                editor.toggle(.code)
            },
        ])

        let format = UIMenu(title: "Format", image: UIImage(systemName: "textformat"), children: [
            UIAction(title: "Strikethrough", image: UIImage(systemName: "strikethrough")) { _ in
                editor.toggle(.strikethrough)
            },
            UIAction(title: "Heading 1") { _ in editor.setHeading(level: 1) },
            UIAction(title: "Heading 2") { _ in editor.setHeading(level: 2) },
            UIAction(title: "Heading 3") { _ in editor.setHeading(level: 3) },
            UIAction(title: "Heading 4") { _ in editor.setHeading(level: 4) },
            UIAction(title: "Heading 5") { _ in editor.setHeading(level: 5) },
            UIAction(title: "Heading 6") { _ in editor.setHeading(level: 6) },
            UIAction(title: "Body") { _ in editor.setHeading(level: 0) },
            UIAction(title: "Inline Formula", image: UIImage(systemName: "function")) { _ in
                editor.insertFormula(display: false)
            },
            UIAction(title: "Display Formula", image: UIImage(systemName: "x.squareroot")) { _ in
                editor.insertFormula(display: true)
            },
        ])

        return UIMenu(options: .displayInline, children: [inline, format])
    }

    private static func share(_ code: String, from textView: UITextView) {
        guard let presenter = textView.window?.rootViewController else { return }

        let activity = UIActivityViewController(activityItems: [code], applicationActivities: nil)

        // iPad presents this as a popover and needs an anchor, so point it
        // at the caret rather than an arbitrary corner.
        if let popover = activity.popoverPresentationController {
            popover.sourceView = textView
            popover.sourceRect = textView.selectedTextRange.map { textView.firstRect(for: $0) }
                ?? CGRect(x: textView.bounds.midX, y: textView.bounds.midY, width: 1, height: 1)
        }

        presenter.present(activity, animated: true)
    }
}

#endif
