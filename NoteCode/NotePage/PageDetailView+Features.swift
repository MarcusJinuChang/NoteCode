//
//  PageDetailView+Features.swift
//  NoteCode
//
//  Where the edition's editor features show on the note's page: an item in
//  the top bar and a panel beside the page (`EditorFeature`). The App Store
//  edition's are Run's Notes | Run control and dock (RunFeature).
//

import SwiftUI

#if canImport(UIKit)
extension PageDetailView {
    /// What the features are told about the page's room.
    var featureLayout: EditorPageLayout {
        EditorPageLayout(isCompact: isCompact, windowWidth: windowWidth)
    }

    /// A feature's item, on the right with Share and •••: the first feature
    /// that offers one. Not `.principal`, which replaces the title: the
    /// note's name and its menu went, leaving a bare chevron.
    @ToolbarContentBuilder
    var featureTopBarItem: some ToolbarContent {
        if let item = editor.features.lazy.compactMap({ $0.topBarItem(in: featureLayout) }).first {
            ToolbarItem(placement: .primaryAction) {
                item
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    /// The note, with each feature's panel docked at its right. A panel
    /// narrows the page's area and nothing else: the page's zoom and place
    /// are its own.
    var sidePanelLayout: some View {
        HStack(spacing: 0) {
            content
            ForEach(editor.features.indices, id: \.self) { index in
                editor.features[index].sidePanel(in: featureLayout)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
    }
}
#endif
