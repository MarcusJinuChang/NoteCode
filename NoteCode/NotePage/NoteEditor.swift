//
//  NoteEditor.swift
//  NoteCode
//
//  What the hotbar talks to: the page's mode, its ink tool, and its text view.
//

#if canImport(UIKit)

import Observation
import PaperKit
import SwiftUI
import UIKit

/// A note page's editing state, shared by the hotbar and the editor.
///
/// SwiftUI owns the hotbar and UIKit owns the text view, and neither can reach
/// the other. This sits between them: the hotbar reads and changes state here,
/// and the text view registers itself so that edits have somewhere to land.
@Observable
final class NoteEditor {

    // MARK: The mode and the ink tool in hand (EditorModeState)

    @ObservationIgnored private(set) var modeState: EditorModeState!

    var mode: EditorMode { modeState.mode }

    /// Called after the mode changes. The text view's code blocks show or
    /// hide their fences with it (`DocumentTextView.Coordinator`), and no
    /// edit or selection change tells them.
    var modeDidChange: (() -> Void)? {
        get { modeState.modeDidChange }
        set { modeState.modeDidChange = newValue }
    }

    /// What the pen, highlighter, eraser and Select tool are set to, and
    /// Finger Draws, kept for the device (`InkToolStore`).
    var inkTools: InkToolStore { modeState.inkTools }

    /// What ink mode draws with: the tool in hand, and the store's settings.
    var inkTool: InkToolState {
        get { modeState.inkTool }
        set { modeState.inkTool = newValue }
    }

    /// The Select tool's selection, once the page exists.
    var selection: InkSelection? { modeState.selection }

    /// The tool in use before the current one.
    var previousInkKind: InkToolKind { modeState.previousInkKind }

    func toggleEraser() { modeState.toggleEraser() }
    func switchToPreviousTool() { modeState.switchToPreviousTool() }
    @discardableResult
    func enterInkForPencil(_ response: PencilResponse) -> Bool { modeState.enterInkForPencil(response) }
    func selectTool(_ kind: InkToolKind) { modeState.selectTool(kind) }
    func stepWidth(by direction: Int) { modeState.stepWidth(by: direction) }
    func toggleMode() { modeState.toggleMode() }
    func setMode(_ newMode: EditorMode) { modeState.setMode(newMode) }
    func selectionEnded() { modeState.selectionEnded() }

    /// Whether only the Pencil draws.
    var isPencilOnly: Bool {
        get { modeState.isPencilOnly }
        set { modeState.isPencilOnly = newValue }
    }

    /// The same switch as `isPencilOnly`, said the way the hotbar's hand
    /// button says it: on, a finger draws.
    var fingerDraws: Bool {
        get { modeState.fingerDraws }
        set { modeState.fingerDraws = newValue }
    }

    /// Whether the selection ending sends the reader back to their tool.
    var returnsToPreviousTool: Bool {
        get { modeState.returnsToPreviousTool }
        set { modeState.returnsToPreviousTool = newValue }
    }

    func applySelecting() { modeState.applySelecting() }
    func applyScrolling() { modeState.applyScrolling() }

    /// Whether the text options row is out on a phone, where it waits to be
    /// asked for (`Hotbar.showsTextRow`). Ignored in a regular width.
    var wantsTextRow = false

    /// Whether the note's text is locked (`Page.isTextLocked`), so text mode
    /// reads rather than edits: no keyboard, no formatting, no undo. The page
    /// holds the setting; this is the copy the text view and the hotbar
    /// follow, set by `setTextLocked(_:)`.
    private(set) var isTextLocked = false

    var canUndo: Bool { undoRouter.canUndo }
    var canRedo: Bool { undoRouter.canRedo }

    /// Undo and redo (`UndoRouter`): which stack, and whether either has a step.
    @ObservationIgnored private(set) var undoRouter: UndoRouter!

    /// The flags that say an edit is the app's own, so the delegate doesn't
    /// take it for the keyboard's: a formatting button's edit, the typing
    /// style's text being written. The text view's coordinator shares them.
    @ObservationIgnored let editGuard = EditGuard()

    /// Typing style (`TypingStyleController`): what the next text typed will be
    /// drawn with, set by a button that has no word to act on.
    @ObservationIgnored private(set) var typing: TypingStyleController!
    var typingStyle: TypingStyle { typing.typingStyle }

    /// A caret move, a mode switch, a locked note, a keyboard going away.
    func clearTypingStyle() { typing.clear() }
    func typingTextWillChange(range: NSRange) { typing.textWillChange(range: range) }
    func typingTextDidChange(in textView: UITextView, isTyping: Bool) { typing.textDidChange(in: textView, isTyping: isTyping) }
    func typingSelectionDidChange(afterEdit: Bool) { typing.selectionDidChange(afterEdit: afterEdit) }

