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
    /// `DocumentStyler.applyStyling(to:source:blocks:previousSignatures:)`.
    nonisolated var nativeUTF8: String {
        var copy = self
        copy.makeContiguousUTF8()
        return copy
    }
}

final class DocumentCache {
    private var cachedSource: String?
    private var cachedBlocks: [BlockNode] = []

    /// How many times the parser actually ran. Exists so tests can prove the
    /// cache is doing its job — a keystroke should cost one parse, not several.
    private(set) var parseCount = 0

    func blocks(for source: String) -> [BlockNode] {
        if cachedSource != source {
            cachedSource = source
            cachedBlocks = DocumentParser.parse(source)
            cachedCodeRanges = nil
            parseCount += 1
        }
        return cachedBlocks
    }

    private var cachedCodeRanges: [CodeRange]?

    /// The code blocks, as UTF-16 ranges.
    ///
    /// Converted against the string the blocks were parsed from. Their
    /// indices belong to that instance, and converting them against another,
    /// even an equal one, forces index reconciliation on every use.
    func codeRanges(for source: String) -> [CodeRange] {
        let blocks = blocks(for: source)
        if let cachedCodeRanges { return cachedCodeRanges }
        let parsed = cachedSource ?? source
        let ranges = blocks.compactMap { block -> CodeRange? in
            guard let code = block.codeBlock else { return nil }
            let range = NSRange(block.range, in: parsed)
            // A closed block's range ends with the closing fence's newline,
            // if it has one; the caret on that line stops before it.
            let terminator = code.isClosed ? parsed[block.range].last.flatMap { $0.isNewline ? $0.utf16.count : nil } ?? 0 : 0
            return CodeRange(
                range: range,
                isClosed: code.isClosed,
                lastCaret: range.location + range.length - terminator,
                isOutput: code.isOutput,
                language: code.language,
                tag: code.infoString.split(separator: " ").first.map(String.init) ?? ""
            )
        }
        cachedCodeRanges = ranges
        return ranges
    }
}
