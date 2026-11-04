//
//  SidebarOnHomeTests.swift
//  NoteCodeTests
//

import Testing
@testable import NoteCode

/// The list is always beside Home in a regular width (feedback #3); over a
/// note it stays a slide-over, away until ☰.
@Suite("Sidebar on Home")
struct SidebarOnHomeTests {

    @Test("Home shows the list; a note opened at launch doesn't, unless storage failed")
    func launchState() {
        #expect(SidebarPlan.showsList(noteOpen: false, storageFailed: false))
        #expect(SidebarPlan.showsList(noteOpen: false, storageFailed: true))
        #expect(!SidebarPlan.showsList(noteOpen: true, storageFailed: false))
        #expect(SidebarPlan.showsList(noteOpen: true, storageFailed: true))
    }

    @Test("Unfolding a Duo onto Home shows the list, whatever the stack held")
    func unfoldingOntoHome() {
        for path: [CompactScreen] in [[], [.list]] {
            #expect(SidebarPlan.showsList(unfoldingFrom: path, noteOpen: false))
        }
    }

    @Test("Unfolding onto a note shows the list over it only if the stack showed it")
    func unfoldingOntoANote() {
        #expect(SidebarPlan.showsList(unfoldingFrom: [.list, .note], noteOpen: true) == false)
        // The stack's top is the note, so the list wasn't what was on screen.
        #expect(SidebarPlan.showsList(unfoldingFrom: [.note], noteOpen: true) == false)
    }

    @Test("Folding Home into a stack gives Home, not a list pushed on it")
    func foldingFromHome() {
        let path = CompactScreen.path(
            listShowing: SidebarPlan.stackShowsList(listShowing: true, noteOpen: false),
            noteOpen: false
        )
        #expect(path == [])
        // Over a note, the list that was slid over it is what the stack keeps.
        let overNote = CompactScreen.path(
            listShowing: SidebarPlan.stackShowsList(listShowing: true, noteOpen: true),
            noteOpen: true
        )
        #expect(overNote == [.list, .note])
    }
}
