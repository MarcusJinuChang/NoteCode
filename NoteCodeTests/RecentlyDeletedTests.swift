//
//  RecentlyDeletedTests.swift
//  NoteCodeTests
//
//  v3 phase 1: deleting moves a note to Recently Deleted, and everything that
//  lists notes leaves those out.
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

@Suite("Recently Deleted")
@MainActor
struct RecentlyDeletedTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    private static let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    @discardableResult
    private func note(_ title: String, in folder: Folder? = nil, deletedDaysAgo: Double? = nil) -> Page {
        let page = Page(title: title, content: "text of \(title)")
        context.insert(page)
        page.folder = folder
        page.modifiedAt = now.addingTimeInterval(-10 * Self.day)
        page.deletedAt = deletedDaysAgo.map { now.addingTimeInterval(-$0 * Self.day) }
        return page
    }

    private func folder(_ name: String) -> Folder {
        let folder = Folder(name: name)
        context.insert(folder)
        return folder
    }

    /// What a relaunch would see: a context of its own reads only what the
    /// store has.
    private func stored() throws -> [Page] {
        try ModelContext(container).fetch(FetchDescriptor<Page>(sortBy: [SortDescriptor(\.title)]))
    }

    // MARK: Deleting and restoring

    @Test("Deleting sets the date, saves, and leaves the note's own date alone")
    func movesToRecentlyDeleted() throws {
        let lecture = note("Lecture 1")
        try context.save()
        let modified = lecture.modifiedAt

        try Page.moveToRecentlyDeleted([lecture], from: context, now: now)

        #expect(lecture.deletedAt == now)
        #expect(!lecture.isLive)
        #expect(lecture.modifiedAt == modified)
        let reloaded = try #require(try stored().first)
        #expect(reloaded.deletedAt == now, "saved at once, not left to autosave")
        #expect(reloaded.content == "text of Lecture 1", "the note is kept, not deleted")
    }

    @Test("Deleting a note already in Recently Deleted doesn't restart its 30 days")
    func deletingTwiceKeepsFirstDate() throws {
        let old = note("Old", deletedDaysAgo: 20)
        let first = old.deletedAt

        try Page.moveToRecentlyDeleted([old], from: context, now: now)

        #expect(old.deletedAt == first)
    }

    @Test("Restoring clears the date, keeps the folder and the note's own date")
    func restores() throws {
        let cs133 = folder("CS133")
        let lecture = note("Lecture 1", in: cs133, deletedDaysAgo: 3)
        try context.save()
        let modified = lecture.modifiedAt

        try Page.restore([lecture], in: context)

        #expect(lecture.isLive)
        #expect(lecture.folder == cs133)
        #expect(lecture.modifiedAt == modified)
        #expect(try #require(try stored().first).deletedAt == nil)
    }

    @Test("A note restored after its folder was deleted comes back at the top level")
    func restoresToTopWhenFolderIsGone() throws {
        let cs133 = folder("CS133")
        let lecture = note("Lecture 1", in: cs133)
        try context.save()

        try Page.moveToRecentlyDeleted([lecture], from: context, now: now)
        try Folder.delete(cs133, .keepingNotes, from: context)
        try Page.restore([lecture], in: context)

        #expect(lecture.isLive)
        #expect(lecture.folder == nil)
        #expect(NoteListSections(pages: [lecture], folders: []).unfiled == [lecture])
    }

    // MARK: Folders

    @Test("Deleting a folder with its notes moves the visible ones to Recently Deleted")
    func folderWithNotesIsSoft() throws {
        let cs133 = folder("CS133")
        let one = note("One", in: cs133)
        let two = note("Two", in: cs133)
        let already = note("Already", in: cs133, deletedDaysAgo: 5)
        let loose = note("Loose")
        let firstDate = already.deletedAt
        try context.save()

        try Folder.delete(cs133, .withNotes, from: context, now: now)

        let titles = try stored().map(\.title)
        #expect(titles == ["Already", "Loose", "One", "Two"], "no note is deleted for good")
        #expect(one.deletedAt == now && two.deletedAt == now)
        #expect(already.deletedAt == firstDate, "a note already deleted keeps its first date")
        #expect(loose.isLive)
        #expect(cs133.deletedAt == now, "the folder waits in Recently Deleted too")
        #expect(try ModelContext(container).fetch(FetchDescriptor<Folder>()).count == 1)
    }

    @Test("Deleting a folder and keeping its notes removes the folder for good")
    func folderKeepingNotesIsHard() throws {
        let cs133 = folder("CS133")
        let one = note("One", in: cs133)
        try context.save()

        try Folder.delete(cs133, .keepingNotes, from: context, now: now)

        #expect(try ModelContext(container).fetch(FetchDescriptor<Folder>()).isEmpty)
        #expect(one.isLive && one.folder == nil)
    }

    // MARK: Folders in Recently Deleted

    @Test("A deleted folder is in no view of folders, and neither is its note")
    func deletedFolderIsHidden() throws {
        let cs133 = folder("CS133")
        let other = folder("Other")
        let one = note("One", in: cs133)
        let kept = note("Kept", in: other)
        try context.save()

        try Folder.delete(cs133, .withNotes, from: context, now: now)

        let pages = [one, kept]
        let folders = [cs133, other]
        let sections = NoteListSections(pages: pages, folders: folders)
        #expect(sections.folders.map(\.folder) == [other])
        #expect(sections.allFolders == [other], "Move to Folder doesn't offer it")
        #expect(HomeSections(pages: pages, folders: folders, lastOpened: nil).folders.map(\.folder) == [other])
        #expect(NoteExportJob.layout(of: pages.live, in: folders).plan.directories.count == 1)
    }

    @Test("Restoring a folder brings back the notes that went with it, and not the one deleted before")
    func restoreFolder() throws {
        let cs133 = folder("CS133")
        let one = note("One", in: cs133)
        let two = note("Two", in: cs133)
        let earlier = note("Earlier", in: cs133, deletedDaysAgo: 5)
        let earlierDate = earlier.deletedAt
        try context.save()
        try Folder.delete(cs133, .withNotes, from: context, now: now)
        #expect(Set(cs133.notesDeletedWithIt) == [one, two])

        try Folder.restore([cs133], in: context)

        #expect(cs133.isLive)
        #expect(one.isLive && two.isLive)
        #expect(one.folder == cs133 && two.folder == cs133)
        #expect(earlier.deletedAt == earlierDate, "a note deleted on its own stays deleted")
        #expect(try ModelContext(container).fetch(FetchDescriptor<Folder>()).first?.deletedAt == nil, "saved at once")
    }

    @Test("A note shows under its folder's row, not as one of its own")
    func notesDeletedWithFolder() throws {
        let cs133 = folder("CS133")
        let one = note("One", in: cs133)
        let earlier = note("Earlier", in: cs133, deletedDaysAgo: 5)
        try context.save()
        try Folder.delete(cs133, .withNotes, from: context, now: now)

        #expect(one.isDeletedWithFolder)
        #expect(!earlier.isDeletedWithFolder)
        #expect(!note("Loose").isDeletedWithFolder)
        #expect(RecentlyDeletedCaption.caption(for: cs133, now: now).hasPrefix("1 note · Deleted today"))
    }

    @Test("Restoring one note of a deleted folder puts it at the top, not in a folder nobody can see")
    func restoreNoteOfDeletedFolder() throws {
        let cs133 = folder("CS133")
        let one = note("One", in: cs133)
        try context.save()
        try Folder.delete(cs133, .withNotes, from: context, now: now)

        try Page.restore([one], in: context)

        #expect(one.isLive && one.folder == nil)
        #expect(!cs133.isLive)
        #expect(cs133.notesDeletedWithIt.isEmpty)
    }

    @Test("Delete Now on a folder deletes it and the notes that went with it, and no others")
    func deleteFolderForGood() throws {
        let cs133 = folder("CS133")
        note("One", in: cs133)
        note("Earlier", in: cs133, deletedDaysAgo: 5)
        note("Loose")
        try context.save()
        try Folder.delete(cs133, .withNotes, from: context, now: now)

        try Folder.deleteForGood([cs133], from: context)

        #expect(try stored().map(\.title) == ["Earlier", "Loose"])
        #expect(try ModelContext(container).fetch(FetchDescriptor<Folder>()).isEmpty)
    }

    @Test("A folder is purged with its notes after 30 days, and not before")
    func purgeFolder() throws {
        let old = folder("Old")
        let recent = folder("Recent")
        note("InOld", in: old)
        note("InRecent", in: recent)
        try context.save()
        try Folder.delete(old, .withNotes, from: context, now: now.addingTimeInterval(-31 * Self.day))
        try Folder.delete(recent, .withNotes, from: context, now: now.addingTimeInterval(-29 * Self.day))

        let purged = try Page.purgeExpired(in: context, now: now)

        #expect(purged == 1)
        #expect(try stored().map(\.title) == ["InRecent"])
        let folders = try ModelContext(container).fetch(FetchDescriptor<Folder>())
        #expect(folders.map(\.name) == ["Recent"])
    }

    @Test("A folder deleted twice keeps its first date, and days left count down")
    func folderDates() throws {
        let cs133 = folder("CS133")
        try context.save()
        try Folder.delete(cs133, .withNotes, from: context, now: now)
        try Folder.delete(cs133, .withNotes, from: context, now: now.addingTimeInterval(5 * Self.day))

        #expect(cs133.deletedAt == now)
        #expect(cs133.daysLeft(now: now) == 30)
        #expect(cs133.daysLeft(now: now.addingTimeInterval(10.5 * Self.day)) == 20)
    }

    @Test("A folder's live notes leave out the ones in Recently Deleted")
    func folderLivePages() {
        let cs133 = folder("CS133")
        let shown = note("Shown", in: cs133)
        note("Hidden", in: cs133, deletedDaysAgo: 1)

        #expect(cs133.pages?.count == 2)
        #expect(cs133.livePages == [shown])
    }

    // MARK: Purging

    @Test("At launch, notes deleted more than 30 days ago go for good and no others")
    func purgesExpired() throws {
        note("Live")
        note("Fresh", deletedDaysAgo: 1)
        note("Almost", deletedDaysAgo: 29.9)
        note("Expired", deletedDaysAgo: 30.1)
        note("Ancient", deletedDaysAgo: 400)
        try context.save()

        let purged = try Page.purgeExpired(in: context, now: now)

        #expect(purged == 2)
        #expect(try stored().map(\.title) == ["Almost", "Fresh", "Live"])
    }

    @Test("Purging with nothing expired changes nothing")
    func purgesNothing() throws {
        note("Live")
        try context.save()

        #expect(try Page.purgeExpired(in: context, now: now) == 0)
        #expect(try stored().count == 1)
    }

    @Test("A drawn note can be purged: nothing reads its ink on the way")
    func purgesDrawnNote() throws {
        let drawn = note("Drawn", deletedDaysAgo: 40)
        drawn.drawingData = Data((0..<300_000).map { UInt8($0 % 251) })
        try context.save()

        try Page.purgeExpired(in: context, now: now)

        #expect(try stored().isEmpty)
    }

    @Test("Days left count down from 30, a whole day at a time, and stop at 0")
    func daysLeft() {
        func left(afterDays days: Double) -> Int? {
            note("n", deletedDaysAgo: days).daysLeft(now: now)
        }
        #expect(left(afterDays: 0) == 30)
        #expect(left(afterDays: 0.9) == 30)
        #expect(left(afterDays: 1) == 29)
        #expect(left(afterDays: 9) == 21)
        #expect(left(afterDays: 29.5) == 1)
        #expect(left(afterDays: 31) == 0)
        #expect(note("live").daysLeft(now: now) == nil)
    }

    @Test("The deleted predicate and isLive are opposites")
    func predicateAgreesWithIsLive() throws {
        note("A")
        note("B", deletedDaysAgo: 2)
        note("C", deletedDaysAgo: 0)
        note("D")
        try context.save()

        let deleted = try context.fetch(FetchDescriptor<Page>(predicate: Page.deletedPredicate))
        let all = try context.fetch(FetchDescriptor<Page>())

        #expect(Set(deleted.map(\.title)) == ["B", "C"])
        #expect(Set(all.live.map(\.title)) == ["A", "D"])
        #expect(all.allSatisfy { page in deleted.contains(page) != page.isLive })
    }

    // MARK: Every view of notes leaves them out

    @Test("The list's sections leave out deleted notes: unfiled, filed and pinned")
    func sectionsLeaveThemOut() {
        let cs133 = folder("CS133")
        let shown = note("Shown")
        let filed = note("Filed", in: cs133)
        let pinned = note("Pinned")
        pinned.isPinned = true
        let hidden = note("Hidden", deletedDaysAgo: 1)
        let hiddenFiled = note("Hidden filed", in: cs133, deletedDaysAgo: 1)
        let hiddenPinned = note("Hidden pinned", deletedDaysAgo: 1)
        hiddenPinned.isPinned = true

        let sections = NoteListSections(
            pages: [shown, filed, pinned, hidden, hiddenFiled, hiddenPinned],
            folders: [cs133]
        )

        #expect(sections.unfiled == [shown])
        #expect(sections.pinnedNotes == [pinned])
        #expect(sections.folders.first?.notes == [filed])
    }

    @Test("Search doesn't find a deleted note by its title or its text")
    func searchLeavesThemOut() {
        let shown = note("Hash tables")
        let hidden = note("Hash maps", deletedDaysAgo: 1)

        let byTitle = NoteSearch("hash").results(in: [shown, hidden], sort: .default)
        let byText = NoteSearch("text of hash").results(in: [shown, hidden], sort: .default)

        #expect(byTitle.map(\.page) == [shown])
        #expect(byText.map(\.page) == [shown])
    }

    @Test("A deleted note isn't the open note a new note is filed beside")
    func newNoteFolderIgnoresDeleted() {
        let cs133 = folder("CS133")
        let open = note("Open", in: cs133)
        let gone = note("Gone", in: cs133, deletedDaysAgo: 1)

        #expect(NewNotes.folder(whileViewing: open) == cs133)
        #expect(NewNotes.folder(whileViewing: gone) == nil)
    }

    @Test("A store holding only deleted notes isn't a first launch")
    func welcomeCountsDeletedNotes() throws {
        let name = "RecentlyDeletedTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        note("Deleted", deletedDaysAgo: 2)
        try context.save()

        #expect(WelcomeNote.makeOnFirstLaunch(in: context, defaults: defaults) == nil)
        #expect(try stored().count == 1)
    }

    // MARK: Duplicate

    @Test("A copy has the note's text, ink, pages, size, folder and run destination")
    func duplicateCopies() throws {
        let cs133 = folder("CS133")
        let original = note("Lecture 1", in: cs133)
        let ink = Data((0..<300_000).map { UInt8($0 % 251) })
        original.drawingData = ink
        original.pageOrientation = PageOrientation.landscape.rawValue
        original.textSize = 19
        original.runDestination = CodeDestination.onlineGDB.id
        try context.save()

        let copy = original.duplicated(in: context)
        try context.save()

        #expect(copy !== original)
        #expect(copy.title == "Lecture 1 copy")
        #expect(copy.content == original.content)
        #expect(copy.drawingData == ink)
        #expect(copy.pageOrientation == original.pageOrientation)
        #expect(copy.textSize == 19)
        #expect(copy.folder == cs133)
        #expect(copy.runDestination == CodeDestination.onlineGDB.id)
        #expect(try stored().count == 2)
        #expect(Set(cs133.pages ?? []) == [original, copy])
    }

    @Test("A copy isn't pinned or locked, has dates of its own, and leaves the original alone")
    func duplicateLeavesOutPinAndLock() throws {
        let original = note("Lecture 1")
        original.isPinned = true
        original.isTextLocked = true
        original.createdAt = now.addingTimeInterval(-30 * Self.day)
        let modified = original.modifiedAt
        let created = original.createdAt

        let before = Date.now
        let copy = original.duplicated(in: context)

        #expect(!copy.isPinned && !copy.isTextLocked)
        #expect(copy.isLive)
        #expect(copy.createdAt >= before && copy.modifiedAt >= before)
        #expect(original.isPinned && original.isTextLocked)
        #expect(original.modifiedAt == modified && original.createdAt == created)
    }

    @Test("A copy of a plain note is a plain note")
    func duplicateOfPlainNote() {
        let copy = note("Scratch").duplicated(in: context)

        #expect(copy.folder == nil)
        #expect(copy.runDestination == nil)
        #expect(copy.drawingData.isEmpty)
    }

    // MARK: Wording

    @Test("A row says when the note was deleted and how long it has left")
    func captions() {
        let calendar = Calendar(identifier: .gregorian)
        let today = now
        let yesterday = now.addingTimeInterval(-Self.day)

        #expect(RecentlyDeletedCaption.deleted(today, now: now, calendar: calendar) == "Deleted today")
        #expect(RecentlyDeletedCaption.deleted(yesterday, now: now, calendar: calendar) == "Deleted yesterday")
        let earlier = RecentlyDeletedCaption.deleted(now.addingTimeInterval(-9 * Self.day), now: now, calendar: calendar)
        #expect(earlier.hasPrefix("Deleted ") && earlier != "Deleted today" && earlier != "Deleted yesterday")

        #expect(RecentlyDeletedCaption.daysLeft(30) == "30 days left")
        #expect(RecentlyDeletedCaption.daysLeft(2) == "2 days left")
        #expect(RecentlyDeletedCaption.daysLeft(1) == "1 day left")
        #expect(RecentlyDeletedCaption.daysLeft(0) == "Less than a day left")

        let nine = note("Nine", deletedDaysAgo: 9)
        #expect(RecentlyDeletedCaption.caption(for: nine, now: now, calendar: calendar).hasSuffix("· 21 days left"))
        #expect(RecentlyDeletedCaption.caption(for: note("Live"), now: now, calendar: calendar).isEmpty)
    }
}

