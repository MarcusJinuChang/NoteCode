//
//  LastCodeLanguageTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

@Suite("The last code language")
struct LastCodeLanguageTests {

    private func freshDefaults() -> UserDefaults {
        let name = "LastCodeLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("A device that has never started a block gets C++")
    func startsOnCpp() {
        #expect(LastCodeLanguage.read(from: freshDefaults()) == .cpp)
    }

    @Test("Each language, and Plain Text, is remembered")
    func remembers() {
        let defaults = freshDefaults()
        for language in CodeLanguage.allCases {
            LastCodeLanguage.store(language, in: defaults)
            #expect(LastCodeLanguage.read(from: defaults) == language)
        }
        LastCodeLanguage.store(nil, in: defaults)
        #expect(LastCodeLanguage.read(from: defaults) == nil)
    }

    @Test("Something unreadable falls back to C++")
    func unreadable() {
        let defaults = freshDefaults()
        defaults.set("cobol", forKey: LastCodeLanguage.defaultsKey)
        #expect(LastCodeLanguage.read(from: defaults) == .cpp)
    }

    @Test("The stored name is stable")
    func key() {
        #expect(LastCodeLanguage.defaultsKey == "lastCodeLanguage")
    }
}
