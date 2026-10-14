//
//  InkInsert.swift
//  NoteCode
//
//  The hotbar's Insert: PaperKit's own shapes, text box and arrows, and a
//  photo from the library, put on the page where the reader is looking.
//

#if canImport(UIKit)

import Observation
import PaperKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Where, and how big

/// Where an inserted element goes and how big a photo is, as pure functions.
nonisolated enum InkInsertion {

    /// The most a photo is drawn at, as a share of the page's width.
    static let photoWidthShare: CGFloat = 0.6

    /// A photo is kept at up to this many pixels to a point of page width:
    /// 2x, the density of the iPad's screen. A 12-megapixel photo is 48MB
    /// decoded and would be stored in the note whole.
    static let pixelsPerPageWidthPoint: CGFloat = 2

    /// How big a shape or text box is taken to be for keeping it on a page.
    /// PaperKit sizes its own: the shape the probe inserted was 155 points.
    static let shapeExtent = CGSize(width: 160, height: 160)

    /// The point to insert an element of `extent` around, in the note's
    /// coordinates for the layout it is shown in.
    ///
    /// The middle of what's on screen, moved into a page's `inkRegion`. An
    /// element belongs to the page its middle is on (`InkCapture.moved`), and
    /// the space between one page's region and the next, which print layout
    /// and compressed hide, takes no ink: an element centred in a margin would
    /// be half under a cover. So the middle goes to the page on screen
    /// (the one it's in, else the one showing most), and where the element
    /// fits the page it's kept wholly on it, not astride a break.
    static func centre(in visible: CGRect, regions: [CGRect], extent: CGSize) -> CGPoint {
        let middle = CGPoint(x: visible.midX, y: visible.midY)
        guard !regions.isEmpty else { return middle }

        func shown(_ region: CGRect) -> CGFloat {
            let part = region.intersection(visible)
            return part.isNull ? 0 : part.height
        }
        let region: CGRect
        if let containing = regions.first(where: { middle.y >= $0.minY && middle.y < $0.maxY }) {
            region = containing
        } else if let most = regions.max(by: { shown($0) < shown($1) }), shown(most) > 0 {
            region = most
        } else {
            region = regions.min { distance(from: middle.y, to: $0) < distance(from: middle.y, to: $1) } ?? regions[0]
        }

        let within = region.intersection(visible)
        var y = within.isNull ? min(max(middle.y, region.minY), region.maxY) : within.midY
        let half = extent.height / 2
        if region.height > extent.height {
            y = min(max(y, region.minY + half), region.maxY - half)
        }
        return CGPoint(x: region.midX, y: y)
    }

    private static func distance(from y: CGFloat, to region: CGRect) -> CGFloat {
        max(region.minY - y, y - region.maxY, 0)
    }

    /// The size a photo of `pixels` is first shown at: fitted inside a share
    /// of the page's width and of `maxHeight`, and never larger than it would
    /// be at 2 pixels to the point.
    static func photoSize(pixels: CGSize, pageWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        guard pixels.width > 0, pixels.height > 0 else { return .zero }
        let scale = min(
            pageWidth * photoWidthShare / pixels.width,
            maxHeight / pixels.height,
            1 / pixelsPerPageWidthPoint
        )
        // Rounded down, so the share is a ceiling.
        return CGSize(width: (pixels.width * scale).rounded(.down), height: (pixels.height * scale).rounded(.down))
    }

    /// The photo at `url` with its longest side at most `maxPixelSize`, turned
    /// the right way up. Not enlarged if it's smaller.
    ///
    /// Decoded at that size from the file, never in full: ImageIO's thumbnail
    /// reads and scales as it goes. Runs off the main thread, in the picker's
    /// callback, where the file is still there (it's removed on return).
    static func downscaled(from url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? Int) ?? maxPixelSize
        let height = (properties?[kCGImagePropertyPixelHeight] as? Int) ?? maxPixelSize
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize, max(width, height)),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

// MARK: - The popover

/// Presents PaperKit's insert popover from a hotbar button, and puts what is
/// chosen on the page.
///
/// **PaperKit's own controller, not a redraw of it** (`MarkupEditViewController`):
/// it has the shapes, lines, arrows and text box, and takes our "Photo…" as
/// an extra row. Its delegate does the inserting. `PaperMarkupViewController`
/// is already one, but it puts a new element at the middle of the canvas's
/// visible frame, which can be a margin or a break. So this is the delegate
/// instead, and does the same thing from the right place
/// (`DrawingCanvas.inserting(around:_:)`). Probed in a test: the controller's
/// own path tells the canvas's delegate once, registers one undo, and
/// selects what it inserted.
///
/// Presented from UIKit, like `InkColorPicker`, so it is the presented
/// controller rather than a child of a SwiftUI popover.
@MainActor
@Observable
final class InkInserter: NSObject {

    /// Whether the popover is up, so the button can show it.
    private(set) var isPresented = false

    @ObservationIgnored weak var anchorView: UIView?
    @ObservationIgnored private weak var editor: NoteEditor?
    @ObservationIgnored private weak var presenter: UIViewController?
    @ObservationIgnored private weak var popover: MarkupEditViewController?
    @ObservationIgnored private var watching: Task<Void, Never>?

    /// Whether the popover is really on screen, as opposed to `isPresented`,
    /// which is what the button last heard.
    private var isOnScreen: Bool {
        popover?.presentingViewController != nil
    }

