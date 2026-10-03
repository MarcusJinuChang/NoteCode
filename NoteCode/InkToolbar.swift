//
//  InkToolbar.swift
//  NoteCode
//
//  The ink tools and their options, shared by the hotbar and the palette
//  the Pencil's squeeze brings up.
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

/// What the current tool can be set to: colours for the pen and
/// highlighter, mode and size for the eraser.
///
/// Both sets are always laid out and only one shows, for the reason the
/// hotbar does the same with its two modes: switching tools doesn't resize
/// the bar and slide the buttons out from under the finger.
struct InkToolOptions: View {
    @Bindable var editor: NoteEditor
    var isVertical: Bool

    var body: some View {
        ZStack(alignment: isVertical ? .top : .leading) {
            InkSwatches(editor: editor, isVertical: isVertical)
                // The lasso has no colour, so the swatches stand down rather
                // than suggesting a choice that does nothing.
                .disabled(!editor.inkTool.kind.usesColor)
                .hotbarLayer(isShowing: editor.inkTool.kind != .eraser)
            EraserOptions(editor: editor, isVertical: isVertical)
                .hotbarLayer(isShowing: editor.inkTool.kind == .eraser)
        }
    }
}

/// What the Pencil's squeeze brings up, beside the Pencil: the ink tools and
/// their options, and undo.
///
/// The same pieces as the hotbar, so a colour or size chosen in either is
/// chosen in both.
struct InkToolPopover: View {
    @Bindable var editor: NoteEditor

    var body: some View {
        HStack(spacing: 0) {
            HotbarButton("Undo", "arrow.uturn.backward") { editor.undo() }
                .disabled(!editor.canUndo)
            HotbarButton("Redo", "arrow.uturn.forward") { editor.redo() }
                .disabled(!editor.canRedo)
            HotbarDivider(isVertical: false)
            InkToolButtons(editor: editor, isVertical: false)
            HotbarDivider(isVertical: false)
            InkToolOptions(editor: editor, isVertical: false)
        }
        .padding(Hotbar.padding)
        .presentationCompactAdaptation(.popover)
    }
}

// MARK: - Colours

/// The palette's colours, and a button to add one.
///
/// Hold a colour to remove it; hold and drag to move it.
struct InkSwatches: View {
    @Bindable var editor: NoteEditor
    var isVertical: Bool

    @AppStorage(InkPalette.defaultsKey) private var palette = InkPalette.standard

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
                picker.present(starting: editor.inkTool.color.displayColor(for: style)) { chosen in
                    let color = palette.add(InkColor(chosen: chosen, on: style))
                    editor.inkTool.color = color
                }
            }
            .background(InkColorPicker.Anchor(picker: picker))
        }
        // A note opens drawing in black. If black has been taken out of the
        // palette, the first colour stands in, so a swatch always shows
        // what the pen draws in.
        .onAppear {
            if !palette.colors.contains(editor.inkTool.color) {
                editor.inkTool.color = palette.colors[0]
            }
        }
    }

    private func swatch(_ color: InkColor) -> some View {
        let isSelected = editor.inkTool.color == color
        // The colour as the ink will look on this page, so black doesn't
        // disappear into a dark bar.
        let shown = Color(uiColor: color.displayColor(for: style))
        let canRemove = palette.colors.count > 1

        return Button {
            editor.inkTool.color = color
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
        if editor.inkTool.color == color {
            editor.inkTool.color = replacement
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
            .background(.quaternary, in: .capsule)

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
            .frame(width: Hotbar.buttonSide, height: Hotbar.buttonSide)
            .background {
                if isSelected {
                    Circle().fill(.tint.opacity(0.18)).padding(4)
                }
            }
            .contentShape(.rect)
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
            .frame(width: Hotbar.buttonSide, height: Hotbar.buttonSide)
            .contentShape(.rect)
    }
}

/// An eraser size: a dot as wide, relatively, as the eraser.
private struct HotbarDot: View {
    var diameter: CGFloat
    var isSelected: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Circle()
            .fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(width: diameter, height: diameter)
            .opacity(isEnabled ? 1 : 0.3)
            .frame(width: Hotbar.buttonSide, height: Hotbar.buttonSide)
            .background {
                if isSelected {
                    Circle().fill(.tint.opacity(0.18)).padding(4)
                }
            }
            .contentShape(.rect)
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
