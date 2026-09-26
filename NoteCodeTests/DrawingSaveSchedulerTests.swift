//
//  DrawingSaveSchedulerTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import Foundation
import PaperKit
import SwiftData
import Testing
@testable import NoteCode

@Suite("Drawing save scheduler")
@MainActor
struct DrawingSaveSchedulerTests {

    /// Stands in for the codec: records every encode, and writes bytes that
    /// say how many strokes were saved, so a test can tell which ink landed.
    actor Encoder {
        private(set) var calls = 0
        /// Seconds each call waits, by call; later calls don't wait.
        private let waits: [Double]
        /// Calls, counted from 0, that throw.
        private let failing: Set<Int>

        init(waits: [Double] = [], failing: Set<Int> = []) {
            self.waits = waits
            self.failing = failing
        }

        struct Failure: Error {}

        func encode(_ markup: PaperMarkup) async throws -> Data {
            let call = calls
            calls += 1
            if call < waits.count {
                try? await Task.sleep(for: .seconds(waits[call]))
            }
            if failing.contains(call) { throw Failure() }
            return Self.bytes(strokes: markup.subelements.count)
        }

        nonisolated static func bytes(strokes: Int) -> Data {
            Data([0xC0, UInt8(strokes)])
        }
    }

    /// An in-memory store, since a page saves only while it's in one, as
    /// every page in the app is.
    @MainActor
    private final class Store {
        let container: ModelContainer
        var context: ModelContext { container.mainContext }

        init() throws {
            container = try ModelContainer(
                for: Page.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }

        func insert(_ page: Page = Page()) -> Page {
            context.insert(page)
            return page
        }
    }

    private static func saver(for page: Page, delay: Duration = .milliseconds(50), encoder: Encoder) -> DrawingSaveScheduler {
        DrawingSaveScheduler(page: page, delay: delay, encode: { try await encoder.encode($0) })
    }

    private static func ink(strokes: Int) -> PaperMarkup {
        TestInk.markup(strokesAt: (0..<strokes).map { CGFloat(100 + $0 * 40) })
    }

