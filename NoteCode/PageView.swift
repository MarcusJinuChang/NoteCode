//
//  PageView.swift
//  NoteCode
//
//  The page: a paged, fixed-width text view, drawn at whatever scale fits.
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import SwiftUI
import UIKit

/// Hosts the editor at its pages' width, breaks its text into pages, and
/// draws it at the scale the area and the reader's zoom call for.
///
/// **Scale.** The text view still scrolls itself, and the scale is a transform
/// on it. A non-scrolling text view inside an outer zoom scroll view makes
/// TextKit 2's viewport the entire document: measured on 12 September 2026, a
/// 500-line note cost 477ms per keystroke against 11ms. This view scrolls only
/// sideways, when zoom makes the page wider than the area.
///
/// **Pages.** Text flows around a band after each page's body, set as the
/// text container's exclusion paths; `PageLayout` has the geometry and why
/// every mode paginates identically. The bands make typing cost more, because
/// TextKit lays out everything below an edit once any exclusion path exists —
/// see docs/archive/phase-drawing-layer.md for the numbers.
final class PageView: UIScrollView, UIGestureRecognizerDelegate {

    let textView: DocumentUITextView

    /// The ink layer. A subview of the text view's content, so it scrolls with
    /// the text and is scaled by the same transform, with no code to keep the
    /// two in step.
    let canvas: DrawingCanvas

    /// The Select tool: what is selected on the canvas, and the view that
    /// owns touches while it is the tool (docs/design/object-system.md).
    let selection: InkSelection
    let selectionOverlay: InkSelectionOverlay

    /// Sheets in print layout, break lines in compressed. Behind the text.
    let decorations = PageDecorationView()

    /// Over the ink, where seamless has no room — see `PageCoverView`.
    let covers = PageCoverView()

    /// What the page is painted, and what shows beside it. Dynamic colours:
    /// white on #F2F2F7 in light, black on #1C1C1E in dark.
    static let pageColor = UIColor.systemBackground
    static let surroundColor = UIColor.secondarySystemBackground

    private let indicator = UIView()
    private var offsetObservation: NSKeyValueObservation?
    private var fadeTask: Task<Void, Never>?
    private var lastPanTranslation = CGPoint.zero
    private let sidewaysFling = SidewaysFling()
    /// The page's edge: a hairline and a soft shadow behind the text view
    /// in the continuous modes (print layout's sheets have their own).
    private let pageEdge = PageEdgeView()

    /// The pages' orientation and how they are shown.
    ///
    /// Changing the mode keeps the reader's place and shows ink on its page.
    /// Changing the orientation re-wraps the text at a new width, so neither
    /// can be carried over exactly: the place is kept proportionally, and ink
    /// keeps its printed position, which no longer sits on the same words.
    var pageLayout = PageLayout() {
        didSet {
            guard pageLayout != oldValue else { return }
            applyPageLayout(replacing: oldValue)
        }
    }

    /// The reader's zoom, relative to fitting the page's width to the area.
    private(set) var zoom: CGFloat = 1

    /// The area's width when the page was last fitted to it, so a change of
    /// width re-centres a page fitted to its text column.
    private var fittedWidth: CGFloat = 0

    /// A search result's matches, waiting for the note's first layout: the
    /// first to scroll to, and all of them to highlight.
    private var pendingReveal: (first: NSRange, all: [NSRange])?

    /// The page to open the note at, waiting for its first layout.
    private var pendingRestore: Int?
    private var restoreScheduled = false

    /// Told which page the reader is on whenever that changes, or the page
    /// count does: the device remembers it for next time. Held back until the
    /// note has been scrolled to where it is opening (`restore`), so opening
    /// at page 4 doesn't first report page 1.
    var onReadingPlaceChanged: ((NoteMemory.Place) -> Void)?
    private var lastReportedPlace: NoteMemory.Place?

    /// Told whenever the note scrolls, with the page then at the top: the
    /// page badge shows while this keeps arriving and fades once it stops.
    /// Unlike the reading place this fires on every move, not only on a new
    /// page, since a scroll within a page still keeps the badge up.
    var onScrolled: ((NoteMemory.Place) -> Void)?
    private var lastScrolledOffset: CGFloat = 0

    /// The scale the page is drawn at right now.
    private(set) var displayScale: CGFloat = 1

    /// How many pages the text and ink fill. Worked out whenever TextKit sets
    /// the text's height — see `noteHeight(forTextHeight:)`.
    private(set) var pageCount = 1

    /// The fewest pages the note has (`Page.minimumPageCount`): Add Page
    /// raises it, and so does ink reaching the last page in seamless.
    /// Setting it from outside only follows the note; it is told onward
    /// (`onMinimumPageCountChanged`) only when this view raises it.
    var minimumPageCount = 1 {
        didSet {
            guard minimumPageCount != oldValue else { return }
            textView.reapplyContentHeightAdjustment()
            textView.setNeedsLayout()
        }
    }

    /// Told the new minimum when this view raises it, so the note keeps it.
    var onMinimumPageCountChanged: ((Int) -> Void)?

    /// Whether a stroke the reader ends in the last page's foot adds a page
    /// (`InkPageGrowth`). Seamless keeps a blank page below ink regardless.
    var addsPagesWhileDrawing = InkPageGrowth.defaultEnabled

    /// How many pages the text currently has bands for.
    private var bandedPageCount = 0

    /// The note's ink, in print layout's coordinates: where each stroke sits
    /// on its sheet, which is also where it prints.
    ///
    /// The canvas shows it converted to the current mode, and every mode
    /// change converts from this rather than from the canvas. Ink in a sheet's
    /// margin has no exact place in a mode with narrower breaks — see
    /// `PageLayout.convert` — so converting what's on screen back and forth
    /// would move it a page on every round trip.
    ///
    /// Strokes the reader made are taken in off the main thread
    /// (`captureInk`), so reading this first finishes any still on their way.
    var ink: PaperMarkup {
        commitInk()
        return inkState.ink
    }

    /// The stored ink, and where each element sat on the canvas when it was
    /// last shown or read. See `InkCapture.State`.
    private var inkState: InkCapture.State

    /// The canvas as the reader last left it, not yet taken into `inkState`,
    /// with the layout and page count it was drawn in.
    private struct InkSnapshot {
        var markup: PaperMarkup
        var layout: PageLayout
        var pageCount: Int
        var serial: Int
    }

    /// The newest snapshot not yet taken in, whether a capture is working on
    /// it or it's waiting for the one before to finish.
    private var newestSnapshot: InkSnapshot?
    private var snapshotSerial = 0
    private var isCapturing = false

    /// Bumped whenever `inkState` is replaced on the main thread, so a
    /// capture that started from the old one drops its result.
    private var inkGeneration = 0

    /// The lowest point of the ink as shown, cached so working out the page
    /// count — which every layout pass does — doesn't walk the strokes.
    private var inkBottom: CGFloat?

    /// Called with the note's ink, in print coordinates, whenever the reader
    /// changes it: a stroke drawn, erased or moved.
    ///
    /// Not when ink is only shown — opened, or moved for a mode switch —
    /// since nothing needs saving then, and a save would bump the note up the
    /// list just for being looked at.
    var onInkChanged: ((PaperMarkup) -> Void)?

    private let pinch = UIPinchGestureRecognizer()
    private var zoomAtPinchStart: CGFloat = 1

    /// Which touches scroll the note on the canvas, for the mode. Set by
    /// `NoteEditor`; off the canvas, `offCanvas` applies instead.
    var scrolling = PageScrolling.standard {
        didSet {
            guard scrolling != oldValue else { return }
            for pan in pans {
                scrolling.apply(to: pan)
            }
        }
    }

    /// The pans that scroll the note: the text view's, up and down, and this
    /// view's, sideways when zoomed in.
    private var pans: [UIPanGestureRecognizer] {
        [textView.panGestureRecognizer]
    }

