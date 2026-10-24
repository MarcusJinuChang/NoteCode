//
//  NoteListFirstRunTests.swift
//  NoteCodeTests
//
//  Phase 8: what the "+" button's tap makes, the Welcome note and the flag
//  that says it has had its turn, and the pieces of the list that are pure.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import NoteCode

@Suite("New notes and the Welcome note")
@MainActor
struct NoteListFirstRunTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    /// A defaults of its own, so a test can't read what another wrote or the
    /// simulator's real settings.
    private func freshDefaults() -> UserDefaults {
        let name = "NoteListFirstRunTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func count<T: PersistentModel>(_ type: T.Type) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    // MARK: New Notes

    @Test("New notes are portrait until a device chooses, and a bad value is ignored")
    func newNotesDefault() {
        let defaults = freshDefaults()
        #expect(NewNotes.orientation(in: defaults) == .portrait)

        defaults.set("sideways", forKey: NewNotes.defaultsKey)
        #expect(NewNotes.orientation(in: defaults) == .portrait)
    }

    @Test("The + button's tap follows the stored choice, under the key the setting writes")
    func newNotesFollowsSetting() {
        #expect(NewNotes.defaultsKey == "newNoteOrientation")
        let defaults = freshDefaults()

        defaults.set(PageOrientation.landscape.rawValue, forKey: NewNotes.defaultsKey)
        let page = Page.create(orientation: NewNotes.orientation(in: defaults), context: context)

        #expect(page.orientation == .landscape)
        #expect(page.folder == nil)
    }

    @Test("A new note is filed in the open note's folder, and at the top without one")
    func newNoteFolder() {
        let folder = Folder(name: "CS133")
        context.insert(folder)
        let filed = Page.create(orientation: .portrait, in: folder, context: context)
        let loose = Page.create(orientation: .portrait, context: context)

        #expect(NewNotes.folder(whileViewing: filed) == folder)
        #expect(NewNotes.folder(whileViewing: loose) == nil)
        #expect(NewNotes.folder(whileViewing: nil) == nil)

        let next = Page.create(
            orientation: .landscape,
            in: NewNotes.folder(whileViewing: filed),
            context: context
        )
        #expect(next.folder == folder)
        #expect(Set(folder.pages ?? []) == [filed, next])
        #expect(next.orientation == .landscape)
    }

    @Test("Open Note After Creating is off until chosen, and off leaves the open note open")
    func openAfterCreating() {
        let defaults = freshDefaults()
        #expect(defaults.object(forKey: NewNotes.opensAfterCreatingKey) == nil)
        #expect(NewNotes.opensAfterCreatingByDefault == false)

        let open = Page.create(orientation: .portrait, context: context)
        let made = Page.create(orientation: .portrait, context: context)

        #expect(NewNotes.selection(afterCreating: made, current: open, opens: false) == open)
        #expect(NewNotes.selection(afterCreating: made, current: nil, opens: false) == nil)
        #expect(NewNotes.selection(afterCreating: made, current: open, opens: true) == made)
    }

    @Test("The toast names the folder a note was added to")
    func addedMessage() {
        let folder = Folder(name: "CS133")
        context.insert(folder)
        #expect(NewNotes.addedMessage(in: folder) == "Note added to CS133")
        #expect(NewNotes.addedMessage(in: nil) == "Note added")
    }

    // MARK: Welcome note

    @Test("The first launch makes the Welcome note, with the brief's title and text")
    func firstLaunchMakesIt() throws {
        let defaults = freshDefaults()

        let page = try #require(WelcomeNote.makeOnFirstLaunch(in: context, defaults: defaults))

        #expect(page.title == "Welcome to NoteCode")
        #expect(page.content.hasPrefix("Type here like any note."))
        #expect(page.content.contains("## Code\n"))
        #expect(page.content.contains("```python\ndef greet(name):\n    return f\"Hello, {name}!\"\n"))
        #expect(page.content.hasSuffix("and Share makes a PDF."))
        #expect(page.drawingData.isEmpty, "no seeded ink")
        #expect(count(Page.self) == 1)
    }

    @Test("It is made once: deleting it doesn't bring it back")
    func madeOnce() throws {
        let defaults = freshDefaults()
        let page = try #require(WelcomeNote.makeOnFirstLaunch(in: context, defaults: defaults))

        try Page.delete([page], from: context)
        let again = WelcomeNote.makeOnFirstLaunch(in: context, defaults: defaults)

        #expect(again == nil)
        #expect(count(Page.self) == 0)
    }

    @Test("A store that already holds a note isn't a first launch, but uses up the flag")
    func notesAlreadyThere() {
        let defaults = freshDefaults()
        context.insert(Page(title: "Lecture 1"))

        #expect(WelcomeNote.makeOnFirstLaunch(in: context, defaults: defaults) == nil)
        #expect(defaults.bool(forKey: WelcomeNote.madeKey))
        #expect(count(Page.self) == 1)
    }

    @Test("Nor is a store that holds only a folder")
    func foldersAlreadyThere() {
        context.insert(Folder(name: "CS133"))

        #expect(WelcomeNote.makeOnFirstLaunch(in: context, defaults: freshDefaults()) == nil)
        #expect(count(Page.self) == 0)
    }

    @Test("Asking for it again makes a new note each time")
    func askedFor() {
        let defaults = freshDefaults()
        WelcomeNote.makeOnFirstLaunch(in: context, defaults: defaults)

        let second = WelcomeNote.make(in: context)
        let third = WelcomeNote.make(in: context)

        #expect(second !== third)
        #expect(count(Page.self) == 3)
        #expect(second.title == WelcomeNote.title)
    }

    @Test("Making it leaves every other note's dates alone")
    func otherNotesKeepTheirDates() {
        let long = Date(timeIntervalSince1970: 86_400)
        let lecture = Page(title: "Lecture 1", createdAt: long)
        lecture.modifiedAt = long
        context.insert(lecture)

        WelcomeNote.make(in: context)
        WelcomeNote.make(in: context)

        #expect(lecture.modifiedAt == long)
        #expect(lecture.createdAt == long)
    }

    @Test("The flag's name is pinned")
    func flagKey() {
        #expect(WelcomeNote.madeKey == "welcomeNoteMade")
    }

    // MARK: Pure pieces of the list

    @Test("A note is renamed to what was typed, trimmed, and never to nothing")
    func renamedTitle() {
        #expect(Page.title(fromTyped: "  Heaps \n") == "Heaps")
        #expect(Page.title(fromTyped: "   ") == "Untitled")
        #expect(Page.title(fromTyped: "") == "Untitled")
    }

    @Test("The selected row's tint is 18% of the accent in light and 22% in dark")
    func selectionTint() {
        #expect(RowSelectionTint.opacity(isDark: false) == 0.18)
        #expect(RowSelectionTint.opacity(isDark: true) == 0.22)
    }
}