    /// Waits for `condition`, up to `timeout`.
    private static func eventually(_ timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let end = clock.now + timeout
        while clock.now < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: When

    @Test("Ink is saved once drawing pauses, and not before")
    func savedAfterPause() async throws {
        let store = try Store()
        let page = store.insert()
        let encoder = Encoder()
        let saver = Self.saver(for: page, delay: .milliseconds(200), encoder: encoder)

        saver.inkDidChange(Self.ink(strokes: 1))
        #expect(page.drawingData.isEmpty)
        #expect(saver.isWaiting)

        #expect(await Self.eventually { page.drawingData == Encoder.bytes(strokes: 1) })
        #expect(!saver.isWaiting)
    }

    @Test("A burst of strokes is saved once, as the last of them")
    func burstSavedOnce() async throws {
        let store = try Store()
        let page = store.insert()
        let encoder = Encoder()
        let saver = Self.saver(for: page, encoder: encoder)

        for count in 1...5 {
            saver.inkDidChange(Self.ink(strokes: count))
        }

        #expect(await Self.eventually { page.drawingData == Encoder.bytes(strokes: 5) })
        #expect(await encoder.calls == 1)
    }

    @Test("Closing the note saves straight away")
    func flushSavesAtOnce() async throws {
        let store = try Store()
        let page = store.insert()
        let encoder = Encoder()
        let saver = Self.saver(for: page, delay: .seconds(60), encoder: encoder)

        saver.inkDidChange(Self.ink(strokes: 2))
        await saver.flush()

        #expect(page.drawingData == Encoder.bytes(strokes: 2))
        #expect(!saver.isWaiting)
    }

    @Test("A slow save can't land over a newer one")
    func newestInkWins() async throws {
        let store = try Store()
        let page = store.insert()
        // The first encode is slow; the one after it isn't.
        let encoder = Encoder(waits: [0.4])
        let saver = Self.saver(for: page, delay: .seconds(60), encoder: encoder)

        saver.inkDidChange(Self.ink(strokes: 1))
        let first = Task { await saver.flush() }
        try await Task.sleep(for: .milliseconds(100))

        saver.inkDidChange(Self.ink(strokes: 2))
        await saver.flush()
        await first.value

        #expect(page.drawingData == Encoder.bytes(strokes: 2))
    }

    // MARK: What it touches

    @Test("A save moves the note up the list")
    func saveBumpsModifiedAt() async throws {
        let long = Date(timeIntervalSince1970: 1_000_000)
        let store = try Store()
        let page = store.insert(Page(createdAt: long))
        let saver = Self.saver(for: page, encoder: Encoder())

        saver.inkDidChange(Self.ink(strokes: 1))
        await saver.flush()

        #expect(page.modifiedAt > long)
    }

    @Test("Opening a note with ink writes nothing")
    func openingWritesNothing() async throws {
        let long = Date(timeIntervalSince1970: 1_000_000)
        let stored = try await DrawingCodec.encode(Self.ink(strokes: 3))
        let store = try Store()
        let page = store.insert(Page(drawingData: stored, createdAt: long))
        let encoder = Encoder()
        let saver = Self.saver(for: page, encoder: encoder)

        let ink = saver.loadInk()
        await saver.flush()

        #expect(ink?.subelements.count == 3)
        #expect(saver.problem == nil)
        #expect(page.drawingData == stored)
        #expect(page.modifiedAt == long)
        #expect(await encoder.calls == 0)
    }

    // MARK: When things go wrong

    @Test("Unreadable ink is left alone, and the reader is told")
    func unreadableNeverOverwritten() async throws {
        let garbage = Data((0..<256).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        let store = try Store()
        let page = store.insert(Page(drawingData: garbage))
        let encoder = Encoder()
        let saver = Self.saver(for: page, encoder: encoder)

        #expect(saver.loadInk() == nil)
        #expect(saver.problem != nil)

        // What's drawn next would otherwise be saved over it.
        saver.inkDidChange(Self.ink(strokes: 1))
        await saver.flush()

        #expect(page.drawingData == garbage)
        #expect(await encoder.calls == 0)
        #expect(saver.problem != nil)
    }

    @Test("A save that fails is tried again, and the warning clears")
    func failedSaveRetried() async throws {
        let store = try Store()
        let page = store.insert()
        let encoder = Encoder(failing: [0])
        let saver = Self.saver(for: page, delay: .seconds(60), encoder: encoder)

        saver.inkDidChange(Self.ink(strokes: 1))
        await saver.flush()
        #expect(page.drawingData.isEmpty)
        #expect(saver.problem != nil)

        await saver.flush()
        #expect(page.drawingData == Encoder.bytes(strokes: 1))
        #expect(saver.problem == nil)
    }

    /// The deletion may or may not have been saved by the time the encode
    /// finishes, and a deleted page looks different in each case.
    ///
    /// This checks the outcome, not the scheduler's guard: writing to the
    /// deleted page did no harm either way when tried (23 September). What
    /// can't be checked is the page itself — reading its ink once the
    /// deletion is saved traps in SwiftData, since external storage leaves
    /// the attribute unloaded.
    @Test("Deleting a note while its ink saves neither crashes nor brings it back", arguments: [false, true])
    func deletedNoteLeftAlone(deletionSaved: Bool) async throws {
        let store = try Store()
        let context = store.context
        let page = store.insert()
        try context.save()

        let encoder = Encoder(waits: [0.2])
        let saver = Self.saver(for: page, delay: .seconds(60), encoder: encoder)
        saver.inkDidChange(Self.ink(strokes: 1))
        let saving = Task { await saver.flush() }
        try await Task.sleep(for: .milliseconds(50))

        context.delete(page)
        if deletionSaved {
            try context.save()
        }
        await saving.value
        // The store autosaves after the write lands, in the app.
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Page>()) == 0)
    }
}

#endif
