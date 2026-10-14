//
//  NoteShareButton.swift
//  NoteCode
//
//  The note header's share button.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

/// The header's Share button: a tap shares the note as a PDF, holding it
/// offers the rest.
///
/// **A menu with a primary action**, as the list's + is: the tap does the
/// common thing and a hold shows PDF, Markdown, Copy as Markdown and Print.
/// The PDF is every page as printed, ink included. Markdown is the note's
/// text as a `.md` file, which is the note itself: the text storage holds
/// the Markdown as typed, and only ink needs a PDF to survive. Printing goes
/// through the PDF (⌘P is the same action).
///
/// The PDF is made when the item is chosen, which takes a moment on a long
/// note, and the button shows that it's working until the sheet opens.
struct NoteShareButton: View {
    let editor: NoteEditor
    let title: String
    /// What to share if the text view doesn't exist yet: the note's saved text.
    var fallbackText: String = ""

    @Environment(ToastCenter.self) private var toasts: ToastCenter?

    @State private var isPreparing = false
    @State private var failed = false
    @State private var anchor = PopoverAnchor()

    var body: some View {
        Menu {
            Button {
                Task { await sharePDF() }
            } label: {
                Text("PDF")
                Text("Every page as printed, ink included")
                Image(systemName: "doc.richtext")
            }
            Button {
                shareMarkdown()
            } label: {
                Text("Markdown")
                Text("A .md file of the text; ink isn't in it")
                Image(systemName: "doc.plaintext")
            }
            Button("Copy as Markdown", systemImage: "doc.on.doc") { copyMarkdown() }
            Divider()
            Button("Print…", systemImage: "printer") {
                Task { await editor.printNote(title: title) }
            }
        } label: {
            if isPreparing {
                ProgressView()
            } else {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } primaryAction: {
            Task { await sharePDF() }
        }
        .disabled(isPreparing)
        .background(PopoverAnchorView(anchor: anchor))
        .accessibilityIdentifier("shareButton")
        .alert("Couldn't prepare this note", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("There may not be enough free space on this device. Free some up and try again.")
        }
    }

    private var markdown: String {
        editor.currentText ?? fallbackText
    }

    private func sharePDF() async {
        isPreparing = true
        defer { isPreparing = false }

        guard let data = await editor.pdf(title: title) else { return }
        guard let url = try? NotePDF.write(data, title: title) else {
            failed = true
            return
        }
        present(url)
    }

    /// The text, exactly, as a `.md` file named for the note.
    private func shareMarkdown() {
        guard let url = try? NoteMarkdown.write(markdown, title: title) else {
            failed = true
            return
        }
        present(url)
    }

    private func copyMarkdown() {
        UIPasteboard.general.string = markdown
        toasts?.show("Copied")
    }

    private func present(_ url: URL) {
        if let view = anchor.view {
            Self.present(url, from: view)
        }
    }

    /// Opens the share sheet over whatever is showing, pointing at the
    /// button on iPad, where it's a popover.
    private static func present(_ url: URL, from anchor: UIView) {
        guard var presenter = anchor.window?.rootViewController else { return }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = anchor
            popover.sourceRect = anchor.bounds
        }
        presenter.present(activity, animated: true)
    }
}

/// Where a UIKit popover points: a plain view behind a SwiftUI control.
///
/// SwiftUI's own popover would hold the share sheet as a child, and the
/// sheet presents Print and Save to Files from itself, so it's presented
/// from UIKit instead, the way the code block's share is.
final class PopoverAnchor {
    weak var view: UIView?
}

private struct PopoverAnchorView: UIViewRepresentable {
    let anchor: PopoverAnchor

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        anchor.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        anchor.view = view
    }
}

#endif
