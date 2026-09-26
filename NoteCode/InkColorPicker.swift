//
//  InkColorPicker.swift
//  NoteCode
//
//  Apple's colour picker, for adding a colour to the palette.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

/// Shows `UIColorPickerViewController` in a popover from a hotbar button,
/// and hands back the colour chosen once it closes.
///
/// Apple's picker rather than one of the app's own: it has the grid, the
/// spectrum, sliders, a hex field and an eyedropper — what GoodNotes and
/// Notability each build by hand — and it's what Notes' tool picker opens.
///
/// Presented from UIKit rather than through SwiftUI's `.popover`: hosted
/// inside a SwiftUI popover, the picker is a child controller rather than the
/// presented one, and its own close button and eyedropper expect to be the
/// presented one.
@MainActor
final class InkColorPicker: NSObject {

    /// The view the popover points at, put behind the button by `Anchor`.
    fileprivate weak var anchorView: UIView?

    /// The colour last chosen while the picker is up, if any.
    private var chosen: UIColor?
    private var onChoose: ((UIColor) -> Void)?

    /// - Parameters:
    ///   - color: the colour the picker opens on, as it looks on the page.
    ///   - onChoose: called once the picker closes, and only if a colour was
    ///     chosen; closing it untouched adds nothing.
    func present(starting color: UIColor, onChoose: @escaping (UIColor) -> Void) {
        guard let anchorView, let presenter = Self.topController(above: anchorView) else { return }

        let picker = UIColorPickerViewController()
        // Ink's opacity is the tool's business: the highlighter is
        // see-through whatever colour it's given.
        picker.supportsAlpha = false
        picker.selectedColor = color
        picker.delegate = self
        picker.modalPresentationStyle = .popover
        if let popover = picker.popoverPresentationController {
            popover.sourceView = anchorView
            popover.sourceRect = anchorView.bounds
            popover.delegate = self
        }

        chosen = nil
        self.onChoose = onChoose
        presenter.present(picker, animated: true)
    }

    private func finish() {
        let chosen = chosen
        let onChoose = onChoose
        self.chosen = nil
        self.onChoose = nil
        if let chosen {
            onChoose?(chosen)
        }
    }

    /// The controller to present from: the one hosting the anchor, or
    /// whatever it's already showing — a popover the button is inside.
    private static func topController(above view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder, !(current is UIViewController) {
            responder = current.next
        }
        guard var top = responder as? UIViewController else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// An empty view behind the button, for the popover to point at.
    struct Anchor: UIViewRepresentable {
        let picker: InkColorPicker

        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.isUserInteractionEnabled = false
            picker.anchorView = view
            return view
        }

        func updateUIView(_ view: UIView, context: Context) {
            picker.anchorView = view
        }
    }
}

extension InkColorPicker: UIColorPickerViewControllerDelegate {

    func colorPickerViewController(
        _ viewController: UIColorPickerViewController,
        didSelect color: UIColor,
        continuously: Bool
    ) {
        chosen = color
    }

    /// The picker's own close button.
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        finish()
    }
}

extension InkColorPicker: UIPopoverPresentationControllerDelegate {

    /// A tap outside the popover, which doesn't go through the picker.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish()
    }
}

#endif