    /// Where the last code language is kept. Replaceable so a test doesn't
    /// write the device's own.
    @ObservationIgnored var defaults = UserDefaults.standard

    /// The text view's coordinator: Run, Copy, indent and the new formula
    /// act on the text it owns, so the editor asks it (`TextCommandTarget`).
    /// Weak, since the text view's coordinator outlives neither the editor's
    /// page nor, in a test, its harness.
    @ObservationIgnored weak var textTarget: TextCommandTarget?

    /// The code block the caret is in, in text mode; `nil` elsewhere. The
    /// options row's feature actions act on it.
    var codeBlockAtCaret: CodeBlockTarget? { textTarget?.codeBlockAtCaret() }

    /// ⌘R and ⇧⌘C: run or copy the code block the caret is in, if it's in
    /// one. Run asks the features first, then opens a compiler site.
    func runBlockAtCaret() { textTarget?.runBlockAtCaret() }
    func copyBlockAtCaret() { textTarget?.copyBlockAtCaret() }

    /// What the edition adds to this editor (`EditorFeature`), in the order
    /// their actions are shown. Empty for `NoteEditor()`.
    private(set) var features: [any EditorFeature] = []
    @ObservationIgnored private var featuresInstalled = false
    /// What the text view's coordinator offers the features, kept for a
    /// feature installed after it connected.
    @ObservationIgnored private var services: EditorServices?

    /// - Parameter inkTools: the tool settings. A store with no device behind
    ///   it unless the note is opened for the reader (`NoteSession`), so an
    ///   editor made in a test reaches no real settings.
    init(features: [EditorFeatureFactory] = [], inkTools: InkToolStore = InkToolStore()) {
        modeState = EditorModeState(editor: self, inkTools: inkTools)
        undoRouter = UndoRouter(editor: self)
        typographyController = NoteTypographyController(editor: self)
        typing = TypingStyleController(editor: self)
        selectionSize = SelectionSizeController(editor: self)
        install(features)
    }

    func undo() { undoRouter.undo() }
    func redo() { undoRouter.redo() }
    func undoFromKeyboard() { undoRouter.undoFromKeyboard() }
    func redoFromKeyboard() { undoRouter.redoFromKeyboard() }

    /// Makes the features, once: a page that is handed its editor's features
    /// after the editor was made (`PageDetailView`) calls this on appearing.
    func install(_ factories: [EditorFeatureFactory]) {
        guard !featuresInstalled, !factories.isEmpty else { return }
        featuresInstalled = true
        features = factories.map { $0(self) }
        if let services {
            for feature in features { feature.connect(services) }
        }
    }

    /// The text view's coordinator connected: hands its services to every
    /// feature, now and as they are installed.
    func connectFeatures(_ services: EditorServices) {
        self.services = services
        for feature in features { feature.connect(services) }
    }

    /// The note's code blocks after an edit, for every feature.
    func blocksDidChange(_ targets: [CodeBlockTarget]) {
        for feature in features { feature.blocksDidChange(targets) }
    }

    /// The installed feature of this type, if there is one.
    func feature<F: EditorFeature>(_ type: F.Type) -> F? {
        features.lazy.compactMap { $0 as? F }.first
    }

    /// Every feature's actions on `target` for one placement, in order.
    func actions(for target: EditorActionTarget, in placement: EditorActionPlacement) -> [EditorAction] {
        features.flatMap { $0.actions(for: target) }.filter { $0.placement == placement }
    }

    /// Told after a code block's code is on the pasteboard, by the button, the
    /// edit menu or ⇧⌘C, so the page can say "Copied".
    @ObservationIgnored var onBlockCopied: (() -> Void)?

    @ObservationIgnored private(set) weak var textView: UITextView?
    @ObservationIgnored weak var canvas: DrawingCanvas?
    @ObservationIgnored weak var page: PageView?

