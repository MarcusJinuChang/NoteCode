//
//  MarkerTaps.swift
//  NoteCode
//
//  Taps on a checklist's boxes and on links, in an editable text view.
//

#if canImport(UIKit)

import UIKit

/// What a tap or a hold landed on.
enum MarkerTapTarget: Equatable {
    /// A checklist box, by the offset of its line.
    case checkbox(lineOffset: Int)
    /// A link and the address it goes to.
    case link(url: URL, destination: String)
}

/// The recognisers and the menu behind `MarkerTapTarget`, owned by the text view.
///
/// **Why not the text view's own link handling.** `UITextView` opens a link
/// on tap only when it isn't editable, and the box is no link at all. Both
/// have the same problem: a touch on an editable text view belongs to the
/// text view's own recognisers too, which place the caret and raise the
/// keyboard. They sit on the text view itself, beside these, and see every
/// touch these do (logged on the iPad, 15 Oct).
///
/// **What keeps them off.** The text view answers `hitTest` with itself for
/// a touch on a box or a link, and refuses the text interaction's
/// recognisers in its `gestureRecognizerShouldBegin` there. Both halves are
/// needed: UIKit asks the view a touch *lands on* whether a recogniser may
/// begin, and without the `hitTest` answer that was a view inside the text
/// view, so the text view was never asked. The `hitTest` answer alone, built
/// first, kept nothing off: on every link tap logged, the caret's recogniser
/// began alongside this tap, and only the handler's `resignFirstResponder`
/// cancelled it before the caret landed. A Pencil tap goes the same way, with
/// Scribble's recogniser refused beside the caret's.
///
/// A separate delegate object, not the text view: a scroll view is the
/// delegate of its own pan and pinch, and answering for them here would
/// answer for scrolling.
final class MarkerGestures: NSObject, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {

    weak var textView: DocumentUITextView?
    private(set) var tap: UITapGestureRecognizer?
    private(set) var hold: UILongPressGestureRecognizer?
    private var menu: UIEditMenuInteraction?
    private var menuTarget: (url: URL, destination: String)?

    /// What a tap landed on, asked of the coordinator.
    var targetAt: ((CGPoint) -> MarkerTapTarget?)?
    var didTap: ((MarkerTapTarget) -> Void)?

    func install(on textView: DocumentUITextView) {
        self.textView = textView

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        textView.addGestureRecognizer(tap)
        self.tap = tap

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.45
        hold.cancelsTouchesInView = false
        hold.delegate = self
        textView.addGestureRecognizer(hold)
        self.hold = hold

        let menu = UIEditMenuInteraction(delegate: self)
        textView.addInteraction(menu)
        self.menu = menu
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let textView,
              let target = targetAt?(recognizer.location(in: textView))
        else { return }
        didTap?(target)
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let textView else { return }
        heldThisTouch = true
        let point = recognizer.location(in: textView)
        guard case .link(let url, let destination)? = targetAt?(point) else { return }
        menuTarget = (url, destination)
        menu?.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
    }

    // MARK: Delegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let textView else { return false }
        let point = gestureRecognizer.location(in: textView)
        guard let target = targetAt?(point) else { return false }
        // A hold is for links: a box has no menu.
        if gestureRecognizer === hold, case .checkbox = target { return false }
        // A finger lifting after a hold has shown the menu isn't also a tap.
        // A tap has no time limit of its own, and the two recognise together.
        // Not read from the hold's state: on the iPad the hold had already
        // ended by the time the tap asked.
        if gestureRecognizer === tap, heldThisTouch { return false }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// Whether the hold began for the touch now down, so lifting it isn't a tap.
    private var heldThisTouch = false

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === hold { heldThisTouch = false }
        return true
    }

    // MARK: The menu a hold on a link shows

    /// The address as typed, then Open Link and Copy Link.
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        guard let target = menuTarget else { return nil }
        return UIMenu(title: target.destination, children: [
            UIAction(title: "Open Link", image: UIImage(systemName: "safari")) { _ in
                UIApplication.shared.open(target.url)
            },
            UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = target.destination
            },
        ])
    }
}

// MARK: - The coordinator's side

extension DocumentTextView.Coordinator {

    /// What is at a point in the text view, if it's a box or a link and the
    /// text view is the one taking touches.
    func markerTapTarget(at point: CGPoint, in textView: DocumentUITextView) -> MarkerTapTarget? {
        guard editor?.mode != .ink,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return nil }

        let inset = textView.textContainerInset
        let container = CGPoint(x: point.x - inset.left, y: point.y - inset.top)
        guard let fragment = layoutManager.textLayoutFragment(for: container),
              fragment.layoutFragmentFrame.insetBy(dx: -PageLayout.margin, dy: 0).contains(container),
              let offset = self.offset(of: fragment)
        else { return nil }
        let frame = fragment.layoutFragmentFrame

        // A box: a generous target around it, since a finger is wider than 16pt.
        // Only where the text can be changed.
        if textView.isEditable, let checklist = fragment as? ChecklistLayoutFragment,
           let box = checklist.boxRect()?.box {
            let target = box.offsetBy(dx: frame.minX, dy: frame.minY).insetBy(dx: -10, dy: -6)
            if target.contains(container) { return .checkbox(lineOffset: offset) }
        }

        // A link: any of the line's links whose text lies under the point.
        let text = textView.textStorage.mutableString
        for link in MarkdownFormatting.links(onLineAt: offset, in: text, codeRanges: codeRanges(in: textView.textStorage)) {
            guard let url = LinkTarget.url(for: link.destination),
                  let start = contentManager.location(contentManager.documentRange.location, offsetBy: link.text.location),
                  let end = contentManager.location(start, offsetBy: link.text.length),
                  let range = NSTextRange(location: start, end: end)
            else { continue }

            var hit = false
            layoutManager.enumerateTextSegments(in: range, type: .standard, options: []) { _, segment, _, _ in
                if segment.insetBy(dx: -4, dy: -3).contains(container) { hit = true }
                return !hit
            }
            if hit { return .link(url: url, destination: link.destination) }
        }
        return nil
    }

    func handleMarkerTap(_ target: MarkerTapTarget, in textView: DocumentUITextView) {
        switch target {
        case .checkbox(let lineOffset):
            guard let edit = MarkdownFormatting.toggleCheckbox(
                onLineAt: lineOffset,
                in: textView.textStorage.mutableString,
                keeping: textView.selectedRange
            ) else { return }
            apply(edit, to: textView)

        case .link(let url, _):
            // Leaving for Safari with the keyboard up means coming back to a
            // view that has to lay out under it.
            textView.resignFirstResponder()
            UIApplication.shared.open(url)
        }
    }

    /// Connects the text view's gestures and ⇧Tab to this coordinator.
    func installMarkerGestures(on textView: DocumentUITextView) {
        guard let gestures = textView.markerGestures else { return }
        gestures.targetAt = { [weak self, weak textView] point in
            guard let self, let textView else { return nil }
            return markerTapTarget(at: point, in: textView)
        }
        gestures.didTap = { [weak self, weak textView] target in
            guard let self, let textView else { return }
            handleMarkerTap(target, in: textView)
        }
        textView.touchTarget = { [weak gestures] point in gestures?.targetAt?(point) != nil }
        textView.outdentHandler = { [weak self, weak textView] in
            guard let self, let textView else { return }
            outdentListItems(in: textView)
        }
        textView.canOutdent = { [weak self, weak textView] in
            guard let self, let textView else { return false }
            return canOutdentListItems(in: textView)
        }
    }
}

#endif
