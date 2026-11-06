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

    /// The page's hotbar state. Optional so the editor still stands alone in
    /// tests and previews.
    var editor: NoteEditor? = nil

    /// The half of the inputs that belong to the `PageView` this makes:
    /// layout, clearances, area, ink, reveal, resume, page count and growth,
    /// callbacks. See `PageConfiguration`.
    var pageConfiguration = PageConfiguration()

    /// The editor's settings, which move together: Show Markdown, marker
    /// dimming, whether the markers take room, Settings › Code and
    /// Autocorrect. See `EditorSettings`.
    var editorSettings = EditorSettings()

    /// The note's text size (`Page.textSize`), which sets every font the
    /// note is laid out in.
    var typography = NoteTypography.standard

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> PageView {
        let textView = Self.makeConfiguredTextView()
        textView.delegate = context.coordinator
        // Fragment selection happens through the layout manager, not the text
        // view, so the coordinator has to be wired in as both delegates.
        textView.textLayoutManager?.delegate = context.coordinator
        context.coordinator.observeEdits(of: textView)
        context.coordinator.attachOverlay(to: textView)
        context.coordinator.observeAppearance(of: textView)
        editorSettings.apply(to: context.coordinator, in: textView, typography: typography)
        textView.text = text
        context.coordinator.invalidateStyling()
        context.coordinator.restyle(textView)
        editorSettings.applyShowMarkdown(to: context.coordinator)
        context.coordinator.connect(editor, to: textView)
        let page = PageView(textView: textView)
        context.coordinator.keepBars(under: page.canvas)
        // After the page: `attach` applies the current mode, which now moves a
        // canvas knob too, and the canvas is the page's.
        editor?.attach(textView, canvas: page.canvas, page: page)
        pageConfiguration.apply(toNew: page, text: text)
        return page
    }

    func updateUIView(_ page: PageView, context: Context) {
        let textView = page.textView
        pageConfiguration.apply(to: page)

        // A new text size re-wraps the whole note, so the page keeps the
        // reader on the line they were reading, as a new orientation does.
        // The flag and the size are compared first: this runs on every
        // keystroke.
        if typography != context.coordinator.typography {
            page.reflow { context.coordinator.setTypography(typography, in: textView) }
        }

        // The struct is recreated on every SwiftUI render but the Coordinator
        // persists, so hand it the current binding or it will keep writing
        // through a stale one.
        context.coordinator.text = $text
        context.coordinator.editor = editor
        editorSettings.applyShowMarkdown(to: context.coordinator)
        editorSettings.apply(to: context.coordinator, in: textView)

        // Only push text down when it actually differs. Assigning `.text`
        // unconditionally would reset the selection on every render and fight
        // the user for control of the caret while they type.
        //
        // Compared as NSStrings, literally. Both sides are NSString-backed,
        // and Swift's `==` compares those canonically, a character at a time
        // through the bridge — on every keystroke, since this runs after each
        // one.
        if !(textView.textStorage.string as NSString).isEqual(to: text) {
            // Assigning `.text` resets the storage to plain attributes, so the
            // styling has to be reapplied every time text arrives from outside,
            // and nothing on screen can be reused.
            textView.text = text
            context.coordinator.invalidateStyling()
            context.coordinator.restyle(textView)
        }
        // After the text, so the setting is applied to the blocks it has now.
        context.coordinator.refreshFenceVisibility(in: textView)
        context.coordinator.refreshHeadingMarkers(in: textView)
    }

    /// The page is going: ink still on its way in is taken in now, so it
    /// reaches the saver while there's a page to save it to.
    static func dismantleUIView(_ page: PageView, coordinator: Coordinator) {
        page.commitInk()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    // MARK: Coordinator

    /// Owns the UIKit delegate callbacks and forwards edits back into SwiftUI.
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var editor: NoteEditor?

        /// The note as the last edit left it, made the first time anything
        /// asks after an edit and dropped by the next one
        /// (`textStorageDidProcessEditing`). Every reader goes through
        /// `snapshot(of:)`, so an edit converts the text and parses it once,
        /// however many callbacks it triggers.
        private var currentSnapshot: DocumentSnapshot?

        /// How many snapshots were made. Exists so a test can see that a
        /// layout, or a caret move, made none.
        private(set) var snapshotCount = 0

        /// The run and copy buttons floating over each code block.
        var overlay: CodeBlockOverlay?

        /// Opens a compiler site's link (`openAtSite`). Replaceable so a test
        /// can see where Run went without leaving the app.
        var openURL: (URL) -> Void = { UIApplication.shared.open($0) }

        /// The keyboard traits the text view has now: prose or code.
        private(set) var rewritingPolicy = TextRewritingPolicy.initial
        private(set) var rewritesProse = TextRewritingPolicy.proseEnabledByDefault

        /// Settings › Writing › Show Markdown, as `DocumentTextView` last had it.
        var showMarkdown = ShowMarkdown.whileEditing

        /// Settings › Writing › Markers, as `DocumentTextView` last had it.
        /// Changed through `setMarkerDimming`, which restyles.
        var markerDimming = MarkerDimming.standard

        /// Settings › Code › Indent Width.
        var indentWidth = CodeIndent.defaultWidth

        /// Settings › Code › Code Keys, and the row it turns on.
        private(set) var codeKeysEnabled = CodeKeys.enabledByDefault
        private lazy var codeKeysRow: CodeKeysRow = {
            let row = CodeKeysRow()
            row.onKey = { [weak self] key in self?.perform(key) }
            return row
        }()
        private var hardwareKeyboardObservers: [NSObjectProtocol] = []

        /// Settings › Code › Line Numbers.
        private(set) var showsLineNumbers = LineNumbers.enabledByDefault

        /// Whether the note lays its Markdown markers out at zero width.
        /// See `MarkdownLayout`. Set through `setRendersMarkdown`.
        private(set) var rendersMarkdown = false

        /// The size the note is styled in. A value the coordinator owns, not
        /// a global: a PDF or a thumbnail made while another note is open
        /// has a coordinator of its own. Set through `setTypography`.
        var typography = NoteTypography.standard

        /// Which blocks show their fences. See `CodeFenceDisplay.swift`.
        var fenceVisibility = FenceVisibility.away

        /// Which headings draw their hashes in the margin. See
        /// `HeadingMarkerDisplay.swift`.
        var headingVisibility = HeadingMarkerVisibility.hidden

        /// How many times the text's characters have been edited, so a
        /// selection change can tell typing from an arrow key.
        private var editCount = 0
        private var editCountAtLastSelection = 0
        /// Where the caret was at the last selection change, for the
        /// direction an arrow key walked it.
        private var lastCaret = 0
        private var isNormalizingCaret = false
        /// The formula editor now showing (`FormulaEditor`).
        var formulaEditor: UIViewController?

        /// Set while the coordinator applies an edit of its own (a Backspace
        /// at a hidden marker, a list's Return), so `shouldChangeTextIn`
        /// doesn't take it for another keystroke.
        private(set) var isApplyingMarkerEdit = false

        /// The text view this coordinator serves, for the parts of the layout
        /// delegate that need its geometry.
        weak var textView: DocumentUITextView?

        /// Set while a language pick rewrites a fence's tag, which the
        /// keyboard-rewrite guard in `shouldChangeTextIn` would turn away: it
        /// replaces text that isn't the selection, in code.
        var isRetagging = false

        /// The parts of the selection currently painted over code panels, so
        /// the next selection change can take them back off. See
        /// `CodeSelectionHighlight`.
        var paintedCodeSelection: [NSRange] = []

        /// What the document looked like at the last styling pass, so only the
        /// blocks that actually changed get restyled.
        var styleSignatures: [DocumentStyler.BlockSignature] = []

        private let highlighter: SyntaxHighlighter = HighlightSwiftHighlighter()
        private var highlightTask: Task<Void, Never>?

        /// Bumped on every edit. A highlight result carrying an older number
        /// describes a document that no longer exists, so it gets dropped.
        private var highlightGeneration = 0

        /// Blocks already coloured, keyed by content. A block whose code hasn't
        /// changed keeps the colours already in the text storage, so only the
        /// block being edited needs re-highlighting.
        var highlightedBlocks: Set<HighlightKey> = []

        /// A block as it was coloured: its code and the language it was
        /// coloured as. The tag is part of it because a retag changes neither
        /// the block's id nor its code, and the colours must still follow.
        struct HighlightKey: Hashable {
            var id: CodeBlockID
            var language: String

            nonisolated init(block: CodeBlock) {
                id = block.id
                language = block.infoString.split(separator: " ").first.map { $0.lowercased() } ?? ""
            }
        }

        /// The appearance `highlightedBlocks` were coloured for.
        ///
        /// Syntax colours are fixed values picked from one theme, not dynamic
        /// colours like `.label`, so a block coloured under dark is not coloured
        /// for light just because its code hasn't changed.
        private var highlightedAppearance: HighlightAppearance?

        /// The appearance code is always coloured for, whatever the text
        /// view's traits say. Nil follows the traits, as the editor does.
        ///
        /// Paper is light (`PrintedNote`), and its text view can't say so
        /// itself: a view in no window takes its appearance from the scene,
        /// and an override on the view doesn't change it (measured 16 Oct).
        /// With the device dark, the PDF and thumbnails had the dark theme's
        /// colours on a light panel.
        var pinnedAppearance: HighlightAppearance?

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

        /// What `highlightDelay` is measured on. Tests set one they move by
        /// hand; the app keeps `ContinuousClock`, as `Task.sleep(for:)` uses.
        var highlightClock: any Clock<Duration> = ContinuousClock()

        init(text: Binding<String>) {
            self.text = text
            super.init()
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

        /// Forgets the snapshot whenever the text storage is edited.
        func observeEdits(of textView: UITextView) {
            self.textView = textView as? DocumentUITextView
            if let documentView = self.textView {
                installMarkerGestures(on: documentView)
                installClipboard(on: documentView)
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(textStorageDidProcessEditing),
                name: NSTextStorage.didProcessEditingNotification,
                object: textView.textStorage
            )
        }

        @objc private func textStorageDidProcessEditing(_ notification: Notification) {
            guard let storage = notification.object as? NSTextStorage,
                  storage.editedMask.contains(.editedCharacters)
            else { return }
            currentSnapshot = nil
            editCount += 1
        }

        /// The note as it stands, made once per edit. `text` is read, and
        /// converted with `nativeUTF8`, only when no snapshot is held.
        func snapshot(of text: @autoclosure () -> String) -> DocumentSnapshot {
            if let currentSnapshot { return currentSnapshot }
            let snapshot = DocumentSnapshot(text: text(), editCount: editCount)
            currentSnapshot = snapshot
            snapshotCount += 1
            return snapshot
        }

        func snapshot(of textView: UITextView) -> DocumentSnapshot {
            snapshot(of: textView.text ?? "")
        }

        /// Turns the collapsed layout on or off, laying the whole note out
        /// again when that changes it. The text storage's elements are cached
        /// per paragraph, so a flag alone would leave every one as it was.
        func setRendersMarkdown(_ renders: Bool, in textView: DocumentUITextView) {
            guard renders != rendersMarkdown else { return }
            rendersMarkdown = renders
            editor?.rendersMarkdown = renders
            textView.blankLineLayout?.markerRuns = renders ? { [weak self, weak textView] in
                guard let self, let textView else { return [] }
                return markerRuns(in: textView.textStorage)
            } : nil
            textView.caretStopResolver = renders ? { [weak self, weak textView] offset in
                guard let self, let textView else { return offset }
                return caretStop(for: offset, direction: 0, in: textView)
            } : nil
            invalidateStyling()
            if textView.textStorage.length > 0 {
                // Regenerates every paragraph element.
                textView.textStorage.edited(.editedAttributes, range: NSRange(location: 0, length: textView.textStorage.length), changeInLength: 0)
                restyle(textView)
            }
        }

        /// The code blocks' ranges in `storage`, worked out once per edit.
        func codeRanges(in storage: NSTextStorage) -> [CodeRange] {
            snapshot(of: storage.string).codeRanges
        }

        /// Keeps the action bars beneath `ceiling` — see `CodeBlockOverlay.ceiling`.
        func keepBars(under ceiling: UIView) {
            overlay?.ceiling = ceiling
        }

        /// Builds the action bars and connects them to the text view's layout.
        ///
        /// Two hooks between them cover everything that can move a block.
        /// `layoutSubviews` covers scrolling (a scroll view lays out on every
        /// offset change), rotation and Split View; TextKit's viewport layout
        /// covers edits, which lay the text out without a layout pass of the
        /// text view. No separate scroll or bounds observers to keep in step.
        func attachOverlay(to textView: DocumentUITextView) {
            let overlay = CodeBlockOverlay(textView: textView)

            overlay.onCopy = { [weak self] target in
                self?.copy(target)
            }

            overlay.onRun = { [weak textView, weak self] target in
                guard let textView else { return }
                self?.run(target, from: textView)
            }

            overlay.onChooseLanguage = { [weak textView, weak self] target, kind in
                guard let textView else { return }
                self?.setKind(kind, of: target, in: textView)
            }
            overlay.allowsEditing = { [weak self] in self?.editor?.isTextLocked != true }

            self.overlay = overlay
            textView.overlay = overlay
            textView.addLayoutObserver { [weak overlay] in overlay?.reposition() }
            // An edit lays its text out with no layout pass of the text view,
            // so a block just typed had a bar and no place for it: hidden,
            // until something else laid the text view out.
            textView.addViewportLayoutObserver { [weak overlay] in overlay?.reposition(laysOutViewport: false) }
        }

        /// Puts a block's code on the pasteboard, with a light tap. One path
        /// for the button, the edit menu and ⇧⌘C.
        func copy(_ target: CodeBlockTarget) {
            UIPasteboard.general.string = target.code
            Haptics.copyBlock()
            editor?.onBlockCopied?()
        }

        /// The code block the caret is in, for the edit menu and ⌘R and ⇧⌘C.
        func target(atCaret caret: Int, in textView: UITextView) -> CodeBlockTarget? {
            let targets = snapshot(of: textView).targets
            return CodeBlockAction.target(atCaret: caret, in: targets, sourceLength: textView.textStorage.length)
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
            let appearance = pinnedAppearance ?? HighlightAppearance(textView.traitCollection)

            // Every block on screen was coloured for the other theme, so none of
            // them can be skipped. A pass still running under that theme is
            // dropped by the generation bump above.
            if appearance != highlightedAppearance {
                highlightedBlocks = []
                highlightedAppearance = appearance
            }

            // Forget blocks that no longer exist, so the set can't grow forever.
            highlightedBlocks.formIntersection(Set(blocks.compactMap { $0.codeBlock.map(HighlightKey.init(block:)) }))

            // Snapshot of what to send, taken before any await. Only blocks
            // whose code changed since the last pass — everything else still
            // holds the right colours, which applyStyling carries across.
            let jobs: [(key: HighlightKey, code: String, tag: String, offset: Int)] = blocks.compactMap { node in
                // Output isn't a language: nothing in it is coloured, and a
                // pass over it would only reset its text to `.label`.
                guard let code = node.codeBlock, !code.isOutput,
                      let tag = code.infoString.split(separator: " ").first,
                      !highlightedBlocks.contains(HighlightKey(block: code))
                else { return nil }
                return (
                    HighlightKey(block: code),
                    String(source[code.contentRange]),
                    // The name highlight.js knows the language by, for a
                    // language the app knows; what was typed otherwise, so
                    // any of its other languages still colours.
                    code.language?.highlightName ?? String(tag),
                    NSRange(code.contentRange, in: source).location
                )
            }
            guard !jobs.isEmpty else { return }

            highlightTask = Task { [weak self, weak textView, highlightClock] in
                try? await highlightClock.sleep(for: Self.highlightDelay)
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
                self.highlightedBlocks.formUnion(jobs.map(\.key))
            }
        }

        /// Returns once the colouring pass in flight, if any, has painted.
        ///
        /// Printing waits on this: paper gets no second chance to be coloured.
        func highlightingFinished() async {
            await highlightTask?.value
        }

        /// Re-colours the code when the view switches between light and dark.
        ///
        /// Nothing else would: highlighting only runs after an edit, so a note
        /// left open across the switch keeps the old theme's colours.
        func observeAppearance(of textView: UITextView) {
            textView.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (textView: UITextView, _) in
                guard let self else { return }
                let snapshot = self.snapshot(of: textView)
                scheduleHighlighting(for: textView, source: snapshot.source, blocks: snapshot.blocks)
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            // Text just typed under a typing style is written with it, before
            // the restyle below, which then sees the note as it will be.
            let undoManager = textView.undoManager
            editor?.typingTextDidChange(
                in: textView,
                isTyping: !isApplyingMarkerEdit && editor?.isFormatting != true && !isRetagging
                    && undoManager?.isUndoing != true && undoManager?.isRedoing != true
            )
            // A search result's highlights are for finding the place, and go
            // once the reader starts working there.
            (textView as? DocumentUITextView)?.clearSearchHighlights()
            restyle(textView)
            text.wrappedValue = textView.text
            editor?.refreshUndoState()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            editor?.typingSelectionDidChange(afterEdit: editCount != editCountAtLastSelection)
            (textView as? DocumentUITextView)?.placeCaretOnTappedBlankLine()
            normalizeCaret(in: textView)
            defer {
                lastCaret = textView.selectedRange.location
                editCountAtLastSelection = editCount
            }

            // Moving the caret across a fence boundary changes what the next
            // character should look like, even though no text changed. This
            // fires on every keystroke too, so it reads through the cache
            // rather than re-parsing.
            let snapshot = self.snapshot(of: textView)
            let source = snapshot.source
            let blocks = snapshot.blocks
            DocumentStyler.applyTypingAttributes(
                to: textView, source: source, blocks: blocks, rendered: rendersMarkdown, typography: typography
            )
            applyRewritingPolicy(to: textView, source: source, blocks: blocks)
            updateCodeSelectionHighlight(in: textView)
            refreshFenceVisibility(in: textView)
            refreshHeadingMarkers(in: textView)
            refreshCaretFormatting(in: textView)
        }

        // MARK: Hidden markers

        /// The offset a caret landing on `offset` should stand at.
        func caretStop(for offset: Int, direction: Int, in textView: UITextView) -> Int {
            let spans = formulaSpans(in: textView, touching: NSRange(location: offset, length: 0))
            let inFormula = FormulaEditing.caretStop(
                for: offset, direction: direction, spans: spans, in: textView.textStorage.mutableString
            )
            if inFormula != offset { return inFormula }
            return MarkdownFormatting.caretStop(
                for: offset,
                direction: direction,
                in: textView.textStorage.mutableString,
                codeRanges: codeRanges(in: textView.textStorage)
            )
        }

        /// The formulas the note draws as attachments near `window` (LaTeX,
        /// step 5). Nothing when the note is not rendered, or has no `$`.
        func formulaSpans(in textView: UITextView, touching window: NSRange? = nil) -> [FormulaEditing.Span] {
            guard rendersMarkdown else { return [] }
            let storage = textView.textStorage
            guard storage.mutableString.range(of: "$").location != NSNotFound else { return [] }
            let snapshot = self.snapshot(of: storage.string)
            return FormulaEditing.spans(in: snapshot.blocks, source: snapshot.source, touching: window)
        }

        /// Moves a collapsed caret off the inside of a hidden marker.
        ///
        /// Not after an edit: the caret typing leaves is where typing put it,
        /// and moving it would put the next letter on the other side of the
        /// marker just typed. An arrow key is told by its caret having moved
        /// one place with no finger down; a tap, or anything else, lands on
        /// the stretch's stop.
        ///
        private func normalizeCaret(in textView: UITextView) {
            // A selection with an edge inside a formula takes the formula whole.
            if rendersMarkdown, !isNormalizingCaret, editCount == editCountAtLastSelection,
               textView.selectedRange.length > 0, textView.markedTextRange == nil {
                let selection = textView.selectedRange
                let snapped = FormulaEditing.snapped(
                    selection,
                    spans: formulaSpans(in: textView, touching: selection),
                    in: textView.textStorage.mutableString
                )
                if snapped != selection {
                    isNormalizingCaret = true
                    textView.selectedRange = snapped
                    isNormalizingCaret = false
                }
                return
            }
            guard rendersMarkdown, !isNormalizingCaret,
                  editCount == editCountAtLastSelection,
                  textView.selectedRange.length == 0,
                  textView.markedTextRange == nil
            else { return }

            let offset = textView.selectedRange.location
            let step = offset - lastCaret
            let arrow = abs(step) == 1 && (textView as? DocumentUITextView)?.wasTouchedRecently != true
            // A tap in the empty space after a line's last markers means the
            // end of the line, after them.
            if !arrow, (textView as? DocumentUITextView)?.lastTapIsBeyondLineEnd(at: offset) == true { return }
            let stop = caretStop(for: offset, direction: arrow ? step : 0, in: textView)
            guard stop != offset else { return }

            isNormalizingCaret = true
            textView.selectedRange = NSRange(location: stop, length: 0)
            isNormalizingCaret = false
        }

        /// An edit of the coordinator's own, through `replace(_:withText:)`
        /// like typing: undoable, restyled, written back to the page.
        func apply(_ edit: TextEdit, to textView: UITextView) {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: edit.range.location),
                  let end = textView.position(from: start, offset: edit.range.length),
                  let range = textView.textRange(from: start, to: end)
            else { return }
            // A Return the app makes (a list's next item) ends the typing style
            // as one the keyboard types does.
            if edit.replacement.contains("\n") { editor?.clearTypingStyle() }
            isApplyingMarkerEdit = true
            textView.replace(range, withText: edit.replacement)
            isApplyingMarkerEdit = false
            textView.selectedRange = edit.selection
            editor?.refreshUndoState()
        }

        /// The edit a keystroke should make instead of its own, or `nil` to
        /// let it through: Backspace at a hidden marker, Return in a list or
        /// at the end of a bold word, and Tab on a list item.
        ///
        /// Never during marked text, where a keystroke belongs to the
        /// composition. Return and Tab work in legacy notes too; Backspace's
        /// rule is about markers nobody can see.
        private func markerEdit(for range: NSRange, replacement: String, in textView: UITextView) -> TextEdit? {
            guard textView.markedTextRange == nil else { return nil }
            let storage = textView.textStorage
            let text = storage.mutableString

            // In code, Return keeps the line's indent and Tab indents the
            // lines. Checked first: code isn't a list, and these answer nil
            // anywhere but in a block's own lines.
            if replacement == "\n", range == textView.selectedRange,
               let edit = CodeIndent.returnEdit(
                   in: text, selection: range, codeRanges: codeRanges(in: storage), width: indentWidth
               ) {
                return edit
            }
            if replacement == "\t", range == textView.selectedRange,
               let edit = CodeIndent.indentEdit(
                   in: text, selection: range, outdent: false, codeRanges: codeRanges(in: storage), width: indentWidth
               ) {
                return edit
            }
            if replacement == "\n", range == textView.selectedRange, range.length == 0 {
                return MarkdownFormatting.returnEdit(
                    in: text, caret: range.location, rendered: rendersMarkdown, codeRanges: codeRanges(in: storage)
                )
            }
            if replacement == "\t", range == textView.selectedRange {
                return MarkdownFormatting.indent(
                    in: text, selection: range, outdent: false, codeRanges: codeRanges(in: storage)
                )
            }
            // In code, Backspace in a line's indent takes back a whole level.
            if replacement.isEmpty, range.length == 1, textView.selectedRange.length == 0,
               NSMaxRange(range) == textView.selectedRange.location,
               let edit = CodeIndent.backspaceEdit(
                   in: text, caret: NSMaxRange(range), codeRanges: codeRanges(in: storage), width: indentWidth
               ) {
                return edit
            }
            guard rendersMarkdown, textView.selectedRange.length == 0,
                  replacement.isEmpty, range.length >= 1,
                  NSMaxRange(range) == textView.selectedRange.location
            else { return nil }
            // Backspace after a formula deletes all of it: one undo step.
            let caret = NSMaxRange(range)
            if let edit = FormulaEditing.backspace(
                at: caret, spans: formulaSpans(in: textView, touching: NSRange(location: caret, length: 0)), in: text
            ) {
                return edit
            }
            return MarkdownFormatting.backspace(
                at: caret, in: text, codeRanges: codeRanges(in: storage)
            )
        }

        /// ⇧Tab, and whether it has anything to do.
        func outdentListItems(in textView: UITextView) {
            guard let edit = indentEdit(outdent: true, in: textView) else { return }
            apply(edit, to: textView)
        }

        func canOutdentListItems(in textView: UITextView) -> Bool {
            textView.isEditable && indentEdit(outdent: true, in: textView) != nil
        }

        /// One level in or out at the caret: the code lines' rule in a code
        /// block, the list item's elsewhere. Tab, ⇧Tab and the text options
        /// row's ⇥ and ⇤ all ask here.
        func indentEdit(outdent: Bool, in textView: UITextView) -> TextEdit? {
            if let edit = CodeIndent.indentEdit(
                in: textView.textStorage.mutableString,
                selection: textView.selectedRange,
                outdent: outdent,
                codeRanges: codeRanges(in: textView.textStorage),
                width: indentWidth
            ) {
                return edit
            }
            return MarkdownFormatting.indent(
                in: textView.textStorage.mutableString,
                selection: textView.selectedRange,
                outdent: outdent,
                codeRanges: codeRanges(in: textView.textStorage)
            )
        }

        /// Tells the hotbar what the caret is in. Called on every caret move
        /// and edit, so it parses one line and assigns only on a change.
        func refreshCaretFormatting(in textView: UITextView) {
            editor?.setCaretFormatting(MarkdownFormatting.formatting(
                at: textView.selectedRange,
                in: textView.textStorage.mutableString,
                codeRanges: codeRanges(in: textView.textStorage)
            ))
        }

        /// The keyboard going away ends the typing style.
        func textViewDidEndEditing(_ textView: UITextView) {
            editor?.clearTypingStyle()
        }

        /// Sets the keyboard up for where the caret is, before it appears.
        ///
        /// A tap that leaves the caret where it was, as every tap into an
        /// empty note does, changes no selection, so the editor kept its
        /// starting code traits and a new note's first letter wasn't
        /// capitalised (measured 3 Oct).
        func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
            let snapshot = self.snapshot(of: textView)
            applyRewritingPolicy(to: textView, source: snapshot.source, blocks: snapshot.blocks)
            return true
        }

        /// Turns away the keyboard's rewrites of code behind the caret.
        ///
        /// The keyboard's own corrections are the edits that replace text
        /// other than the selection. Typing and pasting replace the
        /// selection, deleting leaves nothing, composition replaces its own
        /// marked text, and a formatting button knows what it's changing, so
        /// all of those go through untouched.
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if editor?.isFormatting != true, !isApplyingMarkerEdit { editor?.typingTextWillChange(range: range) }

            // A formatting edit's text is what its button meant (and so is a
            // paste or marker edit the coordinator makes: a window in a scene
            // showed their quotes going curly too). UIKit runs
            // smart punctuation over it as if it had been typed, as edits of
            // their own inside the replace, and turned a colour tag's quotes
            // curly, so it was a tag no longer and showed as text (seen 17
            // Oct, two one-character edits while the colour was applied).
            if editor?.isFormatting == true || isApplyingMarkerEdit, range.length > 0, NSMaxRange(range) <= (textView.text as NSString).length,
               TextRewritingPolicy.isSmartPunctuation(replacing: (textView.text as NSString).substring(with: range), with: text) {
                return false
            }

            // Undo and redo put text back by replacing it, which looks exactly
            // like a keyboard correction: undoing a language pick, whose tag
            // was replaced inside a fence, was turned away, and used up the
            // undo step without changing the text.
            let undoManager = textView.undoManager
            if !isApplyingMarkerEdit, editor?.isFormatting != true, !isRetagging,
               undoManager?.isUndoing != true, undoManager?.isRedoing != true,
               let edit = markerEdit(for: range, replacement: text, in: textView) {
                apply(edit, to: textView)
                return false
            }

            guard range.length > 0, !text.isEmpty, range != textView.selectedRange,
                  textView.markedTextRange == nil, editor?.isFormatting != true, !isRetagging,
                  !isApplyingMarkerEdit, undoManager?.isUndoing != true, undoManager?.isRedoing != true
            else { return true }

            let snapshot = self.snapshot(of: textView)
            return !TextRewritingPolicy.rewriteChangesCode(
                range, with: text, in: snapshot.source, blocks: snapshot.blocks
            )
        }

        /// Gives prose autocorrect and smart punctuation, and code neither,
        /// by where the caret is.
        ///
        /// Only on crossing from one to the other: reloading the keyboard
        /// redraws its suggestion bar, and this runs on every keystroke.
        private func applyRewritingPolicy(to textView: UITextView, source: String, blocks: [BlockNode]) {
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
        private func placeCodeKeys(in textView: UITextView) -> Bool {
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

        // MARK: Line numbers

        func setLineNumbers(_ shown: Bool, in textView: UITextView) {
            guard shown != showsLineNumbers else { return }
            showsLineNumbers = shown
            editor?.showsLineNumbers = shown
            // Drawing only: the numbers are in the margin, so nothing is laid
            // out again. Every block on screen draws once more.
            let ranges = codeRanges(in: textView.textStorage)
            redrawFences(ofBlocks: Set(ranges.indices), ranges: ranges, in: textView)
        }

        /// A paragraph's line number in its block, from 1 for the first line
        /// after the opening fence, `nil` when numbers are off.
        ///
        /// Counted at draw time from the note as it is now: an edit above
        /// moves a block without touching its fragments. A fence line gets a
        /// number here too, which the fragment declines to draw.
        func lineNumber(of fragment: NSTextLayoutFragment, in storage: NSTextStorage) -> Int? {
            let ranges = codeRanges(in: storage)
            guard showsLineNumbers, let offset = offset(of: fragment),
                  let index = ranges.firstIndex(where: { NSLocationInRange(offset, $0.range) })
            else { return nil }
            // Each paragraph starts after a newline, so the newlines between
            // the block's start and this paragraph are the paragraphs before
            // it. The block's newlines are found once, then counted by search.
            let newlines = snapshot(of: storage.string).newlines(ofCodeBlock: index)
            var low = 0, high = newlines.count
            while low < high {
                let mid = (low + high) / 2
                if newlines[mid] < offset { low = mid + 1 } else { high = mid }
            }
            return low
        }
    }

    // MARK: Configuration

    /// Builds the text view. Kept separate from `makeUIView` so tests can
    /// inspect the configuration without standing up a SwiftUI hierarchy.
    static func makeConfiguredTextView(typography: NoteTypography = .standard) -> DocumentUITextView {
        // Opt into TextKit 2 explicitly.
        //
        // Careful: reading the legacy `.layoutManager` property anywhere on this
        // view silently downgrades it to TextKit 1 and leaves `textLayoutManager`
        // nil — at which point none of the code-region rendering will run and
        // there is no error to tell you why.
        let textView = DocumentUITextView(usingTextLayoutManager: true)

        // Blank lines are laid out as zero-width spaces, or TextKit lets them
        // run through page breaks — see BlankLineLayout. The text view holds
        // it, since the content storage's delegate is weak.
        let gestures = MarkerGestures()
        gestures.install(on: textView)
        textView.markerGestures = gestures

        let blankLines = BlankLineLayout()
        textView.blankLineLayout = blankLines
        (textView.textLayoutManager?.textContentManager as? NSTextContentStorage)?.delegate = blankLines

        textView.isEditable = true
        textView.isScrollEnabled = true
        // Find and replace within the note: ⌘F with a keyboard, or the
        // header's magnifying glass.
        textView.isFindInteractionEnabled = true
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
        // rendering. Not Dynamic Type: the body's size is part of the page's
        // pagination (see `NoteTypography`).
        textView.font = typography.prose
        textView.adjustsFontForContentSizeCategory = false

        // All the text-rewriting traits live in TextRewritingPolicy, so
        // switching them as the caret moves between prose and code is one
        // call. Off until the caret is placed.
        TextRewritingPolicy.initial.apply(to: textView)

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
              let storage = (contentManager as? NSTextContentStorage)?.textStorage,
              let elementRange = textElement.elementRange
        else { return plain }

        // NSTextLocation is opaque; offsets come from the content manager.
        let start = contentManager.offset(from: contentManager.documentRange.location, to: elementRange.location)
        let length = contentManager.offset(from: elementRange.location, to: elementRange.endLocation)
        let element = NSRange(location: start, length: length)

        for code in codeRanges(in: storage) {
            guard let position = CodeBlockPosition.of(element: element, in: code.range) else {
                continue
            }
            let fragment = CodeBlockLayoutFragment(textElement: textElement, range: textElement.elementRange)
            fragment.position = position
            fragment.closesBlock = code.isClosed && position.roundsBottom
            fragment.isOutput = code.isOutput
            fragment.lineNumber = { [weak self, weak fragment, weak storage] in
                guard let self, let fragment, let storage else { return nil }
                return lineNumber(of: fragment, in: storage)
            }
            fragment.selectedRanges = { [weak self, weak contentManager] in
                self?.paintedTextRanges(in: contentManager) ?? []
            }
            fragment.fenceDisplay = { [weak self, weak fragment, weak storage] in
                guard let self, let fragment, let storage else {
                    return FenceDisplay(showsFences: true, isEditing: false)
                }
                return self.fenceDisplay(for: fragment, in: storage)
            }
            return fragment
        }

        return proseFragment(for: textElement, range: element, in: storage) ?? plain
    }

    /// A heading, which can draw its hashes, a checklist item, which draws
    /// its box, a quote, which draws its bar, or a rule, which draws its line.
    /// `nil` for anything else.
    private func proseFragment(for textElement: NSTextElement, range element: NSRange, in storage: NSTextStorage) -> NSTextLayoutFragment? {
        guard element.length > 0, element.location + element.length <= storage.length else { return nil }
        let text = storage.mutableString

        if rendersMarkdown, let hashes = ProseLine.headingHashes(in: text, line: element) {
            let fragment = HeadingLayoutFragment(textElement: textElement, range: textElement.elementRange)
            fragment.hashes = hashes
            fragment.markerColour = { [weak self] in self?.markerDimming.headingColour }
            fragment.showsMarker = { [weak self, weak fragment] in
                guard let self, let fragment, let offset = self.offset(of: fragment) else { return false }
                return self.headingVisibility.shows(headingAt: offset)
            }
            return fragment
        }

        if let box = ProseLine.checkbox(in: text, line: element) {
            let fragment = ChecklistLayoutFragment(textElement: textElement, range: textElement.elementRange)
            fragment.isChecked = box.checked
            fragment.boxIndex = box.indent + 2
            fragment.outlineColour = { [weak self] in self?.markerDimming.checkboxColour }
            fragment.collapsed = rendersMarkdown
            return fragment
        }

        if let depth = ProseLine.quoteDepth(in: text, line: element) {
            let fragment = BlockquoteLayoutFragment(textElement: textElement, range: textElement.elementRange)
            fragment.depth = depth
            return fragment
        }

        if ProseLine.isRule(in: text, line: element) {
            return RuleLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
        return nil
    }
}

#endif
