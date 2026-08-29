//
//  CodeBlockIdentityTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

private func codeIDs(_ source: String) -> [CodeBlockID] {
    FenceParser.parse(source).compactMap(\.codeBlock?.id)
}

@Suite("Code block identity")
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
        let cpp = FenceParser.parse("```cpp\nx\n```")[0].codeBlock
        let untagged = FenceParser.parse("```\nx\n```")[0].codeBlock

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

// MARK: - Store

@Suite("Block result store")
struct BlockResultStoreTests {

    private static let document = "```cpp\nint x;\n```\ntext\n```py\nprint(1)\n```"

    private func storeWithResults(_ source: String) -> (BlockResultStore<String>, [Region]) {
        let regions = FenceParser.parse(source)
        var store = BlockResultStore<String>()
        for (index, region) in regions.compactMap(\.codeBlock).enumerated() {
            store[region.id] = "output \(index)"
        }
        return (store, regions)
    }

    @Test("Results survive a re-parse of an unchanged document")
    func resultsSurviveReparse() {
        var (store, _) = storeWithResults(Self.document)
        store.prune(keeping: FenceParser.parse(Self.document))

        #expect(store.count == 2)
    }

    @Test("Results survive edits to prose")
    func resultsSurviveProseEdits() {
        var (store, _) = storeWithResults(Self.document)
        let edited = Self.document.replacingOccurrences(of: "text", with: "text, expanded")

        store.prune(keeping: FenceParser.parse(edited))

        #expect(store.count == 2)
    }

    @Test("Editing a block discards only that block's result")
    func editingBlockDiscardsItsResult() {
        var (store, _) = storeWithResults(Self.document)
        let edited = Self.document.replacingOccurrences(of: "int x;", with: "int y;")
        let editedRegions = FenceParser.parse(edited)

        store.prune(keeping: editedRegions)

        #expect(store.count == 1)
        // The untouched python block keeps its output.
        let survivor = editedRegions.compactMap(\.codeBlock).first { $0.language == .python }
        #expect(store[survivor!.id] == "output 1")
    }

    @Test("Deleting a block discards its result")
    func deletingBlockDiscardsResult() {
        var (store, _) = storeWithResults(Self.document)
        store.prune(keeping: FenceParser.parse("just prose now"))

        #expect(store.count == 0)
    }

    @Test("Inserting a block above discards results below it")
    func insertingAboveDiscardsBelow() {
        var (store, _) = storeWithResults(Self.document)
        let edited = "```java\nclass A {}\n```\n" + Self.document

        store.prune(keeping: FenceParser.parse(edited))

        // Both original blocks shifted ordinal, so neither result still applies.
        #expect(store.count == 0)
    }
}
