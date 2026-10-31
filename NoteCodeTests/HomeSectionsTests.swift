//
//  HomeSectionsTests.swift
//  NoteCodeTests
//
//  Phase 2 of v3: what Home shows, how it dates things, and the title screen's
//  flag.
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

@Suite("Home")
@MainActor
struct HomeSectionsTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private let now = Date(timeIntervalSince1970: 1_791_800_000)

    /// A saved note edited `minutesAgo` minutes before `now`.
    @discardableResult
    private func note(_ title: String, minutesAgo: Double = 0, in folder: Folder? = nil) throws -> Page {
        let page = Page(title: title, createdAt: now.addingTimeInterval(-86_400 * 30))
        page.modifiedAt = now.addingTimeInterval(-minutesAgo * 60)
        context.insert(page)
        page.folder = folder
        try context.save()
        return page
    }

    private func key(of page: Page) -> String? {
        NoteMemory.key(for: page.persistentModelID)
    }

    private func titles(_ pages: [Page]) -> [String] { pages.map(\.title) }

    // MARK: Continue

    @Test("Continue is the note opened last, wherever it is in the order")
    func continueIsLastOpened() throws {
        let newest = try note("Newest", minutesAgo: 1)
        let opened = try note("Opened", minutesAgo: 500)
        let sections = HomeSections(pages: [newest, opened], folders: [], lastOpened: key(of: opened))
        #expect(sections.continuing === opened)
        #expect(titles(sections.recent) == ["Newest"])
    }

    @Test("With nothing opened yet, or the note gone, Continue is the note edited last")
    func continueFallsBack() throws {
        let newest = try note("Newest", minutesAgo: 1)
        let older = try note("Older", minutesAgo: 90)

        #expect(HomeSections(pages: [older, newest], folders: [], lastOpened: nil).continuing === newest)
        #expect(HomeSections(pages: [older, newest], folders: [], lastOpened: "no such note").continuing === newest)

        // Opened last, then deleted: it is in Recently Deleted, so it isn't a
        // way back in.
        let deleted = try note("Deleted", minutesAgo: 5)
        deleted.deletedAt = now
        let sections = HomeSections(pages: [older, newest, deleted], folders: [], lastOpened: key(of: deleted))
        #expect(sections.continuing === newest)
    }

    // MARK: Recent

    @Test("Recent is eight notes, newest first, without the Continue note")
    func recent() throws {
        let pages = try (0..<12).map { try note("Note \($0)", minutesAgo: Double($0) * 10) }
        // Opened last is the oldest, so it comes out of the order.
        let sections = HomeSections(pages: pages.shuffled(), folders: [], lastOpened: key(of: pages[11]))

        #expect(sections.continuing === pages[11])
        #expect(sections.recent.count == HomeSections.recentLimit)
        #expect(titles(sections.recent) == (0..<8).map { "Note \($0)" })
        #expect(!sections.recent.contains { $0 === sections.continuing })
    }

    @Test("A note in Recently Deleted is in none of Home's sections")
    func deletedNotesAreOut() throws {
        let kept = try note("Kept", minutesAgo: 30)
        let gone = try note("Gone", minutesAgo: 1, in: try folder("Class"))
        gone.deletedAt = now

        let sections = HomeSections(pages: [kept, gone], folders: [gone.folder!], lastOpened: key(of: gone))
        #expect(sections.continuing === kept)
        #expect(sections.recent.isEmpty)
        #expect(sections.folders.map(\.noteCount) == [0], "the folder's count leaves the deleted note out")
        #expect(!sections.hasNoNotes)
    }

    @Test("A store of only deleted notes, or with folders and no notes, shows Home's empty state")
    func empty() throws {
        #expect(HomeSections(pages: [], folders: [], lastOpened: nil).hasNoNotes)

        let deleted = try note("Deleted")
        deleted.deletedAt = now
        #expect(HomeSections(pages: [deleted], folders: [], lastOpened: nil).hasNoNotes)

        let sections = HomeSections(pages: [], folders: [try folder("Empty class")], lastOpened: nil)
        #expect(sections.hasNoNotes)
        #expect(sections.continuing == nil)
    }

    // MARK: Folders

    private func folder(_ name: String) throws -> Folder {
        let folder = Folder(name: name)
        context.insert(folder)
        try context.save()
        return folder
    }

    @Test("Folders are in name order with numbers as numbers, each with the notes in it")
    func folderTiles() throws {
        let cs133 = try folder("CS 133")
        let cs9 = try folder("CS 9")
        let practice = try folder("Algorithm practice")
        try note("A", in: cs133)
        try note("B", in: cs133)
        try note("C", in: practice)

        let sections = HomeSections(pages: try context.fetch(FetchDescriptor<Page>()), folders: [cs133, cs9, practice], lastOpened: nil)
        #expect(sections.folders.map(\.folder.name) == ["Algorithm practice", "CS 9", "CS 133"])
        #expect(sections.folders.map(\.noteCount) == [1, 0, 2])
    }

    // MARK: Dates

    private func gregorian() -> (Calendar, Locale) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return (calendar, Locale(identifier: "en_GB"))
    }

    /// Noon, 12 October 2026: a Monday.
    private var monday: Date { Date(timeIntervalSince1970: 1_791_806_400) }

    @Test("Home dates a note in the words a person would use")
    func dates() {
        let (calendar, locale) = gregorian()
        func label(daysAgo: Int, hoursAhead: Int = 0) -> String {
            HomeDate.label(
                for: monday.addingTimeInterval(TimeInterval(-daysAgo * 86_400 + hoursAhead * 3600)),
                now: monday, calendar: calendar, locale: locale
            )
        }

        #expect(label(daysAgo: 0) == "Today")
        #expect(label(daysAgo: 0, hoursAhead: -5) == "Today")
        #expect(label(daysAgo: 1) == "Yesterday")
        #expect(label(daysAgo: 2) == "Saturday")
        #expect(label(daysAgo: 3) == "Friday")
        #expect(label(daysAgo: 6) == "Tuesday")
        #expect(label(daysAgo: 7) == "5 Oct", "a week ago is the date, not a weekday that would be today's")
        #expect(label(daysAgo: 21) == "21 Sep")
        #expect(label(daysAgo: 21 + 365) == "21 Sep 2025")
    }

    @Test("Yesterday is the calendar day, not the last 24 hours")
    func yesterdayIsTheDay() {
        let (calendar, locale) = gregorian()
        // 00:30 on Monday, and 23:30 on Sunday: an hour apart.
        let justAfterMidnight = monday.addingTimeInterval(-12 * 3600 + 30 * 60)
        let lateSunday = justAfterMidnight.addingTimeInterval(-3600)
        #expect(HomeDate.label(for: lateSunday, now: justAfterMidnight, calendar: calendar, locale: locale) == "Yesterday")
    }

    // MARK: Excerpt

    @Test("The excerpt is the first line of prose: no headings, fences, code or blank lines")
    func excerpt() {
        #expect(HomeExcerpt.of("A hash table keeps keys in buckets.\n\nMore.") == "A hash table keeps keys in buckets.")
        #expect(HomeExcerpt.of("# Title\n\n## Section\n\nThe first prose line.") == "The first prose line.")
        #expect(HomeExcerpt.of("```cpp\nint x;\n```\n\nAfter the code.") == "After the code.")
        #expect(HomeExcerpt.of("```cpp\nint x;\n```") == nil)
        #expect(HomeExcerpt.of("") == nil)
        #expect(HomeExcerpt.of("   \n\t\nIndented prose.  ") == "Indented prose.")
        #expect(HomeExcerpt.of(String(repeating: "x", count: 500), limit: 160)?.count == 160)
    }

    @Test("The excerpt is the words the page draws, not the Markdown typed",
          arguments: [
              ("**bold** words", "bold words"),
              ("*italic* words", "italic words"),
              ("~~struck~~ words", "struck words"),
              ("<u>under</u> words", "under words"),
              ("==🟡marked== words", "marked words"),
              ("<span style=\"color:#E5484D\">red</span> words", "red words"),
              ("<span style=\"font-size:1.25em\">big</span> words", "big words"),
              ("See [the docs](https://example.com/x) now", "See the docs now"),
              ("- a bullet", "a bullet"),
              ("1. a number", "a number"),
              ("- [ ] a task", "a task"),
              ("- [x] a done task", "a done task"),
              ("> a quote", "a quote"),
              ("Call `foo()` here", "Call foo() here"),
          ])
    func excerptDropsMarkers(line: String, shown: String) {
        #expect(HomeExcerpt.of(line) == shown)
    }

    @Test("A line that is all markup and no text falls through to the next")
    func excerptSkipsEmptyMarkup() {
        #expect(HomeExcerpt.of("---\n- [ ]\n> \nThe real line.") == "The real line.")
    }

    @Test("An unclosed fence at the top means the rest is code, so there is nothing to quote")
    func excerptUnclosedFence() {
        #expect(HomeExcerpt.of("```python\nprint(1)\nstill code") == nil)
    }
}

@Suite("Title screen")
@MainActor
struct WelcomeScreenTests {

    private func freshDefaults() -> UserDefaults {
        let name = "WelcomeScreenTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("A first launch shows it once; the turn is spent by being asked")
    func firstLaunchOnly() {
        let defaults = freshDefaults()
        #expect(WelcomeScreen.claimFirstLaunch(defaults: defaults))
        #expect(defaults.bool(forKey: WelcomeScreen.shownKey), "the flag is set when the turn is claimed")
        #expect(!WelcomeScreen.claimFirstLaunch(defaults: defaults))
        #expect(!WelcomeScreen.claimFirstLaunch(defaults: defaults))
    }

    @Test("A device that has seen it, or was set before, isn't shown it again")
    func alreadySeen() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: WelcomeScreen.shownKey)
        #expect(!WelcomeScreen.claimFirstLaunch(defaults: defaults))
    }

    @Test("It says three things, each with words")
    func features() {
        #expect(WelcomeScreen.features.map(\.title) == ["Code that runs", "Ink on the same page", "Letter pages"])
        #expect(WelcomeScreen.features.allSatisfy { !$0.detail.isEmpty && !$0.symbol.isEmpty })
    }
}
