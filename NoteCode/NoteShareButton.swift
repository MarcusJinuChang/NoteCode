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
                    .accessibilityLabel("Preparing to Share")
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

        let name = SharePopover.documentTitle(title, text: markdown)
        guard let data = await editor.pdf(title: name) else { return }
        guard let url = try? NotePDF.write(data, title: name) else {
            failed = true
            return
        }
        present(url)
    }

    /// The text, exactly, as a `.md` file named for the note.
    private func shareMarkdown() {
        guard let url = try? NoteMarkdown.write(markdown, title: SharePopover.documentTitle(title, text: markdown)) else {
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
        if let popover = activity.popoverPresentationController, let window = anchor.window {
            // Pointed at in the window's coordinates, not the anchor's own:
            // the anchor sits in the toolbar's hosting view, and in landscape
            // its bounds put the popover in the window's top-left corner.
            let rect = anchor.convert(anchor.bounds, to: window)
            popover.sourceView = window
            popover.sourceRect = SharePopover.sourceRect(button: rect, in: window.bounds)
        }
        presenter.present(activity, animated: true)
    }
}

/// The share sheet's pure choices: where it points, and what the file is called.
nonisolated enum SharePopover {

    /// The rect the popover points at. The Share button's, in window
    /// coordinates, or when that can't be trusted (no size, or outside the
    /// window, as a button not yet laid out reports) a small rect at the
    /// window's top right, where the button is, and never the top left.
    static func sourceRect(button: CGRect, in window: CGRect) -> CGRect {
        guard button.width > 1, button.height > 1, window.intersects(button) else {
            return CGRect(x: window.maxX - 60, y: window.minY + 20, width: 44, height: 44)
        }
        return button
    }

    /// The note's title for the PDF's metadata and the file's name. A note
    /// with no title is named for its first line, as a person would, and only
    /// then "Untitled" (`NoteFileName`).
    static func documentTitle(_ title: String, text: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        for line in text.split(whereSeparator: \.isNewline) {
            let stripped = line.drop { $0 == "#" || $0 == " " || $0 == "\t" }
                .trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty && !stripped.hasPrefix("```") { return stripped }
        }
        return ""
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
