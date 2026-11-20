//
//  CodeBlockIdentity.swift
//  NoteCode
//
//  Identifying a code block across edits, so a run result can stay attached to
//  the block that produced it.
//

import Foundation

/// Identity for a fenced code block that survives editing elsewhere in the page.
///
/// Regions are otherwise purely positional, and a range shifts the moment you
/// type anything above it — so a range alone can't hold a run result in place.
/// Two parts, because neither works alone:
///
/// - `ordinal` — which code block this is in document order. Unchanged when you
///   type in prose, or inside a *different* block; changes when a block is
///   inserted or removed above this one.
/// - `contentHash` — what the code currently says. Changes the moment this block
///   is edited, which is what discards a result that belonged to code the user
///   has since changed.
///
/// Together: a result survives typing anywhere that doesn't touch its block, and
/// is dropped as soon as the block itself changes or moves.
nonisolated struct CodeBlockID: Hashable, Sendable {
    var ordinal: Int
    var contentHash: UInt64

    init(ordinal: Int, code: String) {
        self.ordinal = ordinal
        self.contentHash = Self.hash(code)
    }

    /// FNV-1a.
    ///
    /// Deliberately not Swift's `Hasher`, which seeds randomly per process —
    /// values keyed by it would behave differently run to run and couldn't be
    /// asserted in a test. This is deterministic and cheap.
    static func hash(_ code: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in code.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }
}
