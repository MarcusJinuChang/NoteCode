//
//  ModifiedAtBatcherTests.swift
//  NoteCodeTests
//
//  F6: `modifiedAt` is the list's sort key, so it is written when typing
//  pauses, not per keystroke; the text is saved as it was.
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

@Suite("Modified date batching")
@MainActor
struct ModifiedAtBatcherTests {

    private static let long = Date(timeIntervalSince1970: 1_000_000)

    private func makePage() throws -> (Page, ModelContext) {
        let container = try ModelContainer(
            for: NoteSchema.current,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let page = Page(createdAt: Self.long)
        context.insert(page)
        page.modifiedAt = Self.long
        return (page, context)
    }

    @Test("Typing leaves the date alone until it pauses")
    func notPerKeystroke() async throws {
        let (page, context) = try makePage()
        _ = context
        let clock = ManualClock()
        let batcher = ModifiedAtBatcher()

        for letter in ["a", "b", "c"] {
            page.content += letter
            batcher.edited(page, clock: clock)
            await clock.untilSleeping()
            clock.advance(by: .milliseconds(1_500))
        }
        #expect(page.modifiedAt == Self.long)
        #expect(page.content == "abc")

        clock.advance(by: .seconds(2))
        await batcher.settled()
        #expect(page.modifiedAt > Self.long)
        #expect(batcher.pendingEdit == nil)
    }

    @Test("Closing the note writes the date at once")
    func flushWritesNow() throws {
        let (page, context) = try makePage()
        _ = context
        let batcher = ModifiedAtBatcher()

        batcher.edited(page, clock: ManualClock())
        #expect(page.modifiedAt == Self.long)
        batcher.flush()
        #expect(page.modifiedAt > Self.long)
    }

    @Test("Nothing owed, nothing written")
    func flushWithoutEdit() throws {
        let (page, context) = try makePage()
        _ = context
        ModifiedAtBatcher().flush()
        #expect(page.modifiedAt == Self.long)
    }

    @Test("Another note's edit is written before the next is held")
    func switchingNotes() throws {
        let (first, context) = try makePage()
        let second = Page(createdAt: Self.long)
        context.insert(second)
        second.modifiedAt = Self.long
        let batcher = ModifiedAtBatcher()
        let clock = ManualClock()

        batcher.edited(first, clock: clock)
        batcher.edited(second, clock: clock)
        #expect(first.modifiedAt > Self.long)
        #expect(second.modifiedAt == Self.long)
    }

    @Test("A deleted note is not written to")
    func deletedLeftAlone() throws {
        let (page, context) = try makePage()
        let batcher = ModifiedAtBatcher()
        batcher.edited(page, clock: ManualClock())
        context.delete(page)
        batcher.flush()
        #expect(batcher.pendingEdit == nil)
    }
}
