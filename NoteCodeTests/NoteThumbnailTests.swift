//
//  NoteThumbnailTests.swift
//  NoteCodeTests
//
//  Phase 2 of v3: a picture of a note's first page, made without laying out
//  the rest of the note, and kept under a name that changes when the note does.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import NoteCode

@Suite("Note thumbnails: what they are made from")
@MainActor
struct NoteThumbnailRulesTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func savedPage(_ title: String = "Note") throws -> Page {
        let page = Page(title: title)
        context.insert(page)
        try context.save()
        return page
    }

    @Test("A thumbnail is shown dark in a dark appearance, light otherwise")
    func darkPaper() {
        #expect(NoteThumbnail.isShownDark(colorScheme: .dark))
        #expect(!NoteThumbnail.isShownDark(colorScheme: .light))
    }

    // MARK: Prefix

    @Test("A short note is drawn whole")
    func shortNoteIsWhole() {
        let text = "# Title\n\nA line.\n\n```cpp\nint x;\n```\n"
        #expect(NoteThumbnail.prefix(of: text) == text)
        #expect(NoteThumbnail.prefix(of: "") == "")
    }

    @Test("A long note is cut at its paragraph limit, so page 1 never needs the rest")
    func longNoteIsCut() {
        let text = (1...2000).map { "Line \($0)" }.joined(separator: "\n")
        let prefix = NoteThumbnail.prefix(of: text)
        #expect(prefix.split(separator: "\n", omittingEmptySubsequences: false).count == NoteThumbnail.maxParagraphs)
        #expect(prefix.hasPrefix("Line 1\nLine 2\n"))
        #expect(!prefix.contains("Line 2000"))
    }

    @Test("One enormous paragraph is cut at the character limit")
    func enormousParagraphIsCut() {
        let text = String(repeating: "word ", count: 20_000)
        #expect(NoteThumbnail.prefix(of: text).count == NoteThumbnail.maxCharacters)
    }

    @Test("The prefix is long enough for a page: the most a page holds fits inside it")
    func prefixCoversAPage() {
        // A page's body is 912pt tall in portrait and no line is under 17pt,
        // so 53 paragraphs at most; the limit must be clear of that.
        #expect(NoteThumbnail.maxParagraphs >= 60)
        // About 55 lines of 100 characters is the fullest page of prose.
        #expect(NoteThumbnail.maxCharacters >= 6_000)
    }

    // MARK: Cache names

    @Test("A note's cache name is stable, and changes with its date and its note")
    func cacheNames() throws {
        let a = try savedPage("A")
        let b = try savedPage("B")
        let idA = try #require(a.settledID)
        let idB = try #require(b.settledID)
        let date = Date(timeIntervalSince1970: 1_791_800_000.25)

        let name = try #require(NoteThumbnail.cacheName(for: idA, modifiedAt: date))
        #expect(name.hasSuffix(".png"))
        #expect(Set((0..<50).compactMap { _ in NoteThumbnail.cacheName(for: idA, modifiedAt: date) }).count == 1)

        let later = try #require(NoteThumbnail.cacheName(for: idA, modifiedAt: date.addingTimeInterval(1)))
        #expect(later != name, "a note edited since has a new name, so the old picture is never read")
        #expect(NoteThumbnail.owner(ofCacheName: later) == NoteThumbnail.owner(ofCacheName: name))

        let other = try #require(NoteThumbnail.cacheName(for: idB, modifiedAt: date))
        #expect(other != name)
        #expect(NoteThumbnail.owner(ofCacheName: other) != NoteThumbnail.owner(ofCacheName: name))
    }

    @Test("A line spacing is in the cache name, and none leaves the name as it was")
    func lineSpacingIsInTheName() throws {
        let page = try savedPage("A")
        let id = try #require(page.settledID)
        let date = Date(timeIntervalSince1970: 1_791_800_000)
        let plain = try #require(NoteThumbnail.cacheName(for: id, modifiedAt: date))
        let spaced = try #require(NoteThumbnail.cacheName(for: id, modifiedAt: date, typography: NoteTypography(lineSpacing: 6)))
        #expect(plain == NoteThumbnail.cacheName(for: id, modifiedAt: date, typography: NoteTypography(lineSpacing: 0)))
        #expect(spaced != plain && spaced.contains("-s6"))
        #expect(NoteThumbnail.owner(ofCacheName: spaced) == NoteThumbnail.owner(ofCacheName: plain))
    }

    @Test("Paper is in the cache name, blank leaves it as it was, and it is still a file name")
    func paperIsInTheName() throws {
        let page = try savedPage("A")
        let id = try #require(page.settledID)
        let date = Date(timeIntervalSince1970: 1_791_800_000)
        let plain = try #require(NoteThumbnail.cacheName(for: id, modifiedAt: date))
        #expect(plain == NoteThumbnail.cacheName(for: id, modifiedAt: date, paper: .blank))
        let grid = try #require(NoteThumbnail.cacheName(for: id, modifiedAt: date, paper: PaperSetup(style: .grid)))
        let fine = try #require(NoteThumbnail.cacheName(for: id, modifiedAt: date, paper: PaperSetup(style: .grid, spacing: .fine)))
        #expect(Set([plain, grid, fine]).count == 3)
        #expect(!fine.contains("/") && fine.contains("-pgrid_fine"))
        #expect(NoteThumbnail.owner(ofCacheName: fine) == NoteThumbnail.owner(ofCacheName: plain))
    }

    @Test("A note not yet saved has no cache name")
    func unsavedNoteHasNoName() {
        let page = Page(title: "New")
        context.insert(page)
        #expect(NoteThumbnail.cacheName(for: page.persistentModelID, modifiedAt: .now) == nil)
    }

    @Test("The cache name is a file name: nothing in it a path would treat as more")
    func cacheNameIsAFileName() throws {
        let page = try savedPage()
        let id = try #require(page.settledID)
        let name = try #require(NoteThumbnail.cacheName(for: id, modifiedAt: .now))
        #expect(name.allSatisfy { $0.isHexDigit || $0 == "-" || $0 == "." || "png".contains($0) }, Comment(rawValue: name))
    }
}

