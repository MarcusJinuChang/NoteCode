//
//  PaperMenu.swift
//  NoteCode
//
//  Choosing paper: the open note's ••• › Paper, and Settings › Notes ›
//  Paper for new notes. Both are the same three pickers over one value.
//

import SwiftUI

extension PaperSetup {

    /// Makes this the device's default for new notes: the three keys
    /// together, so none is set and another forgotten.
    func apply(to defaults: UserDefaults) {
        defaults.set(style.rawValue, forKey: Self.defaultStyleKey)
        defaults.set(spacing.rawValue, forKey: Self.defaultSpacingKey)
        defaults.set(strength.rawValue, forKey: Self.defaultStrengthKey)
    }
}

/// The pickers: the pattern, then, unless it is blank, how far apart and how
/// strong. Inline, so they read as sections inside a menu and as rows in a form.
struct PaperPickers: View {
    @Binding var setup: PaperSetup

    var body: some View {
        Section("Paper") {
            Picker("Paper", selection: $setup.style) {
                ForEach(PaperStyle.allCases, id: \.self) { style in
                    Label(style.title, systemImage: style.systemImage).tag(style)
                }
            }
            .pickerStyle(.inline)
        }

        if !setup.isBlank {
            Section("Spacing") {
                Picker("Spacing", selection: $setup.spacing) {
                    ForEach(PaperSpacing.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
            Section("Strength") {
                Picker("Strength", selection: $setup.strength) {
                    ForEach(PaperStrength.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
        }
    }
}

/// ••• › Paper for the open note. Not an edit, and it works in a locked note:
/// paper is not text.
struct NotePaperMenu: View {
    var page: Page

    var body: some View {
        Menu {
            PaperPickers(setup: Binding(
                get: { page.paper },
                set: { $0.apply(to: page) }
            ))
        } label: {
            Label("Paper", systemImage: page.paper.style.systemImage)
        }
        .accessibilityIdentifier("noteMenuPaper")
    }
}

/// Settings › Notes › Paper: what new notes are made with.
struct DefaultPaperSection: View {
    @AppStorage(PaperSetup.defaultStyleKey) private var style = PaperStyle.blank
    @AppStorage(PaperSetup.defaultSpacingKey) private var spacing = PaperSpacing.default
    @AppStorage(PaperSetup.defaultStrengthKey) private var strength = PaperStrength.default

    var body: some View {
        let setup = Binding<PaperSetup>(
            get: { PaperSetup(style: style, spacing: spacing, strength: strength) },
            set: { $0.apply(to: .standard) }
        )
        Section {
            Picker("Paper", selection: setup.style) {
                ForEach(PaperStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if style != .blank {
                Picker("Spacing", selection: setup.spacing) {
                    ForEach(PaperSpacing.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Strength", selection: setup.strength) {
                    ForEach(PaperStrength.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        } header: {
            Text("Paper")
        } footer: {
            Text("The paper new notes are made with: dots, a grid or lines behind the text and ink. A note keeps its paper once it's made; change it for one note in ••• › Paper. It is printed and shown in thumbnails.")
        }
    }
}
