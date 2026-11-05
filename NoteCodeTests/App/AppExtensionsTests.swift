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

    @Test("Consent waits for the launch to decide about the title screen, and for it to go")
    func gate() {
        #expect(!ConsentGate.isOpen(launchSettled: false, titleScreenUp: false), "Home's first appearance, before the screen is decided")
        #expect(!ConsentGate.isOpen(launchSettled: true, titleScreenUp: true), "over the title screen")
        #expect(ConsentGate.isOpen(launchSettled: true, titleScreenUp: false), "Home is in front")
    }

    /// The general rows, in their order, as far as this build has them.
    static var generalRows: [String] {
        (AppInfo.featureRequestURL() == nil ? [] : ["featureRequest"])
            + (AppInfo.feedbackURL() == nil ? [] : ["sendFeedback"])
            + ["privacyPolicy"]
    }

    @Test("With nothing added, the list foot has no ad or tip row, and the general rows keep their order")
    func listFootWithNone() {
        let rows = ListFoot(present: { _ in }).rows(with: .none).map(\.id)
        #expect(rows == Self.generalRows)
        #expect(rows.last == "privacyPolicy")
    }

    @Test("With nothing added, Help and About has no extra rows and the rating prompt waits on nothing")
    func aboutAndReviewWithNone() {
        #expect(AppExtensions.none.aboutRows().isEmpty)
        #expect(AppExtensions.none.mayAskForReview())
    }
}
