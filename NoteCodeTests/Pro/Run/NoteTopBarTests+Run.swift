//
//  NoteTopBarTests+Run.swift
//  NoteCodeTests
//
//  Run's item in the note's top bar, which reaches the page through the
//  editor's features (`EditorFeature.topBarItem`), kept in Pro/ with it.
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

extension NoteTopBarTests {

    @Test("With Run, its item comes before Share and •••; without a service, nothing")
    func runItemBeforeShare() throws {
        let withRun = try Rig(editor: NoteEditor(features: [RunFeature.factory(
            runner: { StubRunner() }, isPro: { false }, transaction: { "" }, refresh: {}
        )]))
        withRun.settle()
        let items = withRun.trailingItems
        withRun.close()

        let noService = try Rig(editor: NoteEditor(features: [RunFeature.factory(
            runner: { nil }, isPro: { false }, transaction: { "" }, refresh: {}
        )]))
        noService.settle()
        let without = noService.trailingItems
        noService.close()

        // The Notes | Run control is titled by its first segment.
        #expect(items == ["Notes", "Share", "More"])
        #expect(without == ["Share", "More"])
    }
}

#endif
