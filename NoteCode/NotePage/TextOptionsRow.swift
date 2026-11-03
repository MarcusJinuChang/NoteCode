//
//  TextOptionsRow.swift
//  NoteCode
//
//  Text mode's counterpart of the ink options row: the note's text size, then
//  what the paragraph at the caret can be.
//

#if canImport(UIKit)

import SwiftUI

/// The groups of the row in prose and lists, in the order they sit along it:
/// the size first (top or left), then Bold, Italic, Underline and
/// Strikethrough, then colour and highlight, then More. Pure, so the order is
/// tested (`TextRowLayoutTests`) and not only looked at.
enum TextRowSection: Hashable {
    case size, style, colour, more

    static let prose: [TextRowSection] = [.size, .style, .colour, .more]
}

/// The row that floats beside the hotbar in text mode.
///
/// It starts with the size control, `+ 17 −` across (`+` over `17` over `−`
/// down the side), in that order: `−` usually comes first, and `+` comes
/// first here because that is how it was asked for. It is the size of the
/// text at the caret or the selection, as in Pages (text overhaul, phase 1,
/// 18 Oct); the note's own size is in ••• › Text Size. The rest follows the
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
    @Environment(\.coveredBySheet) private var coveredBySheet

    var body: some View {
        // Scrolls along the bar when it's longer than the space beside it
        // (a narrow phone, with the size and colour menus at the end).
        OptionsRowTrack(isVertical: isVertical) {
            HotbarStack(isVertical: isVertical) {
                switch editor.caretFormatting.block {
                case .paragraph, .listItem:
                    ForEach(TextRowSection.prose, id: \.self) { section in
                        switch section {
                        case .size:
                            SizeControl(editor: editor, isVertical: isVertical)
                        case .style:
                            InlineStyleButtons(editor: editor)
                        case .colour:
                            ColourSwatches(editor: editor, isVertical: isVertical)
                            HighlightMenu(editor: editor)
                        case .more:
                            MoreMenu(editor: editor)
                        }
                        if section != TextRowSection.prose.last {
                            HotbarDivider(isVertical: isVertical)
                        }
                    }
                case .code(let label, let kind, let isClosed):
                    SizeControl(editor: editor, isVertical: isVertical)
                    HotbarDivider(isVertical: isVertical)
                    CodeControls(editor: editor, label: label, kind: kind, isClosed: isClosed)
                }
            }
            .padding(isVertical ? .vertical : .horizontal, 2)
        }
        .background(alignment: style?.faceAlignment ?? .center) {
            Capsule()
                .fill(Color(.systemBackground))
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                .frame(
                    width: isVertical ? OptionsRowStyle.thickness : nil,
                    height: isVertical ? nil : OptionsRowStyle.thickness
                )
        }
        // Over the controls too, on the 40pt that is drawn, not the reach.
        .overlay(alignment: style?.faceAlignment ?? .center) {
            Color.clear
                .frame(
                    width: isVertical ? OptionsRowStyle.thickness : nil,
                    height: isVertical ? nil : OptionsRowStyle.thickness
                )
                .dimsWhenCovered(coveredBySheet, in: .capsule)
        }
    }
}

// MARK: - Size

/// `+`, the size on a pill, `−`: the size of the text at the caret or the
/// selection, a point a step, or a dash for a selection in several sizes.
/// Tapping the number lists sizes, Default (the text's own) and Custom….
/// In code it shows the code's size and does nothing: code isn't sized.
private struct SizeControl: View {
    @Bindable var editor: NoteEditor
    var isVertical: Bool

