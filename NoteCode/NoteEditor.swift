//
//  NoteEditor.swift
//  NoteCode
//
//  What the hotbar talks to: the page's mode, its ink tool, and its text view.
//

#if canImport(UIKit)

import Observation
import PaperKit
import UIKit

/// A note page's editing state, shared by the hotbar and the editor.
///
/// SwiftUI owns the hotbar and UIKit owns the text view, and neither can reach
/// the other. This sits between them: the hotbar reads and changes state here,
/// and the text view registers itself so that edits have somewhere to land.
@Observable
final class NoteEditor {

    private(set) var mode: EditorMode = .text

    /// Called after the mode changes. The text view's code blocks show or
    /// hide their fences with it (`DocumentTextView.Coordinator`), and no
    /// edit or selection change tells them.
    ///
    /// Not observed state: it is the text view's hook, and hooking it up
    /// must not make the hotbar re-render.
    @ObservationIgnored var modeDidChange: (() -> Void)?

    /// What ink mode draws with. Kept here rather than in the hotbar so the
    /// canvas can take it as it changes.
    var inkTool = InkToolState() {
        didSet {
            guard inkTool != oldValue else { return }
            if inkTool.kind != oldValue.kind {
                previousInkKind = oldValue.kind
            }
            canvas?.tool = inkTool.pencilKitTool
            page?.selection.kind = inkTool.selectionKind
            applySelecting()
            // The selection is the canvas controller's, not the tool's, so it
            // outlived the lasso (reported 21 Oct). Only *leaving* the lasso
            // clears it: `insertIntoInk` selects what it inserted and then
            // switches to the lasso, and that must keep the selection.
            if oldValue.kind == .lasso, inkTool.kind != .lasso {
                canvas?.clearPaperKitSelection()
                page?.selection.clear()
            }
        }
    }

    /// The Select tool's selection, once the page exists.
    var selection: InkSelection? { page?.selection }

    /// Gives touches to the Select tool's overlay while it is the tool in ink
    /// mode, and to the canvas otherwise.
    private func applySelecting() {
        let selecting = mode == .ink && inkTool.kind == .lasso
        // PaperKit gets no touches while the Select tool has the page, except
        // for one object the reader chose to Edit.
        let editing = page?.selection.isEditingInPaperKit ?? false
        canvas?.suspendsPaperKitInput = selecting
        page?.setSelecting(selecting && !editing, allowsFingers: !isPencilOnly)
    }

    /// The tool in use before the current one, for the Pencil's double tap
    /// and squeeze to switch back to.
    private(set) var previousInkKind = InkToolKind.pen

    /// Swaps between the current tool and the eraser: the Pencil's double
    /// tap, as the system sets it up out of the box.
    func toggleEraser() {
        if inkTool.kind == .eraser {
            inkTool.kind = previousInkKind == .eraser ? .pen : previousInkKind
        } else {
            inkTool.kind = .eraser
        }
    }

    /// Swaps between the current tool and the one before it.
    func switchToPreviousTool() {
        inkTool.kind = previousInkKind
    }

    /// The Pencil's double tap or squeeze while the text has the page: goes to
    /// ink mode so the gesture has something to act on, then does what the
    /// reader set it to. Nothing when the setting is off or a shortcut the
    /// system runs itself, since switching mode for a gesture that then does
    /// nothing would only surprise. Whether the mode changed.
    @discardableResult
    func enterInkForPencil(_ response: PencilResponse) -> Bool {
        guard mode == .text, response != .nothing else { return false }
        setMode(.ink)
        return true
    }

    /// Picks a tool from the keyboard (P, H, E, L). Ink mode only: in text
    /// mode these are letters.
    func selectTool(_ kind: InkToolKind) {
        guard mode == .ink else { return }
        inkTool.kind = kind
    }

    /// `[` and `]`: the selected tool one width thinner or thicker.
    func stepWidth(by direction: Int) {
        guard mode == .ink else { return }
        inkTool.stepWidth(by: direction)
    }

    /// ⇧⌘D, and the same switch as the hotbar's text and draw buttons.
    func toggleMode() {
        setMode(mode == .text ? .ink : .text)
    }

    /// Whether only the Pencil draws.
    ///
    /// Off by default. The page already has a hard toggle between typing and
    /// drawing, so a finger in ink mode means to draw; there is no need to
    /// make people reach for the Pencil to leave a mark. On, a finger scrolls
    /// and selects instead — what you want with the Pencil in hand and a palm
    /// resting on the page. After the first change it is whatever the reader
    /// last chose on this device (`fingerDrawsKey`).
    var isPencilOnly = false {
        didSet {
            guard isPencilOnly != oldValue else { return }
            canvas?.allowsFingerDrawing = !isPencilOnly
            applySelecting()
            applyScrolling()
        }
    }

    /// The same switch as `isPencilOnly`, said the way the hotbar's hand
    /// button says it: on, a finger draws.
    var fingerDraws: Bool {
        get { !isPencilOnly }
        set { isPencilOnly = !newValue }
    }

    /// Where the device keeps `fingerDraws`, so it carries over from note to
    /// note and across launches (`InkToolPersistence`). Stored the way the
    /// button says it, so a device that has never set it reads `true`.
    static let fingerDrawsKey = "fingerDraws"

    /// Settings › Drawing › After a Selection: back to the tool before the
    /// Select tool once the selection ends by the reader's choice. Off
    /// unless chosen.
    static let returnToPreviousToolKey = "returnToPreviousTool"

    /// Whether the selection ending sends the reader back to their tool.
    /// Per device (`InkToolPersistence`).
    @ObservationIgnored var returnsToPreviousTool = false

    /// The Select tool's selection ended because the reader let go of it:
    /// Delete, or a tap on empty space. Never a tool or mode switch (they
    /// chose a tool) and never a move, recolour or duplicate (they often
    /// do two in a row). Goes back to the tool before Select, if asked to.
    func selectionEnded() {
        guard returnsToPreviousTool, mode == .ink, inkTool.kind == .lasso, previousInkKind != .lasso else { return }
        inkTool.kind = previousInkKind
    }

    /// Whether the note's text is locked (`Page.isTextLocked`), so text mode
    /// reads rather than edits: no keyboard, no formatting, no undo. The page
    /// holds the setting; this is the copy the text view and the hotbar
    /// follow, set by `setTextLocked(_:)`.
    private(set) var isTextLocked = false

    private(set) var canUndo = false
    private(set) var canRedo = false

    /// Whether a formatting button's edit is going through the text view, so
    /// the delegate doesn't take it for the keyboard rewriting code.
    @ObservationIgnored private(set) var isFormatting = false

    /// What the next text typed will be drawn with, set by a button that has
    /// no word to act on (`TypingStyle`, docs/archive/text-system-overhaul.md,
    /// decision 5). Nothing is written until text is typed. Cleared by a
    /// caret move, a mode switch, a locked note and the keyboard going away.
    private(set) var typingStyle = TypingStyle.none

