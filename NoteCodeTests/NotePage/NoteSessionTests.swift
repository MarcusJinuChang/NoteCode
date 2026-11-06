//
//  NoteSessionTests.swift
//  NoteCodeTests
//
//  `PageDetailView.init` runs far more often than SwiftUI keeps the state it
//  builds, so it must not make a `NoteEditor` or a `DrawingSaveScheduler`
//  (2P3). They are made when first read.
//

#if canImport(UIKit)

import SwiftData
import Testing
@testable import NoteCode

@Suite("Note session", .tags(.layout))
@MainActor
struct NoteSessionTests {

    private func makePage() throws -> (ModelContainer, Page) {
        let container = try ModelContainer(
            for: NoteSchema.current,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let page = Page(title: "Hash tables", content: "text")
        container.mainContext.insert(page)
        return (container, page)
    }

    @Test("Initialising the page view repeatedly makes no editor and no ink saver")
    func initAllocatesNothing() throws {
        let (container, page) = try makePage()
        withExtendedLifetime(container) {
            let editors = NoteSession.editorsMade
            let savers = NoteSession.inkSaversMade
            for _ in 0..<50 { _ = PageDetailView(page: page) }
            #expect(NoteSession.editorsMade == editors, "init made a NoteEditor")
            #expect(NoteSession.inkSaversMade == savers, "init made a DrawingSaveScheduler")
        }
    }

    @Test("The editor and the saver are made once, on first read")
    func madeOnceOnFirstRead() throws {
        let (container, page) = try makePage()
        withExtendedLifetime(container) {
            let session = NoteSession(page: page)
            let editors = NoteSession.editorsMade
            let savers = NoteSession.inkSaversMade
            #expect(session.editor === session.editor)
            #expect(session.inkSaver === session.inkSaver)
            #expect(NoteSession.editorsMade == editors + 1)
            #expect(NoteSession.inkSaversMade == savers + 1)
        }
    }

    @Test("A session given an editor keeps it and makes none")
    func givenEditorIsKept() throws {
        let (container, page) = try makePage()
        withExtendedLifetime(container) {
            let editor = NoteEditor()
            let editors = NoteSession.editorsMade
            #expect(NoteSession(page: page, editor: editor).editor === editor)
            #expect(NoteSession.editorsMade == editors)
        }
    }
}

#endif
