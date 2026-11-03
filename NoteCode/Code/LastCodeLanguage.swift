//
//  LastCodeLanguage.swift
//  NoteCode
//
//  The language ⇧⌘K starts a code block in.
//

import Foundation

/// Which language the last code block the reader started was in, per device,
/// so ⇧⌘K opens the next one in it without a menu.
///
/// Remembers a pick of Code (no language) too, as `plainText`, since that is a choice
/// and not an absence of one. A device that has never started a block gets
/// C++, the course the app is for.
nonisolated enum LastCodeLanguage {

    static let defaultsKey = "lastCodeLanguage"

    /// Stored in place of a language's raw value for Code (no language).
    static let plainText = "plain"

    /// What the reader last started a block in: `nil` is Code (no language).
    static func read(from defaults: UserDefaults = .standard) -> CodeLanguage? {
        guard let stored = defaults.string(forKey: defaultsKey) else { return .cpp }
        if stored == plainText { return nil }
        return CodeLanguage(rawValue: stored) ?? .cpp
    }

    static func store(_ language: CodeLanguage?, in defaults: UserDefaults = .standard) {
        defaults.set(language?.rawValue ?? plainText, forKey: defaultsKey)
    }
}
