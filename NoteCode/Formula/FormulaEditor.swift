//
//  FormulaEditor.swift
//  NoteCode
//
//  LaTeX, step 5 (docs/design/latex.md › Drawing, "Editing"): the popover a tap
//  on a formula opens, and the same popover for a new one from Style ▾. The
//  source is typed in monospace with the formula drawn live above it. Done
//  writes back through the text view's `replace(_:withText:)`, so it is one
//  undo step; the popover is a separate surface, so no line of the note
//  re-wraps because of a caret (the reason this is not Obsidian's reveal on
//  entry).
//

#if canImport(UIKit)

import SwiftUI
import UIKit

/// What the popover edits, and what its buttons do.
@Observable
final class FormulaEditorModel {
    var tex: String
    let display: Bool
    let isBlock: Bool
    let isNew: Bool
    /// A locked note shows the source and the formula and changes nothing.
    let isReadOnly: Bool

    var onDone: (String) -> Void = { _ in }
    var onRemove: () -> Void = {}
    var onCancel: () -> Void = {}

    init(tex: String, display: Bool, isBlock: Bool, isNew: Bool, isReadOnly: Bool) {
        self.tex = tex
        self.display = display
        self.isBlock = isBlock
        self.isNew = isNew
        self.isReadOnly = isReadOnly
    }

    /// What the text would be written as.
    var cleaned: String { FormulaEditing.cleaned(tex, isBlock: isBlock) }
    var validity: FormulaValidity { FormulaValidity.check(cleaned) }
}

struct FormulaEditor: View {
    @Bindable var model: FormulaEditorModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(model.isReadOnly ? "Close" : "Cancel") { model.onCancel() }
                Spacer()
                Text(model.isNew ? "New Formula" : "Formula").font(.headline)
                Spacer()
                if !model.isReadOnly {
                    Button("Done") { model.onDone(model.cleaned) }
                        .fontWeight(.semibold)
                        .disabled(model.cleaned.isEmpty)
                        .accessibilityIdentifier("formulaDone")
                }
            }

            preview
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            TextEditor(text: $model.tex)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .frame(minHeight: 96)
                .focused($focused)
                .disabled(model.isReadOnly)
                .accessibilityLabel("Formula source")
                .accessibilityIdentifier("formulaSource")

            HStack {
                if case .invalid(let message) = model.validity, !model.cleaned.isEmpty {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if !model.isNew, !model.isReadOnly {
                    Button("Remove", role: .destructive) { model.onRemove() }
                }
            }
        }
        .padding(16)
        .onAppear { focused = !model.isReadOnly }
    }

    @ViewBuilder
    private var preview: some View {
        if let tex = model.validity.tex,
           let image = FormulaAttachment.make(tex: tex, pointSize: 22, display: model.display)?.image {
            ScrollView(.horizontal, showsIndicators: false) {
                Image(uiImage: image)
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .padding(12)
                    .accessibilityLabel(model.cleaned)
            }
        } else {
            Text(model.cleaned.isEmpty ? "Type TeX below" : "Can't draw this yet")
                .foregroundStyle(.secondary)
                .padding(12)
        }
    }
}

// MARK: - Presenting it

/// Keeps the popover a popover where there is room and a sheet where there
/// isn't.
private final class FormulaPopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(
        for controller: UIPresentationController, traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .pageSheet
    }
}

extension DocumentTextView.Coordinator {

    /// Opens the editor on a formula the note draws.
    func presentFormulaEditor(for span: FormulaEditing.Span, in textView: DocumentUITextView) {
        let text = textView.textStorage.mutableString
        guard NSMaxRange(span.texRange) <= text.length else { return }
        let locked = !textView.isEditable
        let model = FormulaEditorModel(
            tex: text.substring(with: span.texRange).trimmingCharacters(in: .whitespacesAndNewlines),
            display: span.display, isBlock: span.isBlock, isNew: false, isReadOnly: locked
        )
        let anchor = textView.position(from: textView.beginningOfDocument, offset: span.start)
            .flatMap { start in
                textView.position(from: start, offset: 1).flatMap { textView.textRange(from: start, to: $0) }
            }
            .map { textView.firstRect(for: $0) }
        present(model, from: textView, anchor: anchor)

        model.onDone = { [weak self, weak textView] tex in
            guard let self, let textView else { return }
            let text = textView.textStorage.mutableString
            guard NSMaxRange(span.texRange) <= text.length else { return }
            apply(FormulaEditing.replacing(span, with: tex, in: text), to: textView)
            finishFormulaEditor(in: textView)
        }
        model.onRemove = { [weak self, weak textView] in
            guard let self, let textView else { return }
            apply(FormulaEditing.removing(span, in: textView.textStorage.mutableString), to: textView)
            finishFormulaEditor(in: textView)
        }
        model.onCancel = { [weak self, weak textView] in
            guard let self, let textView else { return }
            finishFormulaEditor(in: textView, returningKeyboard: false)
        }
    }

    /// Opens the editor for a formula that isn't in the note yet; Done inserts
    /// it over the selection (whose text is the starting point).
    func presentNewFormulaEditor(display: Bool, in textView: DocumentUITextView) {
        guard textView.isEditable else { return }
        let text = textView.textStorage.mutableString
        let selection = textView.selectedRange
        guard NSMaxRange(selection) <= text.length,
              !MarkdownFormatting.isCode(selection.location, in: codeRanges(in: textView.textStorage))
        else { return }
        let seed = selection.length > 0 ? text.substring(with: selection) : ""
        let model = FormulaEditorModel(
            tex: FormulaEditing.cleaned(seed, isBlock: display), display: display, isBlock: display,
            isNew: true, isReadOnly: false
        )
        let anchor = textView.selectedTextRange.map { textView.firstRect(for: $0) }
        present(model, from: textView, anchor: anchor)

        model.onDone = { [weak self, weak textView] tex in
            guard let self, let textView else { return }
            let text = textView.textStorage.mutableString
            guard NSMaxRange(selection) <= text.length else { return }
            apply(FormulaEditing.inserting(tex, display: display, over: selection, in: text), to: textView)
            finishFormulaEditor(in: textView)
        }
        model.onCancel = { [weak self, weak textView] in
            guard let self, let textView else { return }
            finishFormulaEditor(in: textView, returningKeyboard: false)
        }
    }

    private func present(_ model: FormulaEditorModel, from textView: DocumentUITextView, anchor: CGRect?) {
        guard let presenter = textView.window?.rootViewController?.topPresented else { return }
        let host = UIHostingController(rootView: FormulaEditor(model: model))
        host.modalPresentationStyle = .popover
        host.preferredContentSize = CGSize(width: 420, height: 360)
        if let popover = host.popoverPresentationController {
            popover.sourceView = textView
            popover.sourceRect = (anchor ?? CGRect(origin: textView.bounds.origin, size: CGSize(width: 1, height: 1)))
                .insetBy(dx: -4, dy: -4)
            popover.permittedArrowDirections = [.up, .down]
            popover.delegate = Self.popoverDelegate
        }
        formulaEditor = host
        presenter.present(host, animated: true)
    }

    private func finishFormulaEditor(in textView: DocumentUITextView, returningKeyboard: Bool = true) {
        formulaEditor?.dismiss(animated: true)
        formulaEditor = nil
        if returningKeyboard, textView.isEditable { textView.becomeFirstResponder() }
    }

    fileprivate static let popoverDelegate = FormulaPopoverDelegate()
}

private extension UIViewController {
    /// The view controller a new presentation goes on top of.
    var topPresented: UIViewController {
        var top = self
        while let next = top.presentedViewController { top = next }
        return top
    }
}

#endif
