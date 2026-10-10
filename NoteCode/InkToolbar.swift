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
/// highlighter, mode and size for the eraser, nothing for the lasso.
///
/// The content only. The hotbar floats it beside itself in a glass capsule
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
            EmptyView()
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

/// Keeps what the pen, highlighter and eraser are set to from one note to the
/// next. The editor has the live copy; this is the device's.
///
/// Per device, like the palettes and the dock: it's how this reader likes to
/// work, not part of any note. Each tool remembers its own colour and width.
struct InkToolPersistence: ViewModifier {
    var editor: NoteEditor

    @AppStorage(InkingSettings.defaultsKey(for: .pen))
    private var pen = InkingSettings.standard(for: .pen)

    @AppStorage(InkingSettings.defaultsKey(for: .highlighter))
    private var highlighter = InkingSettings.standard(for: .highlighter)

    @AppStorage(EraserSettings.defaultsKey)
    private var eraser = EraserSettings()

    func body(content: Content) -> some View {
        content
            .onAppear {
                editor.inkTool.pen = pen
                editor.inkTool.highlighter = highlighter
                editor.inkTool.eraser = eraser
            }
            .onChange(of: editor.inkTool.pen) { _, changed in pen = changed }
            .onChange(of: editor.inkTool.highlighter) { _, changed in highlighter = changed }
            .onChange(of: editor.inkTool.eraser) { _, changed in eraser = changed }
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
/// at the bar's end of that, and the glass is drawn on the 40pt of it. A
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
    @Environment(\.optionsRow) private var row

    private var highlight: some View {
        Circle().fill(.tint.opacity(isHighlighted ? 0.18 : 0)).padding(4)
    }

    func body(content: Content) -> some View {
        if let row {
            content
                .frame(
                    width: row.isVertical ? OptionsRowStyle.thickness : OptionsRowStyle.pitch,
                    height: row.isVertical ? OptionsRowStyle.pitch : OptionsRowStyle.thickness
                )
                .background { highlight }
                .frame(
                    width: row.isVertical ? row.controlThickness : OptionsRowStyle.pitch,
                    height: row.isVertical ? OptionsRowStyle.pitch : row.controlThickness,
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
private struct RowGroupBackground: ViewModifier {
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
    func hotbarTarget(isHighlighted: Bool = false) -> some View {
        modifier(HotbarTarget(isHighlighted: isHighlighted))
    }
}

// MARK: - Colours

/// The palette's colours, and a button to add one.
///
/// Hold a colour to remove it; hold and drag to move it.
struct InkSwatches: View {
    @Bindable var editor: NoteEditor
    /// The pen or the highlighter, each with a palette of its own.
    var kind: InkToolKind
    var isVertical: Bool

    @AppStorage private var palette: InkPalette

    init(editor: NoteEditor, kind: InkToolKind, isVertical: Bool) {
        self.editor = editor
        self.kind = kind
        self.isVertical = isVertical
        _palette = AppStorage(wrappedValue: .standard(for: kind), InkPalette.defaultsKey(for: kind))
    }

    /// The colour this tool draws in.
    private var selected: InkColor {
        get { editor.inkTool[inking: kind].color }
        nonmutating set { editor.inkTool[inking: kind].color = newValue }
    }

    /// The colour being dragged to a new place, while it is.
    @State private var dragged: InkColor?

    @State private var picker = InkColorPicker()

    @Environment(\.colorScheme) private var colorScheme

    private var style: UIUserInterfaceStyle {
        colorScheme == .dark ? .dark : .light
    }

    var body: some View {
        HotbarStack(isVertical: isVertical) {
            ForEach(palette.colors, id: \.self) { color in
                swatch(color)
            }

            HotbarButton("Add Colour", "plus.circle.dashed") {
                picker.present(starting: selected.displayColor(for: style)) { chosen in
                    selected = palette.add(InkColor(chosen: chosen, on: style))
                }
            }
            .background(InkColorPicker.Anchor(picker: picker))
        }
        // If the colour the tool remembers has been taken out of the palette,
        // the first colour stands in, so a swatch always shows what the tool
        // draws in.
        .onAppear {
            if !palette.colors.contains(selected) {
                selected = palette.colors[0]
            }
        }
    }

    private func swatch(_ color: InkColor) -> some View {
        let isSelected = selected == color
        // The colour as the ink will look on this page, so black doesn't
        // disappear into a dark bar.
        let shown = Color(uiColor: color.displayColor(for: style))
        let canRemove = palette.colors.count > 1

        return Button {
            selected = color
        } label: {
            HotbarSwatch(color: shown, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive) { remove(color) }
                .disabled(!canRemove)
        }
        // The drag carries nothing another app could use; `dragged` is what
        // the swatches read. Moving live, as the drag passes each swatch,
        // shows where the colour will land before it's let go.
        .onDrag {
            dragged = color
            return NSItemProvider(object: color.dragName as NSString)
        } preview: {
            HotbarSwatch(color: shown, isSelected: false)
        }
        .onDrop(of: [.plainText], delegate: SwatchDrop(target: color, palette: $palette, dragged: $dragged))
        .accessibilityLabel(color.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            Button(isVertical ? "Move Up" : "Move Left") { palette.move(color, by: -1) }
            Button(isVertical ? "Move Down" : "Move Right") { palette.move(color, by: 1) }
            if canRemove {
                Button("Remove") { remove(color) }
            }
        }
    }

    private func remove(_ color: InkColor) {
        guard let replacement = palette.remove(color) else { return }
        // Still drawing in a colour that's gone from the bar would leave no
        // swatch selected and no way to see what the pen draws in.
        if selected == color {
            selected = replacement
        }
    }
}

/// Moves the dragged colour into each swatch's place as the drag reaches it.
private struct SwatchDrop: DropDelegate {
    let target: InkColor
    @Binding var palette: InkPalette
    @Binding var dragged: InkColor?

    func validateDrop(info: DropInfo) -> Bool {
        // Only a swatch; text dragged in from elsewhere isn't a colour.
        dragged != nil
    }

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target else { return }
        withAnimation(.snappy) {
            palette.move(dragged, to: target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}

private extension InkColor {
    var dragName: String { "\(red),\(green),\(blue),\(alpha)" }
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
                .accessibilityLabel("\(width.title) \(kind.label)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

// MARK: - Eraser

/// Pixel or object erasing, and how wide the pixel eraser is.
struct EraserOptions: View {
    @Bindable var editor: NoteEditor
    var isVertical: Bool

    @State private var editsCustomSize = false

    private var eraser: EraserSettings { editor.inkTool.eraser }

    var body: some View {
        HotbarStack(isVertical: isVertical) {
            HotbarStack(isVertical: isVertical) {
                HotbarButton("Pixel Eraser", "eraser.line.dashed", isSelected: eraser.mode == .partial) {
                    editor.inkTool.eraser.mode = .partial
                }
                HotbarButton("Object Eraser", "scribble.variable", isSelected: eraser.mode == .wholeStroke) {
                    editor.inkTool.eraser.mode = .wholeStroke
                }
            }
            .modifier(RowGroupBackground(isVertical: isVertical))

            HotbarDivider(isVertical: isVertical)

            HotbarStack(isVertical: isVertical) {
                ForEach(EraserSettings.Size.allCases.filter { $0 != .custom }, id: \.self) { size in
                    sizeButton(size)
                }

                HotbarButton("Custom Size", "slider.horizontal.3", isSelected: eraser.size == .custom) {
                    editor.inkTool.eraser.size = .custom
                    editsCustomSize = true
                }
                .popover(isPresented: $editsCustomSize) {
                    EraserSizeEditor(width: $editor.inkTool.eraser.customWidth)
                }
            }
            // The object eraser takes whole strokes and has no width.
            .disabled(eraser.mode == .wholeStroke)
        }
    }

    private func sizeButton(_ size: EraserSettings.Size) -> some View {
        let width = EraserSettings.width(of: size) ?? eraser.customWidth
        // From the eraser's own range onto a dot that fits the button.
        let range = EraserSettings.widthRange
        let diameter = 6 + 14 * (width - range.lowerBound) / (range.upperBound - range.lowerBound)
        let isSelected = eraser.size == size

        return Button {
            editor.inkTool.eraser.size = size
        } label: {
            HotbarDot(diameter: diameter, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(size.rawValue.capitalized) Eraser")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The custom eraser size: a slider over PencilKit's range, and the eraser
/// drawn at the size it will erase at.
private struct EraserSizeEditor: View {
    @Binding var width: Double

    var body: some View {
        VStack(spacing: 16) {
            Text("Eraser Size")
                .font(.headline)

            Circle()
                .strokeBorder(.secondary, lineWidth: 1)
                .background(Circle().fill(.quaternary))
                .frame(width: width, height: width)
                .frame(
                    width: EraserSettings.widthRange.upperBound,
                    height: EraserSettings.widthRange.upperBound
                )

            Slider(value: $width, in: EraserSettings.widthRange) {
                Text("Size")
            } minimumValueLabel: {
                Image(systemName: "circle.fill").font(.system(size: 6))
            } maximumValueLabel: {
                Image(systemName: "circle.fill").font(.system(size: 16))
            }

            Text("\(width, format: .number.precision(.fractionLength(0))) pt")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 300)
        .presentationCompactAdaptation(.popover)
    }
}

// MARK: - Pieces

/// A stack along the bar: down it when the bar is docked to a side, across
/// it at the bottom.
struct HotbarStack<Content: View>: View {
    var isVertical: Bool
    @ViewBuilder var content: Content

    var body: some View {
        let layout = isVertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout { content }
    }
}

struct HotbarButton: View {
    var label: String
    var systemImage: String
    var isSelected = false
    var action: () -> Void

    init(_ label: String, _ systemImage: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HotbarIcon(systemImage: systemImage, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct HotbarDivider: View {
    var isVertical: Bool

    var body: some View {
        Capsule()
            .fill(.separator)
            .frame(width: isVertical ? 24 : 1, height: isVertical ? 1 : 24)
            .padding(isVertical ? .vertical : .horizontal, 6)
    }
}

/// One square hotbar button face.
struct HotbarIcon: View {
    var systemImage: String
    var isSelected = false

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .opacity(isEnabled ? 1 : 0.3)
            .hotbarTarget(isHighlighted: isSelected)
    }
}

struct HotbarSwatch: View {
    var color: Color
    var isSelected: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Circle()
            .fill(color)
            .overlay { Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1) }
            .frame(width: 22, height: 22)
            .padding(4)
            .overlay {
                if isSelected {
                    Circle().strokeBorder(.tint, lineWidth: 2)
                }
            }
            .opacity(isEnabled ? 1 : 0.3)
            .hotbarTarget()
    }
}

/// A size: a dot as wide, relatively, as the eraser or the line.
private struct HotbarDot: View {
    var diameter: CGFloat
    var isSelected: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Circle()
            .fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(width: diameter, height: diameter)
            .opacity(isEnabled ? 1 : 0.3)
            .hotbarTarget(isHighlighted: isSelected)
    }
}

extension View {
    /// One of several sets of controls laid out in the same place: present
    /// for layout always, but only seen, touched, and read aloud when it's
    /// the one showing.
    func hotbarLayer(isShowing: Bool) -> some View {
        opacity(isShowing ? 1 : 0)
            .allowsHitTesting(isShowing)
            .accessibilityHidden(!isShowing)
    }
}

extension InkToolKind {
    var label: String {
        switch self {
        case .pen:         "Pen"
        case .highlighter: "Highlighter"
        case .eraser:      "Eraser"
        case .lasso:       "Lasso"
        }
    }

    var systemImage: String {
        switch self {
        case .pen:         "pencil.tip"
        case .highlighter: "highlighter"
        case .eraser:      "eraser"
        case .lasso:       "lasso"
        }
    }
}

#endif
