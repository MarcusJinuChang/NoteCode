//
//  NoteViewSettings.swift
//  NoteCode
//
//  The settings an open note reads, declared once from the key tables
//  (SettingKeys.swift), so a name and a default are not written here again.
//

import SwiftUI

/// What an open note reads from Settings. A `DynamicProperty`, so a change
/// in Settings reaches an open note at once, as separate `@AppStorage`s in
/// the view did (`TextRewritingPolicyTests`).
struct NoteViewSettings: DynamicProperty {

    /// The edge this device stored. `PageDetailView.dock` decides where the
    /// bar is from it: compact widths and a Duo's fold override it there.
    @AppStorage(SettingKeys.General.hotbarDock)
    var storedDock: HotbarDock

    /// How pages are shown. Per device, like the dock: it's how this reader
    /// likes to look at notes, and changes nothing in the note itself.
    @AppStorage(SettingKeys.Notes.viewMode)
    var viewMode: PageViewMode

    /// Whether a code block's backticks show only while it is edited, or
    /// always. Settings › Writing has the switch.
    @AppStorage(SettingKeys.Writing.showMarkdown)
    var showMarkdown: ShowMarkdown

    /// Settings › Writing › Markers: how dim each kind of visible marker is.
    @AppStorage(SettingKeys.Writing.headingMarkers) var headingMarkers: MarkerLevel
    @AppStorage(SettingKeys.Writing.bulletMarkers) var bulletMarkers: MarkerLevel
    @AppStorage(SettingKeys.Writing.checkboxMarkers) var checkboxMarkers: MarkerLevel
    @AppStorage(SettingKeys.Writing.fenceMarkers) var fenceMarkers: MarkerLevel

    /// Settings › Code: the indent width, the row of code keys, line numbers.
    @AppStorage(SettingKeys.Code.indentWidth)
    var indentWidth: Int

    @AppStorage(SettingKeys.Code.codeKeys)
    var codeKeys: Bool

    @AppStorage(SettingKeys.Code.lineNumbers)
    var lineNumbers: Bool

    /// Settings › Writing › Autocorrect.
    @AppStorage(SettingKeys.Writing.autocorrectInProse)
    var rewritesProse: Bool

    /// Whether the bar ticks as it lands on an edge (Settings › General).
    @AppStorage(SettingKeys.General.hapticOnSnap)
    var hapticOnSnap: Bool

    /// Settings › Drawing › Add Pages While Drawing.
    @AppStorage(SettingKeys.Drawing.addPagesWhileDrawing)
    var addsPagesWhileDrawing: Bool
}
