//
//  UTF16Unit.swift
//  NoteCode
//
//  The UTF-16 units the text code compares against, named once.
//

import Foundation

nonisolated enum UTF16Unit {
    /// `\n`: what `NSString.character(at:)` reads at a line's end.
    static let newline: unichar = 0x0A
    static let space: unichar = 0x20
    static let period: unichar = 0x2E
}
