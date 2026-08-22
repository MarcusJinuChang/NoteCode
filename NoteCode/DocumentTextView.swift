//
//  DocumentTextView.swift
//  NoteCode
//
//  The editor SwiftUI's TextEditor can't be: a real UITextView we own, backed
//  by TextKit 2, so later phases can reach its NSTextLayoutManager to style
//  fenced code regions.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

struct DocumentTextView: UIViewRepresentable {
    @Binding var text: String

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> UITextView {
        let textView = Self.makeConfiguredTextView()
        textView.delegate = context.coordinator
        textView.text = text
        DocumentStyler.applyStyling(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // The struct is recreated on every SwiftUI render but the Coordinator
        // persists, so hand it the current binding or it will keep writing
        // through a stale one.
        context.coordinator.text = $text

        // Only push text down when it actually differs. Assigning `.text`
        // unconditionally would reset the selection on every render and fight
        // the user for control of the caret while they type.
        if textView.text != text {
            // Assigning `.text` resets the storage to plain attributes, so the
            // styling has to be reapplied every time text arrives from outside.
            textView.text = text
            DocumentStyler.applyStyling(to: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    // MARK: Coordinator

    /// Owns the UIKit delegate callbacks and forwards edits back into SwiftUI.
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            let regions = DocumentStyler.applyStyling(to: textView)
            DocumentStyler.applyTypingAttributes(to: textView, regions: regions)
            text.wrappedValue = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Moving the caret across a fence boundary changes what the next
            // character should look like, even though no text changed.
            let regions = FenceParser.parse(textView.text ?? "")
            DocumentStyler.applyTypingAttributes(to: textView, regions: regions)
        }
    }

    // MARK: Configuration

    /// Builds the text view. Kept separate from `makeUIView` so tests can
    /// inspect the configuration without standing up a SwiftUI hierarchy.
    static func makeConfiguredTextView() -> UITextView {
        // Opt into TextKit 2 explicitly.
        //
        // Careful: reading the legacy `.layoutManager` property anywhere on this
        // view silently downgrades it to TextKit 1 and leaves `textLayoutManager`
        // nil — at which point none of the code-region rendering will run and
        // there is no error to tell you why.
        let textView = UITextView(usingTextLayoutManager: true)

        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)

        // Prose is the document's default; code styling arrives with fence
        // rendering. Dynamic Type so the editor respects the reader's text size.
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true

        // All five text-rewriting traits live in TextRewritingPolicy so that
        // switching them per region later is one call. `.code` (everything off)
        // is today's behavior — see the roadmap's deferred-work section.
        TextRewritingPolicy.current.apply(to: textView)

        return textView
    }
}

#endif
