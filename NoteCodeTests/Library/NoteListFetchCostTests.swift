//
//  NoteListFetchCostTests.swift
//  NoteCodeTests
//
//  F8: what the note list and Home fetch. Today each `@Query` takes every
//  note, deleted ones too, with every attribute (the ink among them), and
//  filters in memory.
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

@Suite("What the note lists fetch costs", .tags(.library, .perf), .serialized)
@MainActor
struct NoteListFetchCostTests {

    static let live = 240
    static let deleted = 120

    /// A store on disk (external storage is not used in memory) of 300 notes
    /// with a page and a half of text each, the odd one with ink big enough to
    /// be kept in a file.
    static func makeStore() throws -> (ModelContainer, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("F8-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("store.sqlite")
        let schema = NoteSchema.current
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        let folders = (0..<5).map { Folder(name: "Class \($0)") }
        folders.forEach(context.insert)
        let paragraph = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 12) + "\n\n"
        let ink = Data((0..<400_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        for n in 0..<(live + deleted) {
            let page = Page(title: n % 3 == 0 ? "Note \(n)" : "Untitled",
                            content: "# Lecture \(n)\n\n" + String(repeating: paragraph, count: 40) + "```cpp\nint main() {}\n```\n",
                            drawingData: n % 2 == 0 ? ink : Data())
            page.modifiedAt = Date(timeIntervalSince1970: TimeInterval(n) * 3_600)
            page.folder = folders[n % folders.count]
            if n >= live { page.deletedAt = .now }
            context.insert(page)
        }
        try context.save()
        return (container, dir)
    }

    /// What a row of the list reads of a note.
    private static func touch(_ pages: [Page]) -> Int {
        var n = 0
        for page in pages {
            n += page.displayTitle.count + (page.isPinned ? 1 : 0) + (page.folder == nil ? 0 : 1)
            _ = page.modifiedAt
        }
        return n
    }

    private func measure(_ name: String, _ descriptor: FetchDescriptor<Page>, in container: ModelContainer) throws -> [PersistentIdentifier] {
        let context = ModelContext(container)
        let start = ContinuousClock.now
        let pages = try context.fetch(descriptor)
        _ = Self.touch(pages)
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("F8 \(name): \(pages.count) notes, \(String(format: "%.1f", seconds * 1000)) ms")
        reportPerf("NoteListFetchCost/\(name)", seconds: seconds)
        return pages.map(\.persistentModelID)
    }

    static let sort = [SortDescriptor(\Page.modifiedAt, order: .reverse)]

    /// What `NoteList` and `Home` ask the store for, and what they asked
    /// before F8.
    static var liveList: FetchDescriptor<Page> {
        FetchDescriptor<Page>(predicate: Page.livePredicate, sortBy: sort)
    }

    @Test("Before and after: a store with many notes in Recently Deleted")
    func fetchCost() throws {
        let (container, dir) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try measure("warmup", FetchDescriptor<Page>(sortBy: Self.sort), in: container)
        // Before: everything, the way the bare @Query asked.
        let everything = try measure("everything", FetchDescriptor<Page>(sortBy: Self.sort), in: container)
        // After: the live notes, and the foot's count.
        let live = try measure("live-only", Self.liveList, in: container)
        let start = ContinuousClock.now
        _ = Page.deletedCount(in: ModelContext(container))
        let elapsed = ContinuousClock.now - start
        print("F8 deleted-count: \(elapsed)")

        #expect(live.count == Self.live)
        #expect(everything.count == Self.live + Self.deleted)
    }
}

@Suite("What the note lists fetch", .tags(.library))
@MainActor
struct NoteListQueryTests {
    @Test("The lists' queries hold the same notes in the same order, and the foot counts the deleted ones")
    func sameContents() throws {
        let (container, dir) = try NoteListFetchCostTests.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let context = ModelContext(container)

        let before = try context.fetch(FetchDescriptor<Page>(sortBy: NoteListFetchCostTests.sort)).live.map(\.persistentModelID)
        let after = try context.fetch(NoteListFetchCostTests.liveList).map(\.persistentModelID)
        #expect(after == before)
        #expect(after.count == NoteListFetchCostTests.live)

        #expect(Page.deletedCount(in: context) == NoteListFetchCostTests.deleted)
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit

/// The foot's Recently Deleted row with the list on screen: a purge, Delete Now
/// or Delete All changes no live note, so only a save of the context can tell
/// the list. SwiftUI's text isn't reachable from a test, so this watches the
/// row itself come and go (a cell of the list), which the count decides.
@Suite("The list's Recently Deleted row follows the store", .tags(.library))
@MainActor
struct NoteListDeletedCountTests {

    /// The cells showing: a row that has been taken away is left hidden in the
    /// tree until the list's animation ends.
    private static func cells(in view: UIView) -> Int {
        (view is UICollectionViewCell && !view.isHidden ? 1 : 0) + view.subviews.reduce(0) { $0 + cells(in: $1) }
    }

    @Test("Purging every deleted note, with no live note changing, takes the row away")
    func rowFollowsPurge() async throws {
        let schema = NoteSchema.current
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        context.insert(Page(title: "Live", content: "kept"))
        let gone = (0..<3).map { Page(title: "Gone \($0)", content: "x") }
        gone.forEach { context.insert($0); $0.deletedAt = .now }
        try context.save()

        let list = NoteList(selection: .constant(nil), navigation: NoteNavigation(), searchText: .constant(""))
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = UIHostingController(rootView: NavigationStack { list }.modelContainer(container))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        // The live note, the Recently Deleted row and the foot's rows.
        let drawn = await waitFor({ window.layoutIfNeeded(); return Self.cells(in: window) >= 6 })
        #expect(drawn)
        let withRow = Self.cells(in: window)

        // The 30-day purge, Delete Now, Delete All: deleted notes go, no live note changes.
        let other = ModelContext(container)
        let ids = Set(gone.map(\.persistentModelID))
        let victims = try other.fetch(FetchDescriptor<Page>(predicate: Page.deletedPredicate)).filter { ids.contains($0.persistentModelID) }
        try Page.delete(victims, from: other)
        try other.save()
        let gone1 = await waitFor({ window.layoutIfNeeded(); return Self.cells(in: window) < withRow })
        #expect(gone1)
        #expect(Self.cells(in: window) == withRow - 1)
    }
}
#endif