    /// Where the typing style's text starts and what follows it, so what was
    /// typed since can be told from any other edit without asking the keyboard
    /// what it did (see `typingTextDidChange`).
    private struct TypingAnchor {
        /// Where the text typed next starts.
        var from: Int
        /// The note's length less where the caret is: unchanged while text
        /// is typed or replaced at the caret.
        var suffix: Int
        /// Where the caret was left, so a caret that is somewhere else has moved.
        var caret: Int
    }
    @ObservationIgnored private var typingAnchor: TypingAnchor?
    /// An edit began before the anchor (an autocorrect of the word behind the
    /// caret): the next change re-anchors instead of styling.
    @ObservationIgnored private var typingAnchorIsStale = false
    @ObservationIgnored private var isWritingTypedText = false

    /// Where the last code language is kept. Replaceable so a test doesn't
    /// write the device's own.
    @ObservationIgnored var defaults = UserDefaults.standard

    /// Run or copy the code block the caret is in, if it's in one. The text
    /// view's coordinator sets these: it owns the blocks and where they run.
    @ObservationIgnored var runBlockAtCaret: (() -> Void)?
    @ObservationIgnored var copyBlockAtCaret: (() -> Void)?

    /// The on-device assistant (Explain Code, Summarise Note). One per note,
    /// like the editor; its settings arrive from `PageDetailView` through
    /// `AIFeatureSettings.apply(to:)`.
    @ObservationIgnored var ai = AIAssistant.system()

    /// Explains the code block the caret is in, if it is in one. The text
    /// view's coordinator sets this, as it does `runBlockAtCaret`.
    @ObservationIgnored var explainBlockAtCaret: (() -> Void)?

    /// Told after a code block's code is on the pasteboard, by the button, the
    /// edit menu or ⇧⌘C, so the page can say "Copied".
    @ObservationIgnored var onBlockCopied: (() -> Void)?

    @ObservationIgnored private weak var textView: UITextView?
    @ObservationIgnored private weak var canvas: DrawingCanvas?
    @ObservationIgnored private weak var page: PageView?
    @ObservationIgnored private var savedSession: TextSession?

    /// How many pages the open note runs to, for its info. Read when asked
    /// rather than observed: the count changes as the note is typed, and
    /// nothing on screen shows it.
    var pageCount: Int? {
        page?.pageCount
    }

    /// One more page at the end of the note. Not an edit: nothing goes on
    /// the text's undo stack and the note's date stays.
    func addPage() {
        page?.addPage()
    }

    // MARK: Insert

    /// The page's width in points, which a photo's size and resolution are
    /// measured against. `nil` until the page exists.
    var insertionPageWidth: CGFloat? {
        page?.pageLayout.pageSize.width
    }

    /// The tallest a photo is first shown. See `PageView.insertionMaxHeight`.
    var insertionMaxHeight: CGFloat {
        page?.insertionMaxHeight ?? 0
    }

    /// Runs one of PaperKit's inserts at the middle of the page on screen, and
    /// hands the reader the lasso, so what was added can be moved and resized
    /// at once. Ink mode only; `false` if there was nothing to insert into.
    ///
    /// The lasso is a choice made without a Pencil to hand: PaperKit selects
    /// what it inserts, but whether that selection takes a drag while the pen
    /// is the tool has not been seen on a device.
    @discardableResult
    func insertIntoInk(extent: CGSize, _ insert: (PaperMarkupViewController) -> Void) -> Bool {
        guard mode == .ink, let page, let controller = canvas?.controller else { return false }
        var before: Set<MarkupOrderedSet.ElementID> = []
        for element in canvas?.markup.subelements ?? PaperMarkup(bounds: .zero).subelements { before.insert(element.elementID) }
        page.insertIntoInk(extent: extent) { insert(controller) }
        inkTool.kind = .lasso
        // PaperKit selects what it inserts; the Select tool is the one that
        // shows and moves it, so the selection is handed across.
        var inserted: Set<MarkupOrderedSet.ElementID> = []
        for element in canvas?.markup.subelements ?? PaperMarkup(bounds: .zero).subelements where !before.contains(element.elementID) {
            inserted.insert(element.elementID)
        }
        canvas?.clearPaperKitSelection()
        page.selection.select(ids: inserted)
        return true
    }

    /// Takes in what the reader drew that is still on its way into the
    /// note's ink (`PageView.commitInk`), so a save made now has it.
    func commitInk() {
        page?.commitInk()
    }

    /// The open note as a PDF, a page for each of its pages, ink and all.
    /// `nil` until the page exists.
    ///
    /// The ink is the page's own copy, so strokes drawn moments ago and not
    /// yet saved are on the paper too.
    func pdf(title: String) async -> Data? {
        guard let page else { return nil }
        return await NotePDF.render(NotePDF.Note(
            title: title,
            text: page.textView.text ?? "",
            ink: page.ink,
            orientation: page.pageLayout.orientation,
            pageCount: page.pageCount,
            minimumPages: page.minimumPageCount,
            rendersMarkdown: rendersMarkdown,
            lineNumbers: showsLineNumbers,
            typography: typography
        ))
    }

    /// The note's text as it is now, which is its Markdown: the text storage
    /// holds `#` and `**` as typed (hiding them is layout only,
    /// `MarkdownLayout`). `nil` until the text view exists.
    ///
    /// Read from the text view rather than the model, as the PDF is, so the
    /// last keystrokes are in it.
    var currentText: String? {
        textView?.text
    }

