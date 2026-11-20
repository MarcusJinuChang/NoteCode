//
//  PencilGestureRouter.swift
//  NoteCode
//
//  What the Pencil's double tap and squeeze do on the note (as set in
//  Settings), and where the bar lands when it is dropped. They were methods
//  and `@State` in `PageDetailView`.
//

#if canImport(UIKit)
import SwiftUI

@MainActor
@Observable
final class PencilGestureRouter {
    /// Whether the ink tools are showing beside the Pencil.
    var showsInkTools = false
    private(set) var inkToolsAnchor = UnitPoint.center

    /// Counts the bar's drops; each one is a snap for the haptic to follow.
    private(set) var snaps = 0

    /// Does what the reader has set a Pencil gesture to do, in ink mode.
    ///
    /// - Parameter anchor: where the Pencil is hovering over the page, if it
    ///   is — where the ink tools show. Without it, they show by the hotbar.
    func respond(to response: PencilResponse, at anchor: UnitPoint?, editor: NoteEditor, dock: HotbarDock) {
        // From text mode the gesture first switches to ink, then acts.
        editor.enterInkForPencil(response)
        guard editor.mode == .ink else { return }
        switch response {
        case .toggleEraser:
            editor.toggleEraser()
        case .switchToPreviousTool:
            editor.switchToPreviousTool()
        case .showInkTools:
            if showsInkTools {
                showsInkTools = false
            } else {
                inkToolsAnchor = anchor ?? dock.inkToolsAnchor
                showsInkTools = true
            }
        case .nothing:
            break
        }
    }

    /// Snaps the bar to whichever edge it was let go nearest, by calling
    /// `setDock`.
    ///
    /// Uses the predicted end rather than where the finger stopped, so a flick
    /// toward an edge goes there without having to be dragged all the way.
    func drop(_ drag: DragGesture.Value, in pageSize: CGSize, setDock: (HotbarDock) -> Void) {
        let landing = HotbarDock.nearest(to: drag.predictedEndLocation, in: pageSize)
        // The bar's drag offset springs back on its own as the gesture ends,
        // with the same animation, so the two read as one movement.
        withAnimation(.snappy) {
            setDock(landing)
        }
        snaps += 1
    }
}

/// The note's Pencil gestures and the ink tools' popover they raise.
struct PencilGestures: ViewModifier {
    @Bindable var router: PencilGestureRouter
    let editor: NoteEditor
    let dock: HotbarDock

    /// What the reader has set the Pencil's double tap and squeeze to do,
    /// in Settings.
    @Environment(\.preferredPencilDoubleTapAction) private var doubleTapAction
    @Environment(\.preferredPencilSqueezeAction) private var squeezeAction

    func body(content: Content) -> some View {
        content
            .onPencilDoubleTap { tap in
                router.respond(to: PencilResponse(doubleTapAction), at: tap.hoverPose?.anchor, editor: editor, dock: dock)
            }
            .onPencilSqueeze { phase in
                // On letting go: a squeeze held and released is one request.
                guard case .ended(let squeeze) = phase else { return }
                router.respond(to: PencilResponse(squeezeAction), at: squeeze.hoverPose?.anchor, editor: editor, dock: dock)
            }
            .popover(isPresented: $router.showsInkTools, attachmentAnchor: .point(router.inkToolsAnchor)) {
                InkToolPopover(editor: editor)
            }
    }
}

extension HotbarDock {
    /// Where the bar sits in the page area.
    var alignment: Alignment {
        switch self {
        case .left:   .leading
        case .bottom: .bottom
        case .right:  .trailing
        }
    }

    /// Where the ink tools show when the Pencil isn't hovering: by the bar.
    var inkToolsAnchor: UnitPoint {
        switch self {
        case .left:   .leading
        case .bottom: .bottom
        case .right:  .trailing
        }
    }
}
#endif
