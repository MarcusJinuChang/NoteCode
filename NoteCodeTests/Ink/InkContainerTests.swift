//
//  InkContainerTests.swift
//  NoteCodeTests
//
//  Step 1 of docs/design/object-system.md: the ink container in
//  `Page.drawingData`, with no schema change.
//

#if canImport(UIKit)

import Foundation
import PaperKit
import PencilKit
import SwiftData
import Testing
import UIKit
@testable import NoteCode

@Suite("Ink container")
@MainActor
struct InkContainerTests {

    private static func strokes(_ count: Int) -> PaperMarkup {
        var markup = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 816, height: 1056))
        var made: [any Markup] = []
        for i in 0..<count {
            let points = (0..<8).map { j in
                PKStrokePoint(
                    location: CGPoint(x: 20 + CGFloat(j) * 6, y: 20 + CGFloat(i) * 12),
                    timeOffset: TimeInterval(j) * 0.01, size: CGSize(width: 2, height: 2),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            made.append(PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0))))
        }
        markup.subelements.append(contentsOf: made)
        return markup
    }

    private static func table() -> InkObjectTable {
        InkObjectTable(entries: [
            .init(id: UUID(), kind: "stroke", group: UUID(),
                  anchor: InkAnchor(kind: "text", fields: ["offset": .number(120), "dx": .number(4.5), "dy": .number(-2)])),
            .init(id: UUID(), kind: "hologram", anchor: InkAnchor(kind: "orbit", fields: ["radius": .number(3), "tags": .array([.string("a"), .null, .bool(true)])]),
                  extra: ["future": .object(["x": .number(1)])]),
        ])
    }

    // MARK: Bytes

    @Test("An empty table stores exactly PaperKit's bytes")
    func emptyTableIsLegacy() async throws {
        let paper = try await Self.strokes(3).dataRepresentation()

        let stored = try InkContainer.wrap(table: .empty, paper: paper)

        #expect(stored == paper)
    }

    @Test("Legacy bytes read as ink with an empty table")
    func legacyReads() async throws {
        let paper = try await Self.strokes(3).dataRepresentation()

        let (loaded, table) = DrawingCodec.decodeAll(paper)

        guard case .ink(let markup) = loaded else { Issue.record("not ink: \(loaded)"); return }
        #expect(markup.subelements.count == 3)
        #expect(table.isEmpty)
    }

    @Test("A container reads as its ink and its table")
    func containerRoundTrip() async throws {
        let paper = try await Self.strokes(5).dataRepresentation()
        let table = Self.table()

        let stored = try InkContainer.wrap(table: table, paper: paper)
        let (loaded, read) = DrawingCodec.decodeAll(stored)

        #expect(stored != paper)
        guard case .ink(let markup) = loaded else { Issue.record("not ink: \(loaded)"); return }
        #expect(markup.subelements.count == 5)
        #expect(read == table)
    }

    @Test("Entries and fields this build doesn't know are written back as they were")
    func unknownSurvives() throws {
        let table = Self.table()
        let again = try JSONDecoder().decode(InkObjectTable.self, from: try table.data())

        #expect(again == table)
        #expect(try again.data() == table.data())
        #expect(again.entries[1].kind == "hologram")
        #expect(again.entries[1].anchor?.kind == "orbit")
        #expect(again.entries[1].extra["future"] == .object(["x": .number(1)]))
    }

    @Test("A table with nothing to draw still stores and reads")
    func tableWithoutInk() throws {
        let stored = try InkContainer.wrap(table: Self.table(), paper: Data())

        let (loaded, table) = DrawingCodec.decodeAll(stored)

        guard case .none = loaded else { Issue.record("not empty: \(loaded)"); return }
        #expect(table.entries.count == 2)
    }

    @Test("PaperKit alone refuses a container, so a build without it leaves the bytes be")
    func paperKitRefusesIt() async throws {
        let stored = try InkContainer.wrap(table: Self.table(), paper: try await Self.strokes(2).dataRepresentation())

        #expect((try? PaperMarkup(dataRepresentation: stored)) == nil)
    }

    @Test("A container from a newer build is unreadable, and so is a cut one")
    func newerAndCut() async throws {
        let stored = try InkContainer.wrap(table: Self.table(), paper: try await Self.strokes(2).dataRepresentation())

        var newer = stored
        newer[newer.startIndex + 4] = InkContainer.formatVersion + 1
        guard case .unreadable(let reason) = DrawingCodec.decodeAll(newer).loaded else { Issue.record("read a newer container"); return }
        #expect(reason.contains("newer version"))

        let cut = stored.prefix(12)
        guard case .unreadable = DrawingCodec.decodeAll(Data(cut)).loaded else { Issue.record("read a cut container"); return }

        var future = Self.table()
        future.version = InkObjectTable.currentVersion + 1
        let futureBytes = try InkContainer.wrap(table: future, paper: Data())
        guard case .unreadable = DrawingCodec.decodeAll(futureBytes).loaded else { Issue.record("read a newer table"); return }
    }

    // MARK: The scheduler carries the table

    @Test("A save writes the table back with the ink, and an empty table writes plain PaperKit bytes")
    func schedulerKeepsTable() async throws {
        let container = try ModelContainer(for: NoteSchema.current, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let page = Page()
        container.mainContext.insert(page)
        let table = Self.table()
        page.drawingData = try InkContainer.wrap(table: table, paper: try await Self.strokes(2).dataRepresentation())

        let saver = DrawingSaveScheduler(page: page, delay: .milliseconds(10))
        let ink = try #require(saver.loadInk())
        #expect(saver.objects == table)

        saver.inkDidChange(Self.strokes(ink.subelements.count + 1))
        await saver.flush()

        let (loaded, read) = DrawingCodec.decodeAll(page.drawingData)
        guard case .ink(let saved) = loaded else { Issue.record("not ink"); return }
        #expect(saved.subelements.count == 3)
        #expect(read == table)

        // A note that never had a table stays as plain as it was.
        let plain = Page()
        container.mainContext.insert(plain)
        let other = DrawingSaveScheduler(page: plain, delay: .milliseconds(10))
        other.inkDidChange(Self.strokes(1))
        await other.flush()
        #expect(InkContainer.unwrap(plain.drawingData) == .legacy(plain.drawingData))
        #expect(plain.drawingData.prefix(4) != InkContainer.magic)
    }

    @Test("A container this build can't read is never written over")
    func unreadableContainerIsLeftAlone() async throws {
        let container = try ModelContainer(for: NoteSchema.current, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let page = Page()
        container.mainContext.insert(page)
        var stored = try InkContainer.wrap(table: Self.table(), paper: try await Self.strokes(2).dataRepresentation())
        stored[stored.startIndex + 4] = InkContainer.formatVersion + 1
        page.drawingData = stored

        let saver = DrawingSaveScheduler(page: page, delay: .milliseconds(10))
        #expect(saver.loadInk() == nil)
        saver.inkDidChange(Self.strokes(1))
        await saver.flush()

        #expect(page.drawingData == stored)
        #expect(saver.problem != nil)
    }
}

#endif