    /// ⌘P: the system's print dialog for the note's PDF.
    ///
    /// The same PDF the share button makes, so what prints is what Save to
    /// Files would keep; the share sheet's Print row opens this same dialog.
    func printNote(title: String) async {
        guard UIPrintInteractionController.isPrintingAvailable,
              let data = await pdf(title: title)
        else { return }

        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = title

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true)
    }

    /// Called by `DocumentTextView` once the page, and so the canvas, exists.
    ///
    /// - Parameter page: the page around the text view, if any.
    func attach(_ textView: UITextView, canvas: DrawingCanvas? = nil, page: PageView? = nil) {
        self.textView = textView
        self.canvas = canvas
        self.page = page
        clearTypingStyle()
        canvas?.tool = inkTool.pencilKitTool
        canvas?.allowsFingerDrawing = !isPencilOnly
        canvas?.onUndoDidChange = { [weak self] in
            self?.refreshUndoState()
            // Undo can bring back or remove what is selected.
            self?.page?.selection.refresh()
        }
        page?.selection.kind = inkTool.selectionKind
        page?.selection.textPiecesFor = { [weak self] shape in
            guard let self, !self.isTextLocked, let textView = self.textView else { return [] }
            // Code is never coloured, so it is never selected as text.
            let code = self.codeRanges?() ?? []
            return TextRegion.pieces(for: shape, lines: TextRegion.visibleLines(in: textView)).filter { piece in
                !code.contains { NSIntersectionRange($0.range, piece.range).length > 0 }
            }
        }
        page?.selection.onEditingChange = { [weak self] in self?.applySelecting() }
        page?.selection.onEnded = { [weak self] in self?.selectionEnded() }
        page?.selection.recolourText = { [weak self] ranges, hex in self?.recolourText(ranges, to: hex) }
        savedSession = mode.apply(to: textView, canvas: canvas, saved: nil, textLocked: isTextLocked)
        applySelecting()
        applyScrolling()
        refreshUndoState()
    }

    func setMode(_ newMode: EditorMode) {
        guard newMode != mode else { return }
        mode = newMode
        clearTypingStyle()
        if let textView {
            savedSession = newMode.apply(to: textView, canvas: canvas, saved: savedSession, textLocked: isTextLocked)
        }
        applyScrolling()
        if newMode != .ink { page?.selection.clear() }
        applySelecting()
        refreshUndoState()
        modeDidChange?()
    }

    /// Locks or unlocks the note's text.
    ///
    /// Locking puts the keyboard away. Unlocking doesn't bring it back: the
    /// reader was reading, and a tap is all it takes to start typing. In ink
    /// mode nothing changes until text mode comes back, and a keyboard that
    /// was up before ink only returns then if the text is unlocked by then.
    /// Works before the text view exists too, and `attach` applies it.
    func setTextLocked(_ locked: Bool) {
        guard locked != isTextLocked else { return }
        isTextLocked = locked
        if locked { clearTypingStyle() }
        if let textView {
            savedSession = mode.apply(to: textView, canvas: canvas, saved: savedSession, textLocked: locked)
        }
        refreshUndoState()
    }

    /// Hands the page's pans whatever the mode and the Pencil lock leave them.
    ///
    /// Through the page when there is one: it picks between this rule and
    /// one finger as each touch lands, by whether the canvas takes it.
    private func applyScrolling() {
        let scrolling = mode.scrolling(fingerDraws: !isPencilOnly)
        if let page {
            page.scrolling = scrolling
        } else if let textView {
            scrolling.apply(to: textView.panGestureRecognizer)
        }
    }

    // MARK: Find

    /// Shows the find bar for the note, as ⌘F does.
    ///
    /// In text mode, since finding means selecting the matches, and the text
    /// takes no selection while ink has the page. Coming from ink, the
    /// reader is going to the text anyway.
    func showFind() {
        setMode(.text)
        textView?.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    // MARK: Formatting

    /// Bold, Italic, Strikethrough, Underline and Code. A selection, or a caret inside a
    /// word, is an edit; a caret anywhere else in prose sets the typing style
    /// (`TypingStyle`) and writes nothing.
    func toggle(_ style: MarkdownFormatting.InlineStyle) {
        if let textView, mode == .text, !isTextLocked, isTypingCaret(in: textView) {
            let shown = formattingShown
            let lit = switch style {
            case .bold:          shown.bold
            case .italic:        shown.italic
            case .strikethrough: shown.strikethrough
            case .underline:     shown.underline
            case .code:          shown.code
            }
            setTypingStyle(typingStyle.toggled(style, shown: lit))
            return
        }
        perform { [codeRanges] text, selection in
            MarkdownFormatting.toggle(style, in: text, selection: selection, codeRanges: codeRanges?() ?? [])
        }
    }

    func setHeading(level: Int) {
        perform { MarkdownFormatting.setHeading(level: level, in: $0, selection: $1) }
    }

    func toggleBullet() {
        toggleList(.bullet)
    }

    /// Makes the lines at the caret a quote, or takes the quote off them.
    func toggleQuote() {
        perform { MarkdownFormatting.toggleQuote(in: $0, selection: $1) }
    }

    /// A horizontal rule below the caret's line.
    func insertRule() {
        perform { [codeRanges] text, selection in
            MarkdownFormatting.insertRule(in: text, selection: selection, codeRanges: codeRanges?() ?? [])
        }
    }

    func toggleList(_ style: MarkdownFormatting.ListStyle) {
        perform { MarkdownFormatting.toggleList(style, in: $0, selection: $1) }
    }

    /// Whether the open note lays its Markdown markers out at zero width, set
    /// by the text view's coordinator. The PDF and thumbnails need it: they
    /// lay the note out again, and have to break its lines where the screen does.
    @ObservationIgnored var rendersMarkdown = false

    /// Whether the page shows line numbers beside its code
    /// (Settings › Code), so a PDF of it does too.
    @ObservationIgnored var showsLineNumbers = false

    /// The formatting at the caret, which the hotbar lights up: inline markers
    /// are never drawn in place, so this is where their state shows.
    private(set) var caretFormatting = MarkdownFormatting.CaretFormatting()

    /// Assigns only on a real change: this runs on every caret move and
    /// keystroke, and an observable property invalidates its readers on any
    /// assignment, equal value or not.
    ///
    /// A stepper tap still waiting for the taps to stop goes on at once if
    /// the selection moves away from it: the reader saw the number change.
    func setCaretFormatting(_ formatting: MarkdownFormatting.CaretFormatting) {
        if caretFormatting != formatting { caretFormatting = formatting }
        if let pending = pendingSelectionSize, let textView, textView.selectedRange != pending.selection {
            selectionSizeTask?.cancel()
            settleSelectionSize(keeping: textView.selectedRange)
        }
    }

    /// What the bar shows at the caret: the text's own formatting with the
    /// typing style on top, so Bold lit means the next text typed is bold.
    var formattingShown: MarkdownFormatting.CaretFormatting {
        typingStyle.shown(over: caretFormatting)
    }

    /// Starts a code block, and remembers its language for
    /// `insertCodeBlockInLastLanguage`.
    func insertCodeBlock(language: CodeLanguage?) {
        guard mode == .text, !isTextLocked else { return }
        LastCodeLanguage.store(language, in: defaults)
        perform { MarkdownFormatting.insertCodeBlock(language: language, in: $0, selection: $1) }
    }

    /// Code Block ▾'s choice. Output isn't a language, so it leaves the one
    /// ⇧⌘K remembers alone: a student who writes a program and then its
    /// output wants the next block in the program's language.
    func insertCodeBlock(kind: CodeBlockKind) {
        switch kind {
        case .language(let language): insertCodeBlock(language: language)
        case .plain:                  insertCodeBlock(language: nil)
        case .output:
            guard mode == .text, !isTextLocked else { return }
            perform { MarkdownFormatting.insertCodeBlock(kind: .output, in: $0, selection: $1) }
        }
    }

    /// ⇧⌘K: a code block in whichever language the last one was.
    func insertCodeBlockInLastLanguage() {
        insertCodeBlock(language: LastCodeLanguage.read(from: defaults))
    }

    /// Makes an edit through the text view rather than around it.
    ///
    /// `replace(_:withText:)` is the path typing takes, so the edit lands on
    /// the undo stack and the delegate restyles it and writes it back to the
    /// page, exactly as if it had been typed. Assigning `.text` would do
    /// neither, and would throw away the selection besides.
    private func perform(_ makeEdit: (String, NSRange) -> TextEdit) {
        perform { Optional(makeEdit($0, $1)) }
    }

    /// `perform` for an edit that may have nothing to do.
    private func perform(_ makeEdit: (String, NSRange) -> TextEdit?) {
        guard mode == .text, !isTextLocked, let textView else { return }

        guard let edit = makeEdit(textView.text ?? "", textView.selectedRange) else { return }

        guard let start = textView.position(from: textView.beginningOfDocument, offset: edit.range.location),
              let end = textView.position(from: start, offset: edit.range.length),
              let range = textView.textRange(from: start, to: end)
        else { return }

        // Formatting is a prelude to typing, so the keyboard comes up for it.
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        isFormatting = true
        textView.replace(range, withText: edit.replacement)
        isFormatting = false
        textView.selectedRange = edit.selection
        refreshUndoState()
    }

    // MARK: The typing style

    /// Whether a press with the selection as it is sets the typing style: a
    /// caret that isn't inside a word (`MarkdownFormatting.caretTarget`).
    private func isTypingCaret(in textView: UITextView) -> Bool {
        let selection = textView.selectedRange
        return selection.length == 0 && MarkdownFormatting.caretTarget(
            at: selection.location, in: textView.textStorage.mutableString, codeRanges: codeRanges?() ?? []
        ) == .typing
    }

    /// Sets the typing style, with the keyboard up for it as a formatting
    /// button brings it, and starts watching for the text typed.
    private func setTypingStyle(_ style: TypingStyle) {
        guard let textView else { return }
        if !textView.isFirstResponder { textView.becomeFirstResponder() }
        typingStyle = style
        let caret = textView.selectedRange.location
        typingAnchor = style.isEmpty ? nil : TypingAnchor(from: caret, suffix: textView.textStorage.length - caret, caret: caret)
        typingAnchorIsStale = false
    }

    /// A caret move, a mode switch, a locked note, a keyboard going away.
    func clearTypingStyle() {
        if !typingStyle.isEmpty { typingStyle = .none }
        typingAnchor = nil
        typingAnchorIsStale = false
    }

    /// The text view is about to change `range`. Only a hint, since what the
    /// keyboard says it is doing isn't always what it does (the iPad's Korean
    /// keyboard reports a jamo inserted where it replaces one): an edit that
    /// starts in front of the typing style's place is an autocorrect or
    /// something else, never the text typed there.
    func typingTextWillChange(range: NSRange) {
        guard !isWritingTypedText, let anchor = typingAnchor, range.location < anchor.from else { return }
        typingAnchorIsStale = true
    }

    /// The text changed. If it is text just typed where the typing style
    /// was set, the same text is written again with the style on, in the same
    /// turn of the run loop and so the same undo step as the typing.
    ///
    /// Written after the fact, from here, and never in `shouldChangeTextIn`:
    /// that is told what the keyboard thinks it is doing, which for Korean
    /// on the iPad is a jamo inserted at the caret where the text view really
    /// replaces the one before it, with no marked text. What is typed is
    /// found from the note's length instead. `suffix`, the length less the
    /// caret's place, doesn't change while text is typed or replaced at the
    /// caret, so the caret's place now says where the typed text ends,
    /// whatever the keyboard did to get there.
    ///
    /// Not while a composition is open (`markedTextRange`): that is the
    /// keyboard's text until it commits it, and the commit is where the style
    /// goes on. `isTyping` is false for the app's own edits (a heading, a
    /// list's Return, an undo), which only move the place.
    func typingTextDidChange(in textView: UITextView, isTyping: Bool) {
        guard var anchor = typingAnchor, !typingStyle.isEmpty, !isWritingTypedText, mode == .text else { return }
        let selection = textView.selectedRange
        // The caret moves as the composition does; it hasn't gone anywhere.
        guard textView.markedTextRange == nil else {
            typingAnchor?.caret = selection.location
            return
        }
        guard selection.length == 0 else { return clearTypingStyle() }

        let storage = textView.textStorage
        let end = storage.length - anchor.suffix
        defer { if typingAnchor != nil { typingAnchor?.caret = textView.selectedRange.location } }

        guard isTyping, !typingAnchorIsStale, end == selection.location, end >= anchor.from else {
            // Something else changed the text: start again from the caret.
            typingAnchorIsStale = false
            typingAnchor = TypingAnchor(from: selection.location, suffix: storage.length - selection.location, caret: selection.location)
            return
        }
        guard end > anchor.from else { return }

        let run = NSRange(location: anchor.from, length: end - anchor.from)
        anchor.from = end
        typingAnchor = anchor
        let text = storage.mutableString
        // A new line ends it, as a caret move does; a long paste is left as it is.
        guard text.rangeOfCharacter(from: .newlines, options: [], range: run).location == NSNotFound else {
            return clearTypingStyle()
        }
        guard run.length <= 2_000,
              let edit = MarkdownFormatting.typed(
                  typingStyle, run: run, in: text, blockSizes: blockSizes, codeRanges: codeRanges?() ?? []
              ),
              let start = textView.position(from: textView.beginningOfDocument, offset: edit.range.location),
              let finish = textView.position(from: start, offset: edit.range.length),
              let range = textView.textRange(from: start, to: finish)
        else { return }

        isWritingTypedText = true
        isFormatting = true
        textView.replace(range, withText: edit.replacement)
        isFormatting = false
        textView.selectedRange = edit.selection
        isWritingTypedText = false
        typingAnchor = TypingAnchor(
            from: edit.selection.location, suffix: storage.length - edit.selection.location, caret: edit.selection.location
        )
        refreshUndoState()
    }

    /// The selection changed. A caret that went somewhere the typing didn't
    /// take it has moved, and the typing style goes. A change that came with
    /// an edit is typing (or the keyboard's composition) moving it.
    func typingSelectionDidChange(afterEdit: Bool) {
        guard let anchor = typingAnchor, !isWritingTypedText, !afterEdit, let textView else { return }
        let selection = textView.selectedRange
        // Within a composition the keyboard moves the caret as it likes.
        if textView.markedTextRange != nil {
            typingAnchor?.caret = selection.location
        } else if selection.length != 0 || selection.location != anchor.caret {
            clearTypingStyle()
        }
    }

    // MARK: The text options row

    /// The code blocks, for the edits that need to know where one is. The
    /// text view's coordinator sets it: it owns the parse.
    @ObservationIgnored var codeRanges: (() -> [CodeRange])?

    /// Indents or outdents the list item or code lines at the caret, as Tab
    /// and ⇧Tab do. Set by the coordinator, which owns both rules.
    @ObservationIgnored var indentAtCaret: ((_ outdent: Bool) -> Void)?

    /// Points the code block at the caret at another language, as its
    /// language button does.
    @ObservationIgnored var retagBlockAtCaret: ((CodeBlockKind) -> Void)?

    /// ⇥ and ⇤. Text mode, unlocked.
    func indent(outdent: Bool) {
        guard mode == .text, !isTextLocked else { return }
        indentAtCaret?(outdent)
        refreshUndoState()
    }

    /// The language menu's pick for the block the caret is in.
    func setCodeBlockKind(_ kind: CodeBlockKind) {
        guard mode == .text, !isTextLocked else { return }
        retagBlockAtCaret?(kind)
        refreshUndoState()
    }

    // MARK: The on-device assistant

    /// Explain Code: opens the assistant's sheet on a block.
    func explain(_ target: CodeBlockTarget) {
        guard !target.isOutput, !target.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ai.begin(AIPrompts.explainJob(
            code: target.code,
            languageName: target.language?.displayName,
            insertionOffset: min(NSMaxRange(target.range), textView?.textStorage.length ?? NSMaxRange(target.range)),
            contextTokens: ai.contextTokens,
            length: ai.settings.length
        ))
    }

    /// Summarise Note: opens the assistant's sheet on the note's text.
    func summariseNote(title: String) {
        guard let textView else { return }
        let text = textView.text ?? ""
        ai.begin(AIPrompts.summariseJob(
            text: text,
            title: title,
            insertionOffset: AIInsertion.anchor(caret: textView.selectedRange.location, in: text as NSString, codeRanges: codeRanges?() ?? []),
            contextTokens: ai.contextTokens,
            length: ai.settings.length
        ))
    }

    /// Whether Insert Below can write: text mode, and not a locked note.
    var canInsertAnswer: Bool {
        mode == .text && !isTextLocked && textView != nil
    }

    /// Insert Below: the answer as a quote or an output block under the
    /// block or line it was asked about. One edit through the text view, so
    /// one undo step. Returns whether it wrote anything.
    @discardableResult
    func insertAnswer(_ answer: String, style: AIInsertStyle, at anchor: Int) -> Bool {
        guard canInsertAnswer else { return false }
        var wrote = false
        perform { text, _ in
            let edit = AIInsertion.edit(inserting: answer, style: style, at: anchor, in: text as NSString)
            wrote = edit != nil
            return edit
        }
        return wrote
    }

    /// + Output: an empty output block under the code block the caret is in.
    func addOutputBlock() {
        perform { [codeRanges] text, selection in
            MarkdownFormatting.insertOutputBlock(
                afterBlockAt: selection.location, in: text as NSString, codeRanges: codeRanges?() ?? []
            )
        }
    }

    /// Colour (`TextColour`): sets `hex` on the selection, the coloured run
    /// at the caret or the word there; `nil` takes colour off.
    func setColour(_ hex: Int?) {
        guard mode == .text, !isTextLocked, let textView else { return }
        if isTypingCaret(in: textView) {
            setTypingStyle(typingStyle.colouring(hex))
            return
        }
        perform { [codeRanges] text, selection in
            MarkdownFormatting.colour(hex, selection: selection, in: text as NSString, codeRanges: codeRanges?() ?? [])
        }
    }

    /// Colours text ranges, one per line, for the Select tool. Works in ink
    /// mode, where the text view isn't editable and has no keyboard:
    /// `replace(_:withText:)` doesn't care (scripts/spikes/text-edit-while-ink-probe.swift).
    /// All in one turn of the run loop, so one undo step; bottom up, so the
    /// lines an edit rewrites can't move a range not yet done.
    func recolourText(_ ranges: [NSRange], to hex: Int?) {
        guard !isTextLocked, let textView else { return }
        isFormatting = true
        defer {
            isFormatting = false
            refreshUndoState()
        }
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            let text = textView.text ?? ""
            guard let edit = MarkdownFormatting.colour(hex, selection: range, in: text as NSString, codeRanges: codeRanges?() ?? []),
                  let start = textView.position(from: textView.beginningOfDocument, offset: edit.range.location),
                  let end = textView.position(from: start, offset: edit.range.length),
                  let textRange = textView.textRange(from: start, to: end)
            else { continue }
            textView.replace(textRange, withText: edit.replacement)
        }
    }

    /// Highlight (`HighlightColour`): the same, with a background; `nil`
    /// takes the highlight off.
    func setHighlight(_ colour: HighlightColour?) {
        guard mode == .text, !isTextLocked, let textView else { return }
        if isTypingCaret(in: textView) {
            setTypingStyle(typingStyle.highlighting(colour))
            return
        }
        perform { [codeRanges] text, selection in
            MarkdownFormatting.highlight(colour, selection: selection, in: text as NSString, codeRanges: codeRanges?() ?? [])
        }
    }

    // MARK: The size of the text at the caret

    /// What the size control reads: the text at the caret, or the
    /// selection, in points.
    struct SelectionTextSize: Equatable {
        /// The size, or `nil` for a selection of text in several sizes.
        var points: Double?
        /// The size of the text at the selection's start: where + and −
        /// start from on a selection of several.
        var startPoints: Double
        /// The size the text there has with no size of its own: what
        /// Default sets.
        var ownPoints: Double
        /// Whether there is anything to size: text mode, unlocked, not in
        /// code, and not a caret on no word and in no run.
        var canChange: Bool
    }

    /// A size for the selection in points (`nil`: the text's own), with the
    /// selection it was asked for: kept through the stepper's pause and the
    /// ink question, since the alert takes the keyboard and the text view's
    /// selection isn't something to read back afterwards.
    struct SizeRequest: Equatable {
        /// The size, `nil` for the text's own; for + and −, the size the
        /// text comes to, or `nil` for text in several sizes.
        var points: Double?
        var selection: NSRange
        /// For + and −: how many points each character moves from its own
        /// size, so text in several sizes keeps them apart. `nil` for a size
        /// picked or typed, which `points` says.
        var steps: Int? = nil
    }

    /// The stepper's latest tap, which the text catches up to once the taps
    /// stop (`settleDelay`), so a run of taps re-wraps the note once.
    private(set) var pendingSelectionSize: SizeRequest?
    @ObservationIgnored private var selectionSizeTask: Task<Void, Never>?
    /// The note's length when the pending tap was first made. Text typed
    /// since has moved what its selection points at, so it is dropped.
    @ObservationIgnored private var pendingTextLength = 0

    /// A size waiting for the reader's yes, because the note has ink. `nil`
    /// unless the alert is up.
    private(set) var selectionSizeAwaitingConfirmation: SizeRequest?

    /// The selection Custom… sizes, kept while the size is asked for. `nil`
    /// unless the alert is up.
    private(set) var customSizeSelection: NSRange?

    /// What the size control shows: the tap or the answer in flight, or the
    /// text as it is.
    var selectionTextSize: SelectionTextSize {
        var reading = textSize(reading: caretFormatting)
        if let request = selectionSizeAwaitingConfirmation ?? pendingSelectionSize {
            reading.points = request.steps == nil ? request.points ?? reading.ownPoints : request.points
        } else {
            switch typingStyle.points {
            case .set(let points)?: reading.points = points
            case .clear?:           reading.points = reading.ownPoints
            case nil:               break
            }
        }
        return reading
    }

    /// + and −, and ⌘+ and ⌘−. Off at the control's ends, 8 and 72 points.
    var canStepSelectionSize: (bigger: Bool, smaller: Bool) {
        let reading = selectionTextSize
        guard reading.canChange, selectionSizeAwaitingConfirmation == nil else { return (false, false) }
        let current = reading.points ?? reading.startPoints
        return (Self.stepped(current, by: 1) != nil, Self.stepped(current, by: -1) != nil)
    }

    /// + and −: a point bigger or smaller, for the selection, the run at the
    /// caret or the word there. Text in several sizes moves a point each,
    /// keeping them apart; each stops at the control's ends.
    func stepSelectionSize(by steps: Int) {
        guard let textView, selectionSizeAwaitingConfirmation == nil else { return }
        let reading = textSize(reading: currentFormatting(of: textView))
        guard mode == .text, !isTextLocked, reading.canChange else { return }
        // No word to resize: the next text typed gets the size, at once, since
        // nothing is laid out again.
        if isTypingCaret(in: textView) {
            let shown = selectionTextSize
            if let next = Self.stepped(shown.points ?? shown.startPoints, by: steps) {
                setTypingStyle(typingStyle.sizing(next))
            }
            return
        }
        // Where the control stands now, if the text is one size.
        let shown = pendingSelectionSize.map(\.points) ?? reading.points
        if let shown, Self.stepped(shown, by: steps) == nil { return }
        let total = (pendingSelectionSize?.steps ?? 0) + steps
        if pendingSelectionSize == nil { pendingTextLength = textView.textStorage.length }
        pendingSelectionSize = SizeRequest(
            points: reading.points.flatMap { Self.stepped($0, by: total) ?? $0 },
            selection: pendingSelectionSize?.selection ?? textView.selectedRange,
            steps: total
        )
        selectionSizeTask?.cancel()
        selectionSizeTask = Task { [weak self, settleDelay] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            self?.settleSelectionSize()
        }
    }

    /// A size picked from the list, or `nil` for Default: at once, since a
    /// pick isn't one of a run of taps.
    func setSelectionSize(points: Double?) {
        guard let textView, mode == .text, !isTextLocked, selectionSizeAwaitingConfirmation == nil else { return }
        dropPendingSelectionSize()
        if isTypingCaret(in: textView) {
            setTypingStyle(typingStyle.sizing(points.map { Self.clampedPoints($0) }))
            return
        }
        requestSelectionSize(SizeRequest(points: points.map { Self.clampedPoints($0) }, selection: textView.selectedRange))
    }

    /// Custom…: asks for a size (`PageDetailView`'s alert).
    func beginCustomSize() {
        guard let textView, mode == .text, !isTextLocked,
              textSize(reading: currentFormatting(of: textView)).canChange
        else { return }
        dropPendingSelectionSize()
        customSizeSelection = textView.selectedRange
    }

    /// Whether Custom…'s alert should also say what the ink question says.
    /// One alert, not two: a second can't come up as the first goes. Its Set
    /// counts as the yes.
    var customSizeAsksAboutInk: Bool { hasInk && !inkQuestionAnswered && !sizesTypedText }

    /// Whether the size control would set the typing style: no word to resize.
    /// Nothing is laid out again then, so there is no ink question.
    private var sizesTypedText: Bool {
        guard let textView else { return false }
        return isTypingCaret(in: textView)
    }

    func cancelCustomSize() {
        customSizeSelection = nil
    }

    /// The alert's Set: the typed size, clamped to 8 to 72 and to the half
    /// point. Anything that isn't a number sets nothing.
    func finishCustomSize(typed: String) {
        defer { customSizeSelection = nil }
        guard let selection = customSizeSelection, let points = Self.points(typed: typed) else { return }
        if sizesTypedText {
            setTypingStyle(typingStyle.sizing(points))
            return
        }
        if hasInk { inkQuestionAnswered = true }
        applySelectionSize(SizeRequest(points: points, selection: selection))
    }

    /// The ink alert's Change.
    func confirmSelectionSize() {
        guard let request = selectionSizeAwaitingConfirmation else { return }
        inkQuestionAnswered = true
        selectionSizeAwaitingConfirmation = nil
        applySelectionSize(request)
    }

    /// The ink alert's Cancel: the control goes back to the text's size.
    func cancelSelectionSize() {
        selectionSizeAwaitingConfirmation = nil
    }

    /// `points` stepped a point at a time, or `nil` past the control's ends.
    /// Text already outside them (a large run in a note made larger) steps
    /// back towards them, never further out.
    nonisolated static func stepped(_ points: Double, by steps: Int) -> Double? {
        SpanSize.stepped(points, by: steps)
    }

    /// A size the control can set: 8 to 72, to the half point.
    nonisolated static func clampedPoints(_ points: Double) -> Double {
        (min(max(points, SpanSize.points.lowerBound), SpanSize.points.upperBound) * 2).rounded() / 2
    }

    /// A typed size: a number, with "pt" or without, and a comma for a
    /// decimal point as some keyboards type it.
    nonisolated static func points(typed: String) -> Double? {
        var text = typed.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasSuffix("pt") { text.removeLast(2) }
        text = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), value.isFinite else { return nil }
        return clampedPoints(value)
    }

    /// The caret's formatting read from the text view itself, for an action:
    /// `caretFormatting` is what the coordinator last reported, for the bar.
    private func currentFormatting(of textView: UITextView) -> MarkdownFormatting.CaretFormatting {
        MarkdownFormatting.formatting(at: textView.selectedRange, in: textView.textStorage.mutableString, codeRanges: codeRanges?() ?? [])
    }

    /// `formatting`'s sizes in points, in the note's fonts as laid out.
    private func textSize(reading formatting: MarkdownFormatting.CaretFormatting) -> SelectionTextSize {
        let typography = self.typography
        if case .code = formatting.block {
            let code = Double(typography.code.pointSize)
            return SelectionTextSize(points: code, startPoints: code, ownPoints: code, canChange: false)
        }
        let sizes = blockSizes
        let points = formatting.sizes.map { SpanSize.points($0.size, against: sizes.size(forHeadingLevel: $0.headingLevel)) }
        let own = formatting.sizes.first.map { sizes.size(forHeadingLevel: $0.headingLevel) } ?? sizes.body
        let start = points.first ?? own
        return SelectionTextSize(
            points: Set(points).count > 1 ? nil : start,
            startPoints: start,
            ownPoints: own,
            canChange: mode == .text && !isTextLocked && formatting.canResize
        )
    }

    /// The note's block sizes as laid out, kept per text size: they come from
    /// the system's fonts, and the bar asks on every caret move.
    private var blockSizes: MarkdownFormatting.BlockSizes {
        if let cached = blockSizesCache, cached.bodySize == appliedTextSize { return cached.sizes }
        let sizes = typography.blockSizes
        blockSizesCache = (appliedTextSize, sizes)
        return sizes
    }
    @ObservationIgnored private var blockSizesCache: (bodySize: Int, sizes: MarkdownFormatting.BlockSizes)?

    /// The pending tap goes on. `keeping` is where the reader has just put
    /// the caret, which stays there rather than going back to the text sized.
    private func settleSelectionSize(keeping selection: NSRange? = nil) {
        selectionSizeTask = nil
        guard let request = pendingSelectionSize else { return }
        pendingSelectionSize = nil
        guard textView?.textStorage.length == pendingTextLength else { return }
        requestSelectionSize(request, keeping: selection)
    }

    private func dropPendingSelectionSize() {
        selectionSizeTask?.cancel()
        selectionSizeTask = nil
        pendingSelectionSize = nil
    }

    /// Sizes the text, or asks first on a note with ink: it re-wraps around
    /// the new size, and ink stays where it was drawn. One yes covers this
    /// and the note's own size until the note is next opened.
    private func requestSelectionSize(_ request: SizeRequest, keeping selection: NSRange? = nil) {
        guard let textView, sizeEdit(for: request, in: textView.textStorage.mutableString) != nil else { return }
        if hasInk, !inkQuestionAnswered {
            selectionSizeAwaitingConfirmation = request
        } else {
            applySelectionSize(request, keeping: selection)
        }
    }

    /// Sizes the text. The caret ends on what was sized, unless `keeping`
    /// says where else it was just put: there, moved past the tags if they
    /// went in before it.
    private func applySelectionSize(_ request: SizeRequest, keeping selection: NSRange? = nil) {
        guard let textView, let edit = sizeEdit(for: request, in: textView.textStorage.mutableString) else { return }
        let replaced = textView.textStorage.mutableString.substring(with: edit.range)
        perform { _, _ in edit }
        guard let kept = selection,
              let start = Self.offset(kept.location, through: edit, replacing: replaced),
              let end = Self.offset(NSMaxRange(kept), through: edit, replacing: replaced)
        else { return }
        textView.selectedRange = NSRange(location: start, length: end - start)
    }

    /// Where `offset` in the text before `edit` is after it, if it lies in
    /// what the edit left as it was: the start of the lines it rewrote, up
    /// to the first change, or their end, from the last. `nil` in between.
    nonisolated static func offset(_ offset: Int, through edit: TextEdit, replacing old: String) -> Int? {
        let old = Array(old.utf16)
        let new = Array(edit.replacement.utf16)
        if offset <= edit.range.location { return offset }
        if offset >= NSMaxRange(edit.range) { return offset + new.count - old.count }
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let local = offset - edit.range.location
        if local <= prefix { return offset }
        if local >= old.count - suffix { return offset + new.count - old.count }
        return nil
    }

    private func sizeEdit(for request: SizeRequest, in text: NSString) -> TextEdit? {
        if let steps = request.steps {
            return MarkdownFormatting.size(
                steppedBy: steps, blockSizes: blockSizes, selection: request.selection, in: text, codeRanges: codeRanges?() ?? []
            )
        }
        return MarkdownFormatting.size(
            points: request.points, blockSizes: blockSizes, selection: request.selection, in: text, codeRanges: codeRanges?() ?? []
        )
    }

    /// What Link will wrap, kept while the address is asked for: the alert
    /// takes the keyboard, and with it the text view's selection is not
    /// something to read back afterwards. `nil` when no address is being
    /// asked for.
    private(set) var linkTarget: NSRange?

    /// Whether Link has anything to wrap here: not in code, not across a
    /// line, not inside a link that is already there.
    var canLink: Bool {
        guard mode == .text, !isTextLocked, let textView else { return false }
        return MarkdownFormatting.linkTarget(
            in: textView.textStorage.mutableString, selection: textView.selectedRange, codeRanges: codeRanges?() ?? []
        ) != nil
    }

    /// Link: asks for the address (`PageDetailView`'s alert), for the
    /// selection, or the word at the caret, or a placeholder.
    func beginLink() {
        guard mode == .text, !isTextLocked, let textView,
              let target = MarkdownFormatting.linkTarget(
                  in: textView.textStorage.mutableString,
                  selection: textView.selectedRange,
                  codeRanges: codeRanges?() ?? []
              )
        else { return }
        linkTarget = target
    }

    func cancelLink() {
        linkTarget = nil
    }

    /// The alert's Add: wraps what was asked about in `[text](address)`. An
    /// address with nothing in it adds nothing.
    func finishLink(address typed: String) {
        defer { linkTarget = nil }
        guard let target = linkTarget, let address = MarkdownFormatting.linkAddress(from: typed) else { return }
        perform { text, _ in
            MarkdownFormatting.link(address: address, over: target, in: text as NSString)
        }
    }

    // MARK: The note's text size

    /// The note's own body size as ••• › Text Size shows it: the reader's
    /// latest pick, which the note catches up to after `settleDelay` and,
    /// for a note with ink, a yes. Every size in the note is against it.
    private(set) var textSize = NoteTypography.defaultSize

    /// The size the note is laid out in now, from `Page.textSize`.
    private(set) var appliedTextSize = NoteTypography.defaultSize

    /// The note's typography as it is now, for a PDF made of it.
    var typography: NoteTypography { NoteTypography(bodySize: appliedTextSize, lineSpacing: appliedLineSpacing) }

    /// A size waiting for the reader's yes, because the note has ink: the
    /// text re-flows and ink stays where it was drawn. `nil` unless the alert
    /// is up.
    private(set) var sizeAwaitingConfirmation: Int?

    /// Whether the reader has said yes since this note was opened ("once
    /// each time the note is opened"). The editor is made per note.
    @ObservationIgnored private var inkQuestionAnswered = false

    /// Writes the size into the note (`Page.textSize`). Set by the page.
    /// Not an edit: the page leaves `modifiedAt` and the undo stack alone.
    @ObservationIgnored var commitTextSize: ((Int?) -> Void)?

    /// How long a size waits after a tap or a pick before the text re-flows,
    /// so a run of the size control's taps lays the note out once.
    @ObservationIgnored var settleDelay = Duration.milliseconds(300)
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    /// Follows the note's stored size (`Page.textSize`), as the page opens
    /// and whenever something else changes it. A tap in flight wins until it
    /// settles.
    func syncTextSize(to stored: Int?) {
        let size = NoteTypography(bodySize: stored).bodySize
        appliedTextSize = size
        if settleTask == nil, sizeAwaitingConfirmation == nil, textSize != size { textSize = size }
    }

    /// A size picked from ••• › Text Size. Text mode only, and not for a
    /// locked note, whose text is read and not changed.
    func setTextSize(_ size: Int) {
        guard mode == .text, !isTextLocked, sizeAwaitingConfirmation == nil else { return }
        let size = NoteTypography(bodySize: size).bodySize
        guard size != textSize else { return }
        textSize = size
        settleTask?.cancel()
        settleTask = Task { [weak self, settleDelay] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            self?.settleTextSize()
        }
    }

    private func settleTextSize() {
        settleTask = nil
        guard textSize != appliedTextSize else { return }
        if hasInk, !inkQuestionAnswered {
            sizeAwaitingConfirmation = textSize
        } else {
            commitTextSize?(NoteTypography(bodySize: textSize).storedSize)
            appliedTextSize = textSize
        }
    }

    /// The alert's Change.
    func confirmTextSize() {
        guard let size = sizeAwaitingConfirmation else { return }
        inkQuestionAnswered = true
        sizeAwaitingConfirmation = nil
        commitTextSize?(NoteTypography(bodySize: size).storedSize)
        appliedTextSize = size
        textSize = size
    }

    /// The alert's Cancel: the stepper goes back to the size the note has.
    func cancelTextSize() {
        sizeAwaitingConfirmation = nil
        textSize = appliedTextSize
    }

    // MARK: The note's line spacing

    /// The points of line spacing the note is laid out with, from
    /// `Page.lineSpacing`, and as the text row's menu shows them. A pick is
    /// one action, so it applies at once (no `settleDelay`); a note with ink
    /// asks first, once each time it is opened, with the text size's answer.
    private(set) var lineSpacing = 0
    private(set) var appliedLineSpacing = 0

    /// A spacing waiting for the reader's yes, because the note has ink.
    private(set) var spacingAwaitingConfirmation: Int?

    /// Writes the spacing into the note (`Page.lineSpacing`). Not an edit.
    @ObservationIgnored var commitLineSpacing: ((Int?) -> Void)?

    /// Follows the note's stored spacing, as the page opens and whenever
    /// something else changes it.
    func syncLineSpacing(to stored: Int?) {
        let spacing = NoteTypography(lineSpacing: stored).lineSpacing
        appliedLineSpacing = spacing
        if spacingAwaitingConfirmation == nil { lineSpacing = spacing }
    }

    /// A spacing picked from the text row. Text mode only, and not for a
    /// locked note.
    func setLineSpacing(_ points: Int) {
        guard mode == .text, !isTextLocked, spacingAwaitingConfirmation == nil else { return }
        let spacing = NoteTypography(lineSpacing: points).lineSpacing
        guard spacing != appliedLineSpacing else { return }
        if hasInk, !inkQuestionAnswered {
            spacingAwaitingConfirmation = spacing
        } else {
            commitLineSpacing?(NoteTypography(lineSpacing: spacing).storedLineSpacing)
            appliedLineSpacing = spacing
            lineSpacing = spacing
        }
    }

    /// The alert's Change.
    func confirmLineSpacing() {
        guard let spacing = spacingAwaitingConfirmation else { return }
        inkQuestionAnswered = true
        spacingAwaitingConfirmation = nil
        commitLineSpacing?(NoteTypography(lineSpacing: spacing).storedLineSpacing)
        appliedLineSpacing = spacing
        lineSpacing = spacing
    }

    /// The alert's Cancel.
    func cancelLineSpacing() {
        spacingAwaitingConfirmation = nil
        lineSpacing = appliedLineSpacing
    }

    /// Whether the note has any ink. The page's own copy, so strokes drawn
    /// moments ago count.
    private var hasInk: Bool {
        guard let page else { return false }
        return !page.ink.subelements.isEmpty
    }

    // MARK: Outline

    /// The note's headings, and which one the reader is under: the last at or
    /// above the line at the top of the page. Worked out when the popover
    /// opens, from the text as it is.
    func outline() -> (entries: [NoteOutline.Entry], current: Int?) {
        let entries = NoteOutline.entries(in: (textView?.text ?? "").nativeUTF8)
        let top = page?.topLineCharacter() ?? 0
        return (entries, NoteOutline.currentIndex(in: entries, atCharacter: top))
    }

    /// An outline tap: the heading's line at the top of the page.
    func scroll(toHeading entry: NoteOutline.Entry) {
        page?.scroll(toLineAt: entry.location)
    }

    // MARK: Undo

    /// The undo stack of whichever layer is taking input.
    ///
    /// Two stacks, not one. Left alone they would be one: the canvas's
    /// `undoManager` walks the responder chain into the text view's. Ink and
    /// text are separate kinds of edit, and undoing a stroke by accident while
    /// typing is worse than an arrow that only undoes what the current mode
    /// did, so `DrawingCanvas` vends its own and this picks between them.
    ///
    /// None while the text is locked: undoing typing would change locked
    /// text. Ink keeps its stack, since the lock leaves ink alone.
    private var activeUndoManager: UndoManager? {
        switch mode {
        case .text: isTextLocked ? nil : textView?.undoManager
        case .ink:  canvas?.undoManager
        }
    }

    func undo() {
        activeUndoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        activeUndoManager?.redo()
        refreshUndoState()
    }

    /// ⌘Z and ⇧⌘Z, from the menu bar.
    ///
    /// The note's own stacks, unless some other text field has the keyboard
    /// (the title being renamed, the list's search): undoing there is for
    /// that field, and the note's typing isn't what was asked for. The
    /// system's Undo command reaches only a first responder that has an undo
    /// manager, and in ink mode nothing on the page is first responder, so
    /// the menu would otherwise be dead exactly when ink has the page.
    func undoFromKeyboard() {
        if let other = otherTextInputUndoManager { other.undo() } else { undo() }
    }

    func redoFromKeyboard() {
        if let other = otherTextInputUndoManager { other.redo() } else { redo() }
    }

    private var otherTextInputUndoManager: UndoManager? {
        guard let responder = UIResponder.currentFirstResponder,
              responder is UITextInput, responder !== textView
        else { return nil }
        return responder.undoManager
    }

    /// Re-reads whether undo and redo have anything to do.
    ///
    /// Assigns only on a real change. This runs on every keystroke, and an
    /// observable property invalidates its readers on any assignment, equal
    /// value or not — the whole hotbar would re-render per character.
    func refreshUndoState() {
        let undo = activeUndoManager?.canUndo ?? false
        let redo = activeUndoManager?.canRedo ?? false
        if canUndo != undo { canUndo = undo }
        if canRedo != redo { canRedo = redo }
    }
}

extension UIResponder {
    private weak static var found: UIResponder?

    /// The responder holding the keyboard, if any.
    ///
    /// UIKit has no public accessor. Sending an action to no one in
    /// particular walks the responder chain from the first responder, and the
    /// first one to answer is it.
    static var currentFirstResponder: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.noteCodeReportFirstResponder), to: nil, from: nil, for: nil)
        return found
    }

    @objc fileprivate func noteCodeReportFirstResponder() {
        Self.found = self
    }
}

#endif