    init(textView: DocumentUITextView) {
        let layout = PageLayout()
        self.textView = textView
        self.canvas = DrawingCanvas(pageSize: CGSize(
            width: layout.pageSize.width,
            height: layout.noteHeight(pageCount: 1)
        ))
        let selection = InkSelection()
        self.selection = selection
        self.selectionOverlay = InkSelectionOverlay(selection: selection)
        self.inkState = InkCapture.State(ink: PaperMarkup(bounds: CGRect(
            origin: .zero,
            size: CGSize(
                width: layout.pageSize.width,
                height: PageLayout(orientation: layout.orientation, mode: .print).noteHeight(pageCount: 1)
            )
        )))
        super.init(frame: .zero)

        // Neither scroll view should invent insets of its own. SwiftUI keeps
        // this view clear of the safe area, but not of the keyboard: the page
        // area ignores that, so the page never resizes for it, and
        // `keyboardWillChangeFrame` insets the text view by what's covered.
        contentInsetAdjustmentBehavior = .never
        textView.contentInsetAdjustmentBehavior = .never

        isDirectionalLockEnabled = false
        alwaysBounceVertical = false
        showsVerticalScrollIndicator = false
        addSubview(pageEdge)
        addSubview(textView)
        adoptTextViewPan()

        // A Duo folding or unfolding changes the size class, and with it
        // whether the page is fitted by its text column.
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (view: PageView, _) in
            view.setNeedsLayout()
        }

        // The line width is set here, never inferred. Left tracking the view,
        // a text view whose width is first set while it is scaled below 1x
        // sizes its container from the shrunken frame, and portrait and
        // landscape broke lines differently. Caught by
        // PageViewTests.identicalLineBreaks.
        textView.textContainer.widthTracksTextView = false

        // A note is always whole pages tall.
        textView.contentHeightAdjustment = { [weak self] height in
            self?.noteHeight(forTextHeight: height) ?? height
        }

        decorations.isUserInteractionEnabled = false
        textView.insertSubview(decorations, at: 0)

        // Scrolling, transparency and who may draw are the canvas's own
        // business — see DrawingCanvas.
        canvas.onMarkupChanged = { [weak self] in self?.captureInk() }
        canvas.takesTouch = { [weak self] point in
            guard let self else { return true }
            return pageLayout.takesInk(at: point, pageCount: pageCount)
        }
        textView.addSubview(canvas)
        textView.insertSubview(covers, aboveSubview: canvas)
        selection.canvas = canvas
        selectionOverlay.takesTouch = canvas.takesTouch
        textView.insertSubview(selectionOverlay, aboveSubview: covers)

        pinch.addTarget(self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        applyPageLayout(replacing: nil)

        textView.addLayoutObserver { [weak self] in
            self?.textViewDidLayout()
        }

        // An edit lays its paragraph out again in a new view, at the screen's
        // density, with no layout pass of the text view to raise it: the line
        // being typed stayed soft until the caret moved to another line (on
        // the iPad, and measured on the simulator, 25 September). TextKit's
        // own layout of what's on screen covers edits too, and comes before
        // the frame is drawn.
        textView.addViewportLayoutObserver { [weak self] in
            guard let self, pinch.state != .changed else { return }
            matchRenderingScale()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )

#if DEBUG
        DebugSession.shared.attach(self)
#endif
    }

    // MARK: Keyboard

    /// The keyboard's last frame, in screen coordinates.
    private var keyboardFrame: CGRect?

    /// Brings a screen-coordinates frame into a window's. Replaceable because
    /// a window made outside a scene, as in a test, has no screen space to
    /// convert from and answers with a zero rect.
    var windowFrameForScreenFrame: (CGRect, UIWindow) -> CGRect = { frame, window in
        window.convert(frame, from: window.screen.coordinateSpace)
    }

    /// Room to leave above the keyboard, in screen points: the hotbar's, when
    /// it is docked at the bottom, since it rides up with the keyboard over
    /// the page.
    var keyboardClearance: CGFloat = 0 {
        didSet {
            guard keyboardClearance != oldValue else { return }
            applyKeyboardInset(duration: 0.25)
        }
    }

    /// Room the bottom of the text keeps from the area's edge, in screen
    /// points, for a hotbar floating over the bottom of the page: the end of
    /// the note can then be scrolled out from under it. The keyboard's inset
    /// already includes the bar's height, so the larger of the two applies,
    /// not their sum.
    var restingClearance: CGFloat = 0 {
        didSet {
            guard restingClearance != oldValue else { return }
            applyKeyboardInset(duration: 0.25)
        }
    }

    // MARK: Moving with the hotbar

    /// The space SwiftUI gives the page, as the edges it leaves: the strip a
    /// hotbar docked at a side takes. Only compared, to know the area is
    /// about to change: SwiftUI lays the area out.
    private(set) var areaInsets = UIEdgeInsets.zero

    /// The animation the next change of area moves the page with.
    private var areaMotion: Animation?

    /// Where the page was on screen after the last layout pass: the text
    /// view's centre in window coordinates, its scale and its size.
    private var lastPlaceOnScreen: (center: CGPoint, scale: CGFloat, size: CGSize)?

    /// The page's area is about to become `insets` less than the window, and
    /// the page should get there with `animation`.
    ///
    /// SwiftUI lays a UIKit view out where it ends up, at once: it resized
    /// this view, or moved a container above it, while the hotbar slid to its
    /// new edge with `.snappy`, so the page jumped. This is called before
    /// SwiftUI lays out the new area (logged, 17 Oct), and this view hears of
    /// a move only through here (a move without a resize lays nothing out),
    /// so it lays out again and animates the page from where it was on
    /// screen (`layoutSubviews`). Nothing under Reduce Motion.
    func areaWillChange(to insets: UIEdgeInsets, animation: Animation?) {
        guard insets != areaInsets else { return }
        areaInsets = insets
        guard let animation, !UIAccessibility.isReduceMotionEnabled, lastPlaceOnScreen != nil else { return }
        areaMotion = animation
        setNeedsLayout()
    }

    /// Puts the page back where it was on screen, at its old scale, and
    /// animates it to where this layout pass put it.
    ///
    /// The view stops clipping while it moves: the page starts partly outside
    /// its new area and slides in, which clipped would have lost a strip of
    /// it at once.
    private func movePage(from old: (center: CGPoint, scale: CGFloat, size: CGSize), with animation: Animation) {
        guard window != nil else { return }
        let start = convert(old.center, from: nil)
        let end = (transform: textView.transform, size: textView.bounds.size, center: textView.center)
        guard abs(start.x - end.center.x) > 0.5 || abs(start.y - end.center.y) > 0.5 || old.scale != displayScale
        else { return }

        UIView.performWithoutAnimation {
            textView.transform = CGAffineTransform(scaleX: old.scale, y: old.scale)
            textView.bounds.size = old.size
            textView.center = start
        }
        clipsToBounds = false
        UIView.animate(animation) {
            self.textView.transform = end.transform
            self.textView.bounds.size = end.size
            self.textView.center = end.center
        } completion: {
            self.clipsToBounds = true
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // A clearance set before the page had a window, as it is when made.
        if window != nil, restingClearance > 0 {
            applyKeyboardInset(duration: 0)
        }
    }

    /// Keeps the caret clear of the keyboard without resizing the page.
    ///
    /// Fires for showing, hiding, and the keyboard changing height (the
    /// shortcut bar, the emoji keyboard, undocking). The inset moves with the
    /// keyboard's own animation.
    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let end = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        keyboardFrame = end

        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curve = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? 7
        applyKeyboardInset(duration: duration, options: UIView.AnimationOptions(rawValue: UInt(curve) << 16))
    }

