//
//  AppExtensionsTests.swift
//  NoteCodeTests
//
//  The general app with nothing an edition adds (`AppExtensions.none`).
//

import Foundation
import Testing
@testable import NoteCode

@Suite("App extensions", .tags(.library))
@MainActor
struct AppExtensionsTests {

    @Test("Home is in front once the launch has decided about the title screen, and the screen is gone")
    func gate() {
        #expect(!HomeGate.isOpen(launchSettled: false, titleScreenUp: false), "Home's first appearance, before the screen is decided")
        #expect(!HomeGate.isOpen(launchSettled: true, titleScreenUp: true), "over the title screen")
        #expect(HomeGate.isOpen(launchSettled: true, titleScreenUp: false), "Home is in front")
    }

    @Test("With nothing added, the list foot has no rows, only the sign-off")
    func listFootWithNone() {
        #expect(ListFoot(present: { _ in }).rows(with: .none).isEmpty)
    }

    @Test("With nothing added, Help and About has no extra rows")
    func aboutWithNone() {
        #expect(AppExtensions.none.aboutRows().isEmpty)
    }

    @Test("With nothing added, Settings' list has no Pro row and Writing has no assistant section")
    func settingsWithNone() {
        #expect(AppExtensions.none.settings(at: .afterGeneral).isEmpty)
        #expect(AppExtensions.none.settings(at: .writing).isEmpty)
    }
}
