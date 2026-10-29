//
//  NoteWindowControl.swift
//  NoteCode
//
//  The note window's top-left control (W3): the list and Home as one joined
//  pill, in the two icons `NoteIconGeometry` draws, and the way the note goes
//  home: shrinking toward the card it was opened from.
//

import SwiftUI

/// Where a note was opened from on Home, so closing it can shrink the note
/// back toward the same card. Pure, so it is tested without a view.
struct HomeLaunch: Equatable {
    /// The card's centre as a fraction of the window's detail area.
    var anchor: UnitPoint
    /// The card's size against the detail area's: how small the note ends.
    var scale: CGFloat

    /// A note opened from a list row, or with no card: it shrinks to the
    /// middle, about as far as a card does.
    static let centre = HomeLaunch(anchor: .center, scale: 0.3)

    /// `card` and `container` are in the same coordinate space.
    init(card: CGRect, container: CGSize) {
        guard container.width > 0, container.height > 0, card.width > 0 else {
            self = .centre
            return
        }
        func clamp(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }
        anchor = UnitPoint(x: clamp(card.midX / container.width), y: clamp(card.midY / container.height))
        scale = min(max(card.width / container.width, 0.1), 0.9)
    }

    private init(anchor: UnitPoint, scale: CGFloat) {
        self.anchor = anchor
        self.scale = scale
    }
}

extension AnyTransition {
    /// The note leaving for Home: it shrinks into its card and fades. With
    /// Reduce Motion, a cross-fade and nothing moves.
    static func noteToHome(_ launch: HomeLaunch?, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        let launch = launch ?? .centre
        return .asymmetric(
            insertion: .opacity,
            removal: .scale(scale: launch.scale, anchor: launch.anchor).combined(with: .opacity)
        )
    }
}

/// The sidebar button and the house, joined. An opaque fill rather than
/// glass, since W4 removes the glass from every bar.
struct NoteWindowControl: View {
    var onToggleList: () -> Void
    var onGoHome: (() -> Void)?

    @AppStorage(IconStyle.defaultsKey) private var iconStyle = IconStyle()

    var body: some View {
        HStack(spacing: 0) {
            segment(.sidebar, label: "Notes", identifier: "sidebarButton", action: onToggleList)
            if let onGoHome {
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: 20)
                segment(.home, label: "Home", identifier: "homeButton", action: onGoHome)
            }
        }
        .background(.quaternary, in: Capsule())
    }

    private func segment(_ icon: NoteIcon, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NoteIconView(icon: icon, weight: iconStyle.weight)
                .frame(width: 22, height: 22)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