    var body: some View {
        let reading = editor.selectionTextSize
        let steps = editor.canStepSelectionSize
        HotbarStack(isVertical: isVertical) {
            HotbarButton("Bigger", "plus") { editor.stepSelectionSize(by: 1) }
                .disabled(!steps.bigger)

            Menu {
                ForEach(SpanSize.presets.reversed(), id: \.self) { size in
                    Toggle(isOn: Binding(
                        get: { reading.points == size },
                        set: { _ in editor.setSelectionSize(points: size) }
                    )) {
                        Text(SpanSize.label(points: size))
                    }
                }
                Divider()
                Button("Default · \(SpanSize.label(points: reading.ownPoints))") { editor.setSelectionSize(points: nil) }
                Button("Custom…") { editor.beginCustomSize() }
            } label: {
                Text(reading.points.map(SpanSize.label(points:)) ?? "–")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 28, maxWidth: 36, minHeight: 26, maxHeight: 26)
                    .padding(.horizontal, 2)
                    .background(Color(.secondarySystemFill), in: .capsule)
                    .hotbarTarget()
            }
            .modifier(HotbarMenuStyle())
            .menuOrder(.fixed)
            .disabled(!reading.canChange)
            .accessibilityLabel("Text Size")
            .accessibilityValue(reading.points.map { "\(SpanSize.label(points: $0)) points" } ?? "Mixed")

            HotbarButton("Smaller", "minus") { editor.stepSelectionSize(by: -1) }
                .disabled(!steps.smaller)
        }
    }
}

// MARK: - Prose

/// Bold, Italic, Underline, Strikethrough: lit by the style at the caret.
private struct InlineStyleButtons: View {
    @Bindable var editor: NoteEditor

    var body: some View {
        let shown = editor.formattingShown
        HotbarButton("Bold", "bold", isSelected: shown.bold) { editor.toggle(.bold) }
        HotbarButton("Italic", "italic", isSelected: shown.italic) { editor.toggle(.italic) }
        HotbarButton("Underline", "underline", isSelected: shown.underline) { editor.toggle(.underline) }
        HotbarButton("Strikethrough", "strikethrough", isSelected: shown.strikethrough) { editor.toggle(.strikethrough) }
    }
}

/// What the old row's prose and list controls gave up room for, each still
/// one menu away: headings (prose only), Quote, Link, the three lists, indent
/// and outdent, and line spacing.
private struct MoreMenu: View {
    @Bindable var editor: NoteEditor

    var body: some View {
        let caret = editor.caretFormatting
        Menu {
            if case .paragraph = caret.block {
                let level = caret.headingLevel
                Toggle("Body", isOn: Binding(get: { level == 0 }, set: { _ in editor.setHeading(level: 0) }))
                ForEach(1...3, id: \.self) { heading in
                    Toggle("Heading \(heading)", isOn: Binding(
                        get: { level == heading },
                        set: { _ in editor.setHeading(level: heading) }
                    ))
                }
                Divider()
                Toggle(isOn: Binding(get: { caret.quoteDepth > 0 }, set: { _ in editor.toggleQuote() })) {
                    Label("Quote", systemImage: "text.quote")
                }
                // Nothing to add to a link that is already there.
                Button { editor.beginLink() } label: { Label("Link", systemImage: "link") }
                    .disabled(caret.link)
                Divider()
            }
            ForEach(MarkdownFormatting.ListStyle.allCases, id: \.self) { style in
                Toggle(isOn: Binding(get: { caret.list == style }, set: { _ in editor.toggleList(style) })) {
                    Label(style.title, systemImage: style.systemImage)
                }
            }
            Divider()
            Button { editor.indent(outdent: true) } label: { Label("Outdent", systemImage: "decrease.indent") }
            Button { editor.indent(outdent: false) } label: { Label("Indent", systemImage: "increase.indent") }
            Divider()
            Menu {
                ForEach(NoteTypography.lineSpacings, id: \.self) { points in
                    Toggle(isOn: Binding(get: { editor.lineSpacing == points }, set: { _ in editor.setLineSpacing(points) })) {
                        Text(points == 0 ? "Default" : "+\(points) pt")
                    }
                }
            } label: {
                Label("Line Spacing", systemImage: "line.3.horizontal")
            }
        } label: {
            HotbarIcon(systemImage: "ellipsis.circle")
        }
        .modifier(HotbarMenuStyle())
        .menuOrder(.fixed)
        .accessibilityLabel("More")
    }
}

