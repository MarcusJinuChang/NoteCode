//
//  SelectionOptions.swift
//  NoteCode
//
//  The Select tool's options row: how to draw the shape, and, with something
//  selected, what to do to it. docs/design/object-system.md, decision 2.
//

#if canImport(UIKit)

import SwiftUI

struct SelectOptions: View {
    @Bindable var editor: NoteEditor
    var isVertical: Bool

    var body: some View {
        HotbarStack(isVertical: isVertical) {
            HotbarStack(isVertical: isVertical) {
                ForEach(SelectionKind.allCases, id: \.self) { kind in
                    HotbarButton(kind.title, kind.systemImage, isSelected: editor.inkTool.selectionKind == kind) {
                        editor.inkTool.selectionKind = kind
                    }
                }
            }

            if let selection = editor.selection, !selection.isEmpty {
                HotbarDivider(isVertical: isVertical)
                SelectionSwatches(selection: selection, isVertical: isVertical)
                HotbarDivider(isVertical: isVertical)
                HotbarButton("Duplicate", "plus.square.on.square") { selection.duplicate() }
                HotbarButton("Delete", "trash") { selection.delete() }
            }
        }
    }
}

/// The pen's palette as a way to recolour what is selected.
private struct SelectionSwatches: View {
    var selection: InkSelection
    var isVertical: Bool

    @AppStorage(InkPalette.defaultsKey(for: .pen))
    private var palette = InkPalette.standard(for: .pen)

    @Environment(\.colorScheme) private var colorScheme

    private var style: UIUserInterfaceStyle {
        colorScheme == .dark ? .dark : .light
    }

    var body: some View {
        HotbarStack(isVertical: isVertical) {
            ForEach(palette.colors, id: \.self) { color in
                Button {
                    selection.recolour(to: color.inkColor)
                } label: {
                    HotbarSwatch(color: Color(uiColor: color.displayColor(for: style)), isSelected: false)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel("Colour \(color.name)")
            }
        }
    }
}

#endif
