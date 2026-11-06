//
//  HotbarPrimitives.swift
//  NoteCode
//
//  What the hotbar and the options row are built from: the persisted tool
//  settings, the colour swatches, the eraser's options, and the small
//  pieces (stack, button, divider, icon, swatch, dot). Moved out of
//  InkToolbar.swift.
//

#if canImport(UIKit)

import SwiftUI
import UniformTypeIdentifiers

/// Keeps what the pen, highlighter and eraser are set to, and Finger Draws,
/// from one note to the next. The editor has the live copy; this is the
/// device's.
///
/// Per device, like the palettes and the dock: it's how this reader likes to
/// work, not part of any note. Each tool remembers its own colour and width.
struct InkToolPersistence: ViewModifier {
    var editor: NoteEditor

    @AppStorage(SettingKeys.Drawing.penSettings)
    private var pen

    @AppStorage(SettingKeys.Drawing.highlighterSettings)
    private var highlighter

    @AppStorage(SettingKeys.Drawing.eraser)
    private var eraser

    @AppStorage(SettingKeys.Drawing.fingerDraws)
    private var fingerDraws

    @AppStorage(SettingKeys.Drawing.selectionKind)
    private var selectionKind

    @AppStorage(SettingKeys.Drawing.returnToPreviousTool)
    private var returnsToPreviousTool

    func body(content: Content) -> some View {
        content
            .onAppear {
                editor.inkTool.pen = pen
                editor.inkTool.highlighter = highlighter
                editor.inkTool.eraser = eraser
                editor.fingerDraws = fingerDraws
                editor.inkTool.selectionKind = selectionKind
                editor.returnsToPreviousTool = returnsToPreviousTool
            }
            .onChange(of: editor.inkTool.pen) { _, changed in pen = changed }
            .onChange(of: editor.inkTool.highlighter) { _, changed in highlighter = changed }
            .onChange(of: editor.inkTool.eraser) { _, changed in eraser = changed }
            .onChange(of: editor.fingerDraws) { _, changed in fingerDraws = changed }
            .onChange(of: editor.inkTool.selectionKind) { _, changed in selectionKind = changed }
            .onChange(of: returnsToPreviousTool) { _, stored in editor.returnsToPreviousTool = stored }
            // Settings changes these from a sheet over the open note, whose
            // editor was set from them as it appeared. Guarded by equality
            // so the editor's own change, written above, isn't echoed back.
            .onChange(of: eraser) { _, stored in
                if editor.inkTool.eraser != stored { editor.inkTool.eraser = stored }
            }
            .onChange(of: fingerDraws) { _, stored in
                if editor.fingerDraws != stored { editor.fingerDraws = stored }
            }
            // Choosing a colour set rewrites the highlighter's remembered
            // colour from Settings, over the open note.
            .onChange(of: highlighter) { _, stored in
                if editor.inkTool.highlighter != stored { editor.inkTool.highlighter = stored }
            }
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
        // (A highlighter on a dark bar is shown more vividly than it draws.)
        let shown = Color(uiColor: color.swatchFace(for: style, kind: kind))
        let canRemove = palette.colors.count > 1

        return Button {
            selected = color
        } label: {
            HotbarSwatch(color: shown, isSelected: isSelected, isMarker: kind == .highlighter)
        }
        .buttonStyle(.plain)
        // The pointer lifts the control it is over.
        .hoverEffect(.highlight)
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
            HotbarSwatch(color: shown, isSelected: false, isMarker: kind == .highlighter)
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
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .snappy) {
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
        // The pointer lifts the control it is over.
        .hoverEffect(.highlight)
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
        // No `.hoverEffect` here. Phase 9 had one, and a touch in the 8pt gap
        // between the options row and the bar then ran the Text button, 18pt
        // from where the touch was (the reach tests found it; removing this
        // effect, and only this one, passes them). The pointer still gets
        // the highlight on the row's controls and the bar's menus.
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
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(SettingKeys.General.iconStyle) private var iconStyle

    /// Our own icon for this symbol, unless the reader chose the system's.
    private var drawn: (icon: NoteIcon, weight: IconWeight)? {
        guard iconStyle.isDrawn, let icon = NoteIcon.replacing(systemName: systemImage) else { return nil }
        return (icon, (contrast == .increased ? iconStyle.increased : iconStyle).weight)
    }

    var body: some View {
        face
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .opacity(isEnabled ? 1 : 0.3)
            .hotbarTarget(isHighlighted: isSelected)
    }

    @ViewBuilder private var face: some View {
        if let drawn {
            NoteIconView(icon: drawn.icon, weight: drawn.weight, isTinted: isSelected)
                .frame(width: Self.drawnSize, height: Self.drawnSize)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }
    }

    /// A drawn icon's box, which the 44pt target is laid out around.
    static let drawnSize: CGFloat = 22
}

struct HotbarSwatch: View {
    var color: Color
    var isSelected: Bool
    /// A highlighter's swatch is a marker chip, so the two palettes read as
    /// different tools at a glance; a pen's is a disc.
    var isMarker = false

    @Environment(\.isEnabled) private var isEnabled

    /// A chip's size. Its ring (3pt out) is 32pt wide, so it fits a 34pt cell
    /// beside its neighbours' rings.
    static let chipSize = CGSize(width: 26, height: 18)
    private static let chipRadius: CGFloat = 6

    var body: some View {
        face
            .padding(isMarker ? 3 : 4)
            .overlay {
                if isSelected {
                    ring
                }
            }
            .opacity(isEnabled ? 1 : 0.3)
            .hotbarTarget()
    }

    @ViewBuilder private var face: some View {
        if isMarker {
            RoundedRectangle(cornerRadius: Self.chipRadius)
                .fill(color)
                .overlay { RoundedRectangle(cornerRadius: Self.chipRadius).strokeBorder(.primary.opacity(0.2), lineWidth: 1) }
                .frame(width: Self.chipSize.width, height: Self.chipSize.height)
        } else {
            Circle()
                .fill(color)
                .overlay { Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1) }
                .frame(width: 22, height: 22)
        }
    }

    @ViewBuilder private var ring: some View {
        if isMarker {
            RoundedRectangle(cornerRadius: Self.chipRadius + 3).strokeBorder(.tint, lineWidth: 2)
        } else {
            Circle().strokeBorder(.tint, lineWidth: 2)
        }
    }
}

/// A size: a dot as wide, relatively, as the eraser or the line.
struct HotbarDot: View {
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
