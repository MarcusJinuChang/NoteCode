//
//  CodeBlockPosition.swift
//  NoteCode
//
//  Where a paragraph sits inside a fenced code block. Pure: no UIKit.
//

import Foundation

/// Where one paragraph sits inside a fenced code block.
///
/// TextKit 2 lays out a paragraph at a time, so a five-line code block is five
/// separate fragments that each draw independently. Knowing which end of the
/// block a fragment is at is what lets them round only the outer corners and
/// join into a single panel rather than five stacked boxes.
nonisolated enum CodeBlockPosition: Equatable {
    /// The whole block is one paragraph.
    case only
    case first
    case middle
    case last

    var roundsTop: Bool { self == .first || self == .only }
    var roundsBottom: Bool { self == .last || self == .only }

    /// Locates `element` within `block`, both as UTF-16 ranges.
    /// Returns `nil` when the element isn't part of the block.
    static func of(element: NSRange, in block: NSRange) -> CodeBlockPosition? {
        let blockEnd = block.location + block.length
        guard element.location >= block.location, element.location < blockEnd else {
            return nil
        }

        let isFirst = element.location == block.location
        let isLast = element.location + element.length >= blockEnd

        switch (isFirst, isLast) {
        case (true, true):   return .only
        case (true, false):  return .first
        case (false, true):  return .last
        case (false, false): return .middle
        }
    }
}
