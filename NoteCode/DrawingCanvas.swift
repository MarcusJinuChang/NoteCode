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
        get { controller.markup ?? PaperMarkup(bounds: bounds) }
        set { show { controller.markup = newValue } }
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

    // MARK: Input

    /// Who may draw.
    ///
    /// PaperKit's drawing recognisers take the Pencil on their own. What this
    /// settles is the finger. Left automatic, PaperKit decides: a finger draws
    /// only while a `PKToolPicker` is up and the system's "Draw with Finger"
    /// setting allows it. The hotbar replaced the picker, so that rule would
    /// mean a finger never draws, whatever the app wants. Deciding here
    /// instead is what makes `allowsFingerDrawing` mean anything.
    private func applyTouchMode() {
        controller.directTouchAutomaticallyDraws = false
        controller.directTouchMode = allowsFingerDrawing ? .drawing : .selection
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

        guard window != nil, controller.parent == nil, let parent = nearestViewController() else { return }
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

    // MARK: Layout

    /// Keeps the markup's bounds on the view's.
    ///
    /// PaperKit positions content against the markup's bounds, not the view's.
    /// Resizing the view alone shifted what was drawn until the markup was
    /// assigned again (simulator, 18 September), and the page resizes whenever
    /// the note gains or loses a page.
    override func layoutSubviews() {
        super.layoutSubviews()

        guard var markup = controller.markup, markup.bounds != bounds else { return }
        markup.bounds = bounds
        show { controller.markup = markup }
    }
}

// MARK: - Changes

extension DrawingCanvas: PaperMarkupViewController.Delegate {

    func paperMarkupViewControllerDidChangeMarkup(_ paperMarkupViewController: PaperMarkupViewController) {
        guard !isShowingInk else { return }
        onMarkupChanged?()
    }
}

#endif