    /// Insets the text view for whatever of the page the keyboard covers.
    private func applyKeyboardInset(duration: TimeInterval, options: UIView.AnimationOptions = []) {
        guard let window else { return }

        var inset = displayScale > 0 ? restingClearance / displayScale : 0
        if let keyboardFrame {
            inset = max(inset, CanvasGeometry.keyboardInset(
                keyboard: windowFrameForScreenFrame(keyboardFrame, window),
                area: convert(bounds, to: window),
                screenWidth: window.bounds.width,
                displayScale: displayScale,
                clearance: keyboardClearance
            ))
        }
        guard textView.contentInset.bottom != inset else { return }
        let growing = inset > textView.contentInset.bottom

        UIView.animate(withDuration: duration, delay: 0, options: options.union(.beginFromCurrentState)) {
            self.textView.contentInset.bottom = inset
            self.textView.verticalScrollIndicatorInsets.bottom = inset
        }

        // A keyboard coming up over the line being typed on: bring it back
        // into view, as a text view that insets itself would.
        if growing, textView.isFirstResponder {
            textView.scrollRangeToVisible(textView.selectedRange)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        let area = bounds.size
        guard area.width > 0, area.height > 0 else { return }

        let motion = areaMotion
        areaMotion = nil
        let before = lastPlaceOnScreen

        let scale = CanvasGeometry.displayScale(
            areaWidth: area.width,
            pageWidth: pageLayout.pageSize.width,
            columnWidth: columnWidth,
            zoom: zoom,
            gutter: CanvasGeometry.gutter(for: pageLayout.mode)
        )
        let refitted = scale != displayScale || area.width != fittedWidth
        apply(scale: scale)

        // Fitted to its text column, the page is wider than the area: show
        // the column, with the margins cut evenly either side, rather than
        // the left margin and the column's start. Only when the fit itself
        // changes (opening, rotating, a narrower window), never under a
        // reader who has panned or zoomed.
        if refitted, zoom == 1 {
            fittedWidth = area.width
            contentOffset.x = CanvasGeometry.centredOffset(
                areaWidth: area.width, pageWidth: pageLayout.pageSize.width, scale: scale
            )
        }

        if let motion, let before {
            movePage(from: before, with: motion)
        }
        if window != nil {
            lastPlaceOnScreen = (convert(textView.center, to: nil), displayScale, textView.bounds.size)
        }
    }

    /// The text column, offered for fitting in a compact width only: an
    /// iPhone, a folded Duo, a narrow Split View (`CanvasGeometry.fitScale`).
    private var columnWidth: CGFloat? {
        guard traitCollection.horizontalSizeClass == .compact else { return nil }
        return CanvasGeometry.columnWidth(textWidth: pageLayout.textWidth)
    }

    /// Draws the page at `scale` in the current area.
    private func apply(scale: CGFloat) {
        let area = bounds.size
        let pageWidth = pageLayout.pageSize.width
        let frame = CanvasGeometry.pageFrame(in: area, pageWidth: pageWidth, scale: scale)
        let pageSize = CanvasGeometry.pageBounds(in: area, pageWidth: pageWidth, scale: scale)

        let scaleChanged = displayScale != scale
        displayScale = scale
        if scaleChanged, restingClearance > 0 {
            applyKeyboardInset(duration: 0)
        }
        if textView.transform.a != scale {
            textView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }

        // Size only, never origin: a scroll view's bounds origin is its scroll
        // position, and that is in page points, so it survives a scale change
        // untouched. The line at the top stays at the top through a rotation.
        if textView.bounds.size != pageSize {
            textView.bounds.size = pageSize
            pinLineWidth()
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        if textView.center != center {
            textView.center = center
        }
        paintPage()
        pageEdge.isHidden = pageLayout.mode == .print
        if pageEdge.frame != textView.frame {
            pageEdge.frame = textView.frame
        }

        let content = CGSize(width: max(area.width, frame.width), height: area.height)
        if contentSize != content {
            contentSize = content
        }

        // Re-rendering every line on every frame of a pinch would stutter.
        // The pinch's end catches up.
        if pinch.state != .changed {
            matchRenderingScale()
        }
    }

    /// Paints the page against its surround.
    ///
    /// The page has no border and square corners (16 Oct, roadmap step 5): it
    /// fills its window, and the colours alone say where it ends.
    private func paintPage() {
        let continuous = pageLayout.mode != .print

        // The page against its surround, in every mode. The view itself is
        // the surround: it shows beside the page, and in print layout between
        // the sheets. The continuous modes' page is a column the text view's
        // width, so the text view paints it — under the text, the break
        // decorations and the canvas, which are all its subviews. Print
        // layout's text view stays clear, since its sheets carry
        // the page colour and the surround must show between them. Set by
        // mode, not once, so a switch can't leave the column behind.
        backgroundColor = Self.surroundColor
        let fill = continuous ? Self.pageColor : UIColor.clear
        if textView.backgroundColor != fill {
            textView.backgroundColor = fill
        }
    }

    /// Sets the text container to the pages' text width.
    private func pinLineWidth() {
        let width = pageLayout.textWidth
        if textView.textContainer.size.width != width {
            textView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        }
    }

    /// Runs after every layout pass of the text view, which includes every
    /// scroll, but not every edit.
    private func textViewDidLayout() {
#if DEBUG
        defer { DebugSession.shared.pageDidLayout(self) }
#endif
        updatePageFurniture()
        if pinch.state != .changed {
            matchRenderingScale()
        }
        if let reveal = pendingReveal, textView.bounds.height > 0 {
            pendingReveal = nil
            // After this layout pass rather than inside it.
            DispatchQueue.main.async { [weak self] in self?.show(reveal) }
        }
        if let index = pendingRestore, !restoreScheduled, pendingReveal == nil, textView.bounds.height > 0 {
            restoreScheduled = true
            DispatchQueue.main.async { [weak self] in self?.finishRestore(toPage: index) }
        }
        reportReadingPlace()
        reportScroll()
    }

    /// Tells `onScrolled` the note has moved. Not while it is opening at a
    /// place, which is the app positioning the note rather than the reader.
    private func reportScroll() {
        let offset = textView.contentOffset.y
        defer { lastScrolledOffset = offset }
        guard let onScrolled, abs(offset - lastScrolledOffset) > 0.5,
              pendingRestore == nil, pendingReveal == nil, textView.bounds.height > 0
        else { return }
        let place = readingPlace
        // After this layout pass: the callback changes SwiftUI state, and a
        // pass can be inside a SwiftUI update.
        DispatchQueue.main.async { onScrolled(place) }
    }

    // MARK: Reopening where the reader left off

    /// Opens the note at the top of page `index` (counted from 0) once it has
    /// laid out, the way `reveal` waits for it. A search's match wins if
    /// both are asked for.
    func restore(toPage index: Int) {
        pendingRestore = index > 0 ? index : nil
    }

    private func finishRestore(toPage index: Int) {
        let layout = pageLayout
        // Lay the text out down to the page the way scrolling there by hand
        // would, so the page count is the note's rather than an estimate from
        // the little that is laid out, and the page's first line is placed
        // below every break above it. Not the whole note: what's below can
        // wait for the reader to get there.
        textView.textLayoutManager?.ensureLayout(for: CGRect(
            x: 0,
            y: 0,
            width: layout.textWidth,
            height: layout.scrollTop(forPage: index) + textView.bounds.height
        ))
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        // A note shortened since lands on its last page.
        let landing = min(index, max(pageCount - 1, 0))
        textView.contentOffset.y = clampedOffset(layout.scrollTop(forPage: landing))

        pendingRestore = nil
        restoreScheduled = false
        reportReadingPlace()
    }

    /// The page at the top of the view, and how many pages the note has.
    ///
    /// By the top edge, a point inside it: exactly on a page's scroll-top the
    /// edge is the middle of a band, and rounding there could name the page
    /// before.
    var readingPlace: NoteMemory.Place {
        let index = pageLayout.pageIndex(atY: textView.contentOffset.y + 1)
        return NoteMemory.Place(page: min(index, max(pageCount - 1, 0)), of: max(pageCount, 1))
    }

    private func reportReadingPlace() {
        guard let onReadingPlaceChanged, pendingRestore == nil, pendingReveal == nil,
              textView.bounds.height > 0
        else { return }
        let place = readingPlace
        guard place != lastReportedPlace else { return }
        lastReportedPlace = place
        onReadingPlaceChanged(place)
    }

    // MARK: Search

    /// Shows a search result once the note is laid out: scrolled so the
    /// first match sits near the top, and every match highlighted until the
    /// text changes.
    func reveal(_ first: NSRange, highlighting all: [NSRange]) {
        pendingReveal = (first, all)
    }

    /// Lays the text out down to `character`, the way scrolling there by hand
    /// would, so its line is placed below every page break above it. Not the
    /// whole note: what's below can wait for the reader to get there.
    /// Whether there was anywhere to lay out to.
    @discardableResult
    private func layOut(downTo character: Int) -> Bool {
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager,
              let target = content.location(content.documentRange.location, offsetBy: character),
              let above = NSTextRange(location: content.documentRange.location, end: target)
        else { return false }
        manager.ensureLayout(for: above)
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        return true
    }

    private func show(_ reveal: (first: NSRange, all: [NSRange])) {
        guard layOut(downTo: reveal.first.location) else { return }

        if let top = lineTop(atCharacter: reveal.first.location) {
            // A quarter of the way down, so the lines leading up to the match
            // show too.
            textView.contentOffset.y = clampedOffset(top - textView.bounds.height / 4)
        }
        textView.highlightSearchMatches(reveal.all, current: reveal.first)
    }

    // MARK: Outline

    /// Scrolls so the line holding `character` is the first the reader sees:
    /// the outline's tap, which goes where a search result does (lay out
    /// down to it, then scroll) but puts the line at the top rather than a
    /// quarter of the way down. A page's first line shows that page from its
    /// top edge, the rule a mode switch keeps; and a line too near the end
    /// to reach the top lands as far up as the note scrolls.
    func scroll(toLineAt character: Int) {
        guard layOut(downTo: character) else { return }
        settleOffset(onLineAt: character)
    }

    /// Puts the offset where `character`'s line starts the view, set again
    /// while it moves: the page count, and so the bands, can still change as
    /// the text settles, which shifts everything below them.
    private func settleOffset(onLineAt character: Int) {
        for _ in 0..<4 {
            guard let top = lineTop(atCharacter: character) else { return }
            let index = pageLayout.pageIndex(atY: top)
            let startsPage = top - pageLayout.bodyTop(ofPage: index) < 1
            let target = clampedOffset(startsPage ? pageLayout.scrollTop(forPage: index) : pixelCeiling(top))
            if abs(textView.contentOffset.y - target) < 0.5 { return }
            textView.contentOffset.y = target
            textView.layoutIfNeeded()
        }
    }

    /// `y` rounded up to a whole pixel. A scroll offset snaps to the screen's
    /// pixels, and one that snaps down from a line's top leaves the line above
    /// showing by a fraction of a point, which is then the first line the
    /// reader sees (a size change landed one line early, and a test of the
    /// line at the top caught it).
    private func pixelCeiling(_ y: CGFloat) -> CGFloat {
        let scale = max(textView.traitCollection.displayScale, 1)
        return (y * scale).rounded(.up) / scale
    }

    // MARK: Re-wrapping

    /// Runs a change that re-wraps the text (a new text size), and puts the
    /// reader back on the line they were reading.
    ///
    /// A re-wrap moves every line, and no scroll offset converts across it,
    /// so the line at the top is kept instead, as for a new orientation (see
    /// `applyPageLayout`). The same two precautions: the page count comes out
    /// right before the bands it sets (the count is worked out from the text
    /// as TextKit sets its height, here the new layout's), and TextKit is
    /// re-anchored at the top of the note before going back, or it keeps
    /// the old layout's viewport and the lines on screen sit a stale
    /// break's worth off.
    func reflow(_ change: () -> Void) {
        let anchor = topLineCharacter()
        change()

        setNeedsLayout()
        layoutIfNeeded()
        textView.layoutIfNeeded()
        textView.contentOffset.y = 0
        setNeedsLayout()
        layoutIfNeeded()
        textView.layoutIfNeeded()

        guard let anchor, anchor > 0 else {
            textView.contentOffset.y = clampedOffset(0)
            return
        }
        layOut(downTo: anchor)
        settleOffset(onLineAt: anchor)
    }

    // MARK: Pages

    /// Puts a layout's margins, bands and decorations in place.
    ///
    /// - Parameter old: the layout being replaced, or `nil` when first set.
    private func applyPageLayout(replacing old: PageLayout?) {
        // Where the reader is, taken before anything moves. Within one
        // orientation every mode paginates the same, so this converts by
        // page. A new orientation re-wraps the text and no position converts,
        // so there the line at the top is kept instead.
        let offset = textView.contentOffset.y
        let anchor = old.map { $0.orientation != pageLayout.orientation } == true ? topLineCharacter() : nil
        let oldTextBottom = textView.textContentHeight - textView.textContainerInset.bottom

        if old != nil {
            showInk()
        }

        // The bottom inset is the space after the last page's body. The note's
        // height is rounded to whole pages separately, in the content height,
        // so this never has to be worked out from the text.
        textView.textContainerInset = UIEdgeInsets(
            top: pageLayout.firstBodyTop,
            left: PageLayout.margin,
            bottom: pageLayout.trailingSpace,
            right: PageLayout.margin
        )
        pinLineWidth()

        // The page count, before the bands that depend on it.
        //
        // The text's height is still the old layout's until TextKit lays it
        // out again, and read against the new layout it gave the wrong count:
        // switching a nine-page note from print layout to seamless counted
        // eleven pages, then nine, ten, nine, as the text reflowed. Every
        // change reassigned the bands, which relays out the whole note, and
        // TextKit shifted the scroll offset each time — the reader landed a
        // line and a half into the page. Within one orientation every mode
        // puts the same lines on the same pages, so the old text bottom
        // converts exactly, and the count is right the first time.
        let newLayout = pageLayout
        textView.reapplyContentHeightAdjustment(converting: { [textView] height in
            guard let old, let bottom = old.convert(y: oldTextBottom, to: newLayout) else { return height }
            return bottom + textView.textContainerInset.bottom
        })
        applyBands()
        paintPage()

        guard old != nil else { return }

        // Re-anchor TextKit at the top of the note before going back to the
        // reader's place.
        //
        // TextKit 2 lays text out relative to what the viewport showed last.
        // After the bands change under a viewport deep in a note, it kept that
        // anchor: every line on screen sat 167pt below its true position —
        // exactly print layout's 168pt break less seamless's 1pt, one stale
        // break's worth — and lines ran across seamless's page breaks. The
        // reader saw the previous page's last lines where the page began.
        // Invalidating the layout, a full ensureLayout, and relaying out the
        // viewport all left it there; only scrolling to the top and back
        // cleared it (ZZ probe, 13 Sep). At the top of a note nothing is above
        // the viewport to be stale, so the jump back lays out fresh. It all
        // happens before the next frame is drawn, so nothing flickers.
        textView.contentOffset.y = 0

        // The text reflows against new bands, so lay it out before restoring
        // the reader's place in it.
        setNeedsLayout()
        layoutIfNeeded()
        textView.layoutIfNeeded()

        let target: CGFloat
        if let old, old.orientation == pageLayout.orientation {
            let index = old.pageIndex(atY: offset)
            let intoBody = offset - old.bodyTop(ofPage: index)
            // At or above a page's first line — in its margin, or the break
            // before it — means the page itself: show it from its top edge,
            // and the note from its very top.
            target = intoBody <= 0.5
                ? pageLayout.scrollTop(forPage: index)
                : pageLayout.bodyTop(ofPage: index) + min(intoBody, pageLayout.bodyHeight)
        } else if let anchor, let top = lineTop(atCharacter: anchor) {
            // A page's first line means the page itself, the same rule as a
            // mode switch — and the note's first line means its very top.
            // Keeping the line itself at the top instead opened every note
            // with landscape pages 36pt down, its top margin out of view:
            // PageView starts with default portrait pages, so taking the
            // note's own on opening runs through here.
            let index = pageLayout.pageIndex(atY: top)
            let startsPage = top - pageLayout.bodyTop(ofPage: index) < 1
            target = startsPage ? pageLayout.scrollTop(forPage: index) : top
        } else {
            textView.contentOffset.y = clampedOffset(textView.contentOffset.y)
            return
        }

        // Within one orientation the page count is right from the start, so
        // nothing reassigns the bands after this and the first set sticks.
        // Across orientations the text re-wraps and the count can still move
        // while it settles, which relays out the note and shifts the offset,
        // so set it again if a pass moved it.
        for _ in 0..<3 {
            let clamped = clampedOffset(target)
            if abs(textView.contentOffset.y - clamped) < 0.5 { break }
            textView.contentOffset.y = clamped
            textView.layoutIfNeeded()
        }
    }

    /// A vertical scroll offset kept within the note.
    private func clampedOffset(_ y: CGFloat) -> CGFloat {
        min(max(y, 0), max(textView.contentSize.height - textView.bounds.height, 0))
    }

    /// The character that starts the first line reaching below the top of
    /// the view — the line the reader is looking at.
    ///
    /// With the top edge in a margin or a page break, that's the next page's
    /// first line, which is what someone scrolled to a sheet's top is reading.
    /// Internal rather than private for `DebugStateReport`.
    func topLineCharacter() -> Int? {
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager
        else { return nil }

        let edge = textView.contentOffset.y - textView.textContainerInset.top
        let documentStart = content.documentRange.location
        let from = manager.textViewportLayoutController.viewportRange?.location ?? documentStart

        var found: Int?
        manager.enumerateTextLayoutFragments(from: from, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard let line = fragment.textLineFragments.first(where: { frame.minY + $0.typographicBounds.maxY > edge }) else {
                return true
            }
            found = content.offset(from: documentStart, to: fragment.rangeInElement.location) + line.characterRange.location
            return false
        }
        return found
    }

    /// The top of the line holding `character`, in note coordinates.
    func lineTop(atCharacter character: Int) -> CGFloat? {
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: character),
              let fragment = manager.textLayoutFragment(for: location)
        else { return nil }

        let within = character - content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let line = fragment.textLineFragments.first { NSLocationInRange(within, $0.characterRange) }
            ?? fragment.textLineFragments.first
        guard let line else { return nil }
        return fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + textView.textContainerInset.top
    }

    /// Sets the bands text flows around, one after each page.
    private func applyBands() {
        bandedPageCount = pageCount
        textView.textContainer.exclusionPaths = pageLayout
            .exclusionBands(pageCount: pageCount, containerTop: textView.textContainerInset.top)
            .map { UIBezierPath(rect: $0) }
    }

    /// The note's height for text TextKit says is `height` tall: enough whole
    /// pages for the text and the ink.
    ///
    /// Idempotent. Fed its own answer back — as happens if anything sets the
    /// content size from the content size — the text's bottom lands at the end
    /// of the last page's body, which gives the same page count again.
    private func noteHeight(forTextHeight height: CGFloat) -> CGFloat {
        let textBottom = height - textView.textContainerInset.bottom
        pageCount = pageLayout.pageCount(textBottom: textBottom, inkBottom: inkBottom, minimum: minimumPageCount)
        return pageLayout.noteHeight(pageCount: pageCount)
    }

    /// One more page at the end of the note, for ink or text to go on.
    func addPage() {
        raiseMinimum(to: pageCount + 1)
    }

    /// Seamless has no page ends to see, so a note keeps a blank page below
    /// its ink: when ink reaches the last page, there is one more. Compressed
    /// and print layout show their pages, and have Add Page.
    private func keepPageBelowInk() {
        guard pageLayout.mode == .seamless, let inkBottom,
              pageLayout.pageIndex(atY: inkBottom) >= pageCount - 1
        else { return }
        raiseMinimum(to: pageCount + 1)
    }

    private func raiseMinimum(to count: Int) {
        guard count > minimumPageCount else { return }
        minimumPageCount = count
        onMinimumPageCountChanged?(count)
    }

    /// Brings the bands, canvas and decorations up to the page count.
    ///
    /// A line pushed past the last page's band makes one more page; its band
    /// only affects text below it, so this converges. Reassigning exclusion
    /// paths relays out the text, so only when the count has changed.
    private func updatePageFurniture() {
        if bandedPageCount != pageCount {
            applyBands()
        }

        let noteHeight = pageLayout.noteHeight(pageCount: pageCount)
        canvas.noteSize = CGSize(width: pageLayout.pageSize.width, height: noteHeight)
        let visible = Self.visiblePart(
            ofNoteHeight: noteHeight,
            width: pageLayout.pageSize.width,
            scrolledTo: textView.contentOffset.y,
            viewHeight: textView.bounds.height
        )
        canvas.cover(visible)
        selectionOverlay.cover(visible)
        selection.regions = pageLayout.inkRegions(pageCount: pageCount)
        decorations.update(layout: pageLayout, pageCount: pageCount, height: noteHeight)
        covers.update(layout: pageLayout, pageCount: pageCount, height: noteHeight)
    }

    /// The part of the note on screen, which is all the canvas covers.
    ///
    /// Kept within the note, so a bounce past either end doesn't carry the
    /// canvas off it: the ink there has nothing to draw anyway.
    static func visiblePart(ofNoteHeight noteHeight: CGFloat, width: CGFloat, scrolledTo offset: CGFloat, viewHeight: CGFloat) -> CGRect {
        let height = min(max(viewHeight, 0), noteHeight)
        let top = min(max(offset, 0), noteHeight - height)
        return CGRect(x: 0, y: top, width: width, height: height)
    }

    // MARK: Ink

    /// Replaces the note's ink.
    ///
    /// - Parameter drawing: strokes in print layout's coordinates, for this
    ///   note's orientation — the form ink is stored and printed in.
    func setInk(_ markup: PaperMarkup) {
        // Whatever was on its way in belonged to the ink this replaces.
        newestSnapshot = nil
        inkState = InkCapture.State(ink: markup)
        showInk()
    }

    /// Puts the ink on the canvas, converted to the current mode.
    ///
    /// Strokes drawn on the canvas are converted the other way as they arrive,
    /// each on its own page, rather than by converting the whole canvas back —
    /// that round trip is what `ink` exists to avoid.
    private func showInk() {
        // Strokes still on their way in were drawn in the layout the canvas
        // shows until now, and are taken in by it before anything moves.
        commitInk()
        inkGeneration += 1

        let ink = inkState.ink
        let print = PageLayout(orientation: pageLayout.orientation, mode: .print)
        // Compressed and print layout show a stroke across a border only on
        // the page it was started on (`InkPages`); seamless shows it whole.
        let hidesOverflow = pageLayout.mode != .seamless
        var shown = canvas.markup

        if shown.subelements.isEmpty {
            // Nothing on the canvas to reconcile with: hand it the stored ink,
            // converted, in one go.
            let visible = hidesOverflow ? PageView.withoutOverflow(ink) : ink
            canvas.markup = PageView.convert(visible, from: print, to: pageLayout) ?? visible
        } else {
            // The canvas has its own copy of these elements, and a markup
            // *merges* what it is given rather than replacing it. A copy made
            // from `ink` branched before the canvas's own edits, so assigning
            // it changes nothing — measured on 19 September, when ink stayed
            // where it was drawn through every mode. Moving the canvas's own
            // elements, by the distance its stored copy says, is what takes.
            // Walked with `for`, never `map`: see `frames(of:)`.
            var stored: [MarkupOrderedSet.ElementID: any Markup] = [:]
            for element in ink.subelements where !(hidesOverflow && InkPages.isOverflow(element)) {
                stored[element.elementID] = element
            }

            // A stroke the canvas holds whole but the ink holds cut changes
            // shape, and one shown with specks has a frame that isn't its
            // piece's: each leaves the canvas and comes back as stored,
            // below. A changed copy assigned over the canvas's own doesn't
            // take, and nor does a new one with its id while the old one is
            // there. Ink undo is cleared here anyway, so nothing loses track.
            // Added and placed a set at a time, never an element at a time:
            // see `convert`. Removed one at a time, which is few: a set
            // without them keeps them, and so does `removeAll(where:)`.
            let reshaped = inkState.wholeOnCanvas.union(inkState.specked).filter { stored[$0] != nil }
            for id in Set(shown.subelements.ids) where stored[id] == nil || reshaped.contains(id) {
                shown.subelements.removeElement(for: id)
            }
            let onCanvas = Set(shown.subelements.ids)
            var arriving: [any Markup] = []
            for (id, element) in stored where !onCanvas.contains(id) && !reshaped.contains(id) {
                arriving.append(element)
            }
            if !arriving.isEmpty {
                shown.subelements.append(contentsOf: arriving)
            }

            // Pieces that just replaced a stroke arrive at the end, so they
            // draw above strokes made after it until the note is reopened,
            // which shows the stored order. Assigning the set in the stored
            // order doesn't reorder the canvas (unit test, 9 October).
            var elements: [any Markup] = []
            for element in shown.subelements {
                guard let original = stored[element.elementID] else { continue }
                let target = print.convert(y: original.renderFrame.midY, to: pageLayout)
                    ?? original.renderFrame.midY
                var element = element
                let delta = target - element.renderFrame.midY
                if abs(delta) > 0.001 {
                    element.applyTransform(CGAffineTransform(translationX: 0, y: delta))
                }
                elements.append(element)
            }
            var placed = MarkupOrderedSet()
            placed.append(contentsOf: elements)
            shown.subelements = placed
            canvas.markup = shown

            if !reshaped.isEmpty {
                var returned = canvas.markup
                for id in reshaped {
                    guard let element = stored[id] else { continue }
                    let placed = InkCapture.moved(element, from: print, to: pageLayout)
                    returned.subelements.append((placed as? PKStroke).map(InkPages.redrawn) ?? placed)
                }
                canvas.markup = returned
            }
        }

        // Ink just moved under whatever the undo stack was holding: its
        // actions restore strokes to the mode they were drawn in.
        canvas.forgetUndo()
        // Ids and the box belong to the layout that is gone.
        selection.clear()

        // The canvas holds exactly the stored elements this mode shows now,
        // pieces included, and nothing is left to undo.
        let (frames, contents) = PageView.frames(of: canvas.markup)
        inkState.shown = frames
        inkState.contents = contents
        inkState.wholeOnCanvas = []
        inkState.specked = []
        inkState.buried = [:]
        inkBottom = frames.values.map(\.maxY).max()
        // The page count depends on the ink, and nothing about the text changed.
        textView.reapplyContentHeightAdjustment()
        textView.setNeedsLayout()
    }

    /// Runs one of PaperKit's inserts so what it adds lands on the page the
    /// reader is looking at: see `InkInsertion.centre`.
    ///
    /// The insert tells the canvas's delegate, so it is captured, saved and
    /// undone like any other change the reader makes.
    func insertIntoInk(extent: CGSize, _ insert: () -> Void) {
        let centre = InkInsertion.centre(
            in: canvas.coveredPart,
            regions: pageLayout.inkRegions(pageCount: pageCount),
            extent: extent
        )
        canvas.inserting(around: centre, insert)
    }

    /// The tallest a photo is first shown: a share of what is on screen, and
    /// of a page's body, so it fits one page.
    var insertionMaxHeight: CGFloat {
        min(canvas.coveredPart.height, pageLayout.bodyHeight) * InkInsertion.photoWidthShare
    }

    /// Hands touches to the Select tool's overlay, or back to the canvas.
    func setSelecting(_ selecting: Bool, allowsFingers: Bool) {
        selectionOverlay.allowsFingers = allowsFingers
        selectionOverlay.isActive = selecting
    }

    /// Takes what the reader just drew, erased or moved into the stored ink,
    /// off the main thread (`InkCapture`).
    ///
    /// PaperKit says only that the markup changed, so what changed is found
    /// by walking all of it, and every operation on PaperKit's sets costs
    /// time in proportion to the ink: at 5,000 strokes this was 400ms on the
    /// main thread per stroke even walked properly (simulator, 10 October).
    /// Here the main thread only takes a snapshot, which costs nothing
    /// measurable. A burst of strokes is taken in as one: while a capture
    /// runs, only the newest snapshot waits.
    private func captureInk() {
        snapshotSerial += 1
        newestSnapshot = InkSnapshot(
            markup: canvas.markup,
            layout: pageLayout,
            pageCount: pageCount,
            serial: snapshotSerial
        )
        startCapture()
    }

    private func startCapture() {
        guard !isCapturing, let snapshot = newestSnapshot else { return }
        isCapturing = true
        let state = inkState
        let generation = inkGeneration
        let (markup, layout, pageCount) = (snapshot.markup, snapshot.layout, snapshot.pageCount)
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                InkCapture.capture(markup, into: state, layout: layout, pageCount: pageCount)
            }.value
            guard let self else { return }
            isCapturing = false
            if generation == inkGeneration {
                if newestSnapshot?.serial == snapshot.serial {
                    newestSnapshot = nil
                }
                apply(result)
            }
            startCapture()
        }
    }

    /// Takes in, now and on the main thread, whatever the reader drew that is
    /// still on its way: before ink is shown again, read, printed or saved
    /// for the app leaving the screen.
    func commitInk() {
        guard let snapshot = newestSnapshot else { return }
        newestSnapshot = nil
        // A capture still running started from the state this replaces.
        inkGeneration += 1
        apply(InkCapture.capture(snapshot.markup, into: inkState, layout: snapshot.layout, pageCount: snapshot.pageCount))
    }

    private func apply(_ result: InkCapture.Result) {
        inkState = result.state
        guard result.changed else { return }
        onInkChanged?(result.state.ink)

        let before = inkBottom
        inkBottom = result.inkBottom
        if !result.reshow.isEmpty {
            showOwnPieces(result.reshow)
        }
        // Ink below the last line makes the note longer, and nothing about
        // the text changed to trigger that on its own. Only a page's worth
        // can change the count, and a layout pass on every stroke cost 8ms.
        let page = { (bottom: CGFloat?) in bottom.map(self.pageLayout.pageIndex(atY:)) }
        if page(before) != page(inkBottom) {
            textView.reapplyContentHeightAdjustment()
            textView.setNeedsLayout()
        }
        keepPageBelowInk()
        growPageForStroke(endingAt: result.drawnEnds)
    }

    /// A stroke the reader just drew that ends in the last page's foot adds a
    /// page, as Add Page does (`raiseMinimum`), so they can go on writing.
    ///
    /// Only strokes drawn now count (`InkCapture.Result.drawnEnds`): not ink
    /// that was loaded, moved by the lasso or shown again for a mode switch.
    /// It runs after the stroke has been taken in and told onward, and the
    /// page it adds is the note's minimum, not ink: nothing here calls
    /// `onInkChanged`, so growing never saves ink of its own. Seamless adds
    /// its page from `keepPageBelowInk` as soon as ink reaches the last page.
    private func growPageForStroke(endingAt ends: [CGPoint]) {
        guard addsPagesWhileDrawing, pageLayout.mode != .seamless else { return }
        let last = pageCount
        guard ends.contains(where: { pageLayout.endsInGrowthBand(y: $0.y, pageCount: last) }) else { return }
        raiseMinimum(to: last + 1)
    }

    /// Swaps strokes the canvas holds whole for the piece on the page each
    /// was started on, keeping their ids: in compressed and print layout, a
    /// stroke drawn across a border stops at it once the pen lifts.
    ///
    /// The id is kept so PaperKit's undo still finds the stroke, and
    /// assigning the canvas registers no undo of its own (probe, 10
    /// October). Taken off and put back, since a changed copy assigned over
    /// the canvas's own doesn't take, and with a new path (`InkPages.redrawn`),
    /// or PencilKit goes on drawing it whole.
    private func showOwnPieces(_ pieces: [PKStroke]) {
        var markup = canvas.markup
        for piece in pieces {
            let whole = inkState.shown[piece.elementID] ?? piece.renderFrame
            markup.subelements.updateOrAppend(InkPages.shown(piece, over: whole))
        }
        canvas.markup = markup

        // Where PaperKit has them now, which may be rounded from theirs.
        let now = canvas.markup.subelements
        for piece in pieces {
            inkState.shown[piece.elementID] = now[piece.elementID]?.renderFrame
            inkState.specked.insert(piece.elementID)
        }
        inkBottom = inkState.shown.values.map(\.maxY).max()
        // A snapshot waiting to be taken in was taken before this.
        if var waiting = newestSnapshot {
            waiting.markup = canvas.markup
            newestSnapshot = waiting
        }
    }

    /// Where each element sits, by id.
    ///
    /// Walked with `for`, which uses the set's own iterator. `map` reads
    /// `MarkupOrderedSet` by index, and reading one element by index costs
    /// as much as `count` does, which grows with the set: this took 808ms
    /// for a note of 500 strokes and 10.6s for 2,000 (simulator, 10
    /// October), after every stroke, and drawing stalled. With `for` it
    /// takes 4.7ms at 500.
    ///
    /// With each shape, text box and image's `InkContent` fingerprint, taken
    /// in the same walk.
    private static func frames(of markup: PaperMarkup) -> (frames: [MarkupOrderedSet.ElementID: CGRect], contents: [MarkupOrderedSet.ElementID: Int]) {
        var frames: [MarkupOrderedSet.ElementID: CGRect] = [:]
        var contents: [MarkupOrderedSet.ElementID: Int] = [:]
        for element in markup.subelements {
            frames[element.elementID] = element.renderFrame
            if let fingerprint = InkContent.fingerprint(of: element) {
                contents[element.elementID] = fingerprint
            }
        }
        return (frames, contents)
    }

    /// `markup` without the overflow of strokes drawn across a page break,
    /// for compressed and print layout. Taken out one by one: leaving an
    /// element out of an assigned set keeps it.
    static func withoutOverflow(_ markup: PaperMarkup) -> PaperMarkup {
        var overflow: [MarkupOrderedSet.ElementID] = []
        for element in markup.subelements where InkPages.isOverflow(element) {
            overflow.append(element.elementID)
        }
        guard !overflow.isEmpty else { return markup }
        var result = markup
        for id in overflow {
            result.subelements.removeElement(for: id)
        }
        return result
    }

    /// The ink with every element moved to the same place on its page in
    /// another layout, or `nil` when there's no such place — a different
    /// orientation wraps text at another width.
    ///
    /// Built as an array, appended to a new set in one go, and assigned once.
    /// Moving elements one at a time through `updateOrAppend` cost 3.3s for a
    /// thousand strokes (19 September). Appending them one at a time costs
    /// what the set's `count` does for each, which grows with it: a note of
    /// 5,000 strokes took 7 seconds to open. One `append(contentsOf:)` took
    /// 51ms (simulator, 10 October).
    static func convert(_ markup: PaperMarkup, from old: PageLayout, to new: PageLayout) -> PaperMarkup? {
        guard old.orientation == new.orientation else { return nil }
        guard old != new else { return markup }

        var elements: [any Markup] = []
        for element in markup.subelements {
            elements.append(InkCapture.moved(element, from: old, to: new))
        }
        var moved = MarkupOrderedSet()
        moved.append(contentsOf: elements)

        var result = markup
        result.subelements = moved
        return result
    }

    // MARK: Zoom

    /// Zooms to `newZoom`, keeping what's under `focus` under it.
    ///
    /// - Parameter focus: a point in this view's visible area, in screen
    ///   points from its top left.
    func setZoom(_ newZoom: CGFloat, about focus: CGPoint) {
        let area = bounds.size
        guard area.width > 0, area.height > 0 else { return }

        let clamped = CanvasGeometry.clampedZoom(newZoom)
        let pageWidth = pageLayout.pageSize.width
        let next = CanvasGeometry.zoom(
            CanvasGeometry.Viewport(
                scale: displayScale,
                horizontalOffset: contentOffset.x,
                verticalOffset: textView.contentOffset.y
            ),
            to: CanvasGeometry.displayScale(
                areaWidth: area.width,
                pageWidth: pageWidth,
                columnWidth: columnWidth,
                zoom: clamped,
                gutter: CanvasGeometry.gutter(for: pageLayout.mode)
            ),
            about: focus,
            area: area,
            pageWidth: pageWidth,
            noteHeight: textView.contentSize.height
        )

        zoom = clamped
        apply(scale: next.scale)
        contentOffset.x = next.horizontalOffset
        textView.contentOffset.y = next.verticalOffset
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            zoomAtPinchStart = zoom
            // Two fingers moving apart also look like a scroll. Stop both
            // scroll views taking a share of the gesture while it zooms.
            setPanning(enabled: false)
        case .changed:
            let location = gesture.location(in: self)
            let focus = CGPoint(x: location.x - contentOffset.x, y: location.y - contentOffset.y)
            setZoom(zoomAtPinchStart * gesture.scale, about: focus)
        case .ended, .cancelled, .failed:
            setPanning(enabled: true)
            matchRenderingScale()
        default:
            break
        }
    }

    // MARK: Touches

    /// Sends a touch beside the page to the text view, and sets how many
    /// fingers a scroll from there needs.
    ///
    /// Beside the page is this view's own space, and this view scrolls only
    /// sideways, so a drag there moved nothing — in either mode. Handed to
    /// the text view, it scrolls the note; the pinch, on this view, still
    /// sees it.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let found = super.hitTest(point, with: event)
        guard event?.type != .hover else { return found }
        let hit = found === self ? textView : found
        if event?.type == .touches {
            touchWillLand(on: hit)
        }
        return hit
    }

    /// Picks the scroll rule for a touch that lands on `view`.
    ///
    /// One finger scrolls wherever the canvas takes no touch, and the mode's
    /// rule applies on it. Decided as the first finger lands, before any pan
    /// has a touch: a second finger joins whatever gesture the first began.
    func touchWillLand(on view: UIView?) {
        guard pans.allSatisfy({ $0.numberOfTouches == 0 }) else { return }
        let onCanvas = (view?.isDescendant(of: canvas) ?? false) || (view?.isDescendant(of: selectionOverlay) ?? false)
        let rule = onCanvas ? scrolling : scrolling.offCanvas
        for pan in pans {
            rule.apply(to: pan)
        }
    }

    // MARK: One pan for the page (W2)

    /// The text view's pan lives on this view, so a drag anywhere on it,
    /// beside the page included, scrolls the note, and the same pan drives
    /// the sideways offset: zoomed in, one drag moves the page diagonally.
    /// This view's own pan is switched off for good; the text view still
    /// scrolls itself, so the viewport, the transform and the canvas geometry
    /// are as they were (docs/design/who-owns-scrolling.md › W2).
    private func adoptTextViewPan() {
        let pan = textView.panGestureRecognizer
        pan.view?.removeGestureRecognizer(pan)
        addGestureRecognizer(pan)
        pan.addTarget(self, action: #selector(textViewPanChanged(_:)))
        // Its own pan is off for good: scrolling disabled does that and, unlike
        // the recogniser's isEnabled, UIKit doesn't switch it back on.
        isScrollEnabled = false
        panGestureRecognizer.isEnabled = false

        indicator.isUserInteractionEnabled = false
        indicator.alpha = 0
        addSubview(indicator)
        textView.addLayoutObserver { [weak self] in self?.updateIndicator() }
        offsetObservation = textView.observe(\.contentOffset) { [weak self] _, _ in
            self?.indicatorMoved()
        }
    }

    @objc private func textViewPanChanged(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            sidewaysFling.stop()
            lastPanTranslation = .zero
        case .changed:
            let t = pan.translation(in: self)
            let dx = t.x - lastPanTranslation.x
            lastPanTranslation = t
            scrollSideways(by: -dx)
        case .ended:
            // The text view decelerates itself; the sideways axis is ours.
            let velocity = pan.velocity(in: self).x
            sidewaysFling.start(velocity: -velocity) { [weak self] delta in
                self?.scrollSideways(by: delta) ?? false
            }
        default:
            break
        }
    }

    /// Moves the sideways offset, clamped. Returns whether it moved.
    @discardableResult
    private func scrollSideways(by delta: CGFloat) -> Bool {
        let maxX = max(contentSize.width - bounds.width, 0)
        let next = min(max(contentOffset.x + delta, 0), maxX)
        guard next != contentOffset.x else { return false }
        contentOffset.x = next
        return true
    }

    // MARK: The scroll indicator

    /// A capsule at this view's right edge, so it runs at the window's edge,
    /// not the page's. It shows while the note moves and fades after.
    static let indicatorWidth: CGFloat = 3
    static let indicatorInset: CGFloat = 3
    static let indicatorMinimumLength: CGFloat = 36

    /// Where the indicator sits in this view, or nil when the note fits.
    /// `offset` and `content` are in page points; `scale` turns them to
    /// screen points.
    static func indicatorFrame(
        offset: CGFloat, content: CGFloat, area: CGSize, scale: CGFloat, sideways: CGFloat
    ) -> CGRect? {
        let total = content * scale
        guard total > area.height + 0.5 else { return nil }
        let length = max(area.height * area.height / total, indicatorMinimumLength)
        let travel = area.height - length
        let progress = min(max(offset * scale / (total - area.height), 0), 1)
        return CGRect(
            x: sideways + area.width - indicatorWidth - indicatorInset,
            y: progress * travel,
            width: indicatorWidth,
            height: length
        )
    }

    private func updateIndicator() {
        indicator.backgroundColor = UIColor.label.withAlphaComponent(0.35)
        indicator.layer.cornerRadius = Self.indicatorWidth / 2
        // Not the keyboard's inset: the bar rides above it and the note
        // scrolls under, so the indicator runs the whole window.
        guard let frame = Self.indicatorFrame(
            offset: textView.contentOffset.y + textView.contentInset.top,
            content: textView.contentSize.height,
            area: bounds.size,
            scale: displayScale,
            sideways: contentOffset.x
        ) else {
            indicator.isHidden = true
            return
        }
        indicator.isHidden = false
        indicator.frame = frame.offsetBy(dx: 0, dy: contentOffset.y)
        bringSubviewToFront(indicator)
    }

    private func indicatorMoved() {
        updateIndicator()
        guard !indicator.isHidden else { return }
        fadeTask?.cancel()
        indicator.layer.removeAllAnimations()
        indicator.alpha = 1
        fadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled, let self else { return }
            UIView.animate(withDuration: 0.3) { self.indicator.alpha = 0 }
        }
    }

    private func setPanning(enabled: Bool) {
        textView.panGestureRecognizer.isEnabled = enabled
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // A scroll already under way mustn't keep the pinch from starting.
        gestureRecognizer === pinch && (other === panGestureRecognizer || other === textView.panGestureRecognizer)
    }

    // MARK: Rendering

    /// Renders text at the density it is actually shown at, up to a cap.
    ///
    /// A transform scales pixels that were drawn at the screen's own density,
    /// so text drawn at 1x and shown at 1.25x is soft. Raising the content
    /// scale makes TextKit draw it at the density it lands on. Newly created
    /// fragment views arrive at the default, which is why this also runs after
    /// every text view layout and every layout of the text on screen; it only
    /// touches a view whose value is wrong.
    ///
    /// The canvas is left out: PaperKit keeps its own views' scale, and draws
    /// ink at the density it's shown at by zooming instead — see
    /// `DrawingCanvas.renderScale`.
    private func matchRenderingScale() {
        let value = CanvasGeometry.renderingScale(
            displayScale: displayScale,
            screenScale: traitCollection.displayScale
        )
        Self.setRenderingScale(value, in: textView, skipping: canvas)
        canvas.renderScale = CanvasGeometry.inkRenderScale(displayScale: displayScale)
    }

    private static func setRenderingScale(_ value: CGFloat, in view: UIView, skipping excluded: UIView) {
        guard view !== excluded else { return }
        if view.contentScaleFactor != value {
            view.contentScaleFactor = value
        }
        for subview in view.subviews {
            setRenderingScale(value, in: subview, skipping: excluded)
        }
    }
}

