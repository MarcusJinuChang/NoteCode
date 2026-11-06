//
//  CodeBlockCommands.swift
//  NoteCode
//
//  What can be done to a code block: copy it, run it (the editor's features
//  first, a compiler site after), the edit menu's entries for it, and the
//  one-level indent the Tab key and the options row share. Pulled out of
//  `DocumentTextView.Coordinator` (2T6); the Coordinator keeps forwarding
//  methods, which the action bars, the menu and the tests call.
//
//  It reads nothing of its own: the text view, the editor and the blocks
//  come in with each call, so it holds no reference that could outlive them.
//

#if canImport(UIKit)

import UIKit

@MainActor
final class CodeBlockCommands {

    /// Opens a compiler site's link (`openAtSite`). Replaceable so a test
    /// can see where Run went without leaving the app.
    var openURL: (URL) -> Void = { UIApplication.shared.open($0) }

    // MARK: Copy

    /// Puts a block's code on the pasteboard, with a light tap. One path
    /// for the button, the edit menu and ⇧⌘C.
    func copy(_ target: CodeBlockTarget, told editor: NoteEditor?) {
        UIPasteboard.general.string = target.code
        Haptics.copyBlock()
        editor?.onBlockCopied?()
    }

    // MARK: Run

    /// Runs a block: the editor's features are asked first (Pro's Run: the
    /// paywall, or the panel); with none that takes it, the block opens on a
    /// compiler site.
    ///
    /// Nothing is executed on the device: the panel sends the block to our
    /// run service. Only a build without one hands it to a site instead.
    func run(_ target: CodeBlockTarget, from textView: UITextView, editor: NoteEditor?) {
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

    // MARK: Finding and indenting

    /// The code block the caret is in, for the edit menu and ⌘R and ⇧⌘C.
    func target(atCaret caret: Int, in snapshot: DocumentSnapshot, sourceLength: Int) -> CodeBlockTarget? {
        CodeBlockAction.target(atCaret: caret, in: snapshot.targets, sourceLength: sourceLength)
    }

    /// One level in or out at the caret: the code lines' rule in a code
    /// block, the list item's elsewhere. Tab, ⇧Tab and the text options
    /// row's ⇥ and ⇤ all ask here.
    func indentEdit(outdent: Bool, in textView: UITextView, codeRanges: [CodeRange], width: Int) -> TextEdit? {
        if let edit = CodeIndent.indentEdit(
            in: textView.textStorage.mutableString,
            selection: textView.selectedRange,
            outdent: outdent,
            codeRanges: codeRanges,
            width: width
        ) {
            return edit
        }
        return MarkdownFormatting.indent(
            in: textView.textStorage.mutableString,
            selection: textView.selectedRange,
            outdent: outdent,
            codeRanges: codeRanges
        )
    }

    // MARK: The edit menu

    /// Run Block and Copy Block, then Share, which was here first.
    ///
    /// Run is left out for a block with no language the app knows, as the
    /// action bar leaves out its play button: there's nowhere to send it.
    func menu(for target: CodeBlockTarget, in textView: UITextView, editor: NoteEditor?) -> UIMenu {
        var actions: [UIMenuElement] = []

        if target.canRun {
            actions.append(UIAction(title: "Run Block", image: UIImage(systemName: "play")) { [weak self, weak textView, weak editor] _ in
                guard let self, let textView else { return }
                run(target, from: textView, editor: editor)
            })
        }

        actions.append(UIAction(title: "Copy Block", image: UIImage(systemName: "doc.on.doc")) { [weak self, weak editor] _ in
            self?.copy(target, told: editor)
        })

        actions.append(UIAction(title: "Share Block", image: UIImage(systemName: "square.and.arrow.up")) { [weak textView] _ in
            guard let textView else { return }
            Self.share(target.code, from: textView)
        })

        // What the edition adds (`EditorFeature`), after these: the
        // assistant's Explain Block.
        for action in editor?.actions(for: .codeBlock(target), in: .codeBlockMenu) ?? [] {
            let item = UIAction(title: action.title, image: UIImage(systemName: action.symbol)) { _ in
                action.perform()
            }
            if !action.isAvailable { item.attributes = .disabled }
            actions.append(item)
        }

        return UIMenu(options: .displayInline, children: actions)
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
