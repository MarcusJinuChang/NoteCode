//
//  Hotbar.swift
//  NoteCode
//
//  The note page's one toolbar: undo and redo, the text/ink toggle, and the
//  tools for whichever mode is on. In ink mode the selected tool's options
//  float beside it in a row of their own.
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

    /// Between the bar and the options row beside it.
    static let optionsGap: CGFloat = 8

    /// How far the bar reaches in from the edge it's docked to.
    static var thickness: CGFloat { buttonSide + padding * 2 }

    /// The coordinate space drags are measured in. Named on the page, which
    /// stays still, rather than on the bar, which moves under the finger.
    static let coordinateSpace = "notePage"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var axis: Axis.Set {
        dock.isVertical ? .vertical : .horizontal
    }

    private var stack: AnyLayout {
        dock.isVertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
    }

    var body: some View {
        stack {
            grip

            // Outside the scroll view, so they never scroll away with the
            // tools: undo and the mode toggle are what's reached for most,
            // and they stay where the hand expects them.
            pinned
            divider

            // Hugs its tools when they fit, and scrolls when they don't: the
            // ink tools don't fit down the side of an 11-inch iPad in
            // landscape, and a side dock with the keyboard up is short.
            HotbarTrack(axis: dock.isVertical ? .vertical : .horizontal) {
                ScrollView(axis, showsIndicators: false) { tools }
                    .scrollBounceBehavior(.basedOnSize, axes: axis)
            }
        }
        // One toolbar to VoiceOver, with the buttons inside it, and a frame
        // for tests to find the bar by.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hotbar")
        .padding(Self.padding)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.thickness / 2))
        // An overlay, so the row takes no room: it floats over the page and
        // leaves the bar's size alone, which is what keeps the page where it
        // is whichever mode, tool or edge the bar is on. Inside the offset,
        // so it travels with the bar when the grip drags it.
        .overlay {
            BesideBar(dock: dock, gap: Self.optionsGap) { optionsRow }
        }
        .animation(.snappy, value: showsOptions)
        .offset(dragOffset)
    }

    // MARK: Options row

    /// Whether the row is out: in ink mode, for a tool with anything to set.
    private var showsOptions: Bool {
        editor.mode == .ink && editor.inkTool.hasOptions
    }

    /// The selected ink tool's options, 8pt from the bar on the page's side
    /// and centred along it.
    ///
    /// `fixedSize` because an overlay is proposed the bar's size, and the
    /// pen's row is longer than a side-docked bar. It slides out from the
    /// bar, or under Reduce Motion fades.
    @ViewBuilder
    private var optionsRow: some View {
        if showsOptions {
            InkOptionsRow(editor: editor, isVertical: dock.isVertical)
                .environment(\.optionsRow, OptionsRowStyle(isVertical: dock.isVertical, reach: dock.pageEdge))
                .fixedSize()
                .transition(reduceMotion ? .opacity : .move(edge: dock.barEdge).combined(with: .opacity))
        }
    }

    // MARK: Sections

    private var pinned: some View {
        stack {
            button("Undo", "arrow.uturn.backward") { editor.undo() }
                .disabled(!editor.canUndo)
            button("Redo", "arrow.uturn.forward") { editor.redo() }
                .disabled(!editor.canRedo)

            modeToggle
        }
    }

    private var tools: some View {
        // Both tool sets are always laid out, and only the current one
        // shows. The bar then keeps the size of the larger set in either
        // mode, so switching doesn't resize it — a centred bar that resized
        // would slide the undo arrows and the toggle sideways, right out
        // from under the finger that just pressed it.
        ZStack(alignment: dock.isVertical ? .top : .leading) {
            // Greyed out while the text is locked: still where the hand
            // expects them, but plainly unavailable.
            stack { textTools }
                .disabled(editor.isTextLocked)
                .hotbarLayer(isShowing: editor.mode == .text)
            stack { inkTools }
                .hotbarLayer(isShowing: editor.mode == .ink)
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
            Button("Body") { editor.setHeading(level: 0) }
            Divider()
            Button("Strikethrough", systemImage: "strikethrough") { editor.toggle(.strikethrough) }
        } label: {
            HotbarIcon(systemImage: "textformat")
        }
        .modifier(HotbarMenuStyle())
        .accessibilityLabel("Style")

        button("Bold", "bold") { editor.toggle(.bold) }
        button("Italic", "italic") { editor.toggle(.italic) }
        button("Inline Code", "chevron.left.forwardslash.chevron.right") { editor.toggle(.code) }

        // A menu of one, for now: numbered lists and checklists will join it,
        // and the bar won't have to grow a button for each.
        Menu {
            Button("Bulleted List", systemImage: "list.bullet") { editor.toggleBullet() }
        } label: {
            HotbarIcon(systemImage: "list.bullet")
        }
        .modifier(HotbarMenuStyle())
        .accessibilityLabel("List")

        Menu {
            ForEach(CodeLanguage.allCases, id: \.self) { language in
                Button(language.displayName) { editor.insertCodeBlock(language: language) }
            }
            Button("Plain Text") { editor.insertCodeBlock(language: nil) }
        } label: {
            HotbarIcon(systemImage: "curlybraces.square")
        }
        .modifier(HotbarMenuStyle())
        .accessibilityLabel("Code Block")
    }

    /// Just the tools and the finger. What each tool can be set to is in the
    /// options row, so the bar is short enough to fit down the side of an
    /// 11-inch iPad in landscape.
    @ViewBuilder
    private var inkTools: some View {
        InkToolButtons(editor: editor, isVertical: dock.isVertical)
        divider

        // Off, a finger scrolls and selects instead of drawing. Worth a
        // button rather than a setting alone: which one you want changes with
        // whether the Pencil is in your hand.
        button("Finger Draws", "hand.draw", isSelected: editor.fingerDraws) {
            editor.fingerDraws.toggle()
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
        HotbarDivider(isVertical: dock.isVertical)
    }

    private func button(
        _ label: String,
        _ systemImage: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HotbarButton(label, systemImage, isSelected: isSelected, action: action)
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

/// The options row's glass, around what the selected tool can be set to.
///
/// 40pt thick, drawn at the bar's end of the row: the controls are 4pt
/// thicker than that, toward the page, and the glass doesn't cover the reach.
struct InkOptionsRow: View {
    @Bindable var editor: NoteEditor
    var isVertical: Bool

    @Environment(\.optionsRow) private var style

    var body: some View {
        InkOptions(editor: editor, isVertical: isVertical)
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

/// Puts the options row beside the bar, on the page's side of it, centred
/// along it.
///
/// A layout of its own, used as the bar's overlay, so it is the bar's size and
/// places its row outside those bounds by the gap. This was an overlay
/// alignment with an alignment guide on the row, and the guide was ignored:
/// the row sat on the bar, 48pt from where it belonged, with every guide
/// placement tried (simulator, 9 October). Placing from the bounds says
/// where the row goes, and doesn't depend on a guide being read.
private struct BesideBar<Row: View>: View {
    var dock: HotbarDock
    var gap: CGFloat
    @ViewBuilder var row: Row

    var body: some View {
        BesideBarLayout(dock: dock, gap: gap) { row }
    }
}

private struct BesideBarLayout: Layout {
    var dock: HotbarDock
    var gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // The bar's own size, which is all an overlay is offered.
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let row = subviews.first else { return }
        let size = row.sizeThatFits(.unspecified)
        let origin: CGPoint
        switch dock {
        case .bottom: origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.minY - gap - size.height)
        case .left:   origin = CGPoint(x: bounds.maxX + gap, y: bounds.midY - size.height / 2)
        case .right:  origin = CGPoint(x: bounds.minX - gap - size.width, y: bounds.midY - size.height / 2)
        }
        row.place(at: origin, proposal: ProposedViewSize(size))
    }
}

private extension HotbarDock {
    /// The edge of the options row that faces the page.
    var pageEdge: Edge {
        switch self {
        case .bottom: .top
        case .left:   .trailing
        case .right:  .leading
        }
    }

    /// The edge of the row that faces the bar, which it slides out from.
    var barEdge: Edge {
        switch self {
        case .bottom: .bottom
        case .left:   .leading
        case .right:  .trailing
        }
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

#endif
