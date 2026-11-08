//
//  RunDock.swift
//  NoteCode
//
//  The Run panel docked at the page's right edge, and its width. Split from
//  RunPanel.swift (D4).
//

#if canImport(UIKit)

import SwiftUI
import UIKit

/// The panel as a pane at the page's right: a handle on its left edge to
/// drag its width, and a collapse to a thin tab. It only takes the width it
/// asks for out of the note's area; the page is never told its own size.
struct RunDock: View {
    @Bindable var session: RunSession
    var transaction: () -> String
    var onShow: (RunBlock) -> Void
    /// The window's width, for the half-window limit.
    var availableWidth: CGFloat

    @AppStorage(SettingKeys.Run.panelWidth) private var storedWidth
    @State private var dragStart: Double?

    var body: some View {
        if session.isCollapsed {
            Button {
                withAnimation(.snappy) { session.isCollapsed = false }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 24)
                    .frame(maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show Run panel")
        } else {
            let width = RunDockWidth.clamped(storedWidth, available: availableWidth)
            HStack(spacing: 0) {
                handle
                RunPanel(session: session, transaction: transaction, onShow: onShow)
                    .frame(width: width)
            }
        }
    }

    private var handle: some View {
        ZStack {
            Color(.separator).frame(width: 1)
            Capsule().fill(Color(.tertiaryLabel)).frame(width: 4, height: 36)
        }
        .frame(width: 18)
        .frame(maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { drag in
                    let start = dragStart ?? RunDockWidth.clamped(storedWidth, available: availableWidth)
                    dragStart = start
                    storedWidth = RunDockWidth.clamped(start - drag.translation.width, available: availableWidth)
                }
                .onEnded { _ in dragStart = nil }
        )
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation(.snappy) { session.isCollapsed = true }
            } label: {
                // Drawn in the handle's top 18×36 as before, but tapped
                // anywhere in 30×44: the handle's width and the block
                // strip's empty leading padding (12pt), 44pt down. A plain
                // button's target is otherwise the glyph alone (6×10), and a
                // touch beside it went to the handle's width drag. It can't
                // reach over the page: the page takes those touches.
                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    .frame(width: 18, height: 36)
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse Run panel")
        }
        // Above the panel, so the target's part over the strip is the button's.
        .zIndex(1)
    }
}

/// The dock's width, app-wide: 360pt to start, 280pt to half the window.
nonisolated enum RunDockWidth {
    static let minimum = 280.0

    static func clamped(_ width: Double, available: CGFloat) -> CGFloat {
        let upper = max(minimum, Double(available) / 2)
        return CGFloat(min(max(width, minimum), upper))
    }
}

#endif
