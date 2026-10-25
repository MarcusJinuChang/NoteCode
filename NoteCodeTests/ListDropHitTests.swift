//
//  ListDropHitTests.swift
//  NoteCodeTests
//
//  Which row a drop is over, from where the rows are. The drop itself reaches
//  the list only on a device (`ListDragUITests`).
//

import CoreGraphics
import Testing
@testable import NoteCode

@Suite("Where a drop lands in the list")
struct ListDropHitTests {

    /// Three rows 44 tall with 8 between them, in the window: 100-144,
    /// 152-196, 204-248.
    private let rows: [String: CGRect] = [
        "a": CGRect(x: 0, y: 100, width: 300, height: 44),
        "b": CGRect(x: 0, y: 152, width: 300, height: 44),
        "c": CGRect(x: 0, y: 204, width: 300, height: 44),
    ]

    @Test("the row under the finger, and the zone of it")
    func underFinger() throws {
        let top = try #require(ListDropHit.row(atY: 102, in: rows))
        #expect(top.id == "a" && top.zone == .before)
        let middle = try #require(ListDropHit.row(atY: 174, in: rows))
        #expect(middle.id == "b" && middle.zone == .into)
        let bottom = try #require(ListDropHit.row(atY: 245, in: rows))
        #expect(bottom.id == "c" && bottom.zone == .after)
    }

    @Test("the gap between two rows goes to the nearer, not nowhere")
    func gaps() throws {
        // 146 is 2 below a, 6 above b: only a is within the slack.
        #expect(ListDropHit.row(atY: 146, in: rows)?.id == "a")
        #expect(ListDropHit.row(atY: 150, in: rows)?.id == "b")
    }

    @Test("a row's own span wins over a neighbour's slack")
    func ownSpanWins() throws {
        let tight: [String: CGRect] = [
            "a": CGRect(x: 0, y: 100, width: 300, height: 44),
            "b": CGRect(x: 0, y: 144, width: 300, height: 44),
        ]
        #expect(ListDropHit.row(atY: 143, in: tight)?.id == "a")
        #expect(ListDropHit.row(atY: 144, in: tight)?.id == "b")
    }

    @Test("above, below and between the list's rows is nowhere")
    func outside() {
        #expect(ListDropHit.row(atY: 50, in: rows) == nil)
        #expect(ListDropHit.row(atY: 400, in: rows) == nil)
        #expect(ListDropHit.row(atY: 100, in: [String: CGRect]()) == nil)
    }
}
