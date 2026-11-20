//
//  InkToolbar.swift
//  NoteCode
//
//  The ink tools and their options, shared by the hotbar and the palette
//  the Pencil's squeeze brings up. The tools sit on the hotbar; the options
//  of the tool selected float in a row of their own beside it.
//

#if canImport(UIKit)

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tools

/// Pen, highlighter, eraser and lasso.
struct InkToolButtons: View {
    @Bindable var editor: NoteEditor
    var isVertical: Bool

    var body: some View {
        HotbarStack(isVertical: isVertical) {
            ForEach(InkToolKind.allCases, id: \.self) { kind in
                HotbarButton(kind.label, kind.systemImage, isSelected: editor.inkTool.kind == kind) {
                    editor.inkTool.kind = kind
                }
            }
        }
    }
}

/// What the selected tool can be set to: colours and a width for the pen and
/// highlighter, mode and size for the eraser, and for the Select tool its shape
/// and, with something selected, what to do to it.
///
/// The content only. The hotbar floats it beside itself on the bar material
/// (`Hotbar.optionsRow`), and the Pencil's palette lays it under the tools.
struct InkOptions: View {
    @Bindable var editor: NoteEditor
    var isVertical: Bool

    var body: some View {
        switch editor.inkTool.kind {
        case .pen, .highlighter:
            let kind = editor.inkTool.kind
            HotbarStack(isVertical: isVertical) {
                // One palette for each tool. Keyed by the tool, so going from
                // the pen to the highlighter builds a new set of swatches on
                // the other palette's storage rather than reusing these.
                InkSwatches(editor: editor, kind: kind, isVertical: isVertical)
                    .id(kind)
                HotbarDivider(isVertical: isVertical)
                InkWidths(editor: editor, kind: kind, isVertical: isVertical)
            }
        case .eraser:
            EraserOptions(editor: editor, isVertical: isVertical)
        case .lasso:
            SelectOptions(editor: editor, isVertical: isVertical)
        }
    }
}

/// What the Pencil's squeeze brings up, beside the Pencil: the hotbar's two
/// rows folded into one panel. Undo and the tools, then the selected tool's
/// options.
///
/// The same pieces as the hotbar, so a colour or size chosen in either is
/// chosen in both.
struct InkToolPopover: View {
    @Bindable var editor: NoteEditor

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                HotbarButton("Undo", "arrow.uturn.backward") { editor.undo() }
                    .disabled(!editor.canUndo)
                HotbarButton("Redo", "arrow.uturn.forward") { editor.redo() }
                    .disabled(!editor.canRedo)
                HotbarDivider(isVertical: false)
                InkToolButtons(editor: editor, isVertical: false)
            }

            if editor.inkTool.hasOptions {
                // No page side to reach toward in a popover, so no reach.
                InkOptions(editor: editor, isVertical: false)
                    .environment(\.optionsRow, OptionsRowStyle(isVertical: false, reach: nil))
            }
        }
        .padding(Hotbar.padding)
        .presentationCompactAdaptation(.popover)
    }
}

// MARK: - The options row

/// How a control in the options row is laid out, set on the row and read by
/// every control face in it.
///
/// The row looks 40pt thick, and each control takes touches across 44pt,
/// reaching past the row's edge toward the page rather than back toward the
/// bar, so the 8pt gap between them stays a gap. Along the row a control is
/// 34pt: the design fits the pen's seven colours, Add Colour and three widths
/// in 391pt. Outside the row (`nil`) a control is the bar's 44pt square.
///
/// The reach is layout, not a hit shape: each control is 44pt thick, its face
/// at the bar's end of that, and the surface is drawn on the 40pt of it. A
/// `contentShape` grown past a view's bounds took no touches there (measured
/// in the simulator on 9 October: nothing past the page edge of the frame, and
/// 5pt past the bar's).
struct OptionsRowStyle: Equatable {
    var isVertical: Bool
    /// The edge of the row facing the page, which touches reach past.
    var reach: Edge?

    static let pitch: CGFloat = 34
    static let thickness: CGFloat = 40
    static let reachAmount: CGFloat = 4

