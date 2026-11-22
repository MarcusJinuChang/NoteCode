//
//  FeedbackButton.swift
//  NoteCode
//
//  The Feature Request and Send Feedback rows: a button that takes the
//  route this device can use (FeedbackRoute).
//

import SwiftUI
#if canImport(MessageUI)
import MessageUI
#endif

/// A row that sends a feature request or feedback, by the form, the app's
/// own mail sheet, or failing both the address to copy. Before 21 Nov both
/// rows were `mailto:` links, which on an iPad with no Mail account opened
/// Mail's "add account" screen and went no further.
struct FeedbackButton<Content: View>: View {
    let kind: FeedbackKind
    @ViewBuilder var label: () -> Content

    @Environment(\.openURL) private var openURL
    @State private var composing = false
    @State private var showingAddress: String?

    var body: some View {
        Button(action: send, label: label)
            .accessibilityIdentifier("\(kind.rawValue)Button")
            .sheet(isPresented: $composing) {
                MailComposer(
                    onFinish: { composing = false },
                    to: AppInfo.feedbackAddress ?? "",
                    subject: kind.subject,
                    body: FeedbackRoute.mailBody(
                        version: AppInfo.versionString(),
                        device: AppInfo.deviceName,
                        system: AppInfo.systemString))
                .ignoresSafeArea()
            }
            .sheet(item: Binding(
                get: { showingAddress.map { AddressSheet.Item(address: $0) } },
                set: { showingAddress = $0?.address })) { item in
                AddressSheet(address: item.address, subject: kind.subject)
                    .presentationDetents([.medium])
            }
    }

    private func send() {
        switch FeedbackRoute.choose(
            for: kind,
            canSendMail: MailComposer.canSendMail,
            form: AppInfo.feedbackForm,
            address: AppInfo.feedbackAddress,
            version: AppInfo.versionString()) {
        case .form(let url):           openURL(url)
        case .mail:                    composing = true
        case .copyAddress(let address): showingAddress = address
        case nil:                      break
        }
    }
}

/// The address and the subject to write under, with a Copy button: where
/// neither the form nor Mail is there to take the message.
private struct AddressSheet: View {
    struct Item: Identifiable {
        let address: String
        var id: String { address }
    }

    let address: String
    let subject: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Mail isn't set up on this \(AppInfo.deviceName). Write from any mail app or webmail to the address below, with “\(subject)” as the subject.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text(address)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy Address", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = address
                        copied = true
                    }
                    .accessibilityIdentifier("copyFeedbackAddress")
                }
            }
            .navigationTitle(subject)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// `MFMailComposeViewController` in a sheet: the message is written and sent
/// without leaving the app.
private struct MailComposer: UIViewControllerRepresentable {
    let onFinish: () -> Void
    let to: String
    let subject: String
    let body: String

    static var canSendMail: Bool {
#if canImport(MessageUI)
        MFMailComposeViewController.canSendMail()
#else
        false
#endif
    }

#if canImport(MessageUI)
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([to])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    }
#else
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
#endif
}

#if canImport(MessageUI)
// Sent, saved, cancelled or failed, the sheet closes: Mail reports a failure
// itself, and a sent message is in the outbox.
extension MailComposer.Coordinator: MFMailComposeViewControllerDelegate {
    func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
        onFinish()
    }
}
#endif
