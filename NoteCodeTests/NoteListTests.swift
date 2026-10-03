//
//  NoteListTests.swift
//  NoteCodeTests
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

@Suite("The note list's sections and order")
@MainActor
struct NoteListTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private static func day(_ n: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(n) * 86_400)
    }

    /// A note made on day `created` and last changed on day `modified`.
    private func note(
        _ title: String,
        created: Int = 0,
        modified: Int? = nil,
        in folder: Folder? = nil,
        pinned: Bool = false
    ) -> Page {
        let page = Page(title: title, createdAt: Self.day(created))
        page.modifiedAt = Self.day(modified ?? created)
        context.insert(page)
        page.folder = folder
        page.isPinned = pinned
        return page
    }

    private func folder(_ name: String, pinned: Bool = false) -> Folder {
        let folder = Folder(name: name)
        context.insert(folder)
        folder.isPinned = pinned
        return folder
    }

    // MARK: Sections

    @Test("Folders are in name order, numbers compared as numbers")
    func folderOrder() {
        let folders = [folder("CS 133"), folder("algorithms"), folder("CS 9")]

        let sections = NoteListSections(pages: [], folders: folders)

        #expect(sections.folders.map(\.folder.name) == ["algorithms", "CS 9", "CS 133"])
        #expect(!sections.hasPinned)
    }

    @Test("Notes go under their folder, and the rest stay at the top")
    func notesAreGrouped() {
        let cs133 = folder("CS133")
        let empty = folder("Empty")
        let lecture1 = note("Lecture 1", created: 1, in: cs133)
        let loose = note("Loose", created: 2)
        let lecture2 = note("Lecture 2", created: 3, in: cs133)

        let sections = NoteListSections(pages: [lecture1, loose, lecture2], folders: [empty, cs133])

        #expect(sections.folders.map(\.folder.name) == ["CS133", "Empty"])
        #expect(sections.folders[0].notes.map(\.title) == ["Lecture 2", "Lecture 1"])
        #expect(sections.folders[1].notes.isEmpty)
        #expect(sections.unfiled.map(\.title) == ["Loose"])
    }

    @Test("Pinned notes and folders move to the top, and nothing is listed twice")
    func pinnedComeFirst() {
        let cs133 = folder("CS133")
        let algorithms = folder("Algorithms", pinned: true)
        let syllabus = note("Syllabus", created: 1, in: cs133, pinned: true)
        let lecture = note("Lecture 1", created: 2, in: cs133)
        let todo = note("To do", created: 3, pinned: true)
        let loose = note("Loose", created: 4)

        let sections = NoteListSections(
            pages: [syllabus, lecture, todo, loose],
            folders: [cs133, algorithms]
        )

        #expect(sections.hasPinned)
        #expect(sections.pinnedFolders.map(\.folder.name) == ["Algorithms"])
        #expect(sections.pinnedNotes.map(\.title) == ["To do", "Syllabus"])
        #expect(sections.folders.map(\.folder.name) == ["CS133"])
        // The pinned syllabus isn't repeated in its folder, so the folder's
        // count is the rows under it.
        #expect(sections.folders[0].notes.map(\.title) == ["Lecture 1"])
        #expect(sections.unfiled.map(\.title) == ["Loose"])
        #expect(sections.allFolders.map(\.name) == ["Algorithms", "CS133"])
    }

    @Test("The reader's sort orders notes in every section")
    func sortAppliesEverywhere() {
        let cs133 = folder("CS133")
        let b = note("B", created: 1, modified: 5, in: cs133)
        let a = note("A", created: 2, modified: 4, in: cs133)
        let pinnedB = note("Pinned B", created: 3, pinned: true)
        let pinnedA = note("Pinned A", created: 4, pinned: true)

        let byTitle = NoteListSections(
            pages: [b, a, pinnedB, pinnedA],
            folders: [cs133],
            sort: NoteSort(key: .title, ascending: true)
        )
        #expect(byTitle.folders[0].notes.map(\.title) == ["A", "B"])
        #expect(byTitle.pinnedNotes.map(\.title) == ["Pinned A", "Pinned B"])

        let byCreated = NoteListSections(
            pages: [b, a, pinnedB, pinnedA],
            folders: [cs133],
            sort: NoteSort(key: .created, ascending: false)
        )
        #expect(byCreated.folders[0].notes.map(\.title) == ["A", "B"])
        #expect(byCreated.pinnedNotes.map(\.title) == ["Pinned A", "Pinned B"])

        let byModified = NoteListSections(pages: [b, a], folders: [cs133], sort: .default)
        #expect(byModified.folders[0].notes.map(\.title) == ["B", "A"])
    }
}

