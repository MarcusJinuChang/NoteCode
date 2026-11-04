//
//  HotbarRowLayout.swift
//  NoteCode
//
//  The layouts that size the bar's scrolling tools and place the options row
//  beside the bar.
//

#if canImport(UIKit)

import SwiftUI

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
struct HotbarTrack: Layout {
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

/// Which ends of a scrolling track have controls scrolled out past them.
struct HiddenEdges: Equatable {
    var start = false
    var end = false

    /// A point's slack either way, so a track resting at an end shows no fade there.
    static func of(offset: CGFloat, visible: CGFloat, length: CGFloat) -> HiddenEdges {
        HiddenEdges(start: offset > 1, end: offset + visible < length - 1)
    }
}

/// Fades a track's end where controls run on past it. Without it a phone's
/// bar stopped mid-button at the screen's edge ("f(x"), which read as broken
/// rather than as more to scroll to (iPhone 17, 31 Oct).
struct EdgeFade: ViewModifier {
    var axis: Axis
    @State private var hidden = HiddenEdges()

    static let length: CGFloat = 24

    func body(content: Content) -> some View {
        let horizontal = axis == .horizontal
        let stack = horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        let (from, to): (UnitPoint, UnitPoint) = horizontal ? (.leading, .trailing) : (.top, .bottom)
        content
            .onScrollGeometryChange(for: HiddenEdges.self) { geometry in
                HiddenEdges.of(
                    offset: horizontal
                        ? geometry.contentOffset.x + geometry.contentInsets.leading
                        : geometry.contentOffset.y + geometry.contentInsets.top,
                    visible: horizontal ? geometry.containerSize.width : geometry.containerSize.height,
                    length: horizontal ? geometry.contentSize.width : geometry.contentSize.height
                )
            } action: { _, edges in
                hidden = edges
            }
            .mask {
                stack {
                    LinearGradient(colors: [hidden.start ? .clear : .black, .black], startPoint: from, endPoint: to)
                        .frame(width: horizontal ? Self.length : nil, height: horizontal ? nil : Self.length)
                    Rectangle()
                    LinearGradient(colors: [.black, hidden.end ? .clear : .black], startPoint: from, endPoint: to)
                        .frame(width: horizontal ? Self.length : nil, height: horizontal ? nil : Self.length)
                }
            }
    }
}

extension View {
    /// `EdgeFade`: a fade at whichever end of a scrolling track has more past it.
    func edgeFade(_ axis: Axis) -> some View {
        modifier(EdgeFade(axis: axis))
    }
}

/// An options row's controls, hugged when they fit beside the bar and
/// scrolled along it when they don't, as the bar's tools are. Inside the
/// row's surface, so the capsule's ends stay put while the controls scroll.
struct OptionsRowTrack<Content: View>: View {
    var isVertical: Bool
    @ViewBuilder var content: Content

    var body: some View {
        let axes: Axis.Set = isVertical ? .vertical : .horizontal
        HotbarTrack(axis: isVertical ? .vertical : .horizontal) {
            ScrollView(axes, showsIndicators: false) { content }
                .scrollBounceBehavior(.basedOnSize, axes: axes)
                .edgeFade(isVertical ? .vertical : .horizontal)
        }
    }
}

/// How long an options row may be along the bar.
///
/// The text row is never longer than the bar it hangs off (Marcus, 31 Oct: the
/// secondary bar "should not be larger than the main hotbar"), and scrolls
/// past that. It is the same scroll view as before (`OptionsRowTrack`), only
/// offered less; no `ViewThatFits` choosing between a scrolling row and a
/// plain one, which is what froze the bar (`HotbarTrack`). The pen's row keeps
/// the page's length, since it is longer than a side-docked bar and a phone's
/// 390pt is the limit that matters to it.
enum RowLimit {
    static func length(pageLimit: CGFloat?, barLength: CGFloat, capsToBar: Bool) -> CGFloat? {
        guard capsToBar, barLength > 0 else { return pageLimit }
        return min(pageLimit ?? barLength, barLength)
    }
}

struct BesideBarLayout: Layout {
    var dock: HotbarDock
    var gap: CGFloat
    /// The most the row may take along the bar; past it the row scrolls.
    var maxLength: CGFloat?
    /// Whether the row may be no longer than the bar (`RowLimit`).
    var capsToBar: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // The bar's own size, which is all an overlay is offered.
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let row = subviews.first else { return }
        let limit = RowLimit.length(
            pageLimit: maxLength,
            barLength: dock.isVertical ? bounds.height : bounds.width,
            capsToBar: capsToBar
        )
        let size = row.sizeThatFits(ProposedViewSize(
            width: dock.isVertical ? nil : limit,
            height: dock.isVertical ? limit : nil
        ))
        let origin: CGPoint
        switch dock {
        case .bottom: origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.minY - gap - size.height)
        case .left:   origin = CGPoint(x: bounds.maxX + gap, y: bounds.midY - size.height / 2)
        case .right:  origin = CGPoint(x: bounds.minX - gap - size.width, y: bounds.midY - size.height / 2)
        }
        row.place(at: origin, proposal: ProposedViewSize(size))
    }
}

#endif
