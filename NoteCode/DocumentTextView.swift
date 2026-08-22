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
            textView.text = text
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
        let regionCache = CodeRegionCache()

        private let highlighter: SyntaxHighlighter = HighlightSwiftHighlighter()
        private var highlightTask: Task<Void, Never>?

        /// Bumped on every edit. A highlight result carrying an older number
        /// describes a document that no longer exists, so it gets dropped.
        private var highlightGeneration = 0

        /// How long typing has to pause before the JS round trip is worth
        /// starting. Short enough to feel immediate, long enough that holding
        /// a key down doesn't queue a highlight per character.
        private static let highlightDelay = Duration.milliseconds(200)

        init(text: Binding<String>) {
            self.text = text
        }

        /// Re-parses and re-applies styling. Everything goes through the shared
        /// cache, so an edit parses the document exactly once no matter how many
        /// delegate callbacks it triggers.
        func restyle(_ textView: UITextView) {
            let regions = regionCache.regions(for: textView.text ?? "")
            DocumentStyler.applyStyling(to: textView, regions: regions)
            DocumentStyler.applyTypingAttributes(to: textView, regions: regions)
            scheduleHighlighting(for: textView, regions: regions)
        }

        /// Kicks off syntax colouring after a pause in typing.
        ///
        /// The styling pass above has already reset every foreground to
        /// `.label`, so if this never completes the code simply stays plain
        /// monospace — a working fallback rather than a broken state.
        func scheduleHighlighting(for textView: UITextView, regions: [Region]) {
            highlightTask?.cancel()

            highlightGeneration &+= 1
            let generation = highlightGeneration
            let source = textView.text ?? ""
            let appearance = HighlightAppearance(textView.traitCollection)

            let blocks: [(code: String, language: CodeLanguage, offset: Int)] = regions.compactMap { region in
                guard let block = region.codeBlock, let language = block.language else { return nil }
                return (
                    String(source[block.contentRange]),
                    language,
                    NSRange(block.contentRange, in: source).location
                )
            }
            guard !blocks.isEmpty else { return }

            highlightTask = Task { [weak self, weak textView] in
                try? await Task.sleep(for: Self.highlightDelay)
                guard !Task.isCancelled, let self, let textView else { return }

                var painted: [ColorRun] = []
                for block in blocks {
                    let runs = await highlighter.colorRuns(
                        for: block.code,
                        language: block.language,
                        appearance: appearance
                    )
                    guard !Task.isCancelled else { return }

                    painted += runs.map { run in
                        ColorRun(
                            range: NSRange(location: block.offset + run.range.location, length: run.range.length),
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

                DocumentStyler.applyColors(painted, to: textView)
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            restyle(textView)
            text.wrappedValue = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Moving the caret across a fence boundary changes what the next
            // character should look like, even though no text changed. This
            // fires on every keystroke too, so it reads through the cache
            // rather than re-parsing.
            let regions = regionCache.regions(for: textView.text ?? "")
            DocumentStyler.applyTypingAttributes(to: textView, regions: regions)
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

        for region in regionCache.regions(for: source) where region.isCode {
            guard let position = CodeBlockPosition.of(element: element, in: NSRange(region.range, in: source)) else {
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