// MARK: - Decorations

/// What a view mode draws behind the text: nothing for seamless, a dashed
/// line at each break for compressed, a sheet of paper per page for print.
///
/// One small view or layer per page rather than one tall drawing. A drawn
/// view as tall as a forty-page note would need a backing store to match.
final class PageDecorationView: UIView {

    private var sheets: [UIView] = []
    private var breaks: [CAShapeLayer] = []
    private var layout: PageLayout?
    private var pageCount = 0

    /// Sheet frames in note coordinates, for tests.
    var sheetFrames: [CGRect] { sheets.map(\.frame) }

    /// Each sheet's border width, for tests.
    var sheetBorderWidths: [CGFloat] { sheets.map(\.layer.borderWidth) }

    /// Break line heights in note coordinates, for tests.
    var breakLineYs: [CGFloat] { breaks.map { $0.frame.midY } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PageDecorationView, _) in
            view.resolveColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(layout: PageLayout, pageCount: Int, height: CGFloat) {
        let frame = CGRect(x: 0, y: 0, width: layout.pageSize.width, height: height)
        if self.frame != frame {
            self.frame = frame
        }
        guard layout != self.layout || pageCount != self.pageCount else { return }
        self.layout = layout
        self.pageCount = pageCount

        let sheetCount = layout.mode == .print ? pageCount : 0
        while sheets.count < sheetCount {
            let sheet = Self.makeSheet()
            addSubview(sheet)
            sheets.append(sheet)
        }
        while sheets.count > sheetCount {
            sheets.removeLast().removeFromSuperview()
        }
        for (index, sheet) in sheets.enumerated() {
            Self.place(sheet, at: layout.sheet(ofPage: index))
        }

        let breakCount = layout.mode == .compressed ? max(pageCount - 1, 0) : 0
        while breaks.count < breakCount {
            let line = Self.makeBreakLine()
            layer.addSublayer(line)
            breaks.append(line)
        }
        while breaks.count > breakCount {
            breaks.removeLast().removeFromSuperlayer()
        }
        for (index, line) in breaks.enumerated() {
            Self.place(line, atY: layout.breakLineY(afterPage: index), width: frame.width)
        }

        resolveColors()
    }

