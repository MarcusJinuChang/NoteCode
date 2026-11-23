//
//  ListFoot.swift
//  NoteCode
//
//  The note list's last section: the edition's rows, then the mark.
//

import SwiftUI

/// The foot of the note list (step 12 of docs/ROADMAP.md): the edition's
/// rows (the App Store's: the ad, Tip Jar, Feature Request, Send Feedback
/// and Privacy Policy), then the mark and the version as a sign-off under the
/// notes. With no edition rows the section is the sign-off alone.
///
/// **A row exists only if it works**, as in Settings: the edition hands over
/// only the rows that show.
struct ListFoot: View {
    /// Shows a sheet an edition's row asks for; the note list presents it.
    var present: @MainActor (ExtensionSheet) -> Void
    @Environment(\.appExtensions) private var extensions

    var body: some View {
        Section {
            ForEach(rows(with: extensions)) { $0.view }
        } footer: {
            VStack(spacing: 6) {
                NoteCodeMark()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: NoteCodeMark.cornerRadius(side: 28), style: .continuous))
                    .accessibilityHidden(true)
                Text("NoteCode \(AppInfo.versionString())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)
        }
        // Rows here open things; none is a note, so none is ever selected.
        .buttonStyle(.plain)
        .selectionDisabled()
        // The App Store's asks the store for tips again (AppExtensions).
        .task { extensions.listFootAppeared() }
    }

    /// The rows in order: the edition's, as it lists them.
    func rows(with extensions: AppExtensions) -> [ExtensionRow] {
        extensions.listFootRows { [present] in present($0) }
    }
}
