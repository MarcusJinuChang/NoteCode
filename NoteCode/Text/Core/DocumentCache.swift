//
//  DocumentCache.swift
//  NoteCode
//
//  The parse cache and the UTF-8 conversion every parse starts from. Pure: no UIKit, no TextKit.
//

import Foundation

// MARK: - Region cache

/// Avoids re-parsing the document once per visible fragment during layout.
///
/// TextKit 2 lays out lazily, so the fragment delegate is called for every
/// paragraph entering the viewport. Parsing each time would be O(document) per
/// fragment; caching against the source string makes it O(document) per edit.
extension String {
    /// This text in Swift's own UTF-8 storage.
    ///
    /// `UITextView.text` hands back a String backed by the text storage's
    /// NSString, and every character read through it is a message send:
    /// parsing a 23KB note took about 3ms a keystroke in a Release build,
    /// most of it in `characterAtIndex:` (sampled on the simulator, 25
    /// September). Converting it first is one bulk copy.
    ///
    /// Parse and index the same converted text. Indices from one backing
    /// used on the other are reconciled on every use — see
    /// `DocumentStyler.applyStyling(to:snapshot:previousSignatures:)`.
    nonisolated var nativeUTF8: String {
        var copy = self
        copy.makeContiguousUTF8()
        return copy
    }
}

/// Holds the snapshot of the text last asked about. A snapshot works out its
/// parse and code ranges once and keeps them, so this only has to decide
/// whether the text it was given is the text it already has.
final class DocumentCache {
    private var cachedSnapshot: DocumentSnapshot?

    /// How many snapshots were made, each of which parses at most once. Exists
    /// so tests can prove the cache is doing its job: a keystroke should cost
    /// one parse, not several.
    private(set) var parseCount = 0

    /// The snapshot of `source`, made again only when the text differs from
    /// the last one asked for.
    func snapshot(for source: String) -> DocumentSnapshot {
        if let cachedSnapshot, cachedSnapshot.source == source { return cachedSnapshot }
        let snapshot = DocumentSnapshot(text: source)
        cachedSnapshot = snapshot
        parseCount += 1
        return snapshot
    }

    func blocks(for source: String) -> [BlockNode] {
        snapshot(for: source).blocks
    }

    /// The code blocks, as UTF-16 ranges.
    func codeRanges(for source: String) -> [CodeRange] {
        snapshot(for: source).codeRanges
    }
}