    /// How thick a control is, reach included.
    var controlThickness: CGFloat {
        Self.thickness + (reach == nil ? 0 : Self.reachAmount)
    }

    /// Where a control's face sits within its frame: at the bar's end, so the
    /// reach is all on the page's side.
    var faceAlignment: Alignment {
        switch reach {
        case .top:      .bottom
        case .bottom:   .top
        case .leading:  .trailing
        case .trailing: .leading
        case nil:       .center
        }
    }
}

private struct OptionsRowKey: EnvironmentKey {
    static let defaultValue: OptionsRowStyle? = nil
}

extension EnvironmentValues {
    var optionsRow: OptionsRowStyle? {
        get { self[OptionsRowKey.self] }
        set { self[OptionsRowKey.self] = newValue }
    }
}

/// Sizes a control face: the bar's 44pt square, or in the options row a cell
/// 34pt along it and 40pt across, in a frame 4pt thicker toward the page, so
/// touches there are the control's.
///
/// The selection highlight is drawn here too, on the face, not on the whole
/// frame: behind the frame it was centred on the 44pt, 2pt off the icon toward
/// the page.
private struct HotbarTarget: ViewModifier {
    var isHighlighted: Bool
    /// A cell's length along the row where 34pt is too short for its words
    /// ("Body", "+ Output"); `nil` for the pitch.
    var along: CGFloat?
    @Environment(\.optionsRow) private var row

    private var highlight: some View {
        Circle().fill(.tint.opacity(isHighlighted ? 0.18 : 0)).padding(4)
    }

    func body(content: Content) -> some View {
        if let row {
            let length = along ?? OptionsRowStyle.pitch
            content
                .frame(
                    width: row.isVertical ? OptionsRowStyle.thickness : length,
                    height: row.isVertical ? length : OptionsRowStyle.thickness
                )
                .background { highlight }
                .frame(
                    width: row.isVertical ? row.controlThickness : length,
                    height: row.isVertical ? length : row.controlThickness,
                    alignment: row.faceAlignment
                )
                .contentShape(.rect)
        } else {
            content
                .frame(width: Hotbar.buttonSide, height: Hotbar.buttonSide)
                .background { highlight }
                .contentShape(.rect)
        }
    }
}

/// A pill behind a group of controls in the row, on the 40pt of it that is
/// drawn, not the 4pt of reach: the controls are thicker than the row looks.
struct RowGroupBackground: ViewModifier {
    var isVertical: Bool
    @Environment(\.optionsRow) private var row

    func body(content: Content) -> some View {
        if let row {
            content.background(alignment: row.faceAlignment) {
                Capsule()
                    .fill(.quaternary)
                    .frame(
                        width: isVertical ? OptionsRowStyle.thickness : nil,
                        height: isVertical ? nil : OptionsRowStyle.thickness
                    )
            }
        } else {
            content.background(.quaternary, in: .capsule)
        }
    }
}

extension View {
    /// - Parameter isHighlighted: draws the selection circle behind the face.
    func hotbarTarget(isHighlighted: Bool = false, along: CGFloat? = nil) -> some View {
        modifier(HotbarTarget(isHighlighted: isHighlighted, along: along))
    }
}

// MARK: - Widths

/// Fine, medium and bold, for the pen or the highlighter.
struct InkWidths: View {
    @Bindable var editor: NoteEditor
    var kind: InkToolKind
    var isVertical: Bool

    /// A dot as wide, relatively, as the line it stands for. The same three
    /// for both tools: the multiples are each tool's own.
    private static let diameters: [InkWidth: CGFloat] = [.fine: 6, .medium: 10, .bold: 15]

    var body: some View {
        HotbarStack(isVertical: isVertical) {
            ForEach(InkWidth.allCases, id: \.self) { width in
                let isSelected = editor.inkTool[inking: kind].width == width
                Button {
                    editor.inkTool[inking: kind].width = width
                } label: {
                    HotbarDot(diameter: Self.diameters[width] ?? 10, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                // The pointer lifts the control it is over.
                .hoverEffect(.highlight)
                .accessibilityLabel("\(width.title) \(kind.label)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}


#endif