    func present(for editor: NoteEditor) {
        // Believe the controller over the flag: the flag is set by delegate
        // callbacks, and a popover can go without one (a tap outside while a
        // sub-picker of PaperKit's is up), which left the button lit and
        // refusing to open it again.
        if isPresented, !isOnScreen { isPresented = false }
        guard editor.mode == .ink, !isPresented,
              let anchorView, let presenter = InkColorPicker.topController(above: anchorView)
        else { return }
        self.editor = editor
        self.presenter = presenter

        let photo = UIAction(title: "Photo…", image: UIImage(systemName: "photo")) { [weak self] _ in
            self?.choosePhoto()
        }
        let controller = MarkupEditViewController(supportedFeatureSet: .latest, additionalActions: [photo])
        controller.delegate = self
        controller.modalPresentationStyle = .popover
        if let popover = controller.popoverPresentationController {
            popover.sourceView = anchorView
            popover.sourceRect = anchorView.bounds
            popover.delegate = self
        }
        popover = controller
        isPresented = true
        presenter.present(controller, animated: true)
        watch(controller)
    }

    /// Clears `isPresented` when the popover goes, however it goes. UIKit
    /// reports a tap outside to the presentation's delegate, but not every
    /// route out of PaperKit's nested pickers, and the delegate has no
    /// callback for a dismissal PaperKit makes itself. The controller's own
    /// `presentingViewController` is the one thing all of them change.
    private func watch(_ controller: MarkupEditViewController) {
        watching?.cancel()
        watching = Task { @MainActor [weak self, weak controller] in
            while let controller, controller.presentingViewController != nil, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            self?.isPresented = false
        }
    }

    /// Takes the popover away. The Photo… row doesn't close it by itself, and
    /// neither does an insert.
    private func dismiss(then completion: (() -> Void)? = nil) {
        isPresented = false
        guard let presenter, presenter.presentedViewController is MarkupEditViewController else {
            completion?()
            return
        }
        presenter.dismiss(animated: true, completion: completion)
    }

    // MARK: Putting things on the page

    /// Runs one of PaperKit's inserts at the page's middle, then hands the
    /// reader the lasso, so the new element can be moved and resized at once.
    private func insert(extent: CGSize, _ body: @escaping (PaperMarkupViewController) -> Void) {
        guard let editor, editor.insertIntoInk(extent: extent, body) else { return }
        dismiss()
    }

    private func choosePhoto() {
        dismiss { [weak self] in
            guard let self, let presenter else { return }
            var configuration = PHPickerConfiguration()
            configuration.filter = .images
            configuration.selectionLimit = 1
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            presenter.present(picker, animated: true)
        }
    }

    /// Puts `image` on the page, sized to fit.
    func insert(photo image: CGImage) {
        guard let editor, let pageWidth = editor.insertionPageWidth else { return }
        let size = InkInsertion.photoSize(
            pixels: CGSize(width: image.width, height: image.height),
            pageWidth: pageWidth,
            maxHeight: editor.insertionMaxHeight
        )
        guard size.width > 0, size.height > 0 else { return }

        var contents = PaperMarkup(bounds: CGRect(origin: .zero, size: size))
        contents.insertNewImage(image, frame: CGRect(origin: .zero, size: size))
        let sender = MarkupEditViewController(supportedFeatureSet: .latest)
        insert(extent: size) { controller in
            controller.markupEditViewController(sender, insertNewContents: contents)
        }
    }

    /// An empty view behind the button, for the popover to point at.
    struct Anchor: UIViewRepresentable {
        let inserter: InkInserter

        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.isUserInteractionEnabled = false
            inserter.anchorView = view
            return view
        }

        func updateUIView(_ view: UIView, context: Context) {
            inserter.anchorView = view
        }
    }
}

extension InkInserter: @preconcurrency MarkupEditViewController.Delegate {

    func markupEditViewController(_ markupEditViewController: MarkupEditViewController, insertNewShape type: ShapeConfiguration.Shape) {
        insert(extent: InkInsertion.shapeExtent) { controller in
            controller.markupEditViewController(markupEditViewController, insertNewShape: type)
        }
    }

    func markupEditViewControllerInsertNewTextbox(_ markupEditViewController: MarkupEditViewController) {
        insert(extent: InkInsertion.shapeExtent) { controller in
            controller.markupEditViewControllerInsertNewTextbox(markupEditViewController)
        }
    }

    func markupEditViewController(
        _ markupEditViewController: MarkupEditViewController,
        insertNewLineWithStartMarker lineStartMarker: Bool,
        endMarker lineEndMarker: Bool
    ) {
        insert(extent: InkInsertion.shapeExtent) { controller in
            controller.markupEditViewController(
                markupEditViewController,
                insertNewLineWithStartMarker: lineStartMarker,
                endMarker: lineEndMarker
            )
        }
    }

    func markupEditViewController(_ markupEditViewController: MarkupEditViewController, insertNewContents toInsert: PaperMarkup) {
        insert(extent: InkInsertion.shapeExtent) { controller in
            controller.markupEditViewController(markupEditViewController, insertNewContents: toInsert)
        }
    }
}

extension InkInserter: @preconcurrency PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
              let pageWidth = editor?.insertionPageWidth
        else { return }

        let maxPixels = Int(pageWidth * InkInsertion.pixelsPerPageWidthPoint)
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
            // Called off the main thread, with a file that is removed when
            // this returns: so it's decoded here, and only the picture goes
            // back to the main actor.
            guard let url, let image = InkInsertion.downscaled(from: url, maxPixelSize: maxPixels) else { return }
            Task { @MainActor in self?.insert(photo: image) }
        }
    }
}

extension InkInserter: UIPopoverPresentationControllerDelegate {

    /// Stays a popover on a narrow window, rather than becoming a sheet.
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }

    /// A tap outside it.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        isPresented = false
    }

    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        isPresented = false
    }
}

#endif
