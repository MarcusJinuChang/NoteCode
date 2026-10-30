import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The one surface every bar is drawn on: the hotbar, its options rows, the
/// code keys row and the top bar. Opaque, with a hairline edge, so a bar
/// reads the same over a page, ink or the surround and no glass is involved
/// (docs/archive/release-1.0/W-window.md › W4).
enum BarMaterial {
    #if canImport(UIKit)
    /// A step off the page in both appearances: white on a light page's
    /// grey surround, the elevated grey on a dark one.
    static let uiColor = UIColor.secondarySystemBackground
    static let uiEdge = UIColor.separator
    #endif

    static let fill = Color(uiColor: BarMaterial.uiColor)
    static let edge = Color(uiColor: BarMaterial.uiEdge)
}

extension View {
    /// Draws the view on the bar surface, clipped to `shape`.
    func barMaterial<S: InsettableShape>(in shape: S) -> some View {
        background(BarMaterial.fill, in: shape)
            .overlay { shape.strokeBorder(BarMaterial.edge, lineWidth: 0.5) }
    }
}
