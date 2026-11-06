//
//  PageDetailView+Settings.swift
//  NoteCode
//
//  The settings an open note reads, held beside the view that reads them.
//

import SwiftUI

/// What an open note reads from Settings. A `DynamicProperty`, so a change
/// in Settings reaches an open note at once, as the separate declarations did.
struct NoteViewSettings: DynamicProperty {

    @AppStorage(HotbarDock.defaultsKey)
    var storedDock: HotbarDock = .default

    /// How pages are shown. Per device, like the dock: it's how this reader
    /// likes to look at notes, and changes nothing in the note itself.
    @AppStorage(PageViewMode.defaultsKey)
    var viewMode: PageViewMode = .default

    /// Whether a code block's backticks show only while it is edited, or
    /// always. Settings › Writing has the switch.
    @AppStorage(ShowMarkdown.defaultsKey)
    var showMarkdown: ShowMarkdown = .whileEditing

    /// Settings › Writing › Markers: how dim each kind of visible marker is.
    @AppStorage(MarkerDimming.headingsKey) var headingMarkers = MarkerLevel.dim
    @AppStorage(MarkerDimming.bulletsKey) var bulletMarkers = MarkerLevel.dim
    @AppStorage(MarkerDimming.checkboxesKey) var checkboxMarkers = MarkerLevel.dim
    @AppStorage(MarkerDimming.fencesKey) var fenceMarkers = MarkerLevel.dim

    /// Settings › Code: the indent width, the row of code keys, line numbers.
    @AppStorage(CodeIndent.widthKey)
    var indentWidth = CodeIndent.defaultWidth

    @AppStorage(CodeKeys.enabledKey)
    var codeKeys = CodeKeys.enabledByDefault

    @AppStorage(LineNumbers.defaultsKey)
    var lineNumbers = LineNumbers.enabledByDefault

    /// Settings › Writing › Autocorrect.
    @AppStorage(TextRewritingPolicy.proseDefaultsKey)
    var rewritesProse = TextRewritingPolicy.proseEnabledByDefault
    /// Whether the bar ticks as it lands on an edge (Settings › General).
    @AppStorage(SnapHaptic.defaultsKey)
    var hapticOnSnap = SnapHaptic.isOnByDefault

    /// Settings › Drawing › Add Pages While Drawing.
    @AppStorage(InkPageGrowth.defaultsKey)
    var addsPagesWhileDrawing = InkPageGrowth.defaultEnabled
}
