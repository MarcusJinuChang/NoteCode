//
//  DrawingCanvas.swift
//  NoteCode
//
//  The ink layer: PaperKit's canvas, in a view of NoteCode's own.
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import UIKit

/// PaperKit's canvas, wrapped so the page can treat ink as one more subview.
///
/// **Why a wrapper.** PaperKit's canvas is a view *controller*, and
/// `PaperMarkupViewController` is declared `public`, not `open`, so nothing
/// outside PaperKit can subclass it. Undo is what needs overriding: the
/// controller's `undoManager` walks the responder chain, which here runs
/// through the text view, so ink would register on the text editor's stack —
/// measured on the simulator, 18 September. This view sits between the two and
/// vends a manager of its own, which `NoteEditor` can then route the hotbar's
/// arrows to.
///
/// **Why PaperKit.** Shapes, arrows, images and text boxes come with it, each
/// selectable and resizable, and its strokes are PencilKit's. See
/// docs/phase-drawing-layer.md.
@MainActor
final class DrawingCanvas: UIView {

    let controller: PaperMarkupViewController

    /// Ink's own undo stack, kept off the text view's.
    private let inkUndoManager = UndoManager()

    override var undoManager: UndoManager? { inkUndoManager }

    /// The ink as it is shown, in the current mode's coordinates.
    ///
    /// The note's stored ink lives in `PageView.ink`, in print coordinates.
    var markup: PaperMarkup {
        get { controller.markup ?? PaperMarkup(bounds: CGRect(origin: .zero, size: noteSize)) }
        set {
            show { controller.markup = newValue }
            fitMarkupToNote()
        }
    }

    /// Whether the ink on the canvas is being put there by the app.
    private var isShowingInk = false

    /// Runs a change the app is making, rather than the reader.
    ///
    /// PaperKit calls its delegate **twice, synchronously** for one assignment
    /// to `markup` (measured 19 September). Left alone, showing stored ink
    /// would look exactly like someone drawing it by hand, and the page would
    /// convert what it had just shown straight back into storage.
    private func show(_ change: () -> Void) {
        let wasShowing = isShowingInk
        isShowingInk = true
        change()
        isShowingInk = wasShowing
    }

    /// What a stroke lays down. Set from the hotbar through `NoteEditor`.
    var tool: any PKTool {
        get { controller.drawingTool }
        set { controller.drawingTool = newValue }
    }

    /// Whether a finger draws, as the Pencil always does.
    ///
    /// On by default. The page has a hard toggle between typing and drawing,
    /// so a finger in ink mode is there to draw; someone who wants to scroll
    /// a page of notes leaves ink mode or locks the canvas to the Pencil.
    /// Off, a finger scrolls and selects instead, which is what you want with
    /// a Pencil in hand and a palm on the page.
    var allowsFingerDrawing = true {
        didSet {
            guard allowsFingerDrawing != oldValue else { return }
            applyTouchMode()
        }
    }

    /// Called when ink's undo stack gains or loses something the hotbar's
    /// arrows should reflect.
    var onUndoDidChange: (() -> Void)?

    /// Called after the reader changes what's on the canvas: a stroke drawn,
    /// erased, or moved. Ink the app puts there itself changes nothing the
    /// page doesn't already know, so `PageView` measures against what it last
    /// showed rather than trusting this to mean "the reader did something".
    var onMarkupChanged: (() -> Void)?