@Suite("Sorting notes")
struct NoteSortTests {

    private typealias Note = (title: String, modified: Date, created: Date)

    private static func note(_ title: String, modified: TimeInterval = 0, created: TimeInterval = 0) -> Note {
        (title, Date(timeIntervalSince1970: modified), Date(timeIntervalSince1970: created))
    }

    private static func titles(_ notes: [Note], _ sort: NoteSort) -> [String] {
        notes.sorted(by: sort.areInIncreasingOrder).map(\.title)
    }

    @Test("The default is most recently changed first")
    func defaultIsNewestModified() {
        let notes = [Self.note("Old", modified: 1), Self.note("New", modified: 2)]

        #expect(NoteSort.default == NoteSort(key: .modified, ascending: false))
        #expect(Self.titles(notes, .default) == ["New", "Old"])
    }

    @Test("Each key sorts by its own property, either way round")
    func eachKey() {
        let notes = [
            Self.note("b", modified: 3, created: 1),
            Self.note("a", modified: 1, created: 3),
            Self.note("C", modified: 2, created: 2),
        ]

        #expect(Self.titles(notes, NoteSort(key: .modified, ascending: true)) == ["a", "C", "b"])
        #expect(Self.titles(notes, NoteSort(key: .created, ascending: false)) == ["a", "C", "b"])
        #expect(Self.titles(notes, NoteSort(key: .created, ascending: true)) == ["b", "C", "a"])
        // Titles compare the way Finder does: case aside, numbers as numbers.
        #expect(Self.titles(notes, NoteSort(key: .title, ascending: true)) == ["a", "b", "C"])
        #expect(Self.titles(notes, NoteSort(key: .title, ascending: false)) == ["C", "b", "a"])
        let numbered = [Self.note("Lecture 10"), Self.note("Lecture 9")]
        #expect(Self.titles(numbered, NoteSort(key: .title, ascending: true)) == ["Lecture 9", "Lecture 10"])
    }

    @Test("Ties keep one order, by title and then by creation")
    func tiesAreStable() {
        let notes = [
            Self.note("Untitled", modified: 5, created: 2),
            Self.note("Untitled", modified: 5, created: 1),
            Self.note("Lecture", modified: 5, created: 3),
        ]

        let sorted = notes.sorted(by: NoteSort.default.areInIncreasingOrder)

        #expect(sorted.map(\.title) == ["Lecture", "Untitled", "Untitled"])
        #expect(sorted.map(\.created) == [3, 1, 2].map { Date(timeIntervalSince1970: $0) })
    }

    @Test("Picking a key picks the way round that reads naturally")
    func naturalOrder() {
        let newestFirst = NoteSort.default

        #expect(newestFirst.with(key: .title) == NoteSort(key: .title, ascending: true))
        #expect(NoteSort(key: .title, ascending: false).with(key: .created) == NoteSort(key: .created, ascending: false))
    }

    @Test("The order's names match the key")
    func orderTitles() {
        let dates = NoteSort(key: .modified, ascending: false).orderTitles
        #expect(dates.ascending == "Oldest First")
        #expect(dates.descending == "Newest First")

        let titles = NoteSort(key: .title, ascending: true).orderTitles
        #expect(titles.ascending == "A to Z")
        #expect(titles.descending == "Z to A")
    }

    @Test("Rows show the date the list is sorted by")
    func displayedDate() {
        let modified = Date(timeIntervalSince1970: 2)
        let created = Date(timeIntervalSince1970: 1)

        #expect(NoteSort(key: .created, ascending: false).displayedDate(modified: modified, created: created) == created)
        #expect(NoteSort(key: .modified, ascending: false).displayedDate(modified: modified, created: created) == modified)
        #expect(NoteSort(key: .title, ascending: true).displayedDate(modified: modified, created: created) == modified)
    }

    @Test("The saved setting reads back, and anything else is ignored")
    func rawValues() {
        for key in NoteSort.Key.allCases {
            for ascending in [true, false] {
                let sort = NoteSort(key: key, ascending: ascending)
                #expect(NoteSort(rawValue: sort.rawValue) == sort)
            }
        }
        #expect(NoteSort.default.rawValue == "modified;descending")
        #expect(NoteSort(rawValue: "") == nil)
        #expect(NoteSort(rawValue: "size;descending") == nil)
        #expect(NoteSort(rawValue: "title;sideways") == nil)
        #expect(NoteSort(rawValue: "title;ascending;extra") == nil)
    }
}
