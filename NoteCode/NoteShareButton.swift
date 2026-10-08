//
//  NoteShareButton.swift
//  NoteCode
//
//  The note header's share button.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

/// Shares the open note as a PDF: print it, save it to Files, send it.
///
/// Printing is one of the share sheet's actions, the way iPadOS offers it
/// for any PDF, so there's no separate print button. The PDF is made when
/// the button is tapped, which takes a moment on a long note, and the
/// button shows that it's working until the sheet opens.
struct NoteShareButton: View {
    let editor: NoteEditor
    let title: String

    @State private var isPreparing = false
    @State private var failed = false
    @State private var anchor = PopoverAnchor()

    var body: some View {
        Button {
            Task { await share() }
        } label: {
            if isPreparing {
                ProgressView()
            } else {
                Label("Share as PDF", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(isPreparing)
        .background(PopoverAnchorView(anchor: anchor))
        .alert("Couldn't make a PDF of this note", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("There may not be enough free space on this device. Free some up and try again.")
        }
    }

    private func share() async {
        isPreparing = true
        defer { isPreparing = false }

        guard let data = await editor.pdf(title: title) else { return }
        guard let url = try? NotePDF.write(data, title: title) else {
            failed = true
            return
        }
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