#if canImport(UIKit)

import PaperKit
import UIKit

@Suite("Note thumbnails: pictures", .serialized)
@MainActor
struct NoteThumbnailPictureTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    /// 2,000 lines: about forty pages.
    static let longText = (1...2000).map { "Line \($0): the loop invariant holds before and after every iteration gjpqy." }
        .joined(separator: "\n")

    private func render(_ text: String, orientation: PageOrientation = .portrait, ink: PaperMarkup? = nil) async throws -> UIImage {
        var data = Data()
        if let ink {
            data = try await DrawingCodec.encode(ink)
        }
        let source = NoteThumbnail.Source(text: text, orientation: orientation, drawingData: data)
        return try #require(await NoteThumbnail.render(source))
    }

    /// The picture's pixels as RGBA, and its size in pixels.
    private func pixels(of image: UIImage) throws -> (data: [UInt8], width: Int, height: Int) {
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (data, width, height)
    }

    /// How many pixels in rows `rows` are not white.
    private func inked(_ picture: (data: [UInt8], width: Int, height: Int), rows: Range<Int>) -> Int {
        var count = 0
        for y in rows {
            for x in 0..<picture.width {
                let i = (y * picture.width + x) * 4
                if picture.data[i] < 200 || picture.data[i + 1] < 200 || picture.data[i + 2] < 200 { count += 1 }
            }
        }
        return count
    }

    @Test("A thumbnail is the whole Letter page, in its note's orientation, at the thumbnail's resolution", arguments: PageOrientation.allCases)
    func size(orientation: PageOrientation) async throws {
        let image = try await render("Hello", orientation: orientation)
        let page = PageLayout(orientation: orientation, mode: .print).pageSize
        #expect(Int(image.size.width) == Int((page.width * NoteThumbnail.pixelsPerPagePoint).rounded()))
        #expect(Int(image.size.height) == Int((page.height * NoteThumbnail.pixelsPerPagePoint).rounded()))
    }

    @Test("Its text is on the page's top and its foot is blank paper")
    func textIsDrawn() async throws {
        let picture = try pixels(of: try await render("# gjpqy heading\n\nA line of text, and another line.\n\n```cpp\nint x = 1;\n```"))
        let top = picture.height / 3
        #expect(inked(picture, rows: 0..<top) > 200, "no text on the page's top")
        #expect(inked(picture, rows: (picture.height * 2 / 3)..<picture.height) == 0, "something on the page's foot")
    }

    @Test("It is paper: white behind the text, the same under a dark trait collection")
    func paperIsWhite() async throws {
        let picture = try pixels(of: try await render(""))
        #expect(inked(picture, rows: 0..<picture.height) == 0)
        // Corner pixels, as RGBA.
        #expect(Array(picture.data[0..<4]) == [255, 255, 255, 255])
    }

    @Test("A note with no text but ink on page 1 shows the ink, and ink on page 3 is not drawn")
    func inkOnPageOne() async throws {
        let layout = PageLayout(orientation: .portrait, mode: .print)
        let blank = try pixels(of: try await render(""))

        let onFirst = TestInk.markup(strokesAt: [layout.sheet(ofPage: 0).minY + 300])
        let withInk = try pixels(of: try await render("", ink: onFirst))
        #expect(inked(withInk, rows: 0..<withInk.height) > inked(blank, rows: 0..<blank.height), "page 1's ink is missing")

        let onThird = TestInk.markup(strokesAt: [layout.sheet(ofPage: 2).minY + 300])
        let elsewhere = try pixels(of: try await render("", ink: onThird))
        #expect(elsewhere.data == blank.data, "ink on page 3 reached page 1's picture")
    }

    // MARK: Cost

    /// Seconds a block takes, with the main actor released between steps.
    private func seconds(_ body: () async throws -> Void) async rethrows -> Double {
        let start = ContinuousClock.now
        try await body()
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    @Test("A 2,000-line note's thumbnail costs what a one-page note's does: the rest is never laid out")
    func costDoesNotGrowWithTheNote() async throws {
        // Once first, so a cold highlighter doesn't count against either.
        _ = try await render("warm up")

        let short = String(Self.longText.split(separator: "\n").prefix(40).joined(separator: "\n"))
        var shortBest = Double.infinity
        var longBest = Double.infinity
        for _ in 0..<3 {
            shortBest = min(shortBest, try await seconds { _ = try await render(short) })
            longBest = min(longBest, try await seconds { _ = try await render(Self.longText) })
        }
        print("thumbnail cost: 40 lines \(shortBest * 1000)ms, 2,000 lines \(longBest * 1000)ms")

        // Laying the whole note out costs many times what one page does. With
        // the prefix both are page 1 (the long one a little more of it:
        // 80 lines against 40).
        #expect(longBest < shortBest * 3 + 0.05, "2,000 lines took \(longBest)s against \(shortBest)s for 40")
        #expect(longBest < 1.0, "a thumbnail took \(longBest)s")
    }

    // MARK: The store

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "NoteThumbnailTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func savedPage(_ text: String) throws -> Page {
        let page = Page(title: "Note", content: text)
        context.insert(page)
        try context.save()
        return page
    }

    @Test("A picture is made once, then served from memory, then from its file in a new session")
    func caching() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try savedPage("Hello, thumbnail")

        let store = ThumbnailStore(directory: directory)
        #expect(store.existing(for: page) == nil)
        let made = try #require(await store.thumbnail(for: page))
        #expect(store.rendered == 1)
        #expect(store.existing(for: page) != nil)

        let again = try #require(await store.thumbnail(for: page))
        #expect(again === made, "served from memory")
        #expect(store.rendered == 1)

        let reopened = ThumbnailStore(directory: directory)
        let read = try #require(await reopened.thumbnail(for: page))
        #expect(reopened.rendered == 0, "read back from the file, not drawn again")
        #expect(Int(read.size.width) == Int(made.size.width))
    }

    @Test("A note edited since has a new picture, and its old file is gone")
    func editedNoteIsRedrawn() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try savedPage("First draft")
        let store = ThumbnailStore(directory: directory)
        _ = await store.thumbnail(for: page)
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(before.count == 1)

        page.content = "Second draft"
        page.modifiedAt = page.modifiedAt.addingTimeInterval(60)
        #expect(store.existing(for: page) == nil, "the old picture is for the old date")
        _ = await store.thumbnail(for: page)

        let after = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(store.rendered == 2)
        #expect(after.count == 1, "the note's old picture was removed: \(after)")
        #expect(after != before)
    }

    @Test("A note that has gone, or isn't saved, gets no picture and nothing is drawn")
    func goneNoteGetsNothing() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailStore(directory: directory)

        let unsaved = Page(title: "Unsaved", content: "text")
        #expect(await store.thumbnail(for: unsaved) == nil, "not in a context")

        let deleted = try savedPage("Deleted note")
        deleted.deletedAt = .now
        #expect(await store.thumbnail(for: deleted) == nil, "in Recently Deleted")
        #expect(store.rendered == 0)
    }

    @Test("Requests are served one at a time, each its own turn")
    func oneAtATime() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailStore(directory: directory)
        let pages = try (0..<6).map { try savedPage("Note \($0)") }

        // All asked at once, the way a screenful of rows asks.
        let images = await withTaskGroup(of: UIImage?.self) { group in
            for page in pages {
                group.addTask { @MainActor in await store.thumbnail(for: page) }
            }
            var all: [UIImage?] = []
            for await image in group { all.append(image) }
            return all
        }
        #expect(images.compactMap { $0 }.count == 6)
        #expect(store.rendered == 6)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 6)
    }

    @Test("A request cancelled while it waits its turn draws nothing")
    func cancelledRequestIsSkipped() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailStore(directory: directory)
        let first = try savedPage("First")
        let second = try savedPage("Second")

        let ahead = Task { @MainActor in await store.thumbnail(for: first) }
        let behind = Task { @MainActor in await store.thumbnail(for: second) }
        behind.cancel()
        #expect(await ahead.value != nil)
        #expect(await behind.value == nil)
        #expect(store.rendered == 1)
    }
}

#endif
