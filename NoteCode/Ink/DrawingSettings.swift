//
//  DrawingSettings.swift
//  NoteCode
//
//  Settings › Drawing: where ink starts. iPad only; the Mac's editor has no
//  ink.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

struct DrawingSettings: View {
    @AppStorage(NoteEditor.fingerDrawsKey) private var fingerDraws = true
    @AppStorage(NoteEditor.returnToPreviousToolKey) private var returnsToPreviousTool = false
    @AppStorage(EraserSettings.defaultsKey) private var eraser = EraserSettings()
    @AppStorage(InkPageGrowth.defaultsKey) private var addsPages = InkPageGrowth.defaultEnabled
    @AppStorage(InkPalette.defaultsKey) private var pen = InkPalette.standard
    @AppStorage(InkPalette.highlighterDefaultsKey) private var highlighter = InkPalette.standardHighlighter
    @AppStorage(InkPaletteSet.defaultsKey) private var chosenSet = ""
    @State private var confirmsReset = false
    /// The set the reader picked, until they have said yes to losing their
    /// own colours.
    @State private var pendingSet: InkPaletteSet?

    /// The set the palettes are exactly, or `nil` once they are the reader's.
    private var matchingSet: InkPaletteSet? {
        InkPaletteSet.matching(pen: pen, highlighter: highlighter)
    }

    /// What Reset Colours resets to: the device's set.
    private var resetSet: InkPaletteSet {
        InkPaletteSet(rawValue: chosenSet) ?? InkPaletteSet.stored()
    }

    var body: some View {
        Form {
            Section {
                Toggle("Finger Draws", isOn: $fingerDraws)
            } footer: {
                Text("Where a note starts. The hotbar's hand button switches it, and the device keeps the last choice.")
            }

            Section {
                Toggle("Return to Previous Tool", isOn: $returnsToPreviousTool)
            } footer: {
                Text("After a selection ends, by Delete or by tapping empty space, go back to the tool you had before Select. Choosing another tool never does this.")
            }

            Section {
                Toggle("Add Pages While Drawing", isOn: $addsPages)
            } footer: {
                Text("A stroke that ends near the bottom of the last page adds a page in print layout and compressed view. Continuous view always keeps a blank page below your ink.")
            }

            Section {
                Menu {
                    ForEach(InkPaletteSet.allCases, id: \.self) { set in
                        Button {
                            pendingSet = set
                        } label: {
                            if matchingSet == set { Label(set.title, systemImage: "checkmark") } else { Text(set.title) }
                        }
                    }
                } label: {
                    LabeledContent("Colour Set", value: matchingSet?.title ?? "Custom")
                }
            } footer: {
                Text("Refined lifts the highlighters so they read on a dark page. Original is how they were. The pens are the same in both.")
            }

            Section {
                NavigationLink("Pens") { PaletteSettings(kind: .pen) }
                NavigationLink("Highlighters") { PaletteSettings(kind: .highlighter) }
                NavigationLink {
                    EraserSettingsPage()
                } label: {
                    LabeledContent("Eraser", value: eraser.summary)
                }
                Button("Reset Colours to Defaults", role: .destructive) {
                    confirmsReset = true
                }
            } footer: {
                // Plain text, not a link: no public URL opens Settings ›
                // Apple Pencil, and a link that pretended to would go nowhere.
                Text("Double tap and squeeze follow the Settings app › Apple Pencil.")
            }
        }
        .navigationTitle("Drawing")
        .confirmationDialog(
            "Reset the pen and highlighter palettes to the \(resetSet.title) colours?",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button("Reset Colours", role: .destructive) {
                InkPalette.resetStoredPalettes(to: resetSet)
            }
        } message: {
            Text("Colours you added are removed. Ink already on a page keeps its colour.")
        }
        .confirmationDialog(
            "Switch to the \(pendingSet?.title ?? "") colours?",
            isPresented: Binding(get: { pendingSet != nil }, set: { if !$0 { pendingSet = nil } }),
            titleVisibility: .visible,
            presenting: pendingSet
        ) { set in
            Button("Use \(set.title) Colours", role: .destructive) { set.apply() }
        } message: { _ in
            Text("Colours you added are removed. Ink already on a page keeps its colour.")
        }
    }
}

/// A tool's palette: the swatches the hotbar offers, in order. Swipe to
/// remove one (the last stays), Edit to reorder, and add from Apple's picker.
private struct PaletteSettings: View {
    var kind: InkToolKind

    @AppStorage private var palette: InkPalette
    @State private var picker = InkColorPicker()
    @Environment(\.colorScheme) private var colorScheme

    init(kind: InkToolKind) {
        self.kind = kind
        _palette = AppStorage(wrappedValue: .standard(for: kind), InkPalette.defaultsKey(for: kind))
    }

    private var style: UIUserInterfaceStyle {
        colorScheme == .dark ? .dark : .light
    }

    var body: some View {
        List {
            Section {
                ForEach(palette.colors, id: \.self) { color in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(uiColor: color.displayColor(for: style)))
                            .overlay(Circle().strokeBorder(.separator))
                            .frame(width: 28, height: 28)
                        Text(color.name)
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete { offsets in
                    let doomed = offsets.map { palette.colors[$0] }
                    for color in doomed { palette.remove(color) }
                }
                .onMove { source, destination in
                    var colors = palette.colors
                    colors.move(fromOffsets: source, toOffset: destination)
                    palette = InkPalette(colors)
                }
            }

            Section {
                Button("Restore \(kind == .highlighter ? "Highlighter" : "Pen") Colours", role: .destructive) {
                    InkPaletteSet.stored().resetPalette(for: kind)
                }
            } footer: {
                Text("Puts this palette back to the \(InkPaletteSet.stored().title) colours.")
            }

            Section {
                Button("Add Colour") {
                    let start = palette.colors.last ?? .black
                    picker.present(starting: start.displayColor(for: style)) { chosen in
                        palette.add(InkColor(chosen: chosen, on: style))
                    }
                }
                .background(InkColorPicker.Anchor(picker: picker))
            }
        }
        .navigationTitle(kind == .highlighter ? "Highlighters" : "Pens")
        .toolbar { EditButton() }
    }
}

private struct EraserSettingsPage: View {
    @AppStorage(EraserSettings.defaultsKey) private var eraser = EraserSettings()

    var body: some View {
        Form {
            Section {
                Picker("Erases", selection: $eraser.mode) {
                    Text("Pixels").tag(EraserSettings.Mode.partial)
                    Text("Whole Strokes").tag(EraserSettings.Mode.wholeStroke)
                }
            } footer: {
                Text("Pixels erases only what the eraser passes over. Whole Strokes takes every stroke it touches.")
            }

            // The object eraser takes whole strokes and has no width.
            Section("Size") {
                Picker("Size", selection: $eraser.size) {
                    ForEach(EraserSettings.Size.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if eraser.size == .custom {
                    Slider(value: $eraser.customWidth, in: EraserSettings.widthRange) {
                        Text("Custom Size")
                    }
                }
            }
            .disabled(eraser.mode == .wholeStroke)
        }
        .navigationTitle("Eraser")
    }
}

#endif
