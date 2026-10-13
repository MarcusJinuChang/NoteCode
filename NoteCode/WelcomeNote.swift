//
//  WelcomeNote.swift
//  NoteCode
//
//  The note a first launch opens with, and the note-making the "+" button and
//  Settings share. Pure model code, so the rules can be tested without a view.
//

import Foundation
import SwiftData

/// Settings › Notes › New Notes: which way up the "+" button's tap makes a
/// note's pages.
///
/// Per device, like the view mode. It only picks the orientation of notes
/// made from now on: an existing note keeps its own, since changing it would
/// re-wrap the text and move every line out from under its ink.
nonisolated enum NewNotes {
    static let defaultsKey = "newNoteOrientation"

    /// The stored choice, or portrait where nothing valid is stored.
    static func orientation(in defaults: UserDefaults = .standard) -> PageOrientation {
        defaults.string(forKey: defaultsKey).flatMap(PageOrientation.init(rawValue:)) ?? .default
    }

    /// The folder the "+" button files a note in: the open note's, so adding
    /// notes while working through a class's folder keeps them together. Nil,
    /// the top of the list, when no note is open or the open one is unfiled.
    @MainActor
    static func folder(whileViewing page: Page?) -> Folder? {
        page?.folder
    }
}

extension Page {
    /// Makes a note, files it in `folder` if given, and inserts it.
    ///
    /// One path for the "+" button's tap, its menu and the folder menu, so
    /// they can't disagree about what a new note is.
    @discardableResult
    static func create(
        orientation: PageOrientation,
        in folder: Folder? = nil,
        context: ModelContext
    ) -> Page {
        let page = Page()
        page.orientation = orientation
        context.insert(page)
        page.folder = folder
        return page
    }
}

/// The "Welcome to NoteCode" note: a short tour that is itself a note, so it
/// shows the things it describes.
///
/// Text only. A seeded drawing would mean shipping `PaperMarkup` data in the
/// app, and the tour's ink paragraph says what to do instead.
nonisolated enum WelcomeNote {
    static let title = "Welcome to NoteCode"

    /// Whether a first launch has already had its chance to make the note.
    /// Set the first time it's checked, whether or not a note was made, and
    /// never cleared: deleting the note must not bring it back.
    static let madeKey = "welcomeNoteMade"

    static let content = """
    Type here like any note. Headings, **bold**, lists and `inline code` come from the bar below, or from Markdown as you type.

    ## Code

    Three backticks and a language start a code block. Run opens it in a free online compiler; nothing runs on the iPad. Copy puts it on the clipboard.

    ```python
    def greet(name):
        return f"Hello, {name}!"

    print(greet("CS133"))
    ```

    ## Ink

    Tap the pencil in the bar to draw on the page. The Pencil always draws; a finger draws too, or scrolls, as the hand button says. Ink stays on the words it was drawn over.

    ## Pages

    Notes are Letter pages. ••• › View shows them seamless, compressed or as printed sheets, and Share makes a PDF.
    """

    /// Makes the note, as a new one each time. This is what Settings › Help
    /// and About › Welcome Note asks for, and what the empty list offers.
    ///
    /// The new note's dates are its own: nothing else is touched, so asking
    /// for it doesn't reorder the list by moving another note's date.
    @discardableResult
    @MainActor
    static func make(in context: ModelContext, orientation: PageOrientation = .portrait) -> Page {
        let page = Page(title: title, content: content)
        page.orientation = orientation
        context.insert(page)
        return page
    }

    /// Makes the note on a device's first launch, once.
    ///
    /// "First launch" is decided by the flag, and by the store being empty: a
    /// build that updates over notes already there isn't a first launch, and
    /// shouldn't have a tour dropped into a semester of coursework. The flag
    /// is set either way, so a reader who deletes every note, welcome included,
    /// isn't given it back at the next launch.
    ///
    /// - Returns: the note, or `nil` if it wasn't made.
    @discardableResult
    @MainActor
    static func makeOnFirstLaunch(
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) -> Page? {
        guard !defaults.bool(forKey: madeKey) else { return nil }
        defaults.set(true, forKey: madeKey)

        let noteCount = (try? context.fetchCount(FetchDescriptor<Page>())) ?? 0
        let folderCount = (try? context.fetchCount(FetchDescriptor<Folder>())) ?? 0
        guard noteCount == 0, folderCount == 0 else { return nil }
        return make(in: context)
    }
}
