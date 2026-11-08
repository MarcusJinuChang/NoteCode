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

    /// Whether a sheet covers the page, which takes the text options row away
    /// (the page decides: only it knows which sheets it has).
    var textRowHidden = false

    /// Whether the bar can be dragged to another edge. Not in a compact width
    /// (an iPhone, a folded Duo), where it stays at the bottom: a side would
    /// take a third of the screen from the page.
    var isMovable = true

    /// The longest the options row may be along the bar, or `nil` for no
    /// limit. The page passes its own length less the margins, and a row
    /// longer than that scrolls: the pen's row is about 391pt, which a 390pt
    /// phone can't show whole.
    var maxRowLength: CGFloat?

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.coveredBySheet) private var coveredBySheet

    /// Insert's popover, which points at its button.
    @State private var inserter = InkInserter()

    private var axis: Axis.Set {
        dock.isVertical ? .vertical : .horizontal
    }

    private var stack: AnyLayout {
        dock.isVertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
    }

    var body: some View {
        stack {
            if isMovable {
                grip
            }

            // Outside the tools' scroll view, so they never scroll away with
            // the tools: undo and the mode toggle are what's reached for most,
            // and they stay where the hand expects them.
            //
            // In a scroll view of their own that never scrolls, for its
            // bounds. SwiftUI lets a button take a touch some way past its
            // frame, and docked to a side the undo arrows and the toggle took
            // one 10pt past theirs, in the gap beside the bar: a tap there
            // threw the note out of Draw mode (simulator, 3 Nov; device pass,
            // 7 Nov). A scroll view is a UIKit view, and UIKit gives it no
            // touch outside its bounds, which is why the tools and the
            // options row never reached. `.contentShape` and `.clipShape`
            // don't bound it.
            ScrollView(axis, showsIndicators: false) { pinned }
                .scrollDisabled(true)
                .fixedSize()
            divider

            // Hugs its tools when they fit, and scrolls when they don't: the
            // ink tools don't fit down the side of an 11-inch iPad in
            // landscape, and a side dock with the keyboard up is short.
            HotbarTrack(axis: dock.isVertical ? .vertical : .horizontal) {
                ScrollView(axis, showsIndicators: false) { tools }
                    .scrollBounceBehavior(.basedOnSize, axes: axis)
                    .edgeFade(dock.isVertical ? .vertical : .horizontal)
            }
        }
        // One toolbar to VoiceOver, with the buttons inside it, and a frame
        // for tests to find the bar by.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hotbar")
        .padding(Self.padding)
        .barMaterial(in: .rect(cornerRadius: Self.thickness / 2))
        .dimsWhenCovered(coveredBySheet || textRowHidden, in: .rect(cornerRadius: Self.thickness / 2))
        #if DEBUG
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            SelectionProbe.log("hotbar frame \(frame)")
        }
        #endif
        // An overlay, so the row takes no room: it floats over the page and
        // leaves the bar's size alone, which is what keeps the page where it
        // is whichever mode, tool or edge the bar is on. Inside the offset,
        // so it travels with the bar when the grip drags it.
        .overlay {
            BesideBar(dock: dock, gap: Self.optionsGap, maxLength: maxRowLength, capsToBar: showsTextRow) { optionsRow }
        }
        .animation(.snappy, value: showsOptions)
        .animation(.snappy, value: showsTextRow)
        .offset(dragOffset)
    }

    // MARK: Options row

    /// Whether the row is out: in ink mode, for a tool with anything to set.
    private var showsOptions: Bool {
        editor.mode == .ink && editor.inkTool.hasOptions
    }

    private var showsTextRow: Bool {
        Self.showsTextRow(
            isText: editor.mode == .text, isLocked: editor.isTextLocked, isCovered: textRowHidden,
            isCompact: !isMovable, wanted: editor.wantsTextRow
        )
    }

    /// Whether the text options row is out: in text mode, for a note whose
    /// text can be changed, with nothing over the page. On a phone only when
    /// asked for (the Format button): the two bars over the keyboard left
    /// about half of what was above it to the note (iPhone 17, 31 Oct).
    static func showsTextRow(isText: Bool, isLocked: Bool, isCovered: Bool, isCompact: Bool, wanted: Bool) -> Bool {
        isText && !isLocked && !isCovered && (!isCompact || wanted)
    }

    /// The row beside the bar, 8pt from it on the page's side and centred
    /// along it: the selected ink tool's options in ink mode, the text size
    /// and the paragraph's controls in text mode.
    ///
    /// `BesideBar` sizes it, not the overlay, which proposes the bar's size:
    /// the pen's row is longer than a side-docked bar. It slides out from the
    /// bar, or under Reduce Motion fades.
    @ViewBuilder
    private var optionsRow: some View {
        let style = OptionsRowStyle(isVertical: dock.isVertical, reach: dock.pageEdge)
        let transition: AnyTransition = reduceMotion ? .opacity : .move(edge: dock.barEdge).combined(with: .opacity)
        if showsOptions {
            InkOptionsRow(editor: editor, isVertical: dock.isVertical)
                .environment(\.optionsRow, style)
                .transition(transition)
        } else if showsTextRow {
            TextOptionsRow(editor: editor, isVertical: dock.isVertical)
                .environment(\.optionsRow, style)
                .transition(transition)
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

            // A phone's text options row waits to be asked for. In both
            // modes, greyed in ink, so switching doesn't change the bar's length.
            if !isMovable {
                button("Format", "bold.italic.underline", isSelected: editor.wantsTextRow && editor.mode == .text) {
                    editor.wantsTextRow.toggle()
                }
                .disabled(editor.mode != .text || editor.isTextLocked)
            }
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

    /// One control for the two modes, in a single slot: it shows the icon of
    /// the mode the note is in (the text cursor in text mode, the pencil in
    /// ink mode) and a tap switches. Not `pencil.tip`, which is the pen tool
    /// that sits beside it in ink mode.
    private var modeToggle: some View {
        let isInk = editor.mode == .ink
        return Button {
            editor.toggleMode()
        } label: {
            ZStack {
                HotbarIcon(systemImage: "character.cursor.ibeam").opacity(isInk ? 0 : 1)
                HotbarIcon(systemImage: "pencil.and.scribble").opacity(isInk ? 1 : 0)
            }
            // A grey disc in both modes, the selection highlight's shape:
            // the one control on the bar that looks like something to try,
            // not a formatting button among the others.
            .background { Circle().fill(Color(uiColor: .secondarySystemFill)).padding(4) }
            // A quick cross-fade between the two faces; none under Reduce Motion.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isInk)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mode")
        .accessibilityValue(isInk ? "Draw mode" : "Text mode")
        .accessibilityHint(isInk ? "Switches to Text" : "Switches to Draw")
        .accessibilityIdentifier("modeToggle")
    }

    @ViewBuilder
    private var textTools: some View {
        // Checkmarks show the state at the caret: with the markers hidden,
        // this is the only place a heading's level shows. Headings only (Aa):
        // the other styles have a slot of their own on the bar or a place in
        // the text options row.
        Menu {
            // All six the parser reads. The text options row has chips for
            // the first three only: a row is for what is used most.
            ForEach(MarkdownFormatting.headingLevels, id: \.self) { level in
                Toggle("Heading \(level)", isOn: Binding(
                    get: { editor.caretFormatting.headingLevel == level },
                    set: { _ in editor.setHeading(level: level) }
                ))
            }
            Toggle("Body", isOn: Binding(
                get: { editor.caretFormatting.headingLevel == 0 },
                set: { _ in editor.setHeading(level: 0) }
            ))
        } label: {
            HotbarIcon(systemImage: "textformat")
        }
        .modifier(HotbarMenuStyle())
        .accessibilityLabel("Style")

        // Bold, Italic, Underline and Strikethrough are in the text options
        // row (and ⌘B, ⌘I, ⌘U); the slots are for what Aa used to hold.
        button("Inline Code", "chevron.left.forwardslash.chevron.right", isSelected: editor.formattingShown.code) {
            editor.toggle(.code)
        }
        button("Quote", "text.quote", isSelected: editor.caretFormatting.quoteDepth > 0) {
            editor.toggleQuote()
        }
        button("Horizontal Rule", "minus") { editor.insertRule() }
        button("Inline Formula", "function") { editor.insertFormula(display: false) }
        button("Display Formula", "x.squareroot") { editor.insertFormula(display: true) }

        // One menu for every kind of list, so the bar doesn't grow a button
        // for each.
        Menu {
            ForEach(MarkdownFormatting.ListStyle.allCases, id: \.self) { style in
                Toggle(isOn: Binding(
                    get: { editor.caretFormatting.list == style },
                    set: { _ in editor.toggleList(style) }
                )) {
                    Label(style.title, systemImage: style.systemImage)
                }
            }
        } label: {
            HotbarIcon(systemImage: "list.bullet")
        }
        .modifier(HotbarMenuStyle())
        .accessibilityLabel("List")

        Menu {
            ForEach(CodeBlockKind.languages, id: \.self, content: codeBlockButton)
            Divider()
            ForEach(CodeBlockKind.others, id: \.self, content: codeBlockButton)
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

        // A popover rather than a tool: shapes, a text box and a photo are
        // put on the page, and the lasso is the tool that moves them.
        button("Insert", "plus.circle", isSelected: inserter.isPresented) {
            inserter.present(for: editor)
        }
        .background(InkInserter.Anchor(inserter: inserter))
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

    /// One row of Code Block ▾: the name, and under it what it can't do
    /// (SQL, "Copy only").
    @ViewBuilder
    private func codeBlockButton(_ kind: CodeBlockKind) -> some View {
        Button {
            editor.insertCodeBlock(kind: kind)
        } label: {
            Text(kind.displayName)
            if let subtitle = kind.subtitle { Text(subtitle) }
        }
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

/// The options row's surface, around what the selected tool can be set to.
///
/// 40pt thick, drawn at the bar's end of the row: the controls are 4pt
/// thicker than that, toward the page, and the surface doesn't cover the reach.
struct InkOptionsRow: View {
    @Bindable var editor: NoteEditor
    var isVertical: Bool

    @Environment(\.optionsRow) private var style
    @Environment(\.coveredBySheet) private var coveredBySheet

    var body: some View {
        OptionsRowTrack(isVertical: isVertical) {
            InkOptions(editor: editor, isVertical: isVertical)
                .padding(isVertical ? .vertical : .horizontal, 2)
        }
            .background(alignment: style?.faceAlignment ?? .center) {
                Color.clear
                    .frame(
                        width: isVertical ? OptionsRowStyle.thickness : nil,
                        height: isVertical ? nil : OptionsRowStyle.thickness
                    )
                    .barMaterial(in: .capsule)
            }
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
    var maxLength: CGFloat?
    var capsToBar: Bool
    @ViewBuilder var row: Row

    var body: some View {
        BesideBarLayout(dock: dock, gap: gap, maxLength: maxLength, capsToBar: capsToBar) { row }
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
struct HotbarMenuStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .menuStyle(.button)
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .menuIndicator(.hidden)
    }
}

#endif
