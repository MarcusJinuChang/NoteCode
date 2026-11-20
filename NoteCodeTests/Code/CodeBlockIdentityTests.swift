//
//  CodeBlockIdentityTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

private func codeIDs(_ source: String) -> [CodeBlockID] {
    DocumentParser.parse(source).compactMap(\.codeBlock?.id)
}

@Suite("Code block identity", .tags(.editor))
struct CodeBlockIdentityTests {

    private static let document = """
    notes before
    ```cpp
    int lo = 0;
    ```
    between
    ```py
    print(1)
    ```
    """

    @Test("Identity is stable for an unchanged document")
    func stableAcrossReparse() {
        #expect(codeIDs(Self.document) == codeIDs(Self.document))
    }

    @Test("Blocks are numbered in document order")
    func ordinalsAreDocumentOrder() {
        #expect(codeIDs(Self.document).map(\.ordinal) == [0, 1])
    }

    // MARK: What must survive

    @Test("Editing prose above a block leaves its identity alone")
    func editingProseAboveIsHarmless() {
        let edited = Self.document.replacingOccurrences(of: "notes before", with: "notes before, now longer")
        #expect(codeIDs(edited) == codeIDs(Self.document))
    }

    @Test("Editing prose between blocks leaves both identities alone")
    func editingProseBetweenIsHarmless() {
        let edited = Self.document.replacingOccurrences(of: "between", with: "between the two blocks")
        #expect(codeIDs(edited) == codeIDs(Self.document))
    }

    @Test("Editing one block leaves the other alone")
    func editingOneBlockSparesTheOther() {
        let edited = Self.document.replacingOccurrences(of: "int lo = 0;", with: "int lo = 1;")
        let before = codeIDs(Self.document)
        let after = codeIDs(edited)

        #expect(after[0] != before[0])
        #expect(after[1] == before[1])
    }

    // MARK: What must not survive

    @Test("Editing a block's code changes its identity")
    func editingCodeChangesIdentity() {
        let edited = Self.document.replacingOccurrences(of: "print(1)", with: "print(2)")
        #expect(codeIDs(edited)[1] != codeIDs(Self.document)[1])
    }

    @Test("Inserting a block above shifts the ones below")
    func insertingBlockAboveShifts() {
        let edited = "```java\nclass A {}\n```\n" + Self.document
        let after = codeIDs(edited)

        #expect(after.count == 3)
        #expect(after.map(\.ordinal) == [0, 1, 2])
        // Same code, new position — so a result attached to it is discarded.
        #expect(after[1] != codeIDs(Self.document)[0])
    }

    @Test("The content hash ignores the fence lines and language tag")
    func hashCoversContentOnly() {
        // Same code, different tag: the tag is not part of the content hash, so
        // only the language differs.
        let cpp = DocumentParser.parse("```cpp\nx\n```")[0].codeBlock
        let untagged = DocumentParser.parse("```\nx\n```")[0].codeBlock

        #expect(cpp?.id == untagged?.id)
        #expect(cpp?.language != untagged?.language)
    }

    @Test("Hashing is deterministic, not seeded per process")
    func hashIsDeterministic() {
        #expect(CodeBlockID.hash("int x;") == CodeBlockID.hash("int x;"))
        #expect(CodeBlockID.hash("") == 0xcbf2_9ce4_8422_2325)
        #expect(CodeBlockID.hash("a") != CodeBlockID.hash("b"))
    }
}
