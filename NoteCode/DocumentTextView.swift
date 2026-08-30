//
//  DocumentTextView.swift
//  NoteCode
//
//  The editor SwiftUI's TextEditor can't be: a real UITextView we own, backed
//  by TextKit 2, so later phases can reach its NSTextLayoutManager to style
//  fenced code regions.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

struct DocumentTextView: UIViewRepresentable {
    @Binding var text: String

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> UITextView {
        let textView = Self.makeConfiguredTextView()
        textView.delegate = context.coordinator
        // Fragment selection happens through the layout manager, not the text
        // view, so the coordinator has to be wired in as both delegates.
        textView.textLayoutManager?.delegate = context.coordinator
        textView.text = text
        context.coordinator.invalidateStyling()
        context.coordinator.restyle(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // The struct is recreated on every SwiftUI render but the Coordinator
        // persists, so hand it the current binding or it will keep writing
        // through a stale one.
        context.coordinator.text = $text

        // Only push text down when it actually differs. Assigning `.text`
        // unconditionally would reset the selection on every render and fight
        // the user for control of the caret while they type.
        if textView.text != text {
            // Assigning `.text` resets the storage to plain attributes, so the
            // styling has to be reapplied every time text arrives from outside.
            // Assigning `.text` resets the storage to plain attributes, so
            // nothing on screen can be reused.
            textView.text = text
            context.coordinator.invalidateStyling()
            context.coordinator.restyle(textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    // MARK: Coordinator

    /// Owns the UIKit delegate callbacks and forwards edits back into SwiftUI.
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        let documentCache = DocumentCache()

        /// What the document looked like at the last styling pass, so only the
        /// blocks that actually changed get restyled.
        private var styleSignatures: [DocumentStyler.BlockSignature] = []

        private let highlighter: SyntaxHighlighter = HighlightSwiftHighlighter()
        private var highlightTask: Task<Void, Never>?

        /// Bumped on every edit. A highlight result carrying an older number
        /// describes a document that no longer exists, so it gets dropped.
        private var highlightGeneration = 0

        /// Blocks already coloured, keyed by content. A block whose code hasn't
        /// changed keeps the colours already in the text storage, so only the
        /// block being edited needs re-highlighting.
        private var highlightedBlocks: Set<CodeBlockID> = []

        /// Just enough to coalesce a fast burst of keystrokes.
        ///
        /// This was 200ms, chosen before measuring. Highlighting one block
        /// takes 3.6–5.2ms, so 200ms was roughly forty times more caution than
        /// the work needed — and it was long enough that a word stayed
        /// uncoloured while being typed.
        private static let highlightDelay = Duration.milliseconds(20)

        init(text: Binding<String>) {
            self.text = text
        }

        /// Re-parses and re-applies styling. Everything goes through the shared
        /// cache, so an edit parses the document exactly once no matter how many
        /// delegate callbacks it triggers.
        func restyle(_ textView: UITextView) {
            // Read the text exactly once. Every range below indexes into this
            // instance, and mixing instances is ruinously slow — see the note
            // on DocumentStyler.applyStyling(to:source:blocks:previousSignatures:).
            let source = textView.text ?? ""
            let blocks = documentCache.blocks(for: source)

            styleSignatures = DocumentStyler.applyStyling(
                to: textView,
                source: source,
                blocks: blocks,
                previousSignatures: styleSignatures
            )
            DocumentStyler.applyTypingAttributes(to: textView, source: source, blocks: blocks)
            scheduleHighlighting(for: textView, source: source, blocks: blocks)
        }

        /// Kicks off syntax colouring after a pause in typing.
        ///
        /// The styling pass above has already reset every foreground to
        /// `.label`, so if this never completes the code simply stays plain
        /// monospace — a working fallback rather than a broken state.
        func scheduleHighlighting(for textView: UITextView, source: String, blocks: [BlockNode]) {
            highlightTask?.cancel()

            highlightGeneration &+= 1
            let generation = highlightGeneration
            let appearance = HighlightAppearance(textView.traitCollection)

            // Forget blocks that no longer exist, so the set can't grow forever.
            highlightedBlocks.formIntersection(Set(blocks.compactMap(\.codeBlock?.id)))

            // Snapshot of what to send, taken before any await. Only blocks
            // whose code changed since the last pass — everything else still
            // holds the right colours, which applyStyling carries across.
            let jobs: [(id: CodeBlockID, code: String, tag: String, offset: Int)] = blocks.compactMap { node in
                guard let code = node.codeBlock,
                      let tag = code.infoString.split(separator: " ").first,
                      !highlightedBlocks.contains(code.id)
                else { return nil }
                return (
                    code.id,
                    String(source[code.contentRange]),
                    String(tag),
                    NSRange(code.contentRange, in: source).location
                )
            }
            guard !jobs.isEmpty else { return }

            highlightTask = Task { [weak self, weak textView] in
                try? await Task.sleep(for: Self.highlightDelay)
                guard !Task.isCancelled, let self, let textView else { return }

                var painted: [ColorRun] = []
                for job in jobs {
                    let runs = await highlighter.colorRuns(
                        for: job.code,
                        languageTag: job.tag,
                        appearance: appearance
                    )
                    guard !Task.isCancelled else { return }

                    painted += runs.map { run in
                        ColorRun(
                            range: NSRange(location: job.offset + run.range.location, length: run.range.length),
                            color: run.color
                        )
                    }
                }

                // The document can move while the JS runs. Painting these runs
                // now would colour text at offsets that have shifted underneath
                // them, so both the generation and the text itself are checked.
                guard generation == self.highlightGeneration,
                      textView.text == source
                else { return }

                let covered = jobs.map { NSRange(location: $0.offset, length: ($0.code as NSString).length) }
                DocumentStyler.applyColors(painted, clearing: covered, to: textView)
                self.highlightedBlocks.formUnion(jobs.map(\.id))
            }
        }

        /// Forgets what's on screen, forcing the next restyle to do everything.
        /// Needed whenever the storage is replaced wholesale.
        func invalidateStyling() {
            styleSignatures = []
            // Replacing the storage wipes the colours too.
            highlightedBlocks = []
        }

        func textViewDidChange(_ textView: UITextView) {
            restyle(textView)
            text.wrappedValue = textView.text
        }

        /// Adds copy and share for the code block under the caret.
        ///
        /// The edit menu is the right home for this: no new chrome, no overlay
        /// to position, and it appears exactly where a selection already is.
        ///
        /// Two methods because UIKit changed the shape in iOS 26 — the plural
        /// one is preferred and the singular is its deprecated predecessor.
        /// Implementing only the deprecated one silently never gets called.
        func textView(
            _ textView: UITextView,
            editMenuForTextIn ranges: [NSValue],
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            let caret = ranges.first?.rangeValue.location ?? textView.selectedRange.location
            return menu(for: textView, at: caret, suggestedActions: suggestedActions)
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            menu(for: textView, at: range.location, suggestedActions: suggestedActions)
        }

        private func menu(
            for textView: UITextView,
            at caret: Int,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            let source = textView.text ?? ""
            let blocks = documentCache.blocks(for: source)

            guard let code = CodeBlockAction.code(atCaret: caret, in: source, blocks: blocks),
                  !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return UIMenu(children: suggestedActions)
            }

            let copy = UIAction(title: "Copy Code Block", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = code
            }

            let share = UIAction(title: "Share Code Block", image: UIImage(systemName: "square.and.arrow.up")) { [weak textView] _ in
                guard let textView else { return }
                Self.share(code, from: textView)
            }

            return UIMenu(children: [UIMenu(options: .displayInline, children: [copy, share])] + suggestedActions)
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

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Moving the caret across a fence boundary changes what the next
            // character should look like, even though no text changed. This
            // fires on every keystroke too, so it reads through the cache
            // rather than re-parsing.
            let source = textView.text ?? ""
            let blocks = documentCache.blocks(for: source)
            DocumentStyler.applyTypingAttributes(to: textView, source: source, blocks: blocks)
        }
    }

    // MARK: Configuration

    /// Builds the text view. Kept separate from `makeUIView` so tests can
    /// inspect the configuration without standing up a SwiftUI hierarchy.
    static func makeConfiguredTextView() -> UITextView {
        // Opt into TextKit 2 explicitly.
        //
        // Careful: reading the legacy `.layoutManager` property anywhere on this
        // view silently downgrades it to TextKit 1 and leaves `textLayoutManager`
        // nil — at which point none of the code-region rendering will run and
        // there is no error to tell you why.
        let textView = UITextView(usingTextLayoutManager: true)

        textView.isEditable = true
        textView.isScrollEnabled = true
        // Pasting rich text would drop foreign fonts and colours into the
        // storage that fight the styling pass. Off means paste arrives plain.
        textView.allowsEditingTextAttributes = false
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)

        // Prose is the document's default; code styling arrives with fence
        // rendering. Dynamic Type so the editor respects the reader's text size.
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true

        // All five text-rewriting traits live in TextRewritingPolicy so that
        // switching them per region later is one call. `.code` (everything off)
        // is today's behavior — see the roadmap's deferred-work section.
        TextRewritingPolicy.current.apply(to: textView)

        return textView
    }
}

// MARK: - Fragment selection

extension DocumentTextView.Coordinator: NSTextLayoutManagerDelegate {

    /// Called for each paragraph as it enters the viewport. Returning a
    /// CodeBlockLayoutFragment is what makes that paragraph draw a panel.
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let plain = NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)

        guard let contentManager = textLayoutManager.textContentManager,
              let storage = contentManager as? NSTextContentStorage,
              let source = storage.textStorage?.string,
              let elementRange = textElement.elementRange
        else { return plain }

        // NSTextLocation is opaque; offsets come from the content manager.
        let start = contentManager.offset(from: contentManager.documentRange.location, to: elementRange.location)
        let length = contentManager.offset(from: elementRange.location, to: elementRange.endLocation)
        let element = NSRange(location: start, length: length)

        for block in documentCache.blocks(for: source) where block.isCode {
            guard let position = CodeBlockPosition.of(element: element, in: NSRange(block.range, in: source)) else {
                continue
            }
            let fragment = CodeBlockLayoutFragment(textElement: textElement, range: textElement.elementRange)
            fragment.position = position
            return fragment
        }

        return plain
    }
}

#endif
