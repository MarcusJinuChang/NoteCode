//
//  NotePDF.swift
//  NoteCode
//
//  A note on paper: its pages drawn into a PDF, to print or share.
//

#if canImport(UIKit)

import PaperKit
import SwiftUI
import UIKit

/// Draws a note's pages into a PDF, each one exactly the sheet print layout
/// shows: text, code panels, syntax colours and ink.
///
/// **Laid out afresh, not read off the screen.** TextKit 2 lays out only
/// what's on screen, so the page being viewed has nothing to draw for the
/// pages around it. This lays the whole note out again in a text view of its
/// own, set up by `DocumentTextView.makeConfiguredTextView` like the editor's,
/// in print layout: every mode puts the same lines on the same pages, so the
/// PDF's pages are the note's pages whatever mode the reader is in.
///
/// **Always light.** Paper is white. The text view is forced light, so syntax
/// colours come from the light theme, and drawing runs under a light trait
/// collection, so `.label` and the code panels resolve to their light
/// colours even when the device is dark.
///
/// **Text stays text.** TextKit draws it straight into the PDF's context,
/// so it can be searched and selected and is sharp at any zoom. Ink goes
/// on as a picture at print resolution, since PaperKit draws only into
/// bitmaps — see `drawInk`.
enum NotePDF {

    /// What's needed to draw a note.
    struct Note {
        var title: String
        var text: String
        /// In print layout's coordinates, as `PageView.ink` and storage keep it.
        var ink: PaperMarkup?
        var orientation: PageOrientation
        /// The pages the open note runs to, if known. Only a starting point:
        /// laying out with the right number of page breaks the first time
        /// saves laying the whole note out again.
        var pageCount = 1
    }

    /// PDF points per page point. A page 816 wide prints 612 wide: US
    /// Letter at 72 points to the inch.
    static let pointsPerPagePoint: CGFloat = 72 / PageLayout.unitsPerInch

    /// One PDF page per page of the note.
    static func render(_ note: Note) async -> Data {
        let printed = await PrintedNote(text: note.text, orientation: note.orientation)
        let ink = note.ink.flatMap { $0.subelements.isEmpty ? nil : $0 }
        let pageCount = printed.paginate(inkBottom: ink?.contentsRenderFrame.maxY, startingAt: note.pageCount)
        let layout = printed.layout

        let scale = pointsPerPagePoint
        var mediaBox = CGRect(
            x: 0, y: 0,
            width: layout.pageSize.width * scale,
            height: layout.pageSize.height * scale
        )
        let info = [
            kCGPDFContextTitle as String: note.title,
            kCGPDFContextCreator as String: "NoteCode",
        ] as CFDictionary

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info)
        else { return Data() }