    /// CALayer colours are plain CGColors and don't follow dark mode on their
    /// own, so they're re-resolved whenever the appearance changes.
    private func resolveColors() {
        Self.resolveColors(sheets: sheets, lines: breaks, for: traitCollection)
    }

    // MARK: Pieces, shared with the covers

    /// A sheet of paper for print layout.
    static func makeSheet() -> UIView {
        let sheet = UIView()
        sheet.backgroundColor = .systemBackground
        sheet.layer.shadowColor = UIColor.black.cgColor
        sheet.layer.shadowOpacity = 0.12
        sheet.layer.shadowRadius = 6
        sheet.layer.shadowOffset = CGSize(width: 0, height: 2)
        // The page's border, in both appearances. The shadow lifts the
        // sheet off the surround in light mode; dark mode swallows it.
        sheet.layer.borderWidth = 1
        return sheet
    }

    static func place(_ sheet: UIView, at frame: CGRect) {
        sheet.frame = frame
        sheet.layer.shadowPath = UIBezierPath(rect: sheet.bounds).cgPath
    }

    /// Compressed layout's dashed line at a page end.
    static func makeBreakLine() -> CAShapeLayer {
        let line = CAShapeLayer()
        line.lineWidth = 1
        line.lineDashPattern = [6, 5]
        line.fillColor = nil
        return line
    }

