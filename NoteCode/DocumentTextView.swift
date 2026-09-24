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

    /// Where this page's run buttons send a code block. Resolved by the caller
    /// from the page's own setting and the app-wide default — see
    /// `RunDestinationPreference`.
    var runDestination: CodeDestination = .default

    /// The page's hotbar state. Optional so the editor still stands alone in
    /// tests and previews.
    var editor: NoteEditor? = nil

    /// The note's page orientation and the device's view mode.
    var pageLayout = PageLayout()

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> PageView {
        let textView = Self.makeConfiguredTextView()
        textView.delegate = context.coordinator
        // Fragment selection happens through the layout manager, not the text
        // view, so the coordinator has to be wired in as both delegates.
        textView.textLayoutManager?.delegate = context.coordinator
        context.coordinator.attachOverlay(to: textView)
        context.coordinator.observeAppearance(of: textView)
        textView.text = text
        context.coordinator.invalidateStyling()
        context.coordinator.restyle(textView)
        context.coordinator.editor = editor
        let page = PageView(textView: textView)
        // After the page: `attach` applies the current mode, which now moves a
        // canvas knob too, and the canvas is the page's.
        editor?.attach(textView, canvas: page.canvas)
        page.pageLayout = pageLayout
        return page
    }

    func updateUIView(_ page: PageView, context: Context) {
        let textView = page.textView
        page.pageLayout = pageLayout

        // The struct is recreated on every SwiftUI render but the Coordinator
        // persists, so hand it the current binding or it will keep writing
        // through a stale one.
        context.coordinator.text = $text
        context.coordinator.runDestination = runDestination
        context.coordinator.editor = editor

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
        var runDestination: CodeDestination = .default
        var editor: NoteEditor?
        let documentCache = DocumentCache()

        /// The run and copy buttons floating over each code block.
        private var overlay: CodeBlockOverlay?

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

        /// The appearance `highlightedBlocks` were coloured for.
        ///
        /// Syntax colours are fixed values picked from one theme, not dynamic
        /// colours like `.label`, so a block coloured under dark is not coloured
        /// for light just because its code hasn't changed.
        private var highlightedAppearance: HighlightAppearance?

        /// Just enough to coalesce a fast burst of keystrokes.
        ///
        /// This was 200ms, chosen before measuring, which was long enough that
        /// a word stayed uncoloured while it was being typed.
        ///
        /// Colouring one block measures at a ~12.5ms median on an iPad Pro
        /// 13-inch simulator — see HighlighterCostTests. An earlier note here
        /// claimed 3.6–5.2ms; that is not reproducible, and since neither this
        /// file nor HighlightSwift has changed since it was written, it was
        /// most likely measured somewhere other than that test.
        ///
        /// The delay and the work do not compete for the same time. HighlightSwift's
        /// `Highlight` is a non-isolated Sendable class, so awaiting it from the
        /// main actor runs the JavaScript off-main; this delay only decides when
        /// that work starts. They add: colour lands roughly 32ms after typing
        /// stops, which is imperceptible. The one main-actor step is
        /// DocumentStyler.applyColors at the end, and it is small — that is the
        /// part to watch when the drawing layer starts competing for the main
        /// actor.
        private static let highlightDelay = Duration.milliseconds(20)

        init(text: Binding<String>) {
            self.text = text
        }

        /// Builds the action bars and connects them to the text view's layout.
        ///
        /// `layoutSubviews` is the one hook that covers everything that can
        /// move a block: scrolling (a scroll view lays out on every offset
        /// change), typing, rotation, and Split View. Subscribing to it means
        /// no separate scroll or bounds observers to keep in step.
        func attachOverlay(to textView: DocumentUITextView) {
            let overlay = CodeBlockOverlay(textView: textView)

            overlay.onCopy = { target in
                UIPasteboard.general.string = target.code
            }

            overlay.onRun = { [weak textView] target in
                guard let textView else { return }
                self.run(target, from: textView)
            }

            self.overlay = overlay
            textView.overlay = overlay
            textView.addLayoutObserver { [weak overlay] in overlay?.reposition() }
        }

        /// Hands a block to whichever site the page is pointed at.
        ///
        /// Nothing is executed here or anywhere else in the app. Where the code
        /// travels in the link the student lands on a finished run; where it
        /// can't, it goes on the pasteboard and they paste it on arrival.
        private func run(_ target: CodeBlockTarget, from textView: UITextView) {
            guard let language = target.language else { return }

            let request = CodeDestination.request(
                for: target.code,
                language: language,
                preferring: runDestination
            )

            if let code = request.pasteboardCode {
                UIPasteboard.general.string = code
            }

            // Dismiss the keyboard first. Leaving for Safari with it up means
            // coming back to a view that has to re-lay-out under it.
            textView.resignFirstResponder()
            UIApplication.shared.open(request.url)
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
            overlay?.update(targets: CodeBlockAction.targets(in: source, blocks: blocks))
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

            // Every block on screen was coloured for the other theme, so none of
            // them can be skipped. A pass still running under that theme is
            // dropped by the generation bump above.
            if appearance != highlightedAppearance {
                highlightedBlocks = []
                highlightedAppearance = appearance
            }

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

        /// Re-colours the code when the view switches between light and dark.
        ///
        /// Nothing else would: highlighting only runs after an edit, so a note
        /// left open across the switch keeps the old theme's colours.
        func observeAppearance(of textView: UITextView) {
            textView.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (textView: UITextView, _) in
                guard let self else { return }
                let source = textView.text ?? ""
                scheduleHighlighting(for: textView, source: source, blocks: documentCache.blocks(for: source))
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
            editor?.refreshUndoState()
        }

        /// Adds copy and share for the code block under the caret.
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
    static func makeConfiguredTextView() -> DocumentUITextView {
        // Opt into TextKit 2 explicitly.
        //
        // Careful: reading the legacy `.layoutManager` property anywhere on this
        // view silently downgrades it to TextKit 1 and leaves `textLayoutManager`
        // nil — at which point none of the code-region rendering will run and
        // there is no error to tell you why.
        let textView = DocumentUITextView(usingTextLayoutManager: true)

        textView.isEditable = true
        textView.isScrollEnabled = true
        // Pasting rich text would drop foreign fonts and colours into the
        // storage that fight the styling pass. Off means paste arrives plain.
        textView.allowsEditingTextAttributes = false
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .clear
        // Page points: a page's margins. PageView sets these from the note's
        // PageLayout, and manages the bottom so the note ends on a whole page.
        let pages = PageLayout()
        textView.textContainerInset = UIEdgeInsets(
            top: pages.firstBodyTop,
            left: PageLayout.margin,
            bottom: pages.trailingSpace,
            right: PageLayout.margin
        )

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