        let paragraphs = printed.paragraphsByPage(pageCount: pageCount)
        for index in 0..<pageCount {
            let sheet = layout.sheet(ofPage: index)
            context.beginPDFPage(nil)
            context.saveGState()
            // UIKit's way up, in page points: origin at the sheet's top left.
            context.translateBy(x: 0, y: mediaBox.height)
            context.scaleBy(x: scale, y: -scale)

            printed.draw(paragraphs[index], onSheet: sheet, in: context)
            if let ink {
                await drawInk(ink, onSheet: sheet, region: layout.inkRegion(ofPage: index), in: context)
            }

            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// Pixels per page point for ink on paper: 288 dots per inch.
    static let inkPixelsPerPagePoint: CGFloat = 3

    /// Draws the ink on one sheet, into a context whose origin is the
    /// sheet's top left, in page points.
    ///
    /// **As a picture, at print resolution.** PaperKit draws only into a
    /// bitmap context. Handed the PDF's own context, it drew nothing and
    /// logged "CGBitmapContextGetColorSpace: invalid context" (simulator,
    /// 4 October). So the ink is drawn into a bitmap at 288 dots per inch,
    /// cropped to where the sheet has ink, and that goes on the page.
    ///
    /// Only the sheet's own elements, moved to the sheet's origin, in a
    /// markup the sheet's size. Drawing all of a long note's ink for every
    /// page would cost as many times over as there are pages.
    ///
    /// Added one at a time with `updateOrAppend`, the way `PageView` takes
    /// ink from the canvas. Assigning a set to a new markup's `subelements`
    /// keeps none of it: a markup only updates the elements it already has
    /// from an assigned set (probe on the simulator, 4 October), and the
    /// PDF's ink came out blank.
    ///
    /// Only inside the page's ink region (`PageLayout.inkRegion`), as on
    /// screen: a stroke bent across a page break lies stretched over the
    /// margins and the gap, where `PageCoverView` hides it.
    private static func drawInk(_ ink: PaperMarkup, onSheet sheet: CGRect, region: CGRect, in context: CGContext) async {
        let page = CGRect(origin: .zero, size: sheet.size)
        let toSheet = CGAffineTransform(translationX: -sheet.minX, y: -sheet.minY)
        let shown = region.intersection(sheet).applying(toSheet)

        var markup = PaperMarkup(bounds: page)
        var inked = CGRect.null
        for element in ink.subelements where element.renderFrame.intersects(region) {
            var element = element
            element.applyTransform(toSheet)
            inked = inked.union(element.renderFrame)
            markup.subelements.updateOrAppend(element)
        }
        // A little room around the frames, for a stroke's soft edge.
        let area = inked.insetBy(dx: -4, dy: -4).intersection(page).integral
        guard !area.isNull, !area.isEmpty, area.intersects(shown) else { return }

        guard let image = await bitmap(of: markup, in: page, cropping: area) else { return }

        context.saveGState()
        context.clip(to: shown)
        UIGraphicsPushContext(context)
        // UIKit draws the image the right way up in a context flipped the
        // way this one is.
        UIImage(cgImage: image).draw(in: area)
        UIGraphicsPopContext()
        context.restoreGState()
    }

    /// The part of `markup` inside `area`, drawn at print resolution, with
    /// a transparent background.
    ///
    /// - Parameter page: the frame the markup is drawn into, in page points.
    private static func bitmap(of markup: PaperMarkup, in page: CGRect, cropping area: CGRect) async -> CGImage? {
        let scale = inkPixelsPerPagePoint
        let width = Int((area.width * scale).rounded(.up))
        let height = Int((area.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // UIKit's way up, in page points, with `area`'s corner at the origin.
        //
        // PaperKit draws the markup's coordinates straight into the
        // context's, through its transform: into an unflipped bitmap a
        // stroke 300pt down the page came out 300pt up from the bottom, and
        // a frame three times the page's size didn't scale it, where the
        // transform did (probe, 4 October).
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -area.minX, y: -area.minY)

        await markup.draw(in: context, frame: page)
        return context.makeImage()
    }

    // MARK: Files

    /// A name for the shared file: the note's title, without the characters
    /// a file name can't hold.
    static func fileName(for title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Untitled" : cleaned) + ".pdf"
    }

    /// Writes the PDF where the share sheet can hand it on, named for the
    /// note. Replaces an earlier export of the same title.
    static func write(_ data: Data, title: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Shared PDFs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName(for: title), directoryHint: .notDirectory)
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - The note, laid out for paper

/// A note laid out in print layout, off screen, ready to draw a page at a
/// time.
@MainActor
final class PrintedNote {

    let layout: PageLayout
    let textView: DocumentUITextView

    /// Styles the text and picks each paragraph's fragment, the way it does
    /// for the editor, so code blocks get their panels and colours.
    private let coordinator: DocumentTextView.Coordinator

    init(text: String, orientation: PageOrientation) async {
        layout = PageLayout(orientation: orientation, mode: .print)
        coordinator = DocumentTextView.Coordinator(text: .constant(text))
        textView = DocumentTextView.makeConfiguredTextView()

        // Paper is white, so code takes the light theme's colours.
        textView.overrideUserInterfaceStyle = .light
        textView.isEditable = false
        textView.frame = CGRect(origin: .zero, size: layout.pageSize)
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.size = CGSize(width: layout.textWidth, height: .greatestFiniteMagnitude)
        textView.textContainerInset = UIEdgeInsets(
            top: layout.firstBodyTop,
            left: PageLayout.margin,
            bottom: layout.trailingSpace,
            right: PageLayout.margin
        )

        textView.text = text
        textView.textLayoutManager?.delegate = coordinator
        coordinator.observeEdits(of: textView)
        coordinator.restyle(textView)
        await coordinator.highlightingFinished()
    }

    /// Sets the page breaks and lays the whole note out, returning how many
    /// pages it fills.
    ///
    /// Breaks are set for at least as many pages as the text needs: a break
    /// below the last line pushes nothing, and a missing one lets text run
    /// on past where a page should end. Starting from the open note's count,
    /// one pass is usually enough.
    ///
    /// - Parameter inkBottom: the lowest ink, in print coordinates. Ink can
    ///   reach past the text and make more pages.
    func paginate(inkBottom: CGFloat?, startingAt hint: Int) -> Int {
        guard let manager = textView.textLayoutManager else { return 1 }

        var banded = max(hint, 1)
        var count = banded
        // Each pass adds breaks only where the last one found text running
        // past them, so this converges in two or three passes from a count
        // of one; the limit is a guard, not an expectation.
        for _ in 0..<10 {
            textView.textContainer.exclusionPaths = layout
                .exclusionBands(pageCount: banded, containerTop: textView.textContainerInset.top)
                .map { UIBezierPath(rect: $0) }
            manager.ensureLayout(for: manager.documentRange)

            count = layout.pageCount(textBottom: textBottom(), inkBottom: inkBottom)
            if count <= banded { break }
            banded = count
        }
        return count
    }

    /// The bottom of the last line, in note coordinates.
    private func textBottom() -> CGFloat {
        guard let manager = textView.textLayoutManager else { return 0 }
        var bottom: CGFloat = 0
        manager.enumerateTextLayoutFragments(from: manager.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { fragment in
            bottom = fragment.layoutFragmentFrame.maxY
            return false
        }
        return bottom + textView.textContainerInset.top
    }

    /// A paragraph's lines on one page.
    struct Paragraph {
        let fragment: NSTextLayoutFragment
        let lines: [NSTextLineFragment]
    }

    /// Every laid-out paragraph, filed under each page its lines are on.
    ///
    /// A paragraph whose later lines were pushed past a page break keeps a
    /// frame that spans the break, so it's filed under both pages, each with
    /// only its own lines. Drawing the whole paragraph on both, clipped to
    /// the sheet, would look the same, but would put each split paragraph's
    /// text in the PDF twice, once off the page, where a search or a copy
    /// still finds it.
    func paragraphsByPage(pageCount: Int) -> [[Paragraph]] {
        var pages = Array(repeating: [Paragraph](), count: max(pageCount, 1))
        guard let manager = textView.textLayoutManager else { return pages }

        let top = textView.textContainerInset.top
        let last = pages.count - 1
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            let frameTop = fragment.layoutFragmentFrame.minY + top
            var lines: [Int: [NSTextLineFragment]] = [:]
            for line in fragment.textLineFragments {
                let index = min(layout.pageIndex(atY: frameTop + line.typographicBounds.minY), last)
                lines[index, default: []].append(line)
            }
            for (index, onPage) in lines.sorted(by: { $0.key < $1.key }) {
                pages[index].append(Paragraph(fragment: fragment, lines: onPage))
            }
            return true
        }
        return pages
    }

    /// Draws one sheet's text into a context whose origin is the sheet's top
    /// left, in page points.
    func draw(_ paragraphs: [Paragraph], onSheet sheet: CGRect, in context: CGContext) {
        let inset = textView.textContainerInset

        context.saveGState()
        context.clip(to: CGRect(origin: .zero, size: sheet.size))
        // From the text container's coordinates to the sheet's.
        context.translateBy(x: inset.left - sheet.minX, y: inset.top - sheet.minY)

        UIGraphicsPushContext(context)
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            // Bottom up, so each line ends up in front of the one below, as
            // TextKit stacks them on screen: a code line's panel reaches up
            // under the line above, and drawn last it would cover that
            // line's descenders.
            for paragraph in paragraphs.reversed() {
                let origin = paragraph.fragment.layoutFragmentFrame.origin
                // A panel split at a page break draws a run on each page;
                // the clip keeps the other page's run off this one.
                let code = paragraph.fragment as? CodeBlockLayoutFragment
                code?.drawPanel(at: origin, in: context)
                // Paper has no caret, so no block is being edited: a code
                // block's fence lines are never printed. They keep their
                // lines, as on screen, and so does everything below them.
                if code?.isFence == true { continue }
                for line in paragraph.lines {
                    let bounds = line.typographicBounds
                    line.draw(at: CGPoint(x: origin.x + bounds.minX, y: origin.y + bounds.minY), in: context)
                }
            }
        }
        UIGraphicsPopContext()

        context.restoreGState()
    }
}

#endif