    /// Puts a break line across a page `width` wide, centred on `y`.
    static func place(_ line: CAShapeLayer, atY y: CGFloat, width: CGFloat) {
        line.frame = CGRect(x: 0, y: y - 0.5, width: width, height: 1)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: PageLayout.margin / 2, y: 0.5))
        path.addLine(to: CGPoint(x: width - PageLayout.margin / 2, y: 0.5))
        line.path = path.cgPath
    }

    static func resolveColors(sheets: [UIView], lines: [CAShapeLayer], for traits: UITraitCollection) {
        let separator = UIColor.separator.resolvedColor(with: traits).cgColor
        for sheet in sheets {
            sheet.layer.borderColor = separator
        }
        for line in lines {
            line.strokeColor = separator
        }
    }
}

// MARK: - Covers

/// Hides ink where seamless has no room: compressed's strip, and print
/// layout's top and bottom margins and the surround between its sheets
/// (`PageLayout.inkHiddenBands`).
///
/// It sits above the canvas and draws what the page draws there anyway —
/// the page and its dashed line in compressed, the surround and the
/// sheets' edges and shadows in print layout — so on a page without ink
/// it can't be told apart from what's beneath. Text never sits in these
/// bands: they're inside the ones text flows around. A stroke being drawn
/// across one goes under it, and so does a stroke drawn there that the
/// canvas still holds whole until ink is next shown (`InkCapture.State.wholeOnCanvas`).
///
/// It replaced a mask on the canvas (9 October). Masked, the canvas's ink
/// tiles painted the page white over the text beneath them: around every
/// stroke in print layout, whole blocks of lines lost their words
/// (simulator; taking the mask off in the running app brought them back).
/// A view over the ink needs no offscreen pass, either.
final class PageCoverView: UIView {