@Suite("Toasts")
@MainActor
struct ToastTests {

    @Test("A toast shows its message and action, and a newer one replaces it")
    func replaces() {
        let center = ToastCenter()
        center.show("First")
        center.show("Second", actionTitle: "Undo") {}

        #expect(center.current?.message == "Second")
        #expect(center.current?.action?.title == "Undo")
    }

    @Test("Pressing Undo runs the action once and takes the toast away")
    func performAction() {
        let center = ToastCenter()
        var ran = 0
        center.show("Moved", actionTitle: "Undo") { ran += 1 }

        center.performAction()
        center.performAction()

        #expect(ran == 1)
        #expect(center.current == nil)
    }

    @Test("A toast with no action has no button to press")
    func noAction() {
        let center = ToastCenter()
        center.show("Copied")
        center.performAction()

        #expect(center.current?.message == "Copied")
        #expect(center.current?.action == nil)
    }

    @Test("A toast goes by itself after its time, and a newer one gets its own full time")
    func goesAway() async throws {
        let center = ToastCenter(duration: .milliseconds(150))
        center.show("First")
        try await Task.sleep(for: .milliseconds(90))
        center.show("Second")
        try await Task.sleep(for: .milliseconds(90))
        #expect(center.current?.message == "Second", "the first toast's clock didn't take the second away")

        try await Task.sleep(for: .milliseconds(150))
        #expect(center.current == nil)
    }

    @Test("The brief's four seconds")
    func fourSeconds() {
        #expect(ToastCenter.defaultDuration == .seconds(4))
    }
}
