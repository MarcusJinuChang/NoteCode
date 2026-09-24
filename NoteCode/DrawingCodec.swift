//
//  DrawingCodec.swift
//  NoteCode
//
//  A note's ink to the bytes `Page.drawingData` holds, and back.
//

import Foundation
import PaperKit

/// Reads and writes the bytes a page keeps its ink in.
///
/// Reading never throws. What can't be read comes back as `.unreadable`, and
/// the caller's job is then to leave the stored bytes exactly as they are:
/// saving an empty canvas over unreadable ink would turn a passing bug into a
/// semester of lost notes. See docs/phase-drawing-layer.md, step 4.
nonisolated enum DrawingCodec {

    enum Loaded {
        /// Nothing stored: a note that has never been drawn on.
        case none
        case ink(PaperMarkup)
        /// Bytes that couldn't be read, and why, for the reader.
        case unreadable(reason: String)
    }

    static func decode(_ data: Data) -> Loaded {
        // PaperKit throws for empty data, with the same error as corrupt
        // bytes, so "never drawn on" has to be told apart first.
        guard !data.isEmpty else { return .none }
        do {
            return .ink(try PaperMarkup(dataRepresentation: data))
        } catch MarkupError.incompatibleFormatTooNew {
            return .unreadable(reason: "This note's drawing was saved by a newer version of NoteCode.")
        } catch {
            // Any error at all. Corrupt bytes arrive as an error from
            // PaperKit's storage layer, not the `MarkupError` its API
            // declares.
            return .unreadable(reason: "This note's drawing couldn't be read.")
        }
    }

    /// The bytes to store for `markup`.
    ///
    /// Ink with nothing in it is stored as no bytes, so a note whose ink was
    /// all erased reads exactly like one that was never drawn on.
    ///
    /// `@concurrent` so it runs off the main actor. With approachable
    /// concurrency on, a plain `nonisolated async` function runs on its
    /// caller's actor, and the page calls this from the main one. 1,000
    /// strokes take 73ms (simulator, 19 September).
    @concurrent
    static func encode(_ markup: PaperMarkup) async throws -> Data {
        guard !markup.subelements.isEmpty else { return Data() }
        return try await markup.dataRepresentation()
    }
}
