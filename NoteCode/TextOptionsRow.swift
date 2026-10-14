//
//  TextOptionsRow.swift
//  NoteCode
//
//  Text mode's counterpart of the ink options row: the note's text size, then
//  what the paragraph at the caret can be.
//

#if canImport(UIKit)

import SwiftUI

/// The row that floats beside the hotbar in text mode.
///
/// It starts with the text size stepper, `+ 17 −` across (`+` over `17` over
/// `−` down the side), in that order: `−` usually comes first, and `+` comes
/// first here because that is how it was asked for. The rest follows the
/// caret, by what it is in (`CaretFormatting.block`): a paragraph or heading,
/// a list item, or a code block. Every control does what a menu already did
/// (Style ▾, List ▾, the language button, Tab and ⇧Tab), through the editor's
/// same edits, one tap closer, so they undo like typing.
///
/// The content only: `Hotbar` floats it in glass beside itself, the way it
/// does the ink options.
struct TextOptionsRow: View {
    @Bindable var editor: NoteEditor
    var isVertical: Bool

    @Environment(\.optionsRow) private var style

    var body: some View {
        HotbarStack(isVertical: isVertical) {
            TextSizeStepper(editor: editor, isVertical: isVertical)
            HotbarDivider(isVertical: isVertical)
            switch editor.caretFormatting.block {
            case .paragraph:
                ParagraphControls(editor: editor)
            case .listItem:
                ListControls(editor: editor)
            case .code(let label, let kind, let isClosed):
                CodeControls(editor: editor, label: label, kind: kind, isClosed: isClosed)
            }
        }
        .padding(isVertical ? .vertical : .horizontal, 2)
        .background(alignment: style?.faceAlignment ?? .center) {
            Color.clear
                .frame(
                    width: isVertical ? OptionsRowStyle.thickness : nil,
                    height: isVertical ? nil : OptionsRowStyle.thickness
                )
                .glassEffect(.regular, in: .capsule)
        }
    }
}

// MARK: - Size

/// `+`, the size on a pill, `−`. Tapping the number lists the sizes.
private struct TextSizeStepper: View {
    @Bindable var editor: NoteEditor
    var isVertical: Bool

    var body: some View {
        HotbarStack(isVertical: isVertical) {
            HotbarButton("Increase Text Size", "plus") { editor.stepTextSize(by: 1) }
                .disabled(!editor.canStepTextSize.bigger)

            Menu {
                ForEach(NoteTypography.sizes.reversed(), id: \.self) { size in
                    Toggle(isOn: Binding(
                        get: { editor.textSize == size },
                        set: { _ in editor.setTextSize(size) }
                    )) {
                        Text(size == NoteTypography.defaultSize ? "\(size) · Default" : "\(size)")
                    }
                }
            } label: {
                Text("\(editor.textSize)")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 26)
                    .background(Color(.secondarySystemFill), in: .capsule)
                    .hotbarTarget()
            }
            .modifier(HotbarMenuStyle())
            .accessibilityLabel("Text Size")
            .accessibilityValue("\(editor.textSize) points")

            HotbarButton("Decrease Text Size", "minus") { editor.stepTextSize(by: -1) }
                .disabled(!editor.canStepTextSize.smaller)
        }
    }
}

// MARK: - By what the caret is in

/// A paragraph or a heading: Body, H1, H2, H3, and Link.
private struct ParagraphControls: View {
    @Bindable var editor: NoteEditor

    var body: some View {
        let level = editor.caretFormatting.headingLevel
        RowWord("Body", label: "Body", isSelected: level == 0, along: 44) { editor.setHeading(level: 0) }
        ForEach(1...3, id: \.self) { heading in
            RowWord("H\(heading)", label: "Heading \(heading)", isSelected: level == heading) {
                editor.setHeading(level: heading)
            }
        }
        // Lit while the caret is in a link: nothing to add to one that is there.
        HotbarButton("Link", "link", isSelected: editor.caretFormatting.link) { editor.beginLink() }
            .disabled(editor.caretFormatting.link)
    }
}

/// A list item: the three kinds (the current one tinted), outdent and indent.
private struct ListControls: View {
    @Bindable var editor: NoteEditor

    var body: some View {
        ForEach(MarkdownFormatting.ListStyle.allCases, id: \.self) { style in
            HotbarButton(style.title, style.systemImage, isSelected: editor.caretFormatting.list == style) {
                editor.toggleList(style)
            }
        }
        IndentControls(editor: editor)
    }
}

/// A code block: its language, outdent and indent, and + Output.
private struct CodeControls: View {
    @Bindable var editor: NoteEditor
    var label: String
    var kind: CodeBlockKind?
    var isClosed: Bool

    var body: some View {
        // The language button's own list, so the two can't disagree.
        Menu {
            ForEach(CodeBlockKind.languages, id: \.self, content: item)
            Divider()
            ForEach(CodeBlockKind.others, id: \.self, content: item)
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .hotbarTarget(along: 58)
        }
        .modifier(HotbarMenuStyle())
        .accessibilityLabel("Language")
        .accessibilityValue(label)

        IndentControls(editor: editor)

        // An output block is the output; it takes no output of its own. And
        // an unclosed block has nothing after it to put one in.
        if kind != .output {
            RowWord("+ Output", label: "Add Output Block", isSelected: false, along: 66) { editor.addOutputBlock() }
                .disabled(!isClosed)
        }
    }

    private func item(_ kind: CodeBlockKind) -> some View {
        Toggle(isOn: Binding(
            get: { self.kind == kind },
            set: { _ in editor.setCodeBlockKind(kind) }
        )) {
            Text(kind.displayName)
            if let subtitle = kind.subtitle { Text(subtitle) }
        }
    }
}

private struct IndentControls: View {
    @Bindable var editor: NoteEditor

    var body: some View {
        HotbarButton("Outdent", "decrease.indent") { editor.indent(outdent: true) }
        HotbarButton("Indent", "increase.indent") { editor.indent(outdent: false) }
    }
}

/// A control that is a word and not a symbol.
private struct RowWord: View {
    var word: String
    var label: String
    var isSelected: Bool
    var along: CGFloat?
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ word: String, label: String, isSelected: Bool, along: CGFloat? = nil, action: @escaping () -> Void) {
        self.word = word
        self.label = label
        self.isSelected = isSelected
        self.along = along
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(word)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .opacity(isEnabled ? 1 : 0.3)
                .hotbarTarget(isHighlighted: isSelected, along: along)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#endif
