//
//  AboutSettings.swift
//  NoteCode
//
//  Settings › Help and About (split out of SettingsView.swift).
//

import SwiftData
import SwiftUI

struct AboutSettings: View {
    var onOpenWelcomeNote: () -> Void
    var onShowWelcomeScreen: () -> Void
    @Environment(\.appExtensions) private var extensions
    @Environment(\.modelContext) private var context
    /// Whether this is a tester's copy: a Debug build, or whatever the
    /// edition says (the App Store's: TestFlight).
    @State private var isTesting = false
    @State private var testNotesAdded = 0

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    NoteCodeMark()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: NoteCodeMark.cornerRadius(side: 84), style: .continuous))
                        .accessibilityHidden(true)
                    Text("NoteCode")
                        .font(.title.bold())
                        .tracking(-0.03 * 28)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                // A new note each time it's asked for; the first launch's
                // copy, if it's still there, is left alone.
                Button("Welcome Note", action: onOpenWelcomeNote)
                    .accessibilityIdentifier("welcomeNoteButton")
                // The title screen of a first launch, shown again.
                Button("Welcome Screen", action: onShowWelcomeScreen)
                    .accessibilityIdentifier("welcomeScreenButton")
                if FeedbackRoute.exists(form: AppInfo.feedbackForm, address: AppInfo.feedbackAddress) {
                    FeedbackButton(kind: .featureRequest) { Text("Feature Request") }
                    FeedbackButton(kind: .feedback) { Text("Send Feedback") }
                }
                Link("Privacy Policy", destination: AppInfo.privacyPolicy)
                // Only with the app's App Store id (`AppInfo.appStoreID`).
                if let review = AppInfo.writeReviewURL() {
                    Link("Rate NoteCode", destination: review)
                        .accessibilityIdentifier("rateNoteCodeButton")
                }
                if let page = AppInfo.appStorePage() {
                    ShareLink("Share NoteCode", item: page,
                              message: Text("NoteCode: notes for computer science, with code that runs and ink on the same page."))
                        .accessibilityIdentifier("shareNoteCodeButton")
                }
                // The edition's rows (the App Store's Ad Privacy Options).
                ForEach(extensions.aboutRows()) { $0.view }
                NavigationLink("Acknowledgements") { AcknowledgementsPage() }
                LabeledContent("Version", value: AppInfo.versionString())
            }

            // Testers only: a folder of notes that exercise every feature
            // (`TestNotes`), so a bug hunt doesn't start by writing them.
            if isTesting {
                Section {
                    Button("Add Test Notes") {
                        TestNotes.add(to: context)
                        try? context.save()
                        testNotesAdded += 1
                    }
                    .accessibilityIdentifier("addTestNotesButton")
                } header: {
                    Text("Testing")
                } footer: {
                    if testNotesAdded > 0 {
                        Text("Added \(TestNotes.all.count) notes in the \(TestNotes.folderName) folder.")
                    } else {
                        Text("A \(TestNotes.folderName) folder with a note for each feature, each opening with a checklist. Shown only in test builds.")
                    }
                }
            }
        }
        .navigationTitle("Help and About")
        .task { await extensions.settingsAppeared() }
        .task {
#if DEBUG
            isTesting = true
#else
            isTesting = await extensions.isTestingBuild()
#endif
        }
    }
}

private struct AcknowledgementsPage: View {
    var body: some View {
        ScrollView {
            Text(AppInfo.acknowledgements() ?? "The licence text could not be loaded.")
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Acknowledgements")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
