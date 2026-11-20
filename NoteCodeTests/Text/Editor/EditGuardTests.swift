//
//  EditGuardTests.swift
//  NoteCodeTests
//
//  The re-entrancy flags (2T4): a flag is set for the length of the closure
//  and cleared however it ends, and one nested in another of its kind
//  doesn't clear it early.
//

import Testing

@testable import NoteCode

@MainActor
@Suite struct EditGuardTests {

    @Test func aFlagIsSetOnlyInsideItsClosure() {
        let guardian = EditGuard()
        #expect(!guardian.isActive(.markerEdit))
        guardian.perform(as: .markerEdit) {
            #expect(guardian.isActive(.markerEdit))
            #expect(!guardian.isActive(.formatting))
        }
        #expect(!guardian.isActive(.markerEdit))
    }

    @Test func aFlagIsClearedWhenTheClosureThrows() {
        struct Failure: Error {}
        let guardian = EditGuard()
        #expect(throws: Failure.self) {
            try guardian.perform(as: .retagging) { throw Failure() }
        }
        #expect(!guardian.isActive(.retagging))
    }

    @Test func nestingTheSameFlagKeepsItSetUntilTheOuterEnds() {
        let guardian = EditGuard()
        guardian.perform(as: .formatting) {
            guardian.perform(as: .formatting) {}
            #expect(guardian.isActive(.formatting))
        }
        #expect(!guardian.isActive(.formatting))
    }

    @Test func theAppEditFlagsAreTheOnesThatMakeAKeystrokeNotTheReaders() {
        let guardian = EditGuard()
        for kind in [EditGuard.Kind.formatting, .markerEdit, .retagging] {
            guardian.perform(as: kind) { #expect(guardian.isAppEdit) }
        }
        for kind in [EditGuard.Kind.normalizingCaret, .writingTypedText] {
            guardian.perform(as: kind) { #expect(!guardian.isAppEdit) }
        }
        #expect(!guardian.isAppEdit)
    }
}
