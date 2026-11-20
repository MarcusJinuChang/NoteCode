//
//  NoteCodeMark.swift
//  NoteCode
//
//  The app icon's mark and the empty state's picture (split out of SettingsView.swift).
//

import SwiftUI

/// The mark as an empty state's picture, in the place of an SF Symbol: the
/// default icon's mark at 64pt, hidden from VoiceOver since the title says it.
struct EmptyStateMark: View {
    var body: some View {
        NoteCodeMark()
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: NoteCodeMark.cornerRadius(side: 64), style: .continuous))
            .accessibilityHidden(true)
    }
}

/// An icon's mark, drawn on the design's 120 by 120 grid: two brackets and a
/// tilted pencil. The same geometry the app icons are made from
/// (`scripts/make-icons.swift`), in the icon's own colours: the Default's
/// white and orange on near-black unless told otherwise. It is the picture
/// of each icon in Settings, since an app icon set can't be loaded as an
/// image by name.
struct NoteCodeMark: View {
    var icon: AppIconChoice = .standard

    /// The corner of Apple's app icon mask, as a share of the icon's side, so
    /// a mark shown at any size is clipped the way the Home Screen clips it.
    static let cornerRatio: CGFloat = 0.2237

    /// The corner radius that clips a mark `side` points across.
    static func cornerRadius(side: CGFloat) -> CGFloat { side * cornerRatio }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 120
            context.scaleBy(x: scale, y: scale)

            context.fill(Path(CGRect(x: 0, y: 0, width: 120, height: 120)), with: .color(Color(hex: icon.background)))

            var brackets = Path()
            brackets.move(to: CGPoint(x: 38, y: 38))
            brackets.addLine(to: CGPoint(x: 18, y: 60))
            brackets.addLine(to: CGPoint(x: 38, y: 82))
            brackets.move(to: CGPoint(x: 82, y: 38))
            brackets.addLine(to: CGPoint(x: 102, y: 60))
            brackets.addLine(to: CGPoint(x: 82, y: 82))
            context.stroke(brackets, with: .color(Color(hex: icon.brackets)), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))

            var pencil = Path(roundedRect: CGRect(x: 55, y: 38, width: 10, height: 36), cornerRadius: 2)
            pencil.move(to: CGPoint(x: 55, y: 77))
            pencil.addLine(to: CGPoint(x: 65, y: 77))
            pencil.addLine(to: CGPoint(x: 60, y: 89))
            pencil.closeSubpath()

            var tilted = context
            tilted.translateBy(x: -1, y: 0)
            tilted.translateBy(x: 60, y: 60)
            tilted.rotate(by: .degrees(18))
            tilted.translateBy(x: -60, y: -60)
            tilted.fill(pencil, with: .color(Color(hex: icon.pencil)))
            tilted.stroke(pencil, with: .color(Color(hex: icon.pencil)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }
    }
}
