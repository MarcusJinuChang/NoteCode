//
//  FeedbackRoute.swift
//  NoteCode
//
//  Where Feature Request and Send Feedback take the reader, chosen from what
//  this device can actually do.
//

import Foundation

/// The two things the reader can send the developer.
nonisolated enum FeedbackKind: String, CaseIterable, Sendable {
    case featureRequest
    case feedback

    /// The mail's subject, so the two can be told apart in the inbox.
    var subject: String {
        switch self {
        case .featureRequest: "NoteCode Feature Request"
        case .feedback:       "NoteCode Feedback"
        }
    }

    /// The form's answer to "What is this?", exactly as the form spells it.
    var formChoice: String {
        switch self {
        case .featureRequest: "Feature request"
        case .feedback:       "Bug report"
        }
    }
}

/// The web form both rows can open (a Google Form). A web page needs nothing
/// set up on the device, which a `mailto:` link does: on an iPad with no
/// account in Apple Mail, iOS opens Mail's "add account" screen instead of a
/// message, and the request is never written (Marcus, 21 Nov).
nonisolated struct FeedbackForm: Equatable, Sendable {
    /// The form's `…/viewform` address.
    var url: URL
    /// The pre-filled link's `entry.<n>` names, from Get pre-filled link in
    /// the form's ••• menu. `nil` leaves that question for the reader.
    var kindEntry: String? = nil
    var versionEntry: String? = nil

    /// The form, with the kind and the app's version already answered where
    /// the entries are known.
    func link(for kind: FeedbackKind, version: String) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.queryItems ?? []).filter { item in
            item.name != kindEntry && item.name != versionEntry && item.name != "usp"
        }
        if kindEntry != nil || versionEntry != nil {
            items.append(URLQueryItem(name: "usp", value: "pp_url"))
        }
        if let kindEntry { items.append(URLQueryItem(name: kindEntry, value: kind.formChoice)) }
        if let versionEntry { items.append(URLQueryItem(name: versionEntry, value: version)) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url ?? url
    }
}

/// What a tap on Feature Request or Send Feedback does.
nonisolated enum FeedbackRoute: Equatable, Sendable {
    /// Open the web form in the browser.
    case form(URL)
    /// Write the mail in the app's own sheet (`MFMailComposeViewController`),
    /// which never leaves the app or lands on Mail's setup screen.
    case mail(to: String)
    /// Neither works here: show the address, with a Copy button.
    case copyAddress(String)

    /// The route for `kind`, or `nil` when there is nowhere to send it (no
    /// form and no address), in which case the row is left out.
    ///
    /// The form comes first for both kinds: it needs no account and no app
    /// set up, and every answer lands in one place (Marcus, 21 Nov). Mail is
    /// the way only when there is no form and Mail can send.
    /// `canSendMail` is `MFMailComposeViewController.canSendMail()`: false
    /// when Apple Mail has no account, which is exactly the case that looped.
    static func choose(
        for kind: FeedbackKind,
        canSendMail: Bool,
        form: FeedbackForm?,
        address: String?,
        version: String
    ) -> FeedbackRoute? {
        let address = address.flatMap { $0.isEmpty ? nil : $0 }
        let ordered: [FeedbackRoute?] = [
            form.map { FeedbackRoute.form($0.link(for: kind, version: version)) },
            canSendMail ? address.map { FeedbackRoute.mail(to: $0) } : nil,
        ]
        if let route = ordered.compactMap({ $0 }).first { return route }
        return address.map { FeedbackRoute.copyAddress($0) }
    }

    /// Whether a row for this kind can exist at all: something to send to.
    static func exists(form: FeedbackForm?, address: String?) -> Bool {
        form != nil || !(address ?? "").isEmpty
    }

    /// The mail's opening lines: what the reply will need to reproduce a bug,
    /// left for the reader to see and delete.
    static func mailBody(version: String, device: String, system: String) -> String {
        "\n\n\n—\nNoteCode \(version)\n\(device), \(system)"
    }
}
