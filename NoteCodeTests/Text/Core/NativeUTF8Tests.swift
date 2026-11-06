//
//  NativeUTF8Tests.swift
//  NoteCodeTests
//
//  AGENTS.md › Implementation requirements: parse and index
//  `(textView.text ?? "").nativeUTF8`, never `textView.text` itself.
//

#if canImport(UIKit)

import Foundation
import UIKit
import Testing
@testable import NoteCode

@Suite("nativeUTF8 trap", .tags(.pure))
struct NativeUTF8Tests {

    @Test("A string bridged from an NSString is not contiguous; nativeUTF8 makes it so")
    func nativeIsContiguous() throws {
        // What a text storage hands out: a String backed by an NSString, read
        // a character at a time through `characterAtIndex:`.
        let storage = NSTextStorage(string: String(repeating: "int x = 1; // é\n", count: 500))
        let bridged = storage.string
        try #require(!bridged.isContiguousUTF8, "the premise: the text view's string is bridged")

        let native = bridged.nativeUTF8
        #expect(native.isContiguousUTF8, "the parser reads one buffer")
        #expect(native == bridged)
    }
}

#endif
