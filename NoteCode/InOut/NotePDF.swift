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
/// **Always light.** Paper is white. Code is coloured from the light theme
/// (the coordinator's `pinnedAppearance`), and drawing runs under a light
/// trait collection, so `.label` and the code panels resolve to their light
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
        /// The pages the note was given (`Page.minimumPageCount`). Laid out
        /// with them, but trailing pages with no text and no ink are left
        /// out of the PDF (see `render`): they exist only because pages were
        /// added as the reader wrote near the end.
        var minimumPages = 1
        /// Whether the note's Markdown markers take no room.
        var rendersMarkdown = false
        /// Whether code is numbered in the margin, as on screen (Settings › Code).
        var lineNumbers = false
        /// The note's own text size (`Page.textSize`): paper breaks its lines
        /// where the screen does, or ink would print off its words.
        var typography = NoteTypography.standard
    }

    /// What the reader's settings change about the paper. One value, so the
    /// note's PDF and Export All's cannot read them differently.
    struct Settings: Equatable {
        /// Whether the note's Markdown markers take no room, as on screen.
        var rendersMarkdown: Bool
        /// Whether code is numbered in the margin (Settings › Code).
        var lineNumbers: Bool

        /// Read from the stored settings through the key table
        /// (`SettingKeys`), for a PDF made with no page open. There is no
        /// text view to ask whether markers are hidden, so that is passed:
        /// Export All lays them out at zero width, as an open note does.
        static func stored(rendersMarkdown: Bool = true, in store: UserDefaults = .standard) -> Settings {
            let key = SettingKeys.Code.lineNumbers
            return Settings(
                rendersMarkdown: rendersMarkdown,
                lineNumbers: store.object(forKey: key.name) as? Bool ?? key.defaultValue
            )
        }
    }

    /// PDF points per page point. A page 816 wide prints 612 wide: US
    /// Letter at 72 points to the inch.
    static let pointsPerPagePoint: CGFloat = 72 / PageLayout.unitsPerInch

    /// One PDF page per page of the note, up to the last one with text or ink.
    ///
    /// **Trailing blank pages are left out.** Pages are added automatically
    /// while a reader writes or draws near the end, which grows
    /// `Page.minimumPageCount`, so a note can run to pages nothing is on. A
    /// blank page between two with content stays, since a reader may have
    /// left the room on purpose. A note with nothing on it prints one page.
    /// Ink counts wherever it is on the sheet, margins included. Only the
    /// PDF is trimmed; the note and its page count are untouched.
    static func render(_ note: Note) async -> Data {
        let printed = await PrintedNote(
            text: note.text,
            orientation: note.orientation,
            rendersMarkdown: note.rendersMarkdown,
            lineNumbers: note.lineNumbers,
            typography: note.typography
        )
        let ink = note.ink.flatMap { $0.subelements.isEmpty ? nil : $0 }
        let pageCount = printed.paginate(inkBottom: ink?.contentsRenderFrame.maxY, startingAt: note.pageCount, minimum: note.minimumPages)
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
        // One walk of the ink: overflow pieces count as ink on their page for
        // deciding which pages to keep, and are dropped before drawing.
        let inkBySheet = ink.map { sheetsInk($0, layout: layout, pageCount: pageCount, includingOverflow: true) }
        let printedPages = lastPageWithContent(paragraphs: paragraphs, ink: inkBySheet) + 1
        for index in 0..<printedPages {
            let sheet = layout.sheet(ofPage: index)
            context.beginPDFPage(nil)
            context.saveGState()
            // UIKit's way up, in page points: origin at the sheet's top left.
            context.translateBy(x: 0, y: mediaBox.height)
            context.scaleBy(x: scale, y: -scale)

            printed.draw(paragraphs[index], onSheet: sheet, in: context)
            if let elements = inkBySheet?[index].filter({ !InkPages.isOverflow($0) }), !elements.isEmpty {
                await drawInk(elements, onSheet: sheet, in: context)
            }

            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// The index of the last page that has text or ink, or 0 if none has.
    /// Text counts when a line on the page holds anything but whitespace.
    static func lastPageWithContent(paragraphs: [[PrintedNote.Paragraph]], ink: [[any Markup]]?) -> Int {
        for index in stride(from: paragraphs.count - 1, to: 0, by: -1) {
            if let ink, index < ink.count, !ink[index].isEmpty { return index }
            let hasText = paragraphs[index].contains { paragraph in
                paragraph.lines.contains { line in
                    let string = line.attributedString.string as NSString
                    let range = NSIntersectionRange(line.characterRange, NSRange(location: 0, length: string.length))
                    return string.substring(with: range).contains { !$0.isWhitespace }
                }
            }
            if hasText { return index }
        }
        return 0
    }

    /// Each sheet's ink: the elements whose frame reaches it, from one walk
    /// of the note's ink. Overflow doesn't print, as print layout doesn't
    /// show it: a stroke drawn across a page break stops at the edge of the
    /// page it was started on.
    ///
    /// - Parameter includingOverflow: also files the overflow pieces, which
    ///   don't print but are ink on the page they reach: that is what keeps
    ///   a page from being left out as blank.
    static func sheetsInk(_ ink: PaperMarkup, layout: PageLayout, pageCount: Int, includingOverflow: Bool = false) -> [[any Markup]] {
        var sheets = Array(repeating: [any Markup](), count: pageCount)
        guard pageCount > 0 else { return sheets }
        for element in ink.subelements where includingOverflow || !InkPages.isOverflow(element) {
            let frame = element.renderFrame
            let first = min(layout.pageIndex(atY: frame.minY), pageCount - 1)
            let last = min(layout.pageIndex(atY: frame.maxY), pageCount - 1)
            for index in first...max(first, last) where frame.intersects(layout.sheet(ofPage: index)) {
                sheets[index].append(element)
            }
        }
        return sheets
    }

    /// Pixels per page point for ink on paper: 288 dots per inch.
    nonisolated static let inkPixelsPerPagePoint: CGFloat = 3

    /// Draws the ink on one sheet, into a context whose origin is the
    /// sheet's top left, in page points.
    ///
    /// **As a picture, at print resolution.** PaperKit draws only into a
    /// bitmap context. Handed the PDF's own context, it drew nothing and
    /// logged "CGBitmapContextGetColorSpace: invalid context" (simulator,
    /// 4 October). So the ink is drawn into a bitmap at 288 dots per inch,
    /// cropped to where the sheet has ink, and that goes on the page.
    ///
    /// Only the sheet's own elements (`sheetsInk`), moved to the sheet's
    /// origin, in a markup the sheet's size. Drawing all of a long note's
    /// ink for every page would cost as many times over as there are pages.
    ///
    /// Added through the new markup's `subelements`, in one append.
    /// Assigning a set to a new markup's `subelements` keeps none of it: a
    /// markup only updates the elements it already has from an assigned set
    /// (probe on the simulator, 4 October), and the PDF's ink came out
    /// blank. Added one at a time, each costs what the set's `count` does,
    /// and a note of 2,000 strokes took 7 seconds to print (10 October).
    ///
    /// - Parameter pixelsPerPagePoint: the bitmap's resolution. The PDF draws
    ///   at print resolution; a thumbnail asks for the few pixels it will show,
    ///   since a sheet's worth at 288 dots per inch is 31MB.
    static func drawInk(
        _ elements: [any Markup],
        onSheet sheet: CGRect,
        in context: CGContext,
        pixelsPerPagePoint: CGFloat = inkPixelsPerPagePoint
    ) async {
        let page = CGRect(origin: .zero, size: sheet.size)
        let toSheet = CGAffineTransform(translationX: -sheet.minX, y: -sheet.minY)

        var markup = PaperMarkup(bounds: page)
        var inked = CGRect.null
        var placed: [any Markup] = []
        for element in elements {
            var element = element
            element.applyTransform(toSheet)
            inked = inked.union(element.renderFrame)
            placed.append(element)
        }
        markup.subelements.append(contentsOf: placed)
        // A little room around the frames, for a stroke's soft edge.
        let area = inked.insetBy(dx: -4, dy: -4).intersection(page).integral
        guard !area.isNull, !area.isEmpty else { return }

        guard let image = await bitmap(of: markup, in: page, cropping: area, pixelsPerPagePoint: pixelsPerPagePoint) else { return }

        context.saveGState()
        context.clip(to: page)
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
    private static func bitmap(
        of markup: PaperMarkup,
        in page: CGRect,
        cropping area: CGRect,
        pixelsPerPagePoint scale: CGFloat
    ) async -> CGImage? {
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
    /// a file name can't hold (`NoteFileName`).
    static func fileName(for title: String) -> String {
        NoteFileName.fileName(for: title, extension: "pdf")
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

    /// Keeps each paragraph on one page.
    private lazy var paginator = PagePaginator(textView: textView)

    init(
        text: String,
        orientation: PageOrientation,
        rendersMarkdown: Bool = false,
        lineNumbers: Bool = false,
        typography: NoteTypography = .standard
    ) async {
        layout = PageLayout(orientation: orientation, mode: .print)
        coordinator = DocumentTextView.Coordinator(text: .constant(text))
        textView = DocumentTextView.makeConfiguredTextView(typography: typography)

        // Paper is white, so code takes the light theme's colours. Told to
        // the coordinator, not set on the view: a view in no window keeps
        // the scene's appearance whatever its own override says.
        coordinator.pinnedAppearance = .light
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
        // A rendered note's markers take no room on screen, so they take none
        // on paper: the same lines on the same pages, which is what lets ink
        // print where it was drawn.
        coordinator.setRendersMarkdown(rendersMarkdown, in: textView)
        coordinator.setLineNumbers(lineNumbers, in: textView)
        // The note's own size, before the first styling: the coordinator is
        // this printed note's alone, so it can't pick up another note's.
        coordinator.setTypography(typography, in: textView)
        coordinator.restyle(textView)
        await coordinator.highlightingFinished()
    }

    /// Sets the page breaks and lays the whole note out, returning how many
    /// pages it fills.
    ///
    /// A break is the paragraph below it pushed to the next page
    /// (`PagePaginator`), worked out for the whole note here rather than as
    /// far as a reader has scrolled. Pushing one paragraph moves those below
    /// it, so a pass can change more; it settles in a few.
    ///
    /// - Parameter inkBottom: the lowest ink, in print coordinates. Ink can
    ///   reach past the text and make more pages.
    /// - Parameter hint: unused since breaks stopped being exclusion paths,
    ///   one per page, which had to be set for as many pages as the text
    ///   needed. Kept so the callers read as they did.
    func paginate(inkBottom: CGFloat?, startingAt hint: Int, minimum: Int = 1) -> Int {
        guard let manager = textView.textLayoutManager else { return 1 }

        manager.ensureLayout(for: manager.documentRange)
        for _ in 0..<(PagePaginator.passLimit + 2) {
            guard paginator.paginate(layout: layout) else { break }
            manager.ensureLayout(for: manager.documentRange)
        }
        return layout.pageCount(textBottom: textBottom(), inkBottom: inkBottom, minimum: minimum)
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
                // A line after a break in a tall paragraph starts where the
                // line above it ended; its glyphs are below the break.
                let index = min(layout.pageIndex(atY: frameTop + line.typographicBounds.minY + line.pageLineGap), last)
                lines[index, default: []].append(line)
            }
            for (index, onPage) in lines.sorted(by: { $0.key < $1.key }) {
                pages[index].append(Paragraph(fragment: fragment, lines: onPage))
            }
            return true
        }
        return pages
    }

    /// A line's formulas, drawn as vectors after the line (LaTeX, step 6,
    /// docs/design/latex.md › PDF). The line's own draw of the attachment is
    /// switched off first: `NSTextLineFragment.draw` is no safe way to draw
    /// one (measured: 15 dark pixels of a fraction), and two copies would
    /// show as a heavier formula.
    ///
    /// Blanked with an empty image, never nil: an attachment with no image
    /// and no contents draws TextKit's placeholder, a grey page with a
    /// folded corner, which printed behind every formula (device pass,
    /// export-4). An empty image draws nothing and puts no picture in the PDF.
    private func blankFormulaImages(on line: NSTextLineFragment) {
        let string = line.attributedString
        let range = NSIntersectionRange(line.characterRange, NSRange(location: 0, length: string.length))
        guard range.length > 0 else { return }
        string.enumerateAttribute(.attachment, in: range) { value, at, _ in
            guard string.attribute(FormulaAttachment.sourceKey, at: at.location, effectiveRange: nil) != nil else { return }
            (value as? NSTextAttachment)?.image = UIImage()
        }
    }

    /// - Parameter origin: the line's top left in the context.
    private func drawFormulas(on line: NSTextLineFragment, at origin: CGPoint, in context: CGContext) {
        let string = line.attributedString
        let range = NSIntersectionRange(line.characterRange, NSRange(location: 0, length: string.length))
        guard range.length > 0 else { return }
        let padding = textView.textContainer.lineFragmentPadding
        let room = textView.textContainer.size.width - 2 * padding
        string.enumerateAttribute(FormulaAttachment.sourceKey, in: range) { value, at, _ in
            guard let source = value as? FormulaAttachment.Source else { return }
            let x = origin.x + line.locationForCharacter(at: at.location).x
            // No page break's offset is ever in it: a tall paragraph with a
            // formula keeps exclusion paths (`PagePaginator.hasAttachment`).
            let lift = (string.attribute(.baselineOffset, at: at.location, effectiveRange: nil) as? CGFloat) ?? 0
            let baseline = origin.y + line.glyphOrigin.y - lift
            FormulaAttachment.drawVector(source, at: CGPoint(x: x, y: baseline), room: source.display ? room : nil, in: context)
        }
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
                // The header gets the language's name, as on screen.
                if let code, code.isFence {
                    if let first = code.textLineFragments.first, paragraph.lines.contains(where: { $0 === first }) {
                        code.drawHeaderLabel(at: origin, in: context)
                    }
                    continue
                }
                // A paragraph split by a page break is numbered on the page
                // its first line is on, once.
                if let code, let first = code.textLineFragments.first,
                   paragraph.lines.contains(where: { $0 === first }) {
                    code.drawLineNumber(at: origin, in: context)
                }
                for line in paragraph.lines {
                    let bounds = line.typographicBounds
                    blankFormulaImages(on: line)
                    line.draw(at: CGPoint(x: origin.x + bounds.minX, y: origin.y + bounds.minY), in: context)
                    code?.drawWrapMark(for: line, at: origin, in: context)
                    drawFormulas(on: line, at: CGPoint(x: origin.x + bounds.minX, y: origin.y + bounds.minY), in: context)
                }
                // A checklist's box, with its item's first line. Hashes in
                // the margin are never printed: nothing here draws them.
                if let checklist = paragraph.fragment as? ChecklistLayoutFragment,
                   let first = checklist.textLineFragments.first,
                   paragraph.lines.contains(where: { $0 === first }) {
                    checklist.drawBox(at: origin, in: context)
                }
                // A quote's bar beside the lines on this sheet, so a quote
                // split by a page break has a bar on each and none across the
                // gap; a rule's line with its one line, if that is here.
                (paragraph.fragment as? BlockquoteLayoutFragment)?.drawBars(of: paragraph.lines, at: origin, in: context)
                if let rule = paragraph.fragment as? RuleLayoutFragment,
                   let first = rule.textLineFragments.first,
                   paragraph.lines.contains(where: { $0 === first }) {
                    rule.drawRule(on: first, at: origin, in: context)
                }
            }
        }
        UIGraphicsPopContext()

        context.restoreGState()
    }
}

extension NotePDF.Note {
    /// A note to draw, with the settings applied. The one place the paper is
    /// assembled from a note's parts: the open note's PDF passes what is on
    /// screen now, Export All a stored page's.
    init(
        title: String,
        text: String,
        ink: PaperMarkup?,
        orientation: PageOrientation,
        pageCount: Int = 1,
        minimumPages: Int = 1,
        typography: NoteTypography,
        settings: NotePDF.Settings
    ) {
        self.init(
            title: title,
            text: text,
            ink: ink,
            orientation: orientation,
            pageCount: pageCount,
            minimumPages: minimumPages,
            rendersMarkdown: settings.rendersMarkdown,
            lineNumbers: settings.lineNumbers,
            typography: typography
        )
    }

    /// A stored note, as Export All draws it.
    init(page: Page, ink: PaperMarkup, settings: NotePDF.Settings) {
        self.init(
            title: page.displayTitle,
            text: page.content,
            ink: ink,
            orientation: page.orientation,
            minimumPages: page.minimumPageCount,
            typography: page.typography,
            settings: settings
        )
    }
}

#endif