    init(pageSize: CGSize) {
        let frame = CGRect(origin: .zero, size: pageSize)
        controller = PaperMarkupViewController(
            markup: PaperMarkup(bounds: frame),
            supportedFeatureSet: .latest
        )
        super.init(frame: frame)
        noteSize = pageSize

        // Transparent all the way down, or the canvas paints over every word
        // underneath. The controller's own background is opaque by default,
        // and its `contentView` is what it draws the page onto.
        backgroundColor = .clear
        isOpaque = false
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        controller.contentView = {
            let view = UIView()
            view.backgroundColor = .clear
            view.isOpaque = false
            return view
        }()

        // A drawing surface, not a second scroll view competing for the pan:
        // the text view scrolls both layers, and `PageView` handles zoom as a
        // transform.
        controller.scrollConfiguration.isScrollEnabled = false
        controller.zoomRange = 1...1

        applyTouchMode()
        controller.delegate = self

        controller.view.frame = bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(controller.view)

        // Text owns input until the toggle hands it over.
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Undo

    /// Forgets what ink undo was holding.
    ///
    /// Called when the page replaces what's on the canvas. Each action on that
    /// stack restores a stroke to where it sat in the mode it was drawn in, so
    /// after a switch to print layout, undoing a stroke drawn in seamless
    /// would drop it a page short of its words. The stored ink in
    /// `PageView.ink` is what survives a mode change; the stack isn't.
    func forgetUndo() {
        guard inkUndoManager.canUndo || inkUndoManager.canRedo else { return }
        inkUndoManager.removeAllActions()
        onUndoDidChange?()
    }

    // MARK: Input

    /// Who may draw.
    ///
    /// PaperKit's drawing recognisers take the Pencil on their own. What this
    /// settles is the finger. Left automatic, PaperKit decides: a finger draws
    /// only while a `PKToolPicker` is up and the system's "Draw with Finger"
    /// setting allows it. The hotbar replaced the picker, so that rule would
    /// mean a finger never draws, whatever the app wants.
    ///
    /// Turning the automatic rule off and asking for `.drawing` isn't enough
    /// on its own, though an earlier note here said it was. Measured in the
    /// app on 23 September: PencilKit's canvas inside PaperKit kept its
    /// drawing policy at `.default`, its drawing recognisers accepted only the
    /// Pencil, and a finger landed on the selection view above them. Setting
    /// before or after the view loaded, and toggling, changed none of that.
    /// Setting that canvas's own `drawingPolicy` — the property `PKCanvasView`
    /// makes public — opens the recognisers to a finger and moves the hit
    /// test onto them, and a finger draws.
    private func applyTouchMode() {
        controller.directTouchAutomaticallyDraws = false
        controller.directTouchMode = allowsFingerDrawing ? .drawing : .selection
        releaseTwoFingerDrags()

        let policy: PKCanvasViewDrawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        guard let pencilKitCanvas = Self.pencilKitCanvas(in: controller.view),
              pencilKitCanvas.responds(to: NSSelectorFromString("setDrawingPolicy:"))
        else {
            // PencilKit's insides moved. The Pencil still draws; a finger
            // doesn't, which is where this started.
            return
        }
        pencilKitCanvas.setValue(policy.rawValue, forKey: "drawingPolicy")
    }

    /// Leaves two-finger drags to the text view, which scrolls the note.
    ///
    /// PaperKit's canvas sits on a scroll view of its own, with scrolling off
    /// (`scrollConfiguration`). Its pan wants two fingers, and once a lasso
    /// selection had been dragged, PaperKit switched it on and left it on: it
    /// took every two-finger drag on the canvas with nowhere to scroll it, so
    /// in ink mode, with a finger drawing, nothing scrolled the note. Allowed
    /// no touches at all, it stays out of the way whether PaperKit has it on
    /// or not, and two fingers scroll the note and draw nothing (simulator,
    /// 25 September; switching it off lasted only until the next drag).
    ///
    /// Found by walking the view tree, since PaperKit doesn't expose the
    /// scroll view; `UIScrollView` and its pan are public API.
    private func releaseTwoFingerDrags() {
        for scrollView in Self.scrollViews(in: controller.view) {
            scrollView.panGestureRecognizer.allowedTouchTypes = []
        }
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        let own = (view as? UIScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap(scrollViews(in:))
    }

    /// PaperKit's own scroll views' pans. For tests.
    var paperKitPans: [UIPanGestureRecognizer] {
        Self.scrollViews(in: controller.view).map(\.panGestureRecognizer)
    }

    /// PencilKit's canvas view inside PaperKit's, found by class name.
    ///
    /// Not public API, so looked up rather than assumed, and the setter is
    /// checked before it's used.
    private static func pencilKitCanvas(in view: UIView) -> UIView? {
        if NSStringFromClass(type(of: view)) == "PKTiledView" { return view }
        for subview in view.subviews {
            if let found = pencilKitCanvas(in: subview) { return found }
        }
        return nil
    }

    /// PencilKit's drawing policy, as the canvas has it now. For tests.
    var pencilKitDrawingPolicy: PKCanvasViewDrawingPolicy? {
        guard let pencilKitCanvas = Self.pencilKitCanvas(in: controller.view),
              let raw = pencilKitCanvas.value(forKey: "drawingPolicy") as? UInt
        else { return nil }
        return PKCanvasViewDrawingPolicy(rawValue: raw)
    }

    // MARK: What's on screen

    /// The whole note, which the markup spans.
    ///
    /// The canvas view itself only ever covers what's on screen — see
    /// `show(_:)` — but ink is kept in note coordinates, top to bottom.
    var noteSize: CGSize = .zero {
        didSet {
            guard noteSize != oldValue else { return }
            fitMarkupToNote()
        }
    }

    /// The zoom PaperKit draws ink at, which `PageView` sets to the scale
    /// the page is shown at, up to the same cap as text.
    ///
    /// The canvas sits inside the text view, whose transform scales the page
    /// to fit. PaperKit draws finished ink into tiles at the screen's density,
    /// so under a 1.25x page every tile was stretched a quarter and ink was
    /// visibly softer than in Notes (on the iPad, 25 September; the tiles'
    /// scale read 2.0 on a 2x screen). Zooming PaperKit itself, and shrinking
    /// the canvas by the same factor so the two cancel, has it draw the tiles
    /// at the density they're shown at. Where the canvas sits on the note
    /// doesn't change — see `cover(_:)` and `fitMarkupToNote()`.
    var renderScale: CGFloat = 1 {
        didSet {
            guard renderScale != oldValue, renderScale > 0 else { return }
            controller.zoomRange = renderScale...renderScale
            controller.scrollConfiguration.zoomScale = renderScale
            fitMarkupToNote()
            cover(covered)
        }
    }

    /// The part of the note the canvas was last told to cover.
    private var covered: CGRect = .zero

    /// Covers `visible`, part of the note, and draws the ink that falls there.
    ///
    /// The canvas used to be as tall as the note. PencilKit sizes the buffer a
    /// stroke is drawn into from its canvas's bounds, and past 16,384 pixels
    /// Metal refuses the texture: the first stroke on a nine-page note, 9,237
    /// points tall at 2x, crashed the app (simulator, 23 September) — a little
    /// under eight pages in seamless, and on the iPad the Pencil as much as a
    /// finger. Sized to the screen, the buffer is the screen's size however
    /// long the note is.
    ///
    /// The view stays a subview of the text view's content, so it scrolls with
    /// the text. It's moved to where the text view is scrolled to on each
    /// layout pass, and PaperKit is told which part of the note it's over.
    /// Both happen in the text view's layout, before anything is drawn, so
    /// the ink never lags the words.
    ///
    /// Its own points are `renderScale` times the note's: a transform of the
    /// inverse brings it back to `visible` in the text view's coordinates,
    /// and PaperKit, zoomed by `renderScale`, draws that much of the note
    /// across it.
    ///
    /// - Parameter visible: in note coordinates, within `noteSize`.
    func cover(_ visible: CGRect) {
        covered = visible
        let size = CGSize(width: visible.width * renderScale, height: visible.height * renderScale)
        let resized = bounds.size != size
        if resized {
            bounds.size = size
        }
        let shrink = CGAffineTransform(scaleX: 1 / renderScale, y: 1 / renderScale)
        if transform != shrink {
            transform = shrink
        }
        let middle = CGPoint(x: visible.midX, y: visible.midY)
        if center != middle {
            center = middle
        }
        // PaperKit centres the frame it's given in its viewport as it
        // stands. Until layout reaches its scroll view, that's the old
        // size: a canvas cut from 1,056 to 600 points showed 1,200 at
        // 972 (unit test, 23 September), ink half the difference off.
        if resized {
            layoutIfNeeded()
        }
        if controller.contentVisibleFrame != visible {
            controller.contentVisibleFrame = visible
        }
    }

    /// Keeps the markup's bounds on the note's, times `renderScale`.
    ///
    /// PaperKit positions content against the markup's bounds, not the view's.
    /// Resizing the view alone shifted what was drawn until the markup was
    /// assigned again (simulator, 18 September), and the note gains or loses
    /// a page as it's written.
    ///
    /// Zoomed, PaperKit sizes its content as the markup's bounds *divided* by
    /// the zoom, in the markup's own coordinates. Given the note's size at
    /// 1.25x, it took the note to be 816 points wide where it drew 1,020,
    /// centred it, and every element landed 81.6 points right of its words
    /// (unit test, 25 September). Bounds of the note's size times the zoom
    /// put a shape at exactly its note coordinates at 1x, 1.25x and 3x. Only
    /// the canvas's copy has these bounds; stored ink keeps the note's.
    private func fitMarkupToNote() {
        let bounds = CGRect(
            origin: .zero,
            size: CGSize(width: noteSize.width * renderScale, height: noteSize.height * renderScale)
        )
        guard noteSize.width > 0, noteSize.height > 0,
              var markup = controller.markup, markup.bounds != bounds
        else { return }
        markup.bounds = bounds
        show { controller.markup = markup }
    }

    // MARK: Lifecycle

    /// Adopts the controller into whichever view controller is hosting the
    /// page, once there is one.
    ///
    /// PaperKit's canvas is a view controller and wants a parent for trait and
    /// appearance callbacks. The page is built inside a `UIViewRepresentable`,
    /// which has no controller to offer, so the nearest one up the responder
    /// chain — SwiftUI's own hosting controller — adopts it. The canvas works
    /// uncontained too; this is about lifecycle, not about drawing.
    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard window != nil else { return }
        // PencilKit's canvas can be rebuilt as the controller settles in, and
        // the drawing policy lives on it.
        applyTouchMode()

        guard controller.parent == nil, let parent = nearestViewController() else { return }
        parent.addChild(controller)
        controller.didMove(toParent: parent)
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}

// MARK: - Changes

extension DrawingCanvas: PaperMarkupViewController.Delegate {

    func paperMarkupViewControllerDidChangeMarkup(_ paperMarkupViewController: PaperMarkupViewController) {
        guard !isShowingInk else { return }
        onMarkupChanged?()
        // PaperKit has registered the change on ink's stack by now (measured
        // 23 September), and nothing else tells the hotbar: its undo arrow
        // stayed dim after a stroke.
        onUndoDidChange?()
    }
}

#endif
