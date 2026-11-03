//
//  DrawingCodecTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import Foundation
import PaperKit
import PencilKit
import Testing
@testable import NoteCode

/// Ink to test with, built from strokes because they're easy to place.
enum TestInk {

    /// A short horizontal stroke centred on `y`.
    static func stroke(at y: CGFloat) -> PKStroke {
        let points = (0..<10).map { i in
            PKStrokePoint(
                location: CGPoint(x: 100 + CGFloat(i) * 10, y: y),
                timeOffset: Double(i) * 0.01,
                size: CGSize(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    /// A markup holding one stroke at each of `ys`.
    static func markup(strokesAt ys: [CGFloat]) -> PaperMarkup {
        var markup = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 816, height: 100_000))
        markup.append(contentsOf: PKDrawing(strokes: ys.map(stroke(at:))))
        return markup
    }

    /// Where each element sits, by id.
    static func frames(of markup: PaperMarkup) -> [MarkupOrderedSet.ElementID: CGRect] {
        Dictionary(
            markup.subelements.map { ($0.elementID, $0.renderFrame) },
            uniquingKeysWith: { _, last in last }
        )
    }
}

@Suite("Drawing codec")
@MainActor
struct DrawingCodecTests {

    private static func ink(in loaded: DrawingCodec.Loaded) -> PaperMarkup? {
        if case .ink(let markup) = loaded { return markup }
        return nil
    }

    private static func isUnreadable(_ loaded: DrawingCodec.Loaded) -> Bool {
        if case .unreadable = loaded { return true }
        return false
    }

    @Test("No bytes means a note never drawn on, not unreadable ink")
    func emptyIsNone() {
        let loaded = DrawingCodec.decode(Data())
        if case .none = loaded {} else {
            Issue.record("empty data read as \(loaded)")
        }
    }

    @Test("Bytes that aren't a drawing are unreadable")
    func garbageIsUnreadable() {
        let garbage = Data((0..<512).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) })
        #expect(Self.isUnreadable(DrawingCodec.decode(garbage)))
    }

    @Test("A drawing cut short is unreadable")
    func truncatedIsUnreadable() async throws {
        let data = try await DrawingCodec.encode(TestInk.markup(strokesAt: [300, 1500, 4000]))
        #expect(Self.isUnreadable(DrawingCodec.decode(data.prefix(data.count / 2))))
    }

    @Test("Ink comes back element for element, each where it was")
    func roundTrip() async throws {
        let markup = TestInk.markup(strokesAt: [300, 1500, 4000])
        let data = try await DrawingCodec.encode(markup)
        #expect(!data.isEmpty)

        let back = try #require(Self.ink(in: DrawingCodec.decode(data)))
        let before = TestInk.frames(of: markup)
        let after = TestInk.frames(of: back)

        // Ids too: `PageView` tells what the reader changed by id.
        #expect(Set(after.keys) == Set(before.keys))
        for (id, frame) in before {
            let restored = try #require(after[id])
            #expect(abs(restored.midY - frame.midY) < 0.01)
            #expect(abs(restored.midX - frame.midX) < 0.01)
        }
    }

    @Test("Ink with everything erased is stored as no bytes")
    func emptyInkIsNoBytes() async throws {
        let data = try await DrawingCodec.encode(PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 816, height: 1056)))
        #expect(data.isEmpty)
    }

    /// Reading happens on the main actor as a note opens, so it has to be
    /// quick for a heavily inked note.
    @Test("A thousand strokes read back quickly enough to open a note")
    func decodeCost() async throws {
        let markup = TestInk.markup(strokesAt: (0..<1000).map { CGFloat(100 + $0 * 9) })
        let data = try await DrawingCodec.encode(markup)

        var times: [TimeInterval] = []
        for _ in 0..<5 {
            let start = Date()
            let back = Self.ink(in: DrawingCodec.decode(data))
            times.append(Date().timeIntervalSince(start))
            #expect(back?.subelements.count == 1000)
        }

        let median = times.sorted()[2]
        print("DrawingCodec: 1,000 strokes, \(data.count) bytes, decoded in \(Int(median * 1000))ms (median of 5)")
        #expect(median < 0.25, "decoding 1,000 strokes took \(median)s")
    }
}

#endif
