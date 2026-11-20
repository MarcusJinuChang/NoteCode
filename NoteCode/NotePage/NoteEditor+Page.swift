//
//  NoteEditor+Page.swift
//  NoteCode
//
//  What the editor asks of the page around the text view (`PageView`):
//  its pages, the size an insert is measured against, its ink taken in,
//  the PDF and printing, Find, the outline and scrolling to a line.
//

#if canImport(UIKit)

import UIKit

extension NoteEditor {

    // MARK: Pages

    /// How many pages the open note runs to, for its info. Read when asked
    /// rather than observed: the count changes as the note is typed, and
    /// nothing on screen shows it.
    var pageCount: Int? {
        page?.pageCount
    }

    /// One more page at the end of the note. Not an edit: nothing goes on
    /// the text's undo stack and the note's date stays.
    func addPage() {
        page?.addPage()
    }

    /// The page's width in points, which a photo's size and resolution are
    /// measured against. `nil` until the page exists.
    var insertionPageWidth: CGFloat? {
        page?.pageLayout.pageSize.width
    }

    /// The tallest a photo is first shown. See `PageView.insertionMaxHeight`.
    var insertionMaxHeight: CGFloat {
        page?.insertionMaxHeight ?? 0
    }

    /// Takes in what the reader drew that is still on its way into the
    /// note's ink (`PageView.commitInk`), so a save made now has it.
    func commitInk() {
        page?.commitInk()
    }

    /// The open note as a PDF, a page for each of its pages, ink and all.
    /// `nil` until the page exists.
    ///
    /// The ink is the page's own copy, so strokes drawn moments ago and not
    /// yet saved are on the paper too.
    func pdf(title: String) async -> Data? {
        guard let page else { return nil }
        return await NotePDF.render(NotePDF.Note(
            title: title,
            text: page.textView.text ?? "",
            ink: page.ink,
            orientation: page.pageLayout.orientation,
            pageCount: page.pageCount,
            minimumPages: page.minimumPageCount,
            typography: typography,
            settings: NotePDF.Settings(rendersMarkdown: rendersMarkdown, lineNumbers: showsLineNumbers)
        ))
    }

    /// The note's text as it is now, which is its Markdown: the text storage
    /// holds `#` and `**` as typed (hiding them is layout only,
    /// `MarkdownLayout`). `nil` until the text view exists.
    ///
    /// Read from the text view rather than the model, as the PDF is, so the
    /// last keystrokes are in it.
    var currentText: String? {
        textView?.text
    }

    /// ⌘P: the system's print dialog for the note's PDF.
    ///
    /// The same PDF the share button makes, so what prints is what Save to
    /// Files would keep; the share sheet's Print row opens this same dialog.
    func printNote(title: String) async {
        guard UIPrintInteractionController.isPrintingAvailable,
              let data = await pdf(title: title)
        else { return }

        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = title

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true)
    }

    // MARK: Find

    /// Shows the find bar for the note, as ⌘F does.
    ///
    /// In text mode, since finding means selecting the matches, and the text
    /// takes no selection while ink has the page. Coming from ink, the
    /// reader is going to the text anyway.
    func showFind() {
        setMode(.text)
        textView?.findInteraction?.presentFindNavigator(showingReplace: false)
    }


    // MARK: Outline

    /// The note's headings, and which one the reader is under: the last at or
    /// above the line at the top of the page. Worked out when the popover
    /// opens, from the text as it is.
    func outline() -> (entries: [NoteOutline.Entry], current: Int?) {
        let entries = NoteOutline.entries(in: (textView?.text ?? "").nativeUTF8)
        let top = page?.topLineCharacter() ?? 0
        return (entries, NoteOutline.currentIndex(in: entries, atCharacter: top))
    }

    /// An outline tap: the heading's line at the top of the page.
    func scroll(toHeading entry: NoteOutline.Entry) {
        page?.scroll(toLineAt: entry.location)
    }

    /// The line at a UTF-16 offset at the top of the page: the Run panel's
    /// chips scroll to a block's opening fence.
    func scroll(toLineAt location: Int) {
        page?.scroll(toLineAt: location)
    }
}

#endif
