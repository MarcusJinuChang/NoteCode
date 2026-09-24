//
//  Hotbar.swift
//  NoteCode
//
//  The note page's one toolbar: undo and redo, the text/ink toggle, and the
//  tools for whichever mode is on.
//

#if canImport(UIKit)

import SwiftUI

/// A single bar that docks to the left, bottom, or right of the page.
///
/// One bar rather than a toolbar per mode, so the undo arrows and the mode
/// toggle never move: only the tools after the divider change. It replaces
/// `PKToolPicker` in the drawing-layer plan, which removes the fight between
/// the keyboard and the tool picker over who is first responder.
struct Hotbar: View {
    @Bindable var editor: NoteEditor
    @Binding var dock: HotbarDock

    /// Where the grip was let go, in the page's coordinate space. The page
    /// decides which edge that is.
    var onDrop: (DragGesture.Value) -> Void

    /// How far the bar has been dragged from its dock.
    ///
    /// Gesture state rather than the page's own, so a drag that is cancelled
    /// rather than ended — the system taking the touch at the screen's edge —
    /// puts the bar back. A plain `@State` offset is only cleared by the
    /// drop, and a cancelled drag never drops. The reset springs, like the
    /// dock change it usually goes with, so the bar travels from where it was
    /// let go to where it lands in one movement.
    @GestureState(resetTransaction: Transaction(animation: .snappy))
    private var dragOffset: CGSize = .zero

    /// Apple's minimum comfortable touch target.
    static let buttonSide: CGFloat = 44
    static let padding: CGFloat = 4

    /// How far the bar reaches in from the edge it's docked to.
    static var thickness: CGFloat { buttonSide + padding * 2 }

    /// The coordinate space drags are measured in. Named on the page, which
    /// stays still, rather than on the bar, which moves under the finger.
    static let coordinateSpace = "notePage"

    @Environment(\.colorScheme) private var colorScheme

    private var axis: Axis.Set {
        dock.isVertical ? .vertical : .horizontal
    }

    private var stack: AnyLayout {
        dock.isVertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
    }