    private var bands: [UIView] = []
    private var sheets: [UIView] = []
    private var lines: [CAShapeLayer] = []
    private var layout: PageLayout?
    private var pageCount = 0

    /// Each band's frame in note coordinates, for tests.
    var bandFrames: [CGRect] { bands.map(\.frame) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PageCoverView, _) in
            PageDecorationView.resolveColors(sheets: view.sheets, lines: view.lines, for: view.traitCollection)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(layout: PageLayout, pageCount: Int, height: CGFloat) {
        let frame = CGRect(x: 0, y: 0, width: layout.pageSize.width, height: height)
        if self.frame != frame {
            self.frame = frame
        }
        guard layout != self.layout || pageCount != self.pageCount else { return }
        self.layout = layout
        self.pageCount = pageCount

        for band in bands {
            band.removeFromSuperview()
        }
        bands = []
        sheets = []
        lines = []

        for area in layout.inkHiddenBands(pageCount: pageCount) {
            let band = UIView(frame: area)
            band.clipsToBounds = true
            band.isUserInteractionEnabled = false
            band.backgroundColor = layout.mode == .print ? PageView.surroundColor : PageView.pageColor
            switch layout.mode {
            case .print:
                for index in 0..<max(pageCount, 1) where layout.sheet(ofPage: index).intersects(area) {
                    let sheet = PageDecorationView.makeSheet()
                    PageDecorationView.place(sheet, at: layout.sheet(ofPage: index).offsetBy(dx: 0, dy: -area.minY))
                    band.addSubview(sheet)
                    sheets.append(sheet)
                }
            case .compressed:
                for index in 0..<max(pageCount - 1, 0) {
                    let y = layout.breakLineY(afterPage: index)
                    guard y > area.minY, y < area.maxY else { continue }
                    let line = PageDecorationView.makeBreakLine()
                    PageDecorationView.place(line, atY: y - area.minY, width: area.width)
                    band.layer.addSublayer(line)
                    lines.append(line)
                }
            case .seamless:
                break
            }
            addSubview(band)
            bands.append(band)
        }
        PageDecorationView.resolveColors(sheets: sheets, lines: lines, for: traitCollection)
    }
}

#endif
