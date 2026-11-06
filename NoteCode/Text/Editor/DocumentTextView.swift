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
        /// Set by the page. The editor's `EditGuard` becomes the router's, so
        /// the flags a formatting edit sets are seen from both sides.
        var editor: NoteEditor? {
            didSet { editRouter.editGuard = editor?.editGuard ?? ownEditGuard }
        }
        private let ownEditGuard = EditGuard()

        /// What the note was last styled with and the snapshot of its text
        /// (`TextStyleSession`). Every reader of the snapshot goes through
        /// `snapshot(of:)`, so an edit converts the text and parses it once,
        /// however many callbacks it triggers.
        let styleSession = TextStyleSession()

        /// How many snapshots were made.
        var snapshotCount: Int { styleSession.snapshotCount }

        /// The run and copy buttons floating over each code block.
        var overlay: CodeBlockOverlay?

        /// Opens a compiler site's link (`openAtSite`). Replaceable so a test
        /// can see where Run went without leaving the app.
        var openURL: (URL) -> Void = { UIApplication.shared.open($0) }

        /// The keyboard traits and the code-keys row (`KeyboardPolicyController`).
        let keyboard = KeyboardPolicyController()

        /// Settings › Writing › Show Markdown, as `DocumentTextView` last had it.
        var showMarkdown: ShowMarkdown {
            get { styleSession.showMarkdown }
            set { styleSession.showMarkdown = newValue }
        }

        /// Settings › Writing › Markers, as `DocumentTextView` last had it.
        /// Changed through `setMarkerDimming`, which restyles.
        var markerDimming: MarkerDimming {
            get { styleSession.markerDimming }
            set { styleSession.markerDimming = newValue }
        }

        /// Settings › Code › Indent Width.
        var indentWidth = CodeIndent.defaultWidth

        /// Settings › Code › Line Numbers.
        private(set) var showsLineNumbers = LineNumbers.enabledByDefault

        /// Whether the note lays its Markdown markers out at zero width.
        /// See `MarkdownLayout`. Set through `setRendersMarkdown`.
        var rendersMarkdown: Bool { styleSession.rendersMarkdown }

        /// The size the note is styled in. A value the coordinator owns, not
        /// a global: a PDF or a thumbnail made while another note is open
        /// has a coordinator of its own. Set through `setTypography`.
        var typography: NoteTypography { styleSession.typography }

        /// Which blocks show their fences and which headings their hashes
        /// (`FenceDisplayController`).
        let fenceController = FenceDisplayController()

        /// Which blocks show their fences. See `CodeFenceDisplay.swift`.
        var fenceVisibility: FenceVisibility { fenceController.fenceVisibility }

        /// Which headings draw their hashes in the margin. See
        /// `HeadingMarkerDisplay.swift`.
        var headingVisibility: HeadingMarkerVisibility { fenceController.headingVisibility }

        /// How many times the text's characters have been edited, so a
        /// selection change can tell typing from an arrow key.
        var editCount: Int { styleSession.editCount }
        /// Where the caret was at the last selection change, and moving it off
        /// the inside of a hidden marker (`CaretTracker`).
        let caretTracker = CaretTracker()
        /// What a keystroke or an edit of the app's own turns into
        /// (`EditRouter`), and the flags that tell the two apart.
        let editRouter = EditRouter()
        /// The formula editor now showing (`FormulaEditor`).
        var formulaEditor: UIViewController?

        /// The re-entrancy flags (`EditGuard`).
        var editGuard: EditGuard { editRouter.editGuard }

        /// The text view this coordinator serves, for the parts of the layout
        /// delegate that need its geometry.
        weak var textView: DocumentUITextView? {
            didSet { keyboard.textView = textView }
        }

        /// The parts of the selection currently painted over code panels, so
        /// the next selection change can take them back off. See
        /// `CodeSelectionHighlight`.
        var paintedCodeSelection: [NSRange] = []

        /// The syntax colours: what is coloured, the pass in flight and the
        /// appearance (`SyntaxColouring`). The members below forward to it.
        let syntaxColouring = SyntaxColouring()

        init(text: Binding<String>) {
            self.text = text
            super.init()
            keyboard.onKey = { [weak self] key in self?.perform(key) }
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
            styleSession.textDidEdit()
        }

        /// The note as it stands, made once per edit. `text` is read, and
        /// converted with `nativeUTF8`, only when no snapshot is held.
        func snapshot(of text: @autoclosure () -> String) -> DocumentSnapshot {
            styleSession.snapshot(of: text())
        }

        func snapshot(of textView: UITextView) -> DocumentSnapshot {
            snapshot(of: textView.text ?? "")
        }

        /// Turns the collapsed layout on or off, laying the whole note out
        /// again when that changes it. The text storage's elements are cached
        /// per paragraph, so a flag alone would leave every one as it was.
        func setRendersMarkdown(_ renders: Bool, in textView: DocumentUITextView) {
            guard styleSession.setRendersMarkdown(renders) else { return }
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