    var body: some View {
        stack {
            grip

            // Hugs its tools when they fit, and scrolls when they don't: the
            // ink tools don't fit down the side of an 11-inch iPad in
            // landscape, and a side dock with the keyboard up is short.
            HotbarTrack(axis: dock.isVertical ? .vertical : .horizontal) {
                ScrollView(axis, showsIndicators: false) { tools }
                    .scrollBounceBehavior(.basedOnSize, axes: axis)
            }
        }
        .padding(Self.padding)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.thickness / 2))
        .offset(dragOffset)
    }

    // MARK: Sections

    private var tools: some View {
        stack {
            button("Undo", "arrow.uturn.backward") { editor.undo() }
                .disabled(!editor.canUndo)
            button("Redo", "arrow.uturn.forward") { editor.redo() }
                .disabled(!editor.canRedo)

            modeToggle
            divider

            // Both tool sets are always laid out, and only the current one
            // shows. The bar then keeps the size of the larger set in either
            // mode, so switching doesn't resize it — a centred bar that
            // resized would slide the undo arrows and the toggle sideways,
            // right out from under the finger that just pressed it.
            ZStack(alignment: dock.isVertical ? .top : .leading) {
                stack { textTools }
                    .modeLayer(isShowing: editor.mode == .text)
                stack { inkTools }
                    .modeLayer(isShowing: editor.mode == .ink)
            }
        }
    }

    private var modeToggle: some View {
        stack {
            button("Text", "character.cursor.ibeam", isSelected: editor.mode == .text) {
                editor.setMode(.text)
            }
            // Not `pencil.tip`: that is the pen tool, which sits beside this
            // in ink mode.
            button("Draw", "pencil.and.scribble", isSelected: editor.mode == .ink) {
                editor.setMode(.ink)
            }
        }
        .background(.quaternary, in: .capsule)
    }

    @ViewBuilder
    private var textTools: some View {
        Menu {
            ForEach(1...3, id: \.self) { level in
                Button("Heading \(level)") { editor.setHeading(level: level) }
            }
            Button("Body Text") { editor.setHeading(level: 0) }
        } label: {
            HotbarIcon(systemImage: "textformat.size")
        }
        .modifier(HotbarMenuStyle())
        .accessibilityLabel("Heading")

        button("Bold", "bold") { editor.toggle(.bold) }
        button("Italic", "italic") { editor.toggle(.italic) }
        button("Strikethrough", "strikethrough") { editor.toggle(.strikethrough) }
        button("Inline Code", "chevron.left.forwardslash.chevron.right") { editor.toggle(.code) }
        button("Bulleted List", "list.bullet") { editor.toggleBullet() }

        Menu {
            ForEach(CodeLanguage.allCases, id: \.self) { language in
                Button(language.displayName) { editor.insertCodeBlock(language: language) }
            }
            Button("No Language") { editor.insertCodeBlock(language: nil) }
        } label: {
            HotbarIcon(systemImage: "curlybraces.square")
        }
        .modifier(HotbarMenuStyle())
        .accessibilityLabel("Code Block")
    }

    @ViewBuilder
    private var inkTools: some View {
        ForEach(InkToolKind.allCases, id: \.self) { kind in
            button(kind.label, kind.systemImage, isSelected: editor.inkTool.kind == kind) {
                editor.inkTool.kind = kind
            }
        }

        divider

        ForEach(InkColor.allCases, id: \.self) { color in
            swatch(color)
        }
        // The eraser and lasso have no colour, so the swatches stand down
        // rather than suggesting a choice that does nothing.
        .disabled(!editor.inkTool.kind.usesColor)

        divider

        // Locked, a finger scrolls and selects instead of drawing. Worth a
        // button rather than a setting: which one you want changes with
        // whether the Pencil is in your hand.
        button(
            "Pencil Only",
            editor.isPencilOnly ? "applepencil" : "hand.draw",
            isSelected: editor.isPencilOnly
        ) {
            editor.isPencilOnly.toggle()
        }
    }

    // MARK: Pieces

    private var grip: some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: dock.isVertical ? 20 : 5, height: dock.isVertical ? 5 : 20)
            .frame(
                width: dock.isVertical ? Self.buttonSide : 28,
                height: dock.isVertical ? 28 : Self.buttonSide
            )
            .contentShape(.rect)
            .gesture(
                DragGesture(coordinateSpace: .named(Self.coordinateSpace))
                    .updating($dragOffset) { drag, offset, _ in offset = drag.translation }
                    .onEnded(onDrop)
            )
            .accessibilityElement()
            .accessibilityLabel("Move Toolbar")
            .accessibilityValue("Docked \(dock.rawValue)")
            .accessibilityActions {
                ForEach(HotbarDock.allCases.filter { $0 != dock }, id: \.self) { edge in
                    Button("Dock \(edge.rawValue.capitalized)") { dock = edge }
                }
            }
    }

    private var divider: some View {
        Capsule()
            .fill(.separator)
            .frame(width: dock.isVertical ? 24 : 1, height: dock.isVertical ? 1 : 24)
            .padding(dock.isVertical ? .vertical : .horizontal, 6)
    }

    private func button(
        _ label: String,
        _ systemImage: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HotbarIcon(systemImage: systemImage, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func swatch(_ color: InkColor) -> some View {
        let isSelected = editor.inkTool.color == color
        // The colour as the ink will look on this page, so black doesn't
        // disappear into a dark bar.
        let shown = color.displayColor(for: colorScheme == .dark ? .dark : .light)

        return Button {
            editor.inkTool.color = color
        } label: {
            HotbarSwatch(color: Color(uiColor: shown), isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.rawValue.capitalized)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Gives the bar's scrolling tools their own length when there's room for it,
/// and the room there is when there isn't.
///
/// This was a `ViewThatFits` choosing between the tools and the tools in a
/// scroll view, and it froze the app. Docked to a side in ink mode on an
/// 11-inch iPad in landscape, the tools don't fit and it held the scroll view;
/// dropped back at the bottom, the axis flipped mid-animation and the two
/// branches traded places on every update, without end — the main thread at
/// 100% inside SwiftUI's transaction flush and the bar stuck mid-flight
/// (simulator, 23 September). Here the scroll view is always there and is
/// sized in one pass, so there's no branch to trade.
private struct HotbarTrack: Layout {
    var axis: Axis

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let track = subviews.first else { return .zero }
        // A scroll view's ideal size is its content's.
        let natural = track.sizeThatFits(.unspecified)
        switch axis {
        case .vertical:
            return CGSize(width: natural.width, height: min(natural.height, proposal.height ?? natural.height))
        case .horizontal:
            return CGSize(width: min(natural.width, proposal.width ?? natural.width), height: natural.height)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

private extension View {
    /// One mode's tools: present for layout in both modes, but only seen,
    /// touched, and read aloud in its own.
    func modeLayer(isShowing: Bool) -> some View {
        opacity(isShowing ? 1 : 0)
            .allowsHitTesting(isShowing)
            .accessibilityHidden(!isShowing)
    }
}

/// Makes a menu look like the buttons beside it. A `Menu` tints its label
/// with the accent colour by default, which reads as "selected" in a bar
/// where tint means exactly that.
private struct HotbarMenuStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
    }
}

/// One square hotbar button face.
private struct HotbarIcon: View {
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

private struct HotbarSwatch: View {
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

private extension InkToolKind {
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

private extension CodeLanguage {
    var displayName: String {
        switch self {
        case .cpp:    "C++"
        case .java:   "Java"
        case .python: "Python"
        }
    }
}

#endif
