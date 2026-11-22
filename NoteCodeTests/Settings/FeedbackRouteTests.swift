//
//  FeedbackRouteTests.swift
//  NoteCodeTests
//
//  Feature Request and Send Feedback reach the developer on a device with no
//  Mail account: before 21 Nov both were `mailto:` links, and there iOS
//  opened Mail's "add account" screen and nothing was sent.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Feedback route", .tags(.pure))
struct FeedbackRouteTests {

    static let form = FeedbackForm(
        url: URL(string: "https://docs.google.com/forms/d/e/FORM/viewform")!,
        kindEntry: "entry.111",
        versionEntry: "entry.222")

    @Test("Without Mail set up, a request goes to the form, never to mail")
    func noMailUsesTheForm() {
        for kind in FeedbackKind.allCases {
            let route = FeedbackRoute.choose(
                for: kind, canSendMail: false, form: Self.form,
                address: "hello@example.com", version: "1.2 (3)")
            guard case .form = route else {
                Issue.record("\(kind) took \(String(describing: route))")
                continue
            }
        }
    }

    @Test("The form comes first even where Mail can send")
    func formFirst() {
        for kind in FeedbackKind.allCases {
            let route = FeedbackRoute.choose(
                for: kind, canSendMail: true, form: Self.form,
                address: "hello@example.com", version: "1")
            guard case .form = route else {
                Issue.record("\(kind) took \(String(describing: route))")
                continue
            }
        }
    }

    @Test("With no form: the app's mail sheet where Mail can send, else the address to copy")
    func noForm() {
        #expect(FeedbackRoute.choose(for: .featureRequest, canSendMail: true, form: nil,
                                     address: "hello@example.com", version: "1")
                == .mail(to: "hello@example.com"))
        #expect(FeedbackRoute.choose(for: .featureRequest, canSendMail: false, form: nil,
                                     address: "hello@example.com", version: "1")
                == .copyAddress("hello@example.com"))
    }

    @Test("Nothing to send to: no route, and no row")
    func nowhere() {
        #expect(FeedbackRoute.choose(for: .feedback, canSendMail: true, form: nil, address: nil, version: "1") == nil)
        #expect(FeedbackRoute.choose(for: .feedback, canSendMail: true, form: nil, address: "", version: "1") == nil)
        #expect(!FeedbackRoute.exists(form: nil, address: nil))
        #expect(!FeedbackRoute.exists(form: nil, address: ""))
        #expect(FeedbackRoute.exists(form: nil, address: "hello@example.com"))
        #expect(FeedbackRoute.exists(form: Self.form, address: nil))
    }

    @Test("The form opens with the kind and the version answered")
    func prefill() throws {
        let url = Self.form.link(for: .featureRequest, version: "1.2 (3)")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let answers = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
        #expect(answers["usp"] == "pp_url")
        #expect(answers["entry.111"] == "Feature request")
        #expect(answers["entry.222"] == "1.2 (3)")
        #expect(url.absoluteString.hasPrefix("https://docs.google.com/forms/d/e/FORM/viewform?"))

        let bug = Self.form.link(for: .feedback, version: "1")
        #expect(bug.absoluteString.contains("entry.111=Bug%20report"))
    }

    @Test("A pre-filled link pasted whole has its answers replaced, not doubled")
    func pastedPrefilledLink() throws {
        let pasted = FeedbackForm(
            url: URL(string: "https://docs.google.com/forms/d/e/FORM/viewform?usp=pp_url&entry.111=Feature+request&entry.222=TEST")!,
            kindEntry: "entry.111", versionEntry: "entry.222")
        let url = pasted.link(for: .feedback, version: "2.0 (9)")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.filter { $0.name == "entry.111" }.map(\.value) == ["Bug report"])
        #expect(items.filter { $0.name == "entry.222" }.map(\.value) == ["2.0 (9)"])
        #expect(items.filter { $0.name == "usp" }.count == 1)
    }

    @Test("A form with no known entries opens as it is")
    func plainForm() {
        let plain = FeedbackForm(url: URL(string: "https://forms.gle/abc")!)
        #expect(plain.link(for: .featureRequest, version: "1") == URL(string: "https://forms.gle/abc")!)
    }

    @Test("The two kinds keep their own subjects, which the inbox sorts by")
    func subjects() {
        #expect(FeedbackKind.featureRequest.subject == "NoteCode Feature Request")
        #expect(FeedbackKind.feedback.subject == "NoteCode Feedback")
        #expect(AppInfo.featureRequestURL(address: "a@b.c")?.absoluteString.contains("Feature%20Request") == true)
    }
}