    // MARK: Insert

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
        lastInserted = inserted
        return true
    }

    /// What the last Insert put on the page, for `reselectInserted`.
    @ObservationIgnored private var lastInserted: Set<MarkupOrderedSet.ElementID> = []

    /// Selects what the last Insert added again, if the Select tool is still
    /// the tool and nothing is selected: the popover's dismissal and
    /// PaperKit's own callbacks arrive after the insert returns, and the
    /// options row must not be left without its object. Does nothing once
    /// the reader has chosen something else.
    func reselectInserted() {
        guard mode == .ink, inkTool.kind == .lasso, let selection = page?.selection,
              selection.isEmpty, !lastInserted.isEmpty
        else { return }
        selection.select(ids: lastInserted)
        selection.refresh()
        lastInserted = []
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
            self?.undoRouter.refresh()
            // Undo can bring back or remove what is selected.
            self?.page?.selection.refresh()
        }
        page?.selection.kind = inkTool.selectionKind
        page?.selection.textPiecesFor = { [weak self] shape in
            guard let self, !self.isTextLocked, let textView = self.textView else { return [] }
            // Code is never coloured, so it is never selected as text.
            let code = self.codeRanges
            return TextRegion.pieces(for: shape, lines: TextRegion.visibleLines(in: textView)).filter { piece in
                !code.contains { NSIntersectionRange($0.range, piece.range).length > 0 }
            }
        }
        page?.selection.onEditingChange = { [weak self] in self?.applySelecting() }
        page?.selection.onEnded = { [weak self] in self?.selectionEnded() }
        page?.selection.recolourText = { [weak self] ranges, hex in self?.recolourText(ranges, to: hex) }
        modeState.attachViews(textView, canvas: canvas)
        applySelecting()
        applyScrolling()
        undoRouter.refresh()
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
        modeState.textLockDidChange(locked)
        undoRouter.refresh()
    }

    // MARK: Formatting state (the commands are in NoteEditor+Formatting)

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
        selectionSize.selectionDidMove()
    }

    // MARK: The size at the caret (SelectionSizeController)

    @ObservationIgnored private(set) var selectionSize: SelectionSizeController!

    typealias SelectionTextSize = SelectionSizeController.SelectionTextSize
    typealias SizeRequest = SelectionSizeController.SizeRequest

    var pendingSelectionSize: SizeRequest? { selectionSize.pendingSelectionSize }
    var customSizeSelection: NSRange? { selectionSize.customSizeSelection }

    /// What the size control shows: the tap or the answer in flight, or the
    /// text as it is.
    var selectionTextSize: SelectionTextSize { selectionSize.selectionTextSize }
    var canStepSelectionSize: (bigger: Bool, smaller: Bool) { selectionSize.canStepSelectionSize }

    func stepSelectionSize(by steps: Int) { selectionSize.stepSelectionSize(by: steps) }
    func setSelectionSize(points: Double?) { selectionSize.setSelectionSize(points: points) }
    func beginCustomSize() { selectionSize.beginCustomSize() }
    func cancelCustomSize() { selectionSize.cancelCustomSize() }
    func finishCustomSize(typed: String) { selectionSize.finishCustomSize(typed: typed) }

    /// What Link will wrap, kept while the address is asked for: the alert
    /// takes the keyboard, and with it the text view's selection is not
    /// something to read back afterwards. `nil` when no address is being
    /// asked for.
    private(set) var linkTarget: NSRange?

    /// Link: asks for the address (`PageDetailView`'s alert), for the
    /// selection, or the word at the caret, or a placeholder.
    func beginLink() {
        guard mode == .text, !isTextLocked, let textView,
              let target = MarkdownFormatting.linkTarget(
                  in: textView.textStorage.mutableString,
                  selection: textView.selectedRange,
                  codeRanges: codeRanges
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

    /// How long a size waits after a tap or a pick before the text re-flows,
    /// so a run of the size control's taps lays the note out once.
    @ObservationIgnored var settleDelay = Duration.milliseconds(120)

    /// What `settleDelay` is measured on. Tests set one they move by hand;
    /// the app keeps `ContinuousClock`, as `Task.sleep(for:)` uses.
    @ObservationIgnored var settleClock: any Clock<Duration> = ContinuousClock()

    // MARK: The note's typography (NoteTypographyController)

    @ObservationIgnored private(set) var typographyController: NoteTypographyController!

    var textSize: Int { typographyController.textSize }
    var appliedTextSize: Int { typographyController.appliedTextSize }
    var lineSpacing: Int { typographyController.lineSpacing }
    var appliedLineSpacing: Int { typographyController.appliedLineSpacing }

    /// The note's typography as it is now, for a PDF made of it.
    var typography: NoteTypography { typographyController.typography }

    /// Writes the size into the note (`Page.textSize`). Set by the page.
    var commitTextSize: ((Int?) -> Void)? {
        get { typographyController.commitTextSize }
        set { typographyController.commitTextSize = newValue }
    }

    /// Writes the spacing into the note (`Page.lineSpacing`). Not an edit.
    var commitLineSpacing: ((Int?) -> Void)? {
        get { typographyController.commitLineSpacing }
        set { typographyController.commitLineSpacing = newValue }
    }

    func syncTextSize(to stored: Int?) { typographyController.syncTextSize(to: stored) }
    func setTextSize(_ size: Int) { typographyController.setTextSize(size) }
    func syncLineSpacing(to stored: Int?) { typographyController.syncLineSpacing(to: stored) }
    func setLineSpacing(_ points: Int) { typographyController.setLineSpacing(points) }

    /// Returns once the sizes waiting for `settleDelay`, the note's and the
    /// selection's, have been applied, or were dropped. For tests.
    func sizeSettled() async {
        await typographyController.settleTask?.value
        await selectionSize.selectionSizeTask?.value
    }
}

#endif