/// The text colours (`TextColour`) as a row of swatches, after a ring for
/// Default, which takes colour off. The one the caret is in is circled.
private struct ColourSwatches: View {
    @Bindable var editor: NoteEditor
    var isVertical: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let current = editor.formattingShown.colour
        let isDark = colorScheme == .dark
        HotbarStack(isVertical: isVertical) {
            swatch("Default Colour", image: Self.face(hex: nil, isDark: isDark), isSelected: current == nil, template: true) {
                editor.setColour(nil)
            }
            ForEach(TextColour.allCases, id: \.self) { colour in
                swatch("\(colour.name) Text", image: Self.swatch(hex: colour.hex, isDark: isDark), isSelected: current == colour.hex, template: false) {
                    editor.setColour(colour.hex)
                }
            }
        }
    }

    private func swatch(_ label: String, image: UIImage, isSelected: Bool, template: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(uiImage: image)
                .renderingMode(template ? .template : .original)
                .foregroundStyle(.primary)
                .hotbarTarget(isHighlighted: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A filled circle in the colour as it is drawn on this page.
    static func swatch(hex: Int, isDark: Bool, side: CGFloat = 16) -> UIImage {
        let colour = AccentPalette.uiColor(AccentPalette.textHex(for: hex, isDark: isDark))
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            colour.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).fill()
        }
    }

    /// The menu's face: the colour's swatch, or a ring for none.
    static func face(hex: Int?, isDark: Bool) -> UIImage {
        if let hex { return swatch(hex: hex, isDark: isDark, side: 20) }
        return UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in
            UIColor.black.setStroke()
            let ring = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 18, height: 18))
            ring.lineWidth = 2
            ring.stroke()
        }.withRenderingMode(.alwaysTemplate)
    }
}

/// Highlight (`HighlightColour`): the six, then None, which takes it off.
/// The face is the highlighter, in the colour the caret is in.
private struct HighlightMenu: View {
    @Bindable var editor: NoteEditor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let current = editor.formattingShown.highlight
        Menu {
            ForEach(HighlightColour.allCases, id: \.self) { colour in
                Toggle(isOn: Binding(get: { current == colour }, set: { _ in editor.setHighlight(colour) })) {
                    Label {
                        Text(colour.name)
                    } icon: {
                        Image(uiImage: Self.swatch(colour, isDark: colorScheme == .dark)).renderingMode(.original)
                    }
                }
            }
            Divider()
            Toggle(isOn: Binding(get: { current == nil }, set: { _ in editor.setHighlight(nil) })) {
                Text("None")
            }
        } label: {
            Image(systemName: "highlighter")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(current.map { Color(Self.solid($0, isDark: colorScheme == .dark)) } ?? Color.primary)
                .hotbarTarget()
        }
        .modifier(HotbarMenuStyle())
        .menuOrder(.fixed)
        .accessibilityLabel("Highlight")
        .accessibilityValue(current?.name ?? "None")
    }

    /// The hue as the menu paints it, opaque.
    private static func solid(_ colour: HighlightColour, isDark: Bool) -> UIColor {
        AccentPalette.uiColor(isDark ? colour.hex.dark : colour.hex.light)
    }

    /// A rounded square in the highlight as it shows on this page.
    static func swatch(_ colour: HighlightColour, isDark: Bool, side: CGFloat = 16) -> UIImage {
        let fill = solid(colour, isDark: isDark).withAlphaComponent(HighlightColour.alpha(isDark: isDark) + 0.35)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            fill.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: 4).fill()
        }
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
            if editor.ai.offersFeatures {
                RowWord("Explain", label: "Explain Code Block", isSelected: false, along: 58) { editor.explainBlockAtCaret?() }
            }
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
