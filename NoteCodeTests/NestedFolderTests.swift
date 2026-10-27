//
//  NestedFolderTests.swift
//  NoteCodeTests
//
//  Roadmap step 8: folders that nest and are arranged by hand, and dragging
//  notes and folders in the list. The rules are pure, so no drag is made.
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

@Suite("Nested folders")
@MainActor
struct NestedFolderTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    @discardableResult
    private func folder(_ name: String, in parent: Folder? = nil) -> Folder {
        let folder = Folder(name: name)
        context.insert(folder)
        folder.parent = parent
        return folder
    }

    @discardableResult
    private func note(_ title: String, in folder: Folder? = nil) -> Page {
        let page = Page(title: title)
        context.insert(page)
        page.folder = folder
        return page
    }

    private var everyFolder: [Folder] { (try? context.fetch(FetchDescriptor<Folder>())) ?? [] }

    // MARK: Nesting

    @Test("A folder knows what is above and below it")
    func ancestorsAndDescendants() {
        let a = folder("A"), b = folder("B", in: a), c = folder("C", in: b), d = folder("D", in: a)
        #expect(c.ancestors.map(\.name) == ["B", "A"])
        #expect(c.depth == 2)
        #expect(Set(a.descendants.map(\.name)) == ["B", "C", "D"])
        #expect(c.path == "A › B › C")
        _ = d
    }

    @Test("A folder can't go inside itself or anything inside it")
    func cyclesAreRefused() {
        let a = folder("A"), b = folder("B", in: a), c = folder("C", in: b), other = folder("Other")
        #expect(!a.canMove(into: a))
        #expect(!a.canMove(into: b))
        #expect(!a.canMove(into: c))
        #expect(a.canMove(into: other))
        #expect(c.canMove(into: nil))
        #expect(c.canMove(into: a))
        #expect(!Folder.move(a, into: c, among: everyFolder))
        #expect(a.parent == nil, "a refused move changes nothing")
    }

    // MARK: Order

    @Test("An unarranged level is in name order, numbers as numbers")
    func unarrangedIsByName() {
        folder("CS 133"); folder("CS 9"); folder("algorithms")
        #expect(Folder.children(of: nil, in: everyFolder).map(\.name) == ["algorithms", "CS 9", "CS 133"])
    }

    @Test("Moving a folder to an index arranges the level in the reader's order")
    func arrangeByHand() {
        let a = folder("A"), b = folder("B"), c = folder("C")
        Folder.move(c, into: nil, at: 0, among: everyFolder)
        #expect(Folder.children(of: nil, in: everyFolder).map(\.name) == ["C", "A", "B"])
        Folder.move(a, into: nil, at: 2, among: everyFolder)
        #expect(Folder.children(of: nil, in: everyFolder).map(\.name) == ["C", "B", "A"])
        #expect([c, b, a].map(\.sortIndex) == [0, 1, 2], "the level is numbered afresh")
    }

    @Test("A folder made after arranging comes last, by name")
    func newFolderIsLast() {
        let a = folder("A"), b = folder("B")
        Folder.move(b, into: nil, at: 0, among: everyFolder)
        folder("Aardvark")
        #expect(Folder.children(of: nil, in: everyFolder).map(\.name) == ["B", "A", "Aardvark"])
        _ = a
    }

    @Test("Moving into a folder puts it at the end, or where asked, and closes the gap behind")
    func nestAndRenumber() {
        let parent = folder("Parent"), x = folder("X"), y = folder("Y"), z = folder("Z")
        Folder.move(x, into: nil, at: 0, among: everyFolder)
        Folder.move(y, into: nil, at: 1, among: everyFolder)
        Folder.move(z, into: nil, at: 2, among: everyFolder)

        Folder.move(y, into: parent, among: everyFolder)
        #expect(y.parent === parent)
        #expect(Folder.children(of: parent, in: everyFolder).map(\.name) == ["Y"])
        #expect(Folder.children(of: nil, in: everyFolder).prefix(2).map(\.name) == ["X", "Z"], "X and Z keep their order")
        #expect(x.sortIndex == 0 && z.sortIndex == 1)
    }

    // MARK: The list's tree

    @Test("Sections nest: a folder's children and counts include what is below")
    func sectionsNest() {
        let cs = folder("CS133"), labs = folder("Labs", in: cs)
        let n1 = note("Lecture", in: cs), n2 = note("Lab 1", in: labs)
        let sections = NoteListSections(pages: [n1, n2], folders: everyFolder)

        #expect(sections.folders.map(\.folder.name) == ["CS133"], "Labs isn't a top-level row")
        let top = sections.folders[0]
        #expect(top.children.map(\.folder.name) == ["Labs"])
        #expect(top.notes.map(\.title) == ["Lecture"])
        #expect(top.noteCount == 2)
        #expect(sections.allFolders.map(\.path) == ["CS133", "CS133 › Labs"])
    }

    @Test("A pinned folder is listed in Pinned and not again in its parent")
    func pinnedNestedOnce() {
        let cs = folder("CS133"), labs = folder("Labs", in: cs)
        labs.isPinned = true
        let sections = NoteListSections(pages: [], folders: everyFolder)
        #expect(sections.pinnedFolders.map(\.folder.name) == ["Labs"])
        #expect(sections.folders.map(\.folder.name) == ["CS133"])
        #expect(sections.folders[0].children.isEmpty)
    }

    @Test("Rows: an open folder shows what is in it, folders and notes together; a closed one nothing")
    func rowsFlatten() {
        let cs = folder("CS133"), labs = folder("Labs", in: cs), empty = folder("Empty")
        let lecture = note("Lecture", in: cs), lab = note("Lab 1", in: labs)
        let sections = NoteListSections(
            pages: [lecture, lab], folders: everyFolder,
            sort: NoteSort(key: .title, ascending: true)
        )

        func shape(_ closed: Set<PersistentIdentifier>) -> [String] {
            NoteListRow.rows(for: sections.items, closed: closed).map {
                switch $0 {
                case .folder(let s, let depth, _): "\(depth) folder \(s.folder.name)"
                case .note(let p, let depth, _):   "\(depth) note \(p.title)"
                case .empty(_, let depth):         "\(depth) empty"
                }
            }
        }

        #expect(shape([]) == ["0 folder CS133", "1 folder Labs", "2 note Lab 1", "1 note Lecture", "0 folder Empty", "1 empty"])
        #expect(shape([cs.persistentModelID]) == ["0 folder CS133", "0 folder Empty", "1 empty"])
        #expect(shape([labs.persistentModelID]) == ["0 folder CS133", "1 folder Labs", "1 note Lecture", "0 folder Empty", "1 empty"])
        _ = empty
    }

    // MARK: Drop rules

    @Test("A note dropped on a folder is filed there; dropped on its own folder, nothing")
    func noteOntoFolder() {
        let a = folder("A"), b = folder("B")
        let n = note("N", in: a)
        let all = everyFolder
        #expect(ListDrop.resolve(.note(n), onto: .folder(b), zone: .into, among: all) == .fileNote(n, into: b))
        #expect(ListDrop.resolve(.note(n), onto: .folder(b), zone: .before, among: all) == .fileNote(n, into: b),
                "a note is never arranged, so any zone files it")
        #expect(ListDrop.resolve(.note(n), onto: .folder(a), zone: .into, among: all) == nil)
    }

    @Test("A note dropped on another note goes where that one is; on a header, out of its folder")
    func noteOntoNoteAndHeaders() {
        let a = folder("A")
        let inA = note("In A", in: a), top = note("Top"), filed = note("Filed", in: a)
        let all = everyFolder
        #expect(ListDrop.resolve(.note(top), onto: .note(inA), zone: .into, among: all) == .fileNote(top, into: a))
        #expect(ListDrop.resolve(.note(inA), onto: .note(top), zone: .into, among: all) == .fileNote(inA, into: nil))
        #expect(ListDrop.resolve(.note(inA), onto: .note(filed), zone: .into, among: all) == nil)
        #expect(ListDrop.resolve(.note(inA), onto: .topNotes, zone: .into, among: all) == .fileNote(inA, into: nil))
        #expect(ListDrop.resolve(.note(top), onto: .topNotes, zone: .into, among: all) == nil)
    }

    @Test("A folder dropped on the middle of another goes inside it")
    func folderInto() {
        let a = folder("A"), b = folder("B")
        let action = ListDrop.resolve(.folder(a), onto: .folder(b), zone: .into, among: everyFolder)
        #expect(action == .moveFolder(a, into: b, at: nil))
        ListDrop.perform(action!, among: everyFolder)
        #expect(a.parent === b)
    }

    @Test("A folder dropped on an edge is arranged beside it, among the same parent's folders")
    func folderBeforeAfter() {
        let a = folder("A"), b = folder("B"), c = folder("C")
        let all = everyFolder
        #expect(ListDrop.resolve(.folder(c), onto: .folder(a), zone: .before, among: all) == .moveFolder(c, into: nil, at: 0))
        #expect(ListDrop.resolve(.folder(a), onto: .folder(c), zone: .after, among: all) == .moveFolder(a, into: nil, at: 2),
                "after C, once A has left the level")
        ListDrop.perform(ListDrop.resolve(.folder(c), onto: .folder(a), zone: .before, among: all)!, among: all)
        #expect(Folder.children(of: nil, in: everyFolder).map(\.name) == ["C", "A", "B"])
        _ = b
    }

    @Test("Arranging beside a folder in another folder moves it there")
    func arrangeAcrossParents() {
        let p = folder("P"), inside = folder("Inside", in: p), loose = folder("Loose")
        let action = ListDrop.resolve(.folder(loose), onto: .folder(inside), zone: .before, among: everyFolder)
        #expect(action == .moveFolder(loose, into: p, at: 0))
    }

    @Test("A folder can't be dropped on itself or into its own subtree")
    func folderCycles() {
        let a = folder("A"), b = folder("B", in: a), c = folder("C", in: b)
        let all = everyFolder
        for zone in [DropZone.before, .into, .after] {
            #expect(ListDrop.resolve(.folder(a), onto: .folder(a), zone: zone, among: all) == nil)
            #expect(ListDrop.resolve(.folder(a), onto: .folder(c), zone: zone, among: all) == nil, "\(zone)")
        }
        // Beside its own child means inside itself.
        #expect(ListDrop.resolve(.folder(a), onto: .folder(b), zone: .before, among: all) == nil)
    }

    @Test("A pinned folder is only dropped into: there is no beside it")
    func pinnedTargetIsInto() {
        let a = folder("A"), pinned = folder("P")
        pinned.isPinned = true
        let action = ListDrop.resolve(.folder(a), onto: .folder(pinned), zone: .before, among: everyFolder)
        #expect(action == .moveFolder(a, into: pinned, at: nil))
    }

    @Test("A folder dropped on Folders goes to the top level; none goes on a note or Notes")
    func folderToTop() {
        let a = folder("A"), b = folder("B", in: a)
        let n = note("N")
        #expect(ListDrop.resolve(.folder(b), onto: .topFolders, zone: .into, among: everyFolder) == .moveFolder(b, into: nil, at: nil))
        #expect(ListDrop.resolve(.folder(b), onto: .note(n), zone: .into, among: everyFolder) == nil)
        #expect(ListDrop.resolve(.folder(b), onto: .topNotes, zone: .into, among: everyFolder) == nil)
    }

    @Test("The edges of a row arrange and its middle files")
    func zones() {
        #expect(DropZone.zone(atY: 2, height: 44) == .before)
        #expect(DropZone.zone(atY: 22, height: 44) == .into)
        #expect(DropZone.zone(atY: 42, height: 44) == .after)
        #expect(DropZone.zone(atY: 5, height: 0) == .into)
    }

    @Test("Filing a note by drop leaves its date alone")
    func filingIsNotAnEdit() {
        let a = folder("A")
        let n = note("N")
        let before = n.modifiedAt
        ListDrop.perform(.fileNote(n, into: a), among: everyFolder)
        #expect(n.folder === a)
        #expect(n.modifiedAt == before)
    }

    // MARK: Deleting

    @Test("Deleting a folder with its notes takes the folders in it and their notes along, and restoring brings them back")
    func deleteWithNotesCascades() throws {
        let cs = folder("CS133"), labs = folder("Labs", in: cs)
        let lecture = note("Lecture", in: cs), lab = note("Lab", in: labs)
        let earlier = note("Earlier", in: labs)
        earlier.deletedAt = Date(timeIntervalSince1970: 1)

        try Folder.delete(cs, .withNotes, from: context)
        #expect(!cs.isLive && !labs.isLive)
        #expect(lecture.deletedAt == cs.deletedAt && lab.deletedAt == cs.deletedAt)
        #expect(earlier.deletedAt == Date(timeIntervalSince1970: 1), "a note deleted before keeps its own date")
        #expect(labs.isDeletedWithParent && !cs.isDeletedWithParent)
        #expect(Set(cs.notesDeletedWithIt.map(\.title)) == ["Lecture", "Lab"])

        try Folder.restore([cs], in: context)
        #expect(cs.isLive && labs.isLive)
        #expect(lecture.isLive && lab.isLive && !earlier.isLive)
        #expect(labs.parent === cs, "the nesting comes back with it")
    }

    @Test("Deleting a folder and keeping its notes moves what is in it up one level")
    func deleteKeepingMovesUp() throws {
        let top = folder("Top"), mid = folder("Mid", in: top), low = folder("Low", in: mid)
        let n = note("N", in: mid)
        try Folder.delete(mid, .keepingNotes, from: context)
        #expect(low.parent === top)
        #expect(n.folder === top)
        #expect(Folder.children(of: top, in: everyFolder).map(\.name) == ["Low"])
    }

    @Test("A deleted-with folder restored alone goes to the top level, not into a hidden folder")
    func restoreChildAlone() throws {
        let cs = folder("CS133"), labs = folder("Labs", in: cs)
        try Folder.delete(cs, .withNotes, from: context)
        try Folder.restore([labs], in: context)
        #expect(labs.isLive && labs.parent == nil)
    }

    @Test("Deleting for good takes the whole group once, even handed in together")
    func deleteForGoodOnce() throws {
        let cs = folder("CS133"), labs = folder("Labs", in: cs)
        note("Lecture", in: cs); note("Lab", in: labs)
        let outside = note("Outside")
        try Folder.delete(cs, .withNotes, from: context)

        try Folder.deleteForGood([cs, labs], from: context)

        #expect(everyFolder.isEmpty)
        #expect((try context.fetch(FetchDescriptor<Page>())).map(\.title) == ["Outside"])
        _ = outside
    }

    @Test("Run destinations are inherited down the folders")
    func runDestinationInherits() {
        let cs = folder("CS133"), labs = folder("Labs", in: cs)
        cs.runDestination = "onlinegdb"
        let n = note("N", in: labs)
        let levels = n.runDestinationLevels(appDefault: "app")
        #expect(RunDestinationPreference.resolve(levels).id == CodeDestination.onlineGDB.id)
    }

    // MARK: Home and export

    @Test("Home's tiles are the top-level folders, counting the folders in them")
    func homeTiles() {
        let cs = folder("CS133"), labs = folder("Labs", in: cs)
        let n1 = note("A", in: cs), n2 = note("B", in: labs)
        let home = HomeSections(pages: [n1, n2], folders: everyFolder, lastOpened: nil)
        #expect(home.folders.map(\.folder.name) == ["CS133"])
        #expect(home.folders.map(\.noteCount) == [2])
    }

    @Test("Export makes a directory for each folder inside its parent's, names unique among siblings")
    func exportPlanNests() {
        let plan = NoteExport.plan(
            folderNames: ["CS133", "Labs", "Labs", "Other"],
            parents: [nil, 0, 0, nil],
            items: [
                NoteExport.Item(folder: 1, title: "Lab 1"),
                NoteExport.Item(folder: 2, title: "Lab 1"),
                NoteExport.Item(folder: nil, title: "Top"),
            ]
        )
        #expect(plan.directories == ["CS133", "CS133/Labs", "CS133/Labs 2", "Other"])
        #expect(plan.entries.map(\.directory) == ["CS133/Labs", "CS133/Labs 2", nil])
    }

    @Test("Export All's layout reads the nesting off the folders")
    func exportLayoutNests() {
        let cs = folder("CS133"), labs = folder("Labs", in: cs)
        let n = note("Lab 1", in: labs)
        let layout = NoteExportJob.layout(of: [n], in: everyFolder)
        #expect(layout.plan.directories == ["CS133", "CS133/Labs"])
        #expect(layout.plan.entries.first?.directory == "CS133/Labs")
    }

    // MARK: Dropped on Recently Deleted

    @Test("A note dropped on Recently Deleted is deleted and saved")
    func noteDroppedOnRecentlyDeleted() throws {
        let a = folder("A")
        let n = note("Lecture", in: a)
        try context.save()
        let action = try #require(ListDrop.resolve(.note(n), onto: .recentlyDeleted, zone: .into, among: everyFolder))
        #expect(action == .deleteNote(n))
        ListDrop.perform(action, among: everyFolder, in: context)

        // A fresh context reads only what was saved.
        let fresh = ModelContext(container)
        let pages = try fresh.fetch(FetchDescriptor<Page>())
        #expect(pages.count == 1 && pages[0].deletedAt != nil)
        #expect(pages[0].folder != nil, "it keeps its folder, so restoring puts it back")
    }

    @Test("A folder dropped on Recently Deleted goes with its notes and folders, saved")
    func folderDroppedOnRecentlyDeleted() throws {
        let a = folder("A"), b = folder("B", in: a)
        note("One", in: a); note("Two", in: b)
        try context.save()
        let action = try #require(ListDrop.resolve(.folder(a), onto: .recentlyDeleted, zone: .into, among: everyFolder))
        ListDrop.perform(action, among: everyFolder, in: context)

        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<Folder>()).allSatisfy { $0.deletedAt != nil })
        #expect(try fresh.fetch(FetchDescriptor<Page>()).allSatisfy { $0.deletedAt != nil })
    }

    @Test("Something already in Recently Deleted can't be dropped on it again")
    func deletedStaysPut() throws {
        let n = note("Old")
        try Page.moveToRecentlyDeleted([n], from: context)
        #expect(ListDrop.resolve(.note(n), onto: .recentlyDeleted, zone: .into, among: everyFolder) == nil)
    }
}
