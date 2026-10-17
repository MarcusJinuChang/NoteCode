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
        }
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

    /// Where the last code language is kept. Replaceable so a test doesn't
    /// write the device's own.
    @ObservationIgnored var defaults = UserDefaults.standard

    /// Run or copy the code block the caret is in, if it's in one. The text
    /// view's coordinator sets these: it owns the blocks and where they run.
    @ObservationIgnored var runBlockAtCaret: (() -> Void)?
    @ObservationIgnored var copyBlockAtCaret: (() -> Void)?

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
        page.insertIntoInk(extent: extent) { insert(controller) }
        inkTool.kind = .lasso
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
        canvas?.tool = inkTool.pencilKitTool
        canvas?.allowsFingerDrawing = !isPencilOnly
        canvas?.onUndoDidChange = { [weak self] in self?.refreshUndoState() }
        savedSession = mode.apply(to: textView, canvas: canvas, saved: nil, textLocked: isTextLocked)
        applyScrolling()
        refreshUndoState()
    }

    func setMode(_ newMode: EditorMode) {
        guard newMode != mode else { return }
        mode = newMode
        if let textView {
            savedSession = newMode.apply(to: textView, canvas: canvas, saved: savedSession, textLocked: isTextLocked)
        }
        applyScrolling()
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

    func toggle(_ style: MarkdownFormatting.InlineStyle) {
        perform { MarkdownFormatting.toggle(style, in: $0, selection: $1) }
    }

    func setHeading(level: Int) {
        perform { MarkdownFormatting.setHeading(level: level, in: $0, selection: $1) }
    }

    func toggleBullet() {
        toggleList(.bullet)
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
    func setCaretFormatting(_ formatting: MarkdownFormatting.CaretFormatting) {
        if caretFormatting != formatting { caretFormatting = formatting }
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
        guard mode == .text, !isTextLocked else { return }
        perform { [codeRanges] text, selection in
            MarkdownFormatting.colour(hex, selection: selection, in: text as NSString, codeRanges: codeRanges?() ?? [])
        }
    }

    /// A size for a run (`SpanSize`) waiting for the reader's yes, with the
    /// selection it was asked for: the alert takes the keyboard, and the
    /// text view's selection isn't something to read back afterwards.
    struct SpanSizeRequest: Equatable {
        var size: SpanSize?
        var selection: NSRange
    }

    /// `nil` unless the alert is up.
    private(set) var spanSizeAwaitingConfirmation: SpanSizeRequest?

    /// Size: sets `size` on the selection, the run at the caret or the word
    /// there; `nil` makes them normal size. The text re-wraps around it, so
    /// on a note with ink it asks first, as the note's text size does, and
    /// one yes covers both until the note is next opened.
    func setSpanSize(_ size: SpanSize?) {
        guard mode == .text, !isTextLocked, let textView,
              MarkdownFormatting.size(
                  size, selection: textView.selectedRange, in: textView.textStorage.mutableString, codeRanges: codeRanges?() ?? []
              ) != nil
        else { return }
        let request = SpanSizeRequest(size: size, selection: textView.selectedRange)
        if hasInk, !inkQuestionAnswered {
            spanSizeAwaitingConfirmation = request
        } else {
            applySpanSize(request)
        }
    }

    /// The alert's Change.
    func confirmSpanSize() {
        guard let request = spanSizeAwaitingConfirmation else { return }
        inkQuestionAnswered = true
        spanSizeAwaitingConfirmation = nil
        applySpanSize(request)
    }

    /// The alert's Cancel.
    func cancelSpanSize() {
        spanSizeAwaitingConfirmation = nil
    }

    private func applySpanSize(_ request: SpanSizeRequest) {
        perform { [codeRanges] text, _ in
            MarkdownFormatting.size(request.size, selection: request.selection, in: text as NSString, codeRanges: codeRanges?() ?? [])
        }
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

    // MARK: Text size

    /// The size the stepper shows: the reader's latest tap, which the note
    /// catches up to once they stop (`settleDelay`) and, for a note with ink,
    /// say yes.
    private(set) var textSize = NoteTypography.defaultSize

    /// The size the note is laid out in now, from `Page.textSize`.
    private(set) var appliedTextSize = NoteTypography.defaultSize

    /// The note's typography as it is now, for a PDF made of it.
    var typography: NoteTypography { NoteTypography(bodySize: appliedTextSize) }

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

    /// How long the stepper waits after a tap before the note re-flows, so a
    /// run of taps lays the note out once.
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

    /// + and −: one step bigger or smaller. Text mode only, and not for a
    /// locked note, whose text is read and not changed.
    func stepTextSize(by steps: Int) {
        guard let size = NoteTypography(bodySize: textSize).size(steppedBy: steps) else { return }
        setTextSize(size)
    }

    /// A size picked from the list, or stepped to.
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

    /// ⌘+ and ⌘−.
    var canStepTextSize: (bigger: Bool, smaller: Bool) {
        let typography = NoteTypography(bodySize: textSize)
        return (typography.size(steppedBy: 1) != nil, typography.size(steppedBy: -1) != nil)
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
