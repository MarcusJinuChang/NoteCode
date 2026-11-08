//
//  SettingKeys.swift
//  NoteCode
//
//  Every setting's stored name and what it reads as where nothing is
//  stored, one table per Settings section. An `@AppStorage` takes an entry
//  in place of a name and a default, so a declaration can't repeat a
//  default, or get it wrong. Code that reads `UserDefaults` itself names
//  the entry too (`SettingKeys.Code.indentWidth.name`): an owning type keeps
//  no second name for a key (debt D6).
//
//  The Pro tables (the assistant, Run, ads) are in Pro/ProSettingKeys.swift,
//  so the open-source build, which has no Pro/, has none of their keys.
//

import SwiftUI

/// A stored setting: the name it is kept under in `UserDefaults`, and what it
/// reads as on a device that has never set it.
nonisolated struct SettingKey<Value: Sendable>: Sendable {
    let name: String
    let defaultValue: Value
}

/// The settings, by the Settings section that shows them. The names and
/// defaults are what devices have already saved under and started on
/// (`SettingsTests`, `SettingKeysTests`): never change one.
nonisolated enum SettingKeys {

    /// Settings › General.
    enum General {
        static let appearance = SettingKey(name: "appearance", defaultValue: AppAppearance.system)
        /// The accent as `#RRGGBB`; empty is the design's own orange
        /// (`AccentPalette`).
        static let accent = SettingKey(name: "accentColor", defaultValue: "")
        /// Per device: where the bar belongs depends on how this iPad is held
        /// and which hand has the Pencil, not on which note is open.
        static let hotbarDock = SettingKey(name: "hotbarDock", defaultValue: HotbarDock.bottom)
        /// A tick as the hotbar lands on an edge.
        static let hapticOnSnap = SettingKey(name: "hapticOnSnap", defaultValue: true)
        static let iconStyle = SettingKey(name: "iconStyle", defaultValue: IconStyle())
    }

    /// Settings › Notes.
    enum Notes {
        static let newNoteOrientation = SettingKey(name: "newNoteOrientation", defaultValue: PageOrientation.default)
        /// Open Note After Creating: whether the list's "+" (its tap, its menu
        /// and the folder menu) opens the note it makes. On until switched off
        /// (31 Oct): a "+" that made a note and showed nothing read as broken.
        /// Off, adding several notes in a row leaves the reader where they
        /// were, and the note shows up in the list with a toast.
        static let opensAfterCreating = SettingKey(name: "openNoteAfterCreating", defaultValue: true)
        static let viewMode = SettingKey(name: "pageViewMode", defaultValue: PageViewMode.seamless)
        static let sort = SettingKey(name: "noteSort", defaultValue: NoteSort(key: .modified, ascending: false))
    }

    /// Settings › Writing.
    enum Writing {
        static let showMarkdown = SettingKey(name: ShowMarkdown.defaultsKey, defaultValue: ShowMarkdown.whileEditing)
        /// Autocorrect: whether prose is autocorrected, capitalised and given
        /// smart punctuation. Per device.
        static let autocorrectInProse = SettingKey(name: "autocorrectInProse", defaultValue: true)
        static let headingMarkers = SettingKey(name: "markerDimming.headings", defaultValue: MarkerLevel.dim)
        static let bulletMarkers = SettingKey(name: "markerDimming.bullets", defaultValue: MarkerLevel.dim)
        static let checkboxMarkers = SettingKey(name: "markerDimming.checkboxes", defaultValue: MarkerLevel.dim)
        static let fenceMarkers = SettingKey(name: "markerDimming.fences", defaultValue: MarkerLevel.dim)
    }

    /// Settings › Code.
    enum Code {
        static let indentWidth = SettingKey(name: "indentWidth", defaultValue: 4)
        static let codeKeys = SettingKey(name: "codeKeys", defaultValue: true)
        static let lineNumbers = SettingKey(name: "lineNumbers", defaultValue: false)
    }

    /// Settings › Drawing, and what the hotbar remembers per tool.
    enum Drawing {
        /// Whether a finger draws (`EditorModeState.fingerDraws`), so it carries
        /// over from note to note and across launches (`InkToolStore`).
        /// Stored the way the button says it, so a device that has never set
        /// it reads `true`.
        static let fingerDraws = SettingKey(name: "fingerDraws", defaultValue: true)
        /// After a Selection: back to the tool before the Select tool once the
        /// selection ends by the reader's choice.
        static let returnToPreviousTool = SettingKey(name: "returnToPreviousTool", defaultValue: false)
        static let eraser = SettingKey(name: "eraser", defaultValue: EraserSettings())
        static let addPagesWhileDrawing = SettingKey(name: "addPagesWhileDrawing", defaultValue: true)
        static let selectionKind = SettingKey(name: "selectionKind", defaultValue: SelectionKind.lasso)
        /// The set the palettes start from; empty is the device's own
        /// (`InkPaletteSet`).
        static let paletteSet = SettingKey(name: "inkPaletteSet", defaultValue: "")

        /// The pen's palette. It kept this name when the highlighter got its
        /// own, so a palette a device saved before then is still its pen's.
        static let penPalette = SettingKey(name: "inkPalette", defaultValue: InkPalette(InkColor.penShades.map(\.color)))
        static let highlighterPalette = SettingKey(name: "highlighterPalette", defaultValue: InkPalette(InkColor.highlighterShades.map(\.color)))

        /// The pen in black, and the highlighter in yellow, since graphite,
        /// first in its palette, is the least like one.
        static let penSettings = SettingKey(name: "penSettings", defaultValue: InkingSettings(color: .black))
        static let highlighterSettings = SettingKey(name: "highlighterSettings", defaultValue: InkingSettings(color: InkColor.highlighterYellow))

        /// A tool's palette. Only the pen and highlighter have one; anything
        /// else answers with the pen's.
        static func palette(for kind: InkToolKind) -> SettingKey<InkPalette> {
            kind == .highlighter ? highlighterPalette : penPalette
        }

        /// A tool's colour and width: the highlighter's, else the pen's.
        static func inking(for kind: InkToolKind) -> SettingKey<InkingSettings> {
            kind == .highlighter ? highlighterSettings : penSettings
        }
    }
}

// MARK: - @AppStorage from a table entry

/// One init per kind of value a setting holds, each the `@AppStorage` init
/// for that kind with the entry's name and default.
nonisolated extension AppStorage {

    init(_ key: SettingKey<Value>, store: UserDefaults? = nil) where Value == Bool {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }

    init(_ key: SettingKey<Value>, store: UserDefaults? = nil) where Value == Int {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }

    init(_ key: SettingKey<Value>, store: UserDefaults? = nil) where Value == Double {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }

    init(_ key: SettingKey<Value>, store: UserDefaults? = nil) where Value == String {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }

    init(_ key: SettingKey<Value>, store: UserDefaults? = nil) where Value: RawRepresentable & Sendable, Value.RawValue == String {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }

    init(_ key: SettingKey<Value>, store: UserDefaults? = nil) where Value: RawRepresentable & Sendable, Value.RawValue == Int {
        self.init(wrappedValue: key.defaultValue, key.name, store: store)
    }
}
