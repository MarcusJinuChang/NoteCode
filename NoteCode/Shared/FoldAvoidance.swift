//
//  FoldAvoidance.swift
//  NoteCode
//
//  Keeping the hotbar off a Duo's fold (roadmap step 11).
//

import CoreGraphics
import SwiftUI

/// Where the hotbar goes when a fold runs under the edge it's docked to.
///
/// A Duo reports its fold as a division region (`UIView.reservedRegions(kind:
/// .division)`, iOS 27.1): unfolded and held sideways, a 40pt band down the
/// middle of a 951 by 669pt window, margins for controls included (simulator,
/// 17 Oct). Flat open, the region is **inactive**, and content and controls
/// may cross it; only an active region (partly folded) moves the bar. The
/// stored edge is never changed, so the bar comes back when the fold goes.
nonisolated enum FoldAvoidance {

    /// The edge the bar is shown at: `stored`, unless an active fold crosses
    /// the band the bar takes along that edge.
    ///
    /// - A fold down the screen (taller than wide) crossing the bottom band
    ///   sends a bottom bar to the left: the system runs its own buttons down
    ///   the right side on a Duo, and a bar there would crowd them.
    /// - A fold across the screen crossing a side band sends a side bar to
    ///   the bottom.
    ///
    /// - Parameters:
    ///   - folds: active fold regions, in the page area's coordinates.
    ///   - area: the page area's size.
    ///   - band: how far the bar and its options row reach in from an edge.
    static func dock(_ stored: HotbarDock, avoiding folds: [CGRect], in area: CGSize, band: CGFloat) -> HotbarDock {
        guard area.width > 0, area.height > 0 else { return stored }
        switch stored {
        case .bottom:
            let strip = CGRect(x: 0, y: area.height - band, width: area.width, height: band)
            return folds.contains { $0.height >= $0.width && $0.intersects(strip) } ? .left : .bottom
        case .left, .right:
            let strip = stored == .left
                ? CGRect(x: 0, y: 0, width: band, height: area.height)
                : CGRect(x: area.width - band, y: 0, width: band, height: area.height)
            return folds.contains { $0.width > $0.height && $0.intersects(strip) } ? .bottom : stored
        }
    }
}

#if canImport(UIKit)
import UIKit

/// Reports the active folds over the view it sits behind, in that view's
/// coordinates, whenever they change: on layout (the window resizing as the
/// Duo opens or closes) and on the hinge moving (`UIHingeInteraction`).
/// Nothing before iOS 27.1, which has no folds to report.
struct FoldReader: UIViewRepresentable {
    var onChange: ([CGRect]) -> Void

    func makeUIView(context: Context) -> FoldReaderView {
        let view = FoldReaderView()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: FoldReaderView, context: Context) {
        view.onChange = onChange
    }
}

final class FoldReaderView: UIView {
    var onChange: (([CGRect]) -> Void)?
    private var reported: [CGRect]?

    override init(frame: CGRect) {
        super.init(frame: frame)
        if #available(iOS 27.1, *) {
            addInteraction(UIHingeInteraction { [weak self] _, _ in
                self?.report()
            })
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        report()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        report()
    }

    /// The active division regions now, told only when they've changed. Told
    /// on the next turn of the main queue: a layout pass can be inside a
    /// SwiftUI update, and the callback sets state.
    private func report() {
        var folds: [CGRect] = []
        if #available(iOS 27.1, *), window != nil {
            folds = reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
        }
        guard folds != reported else { return }
        reported = folds
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(folds)
        }
    }
}
#endif
