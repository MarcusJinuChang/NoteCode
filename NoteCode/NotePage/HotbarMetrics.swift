//
//  HotbarMetrics.swift
//  NoteCode
//
//  The bar's measurements, which the page, the ink toolbar and the tests read
//  as `Hotbar.footprint` and the like.
//

#if canImport(UIKit)

import SwiftUI

extension Hotbar {
    /// Apple's minimum comfortable touch target.
    static let buttonSide: CGFloat = 44
    static let padding: CGFloat = 4

    /// Between the bar and the options row beside it.
    static let optionsGap: CGFloat = 8

    /// How far the bar reaches in from the edge it's docked to.
    static var thickness: CGFloat { buttonSide + padding * 2 }

    /// Gap between the bar and the edges around it.
    static let margin: CGFloat = 12

    /// The gap kept between the page and the screen's edge on every side the
    /// bar doesn't take (feedback item 1, 23 Oct). 10pt: enough to read as a
    /// margin of surround rather than a rendering glitch, a little under the
    /// bar's own 12pt margin so a bar floating over the page's bottom still
    /// sits inside it, and small enough that the fit scale moves about 2.4% on
    /// an 11-inch iPad. See `CanvasGeometry.areaInsets`.
    static let pageBuffer: CGFloat = 10

    /// How far the bar and its margin take in from the edge it's docked to.
    static var barFootprint: CGFloat { margin + thickness }

    /// The bar, its margin and the options row beside it, with the row's
    /// touch reach. The page keeps this much clear on a side the bar is docked
    /// to whether the row is out or not, so a change of tool or mode never
    /// moves the page.
    static var footprint: CGFloat {
        barFootprint + optionsGap + OptionsRowStyle.thickness + OptionsRowStyle.reachAmount
    }

    /// Room kept below the caret's line, above the bars, so the next lines
    /// show too (31 Oct review: the bars covered the lines just below the
    /// cursor, as the clearance stopped at the caret's own line). Three lines
    /// of body text at its 22pt leading, in screen points.
    static let linesBelowCaret: CGFloat = 66

    /// How much of the page above the keyboard the bars cover, which the text
    /// view is inset by so the caret and the lines after it stay clear. Only
    /// for a bar docked at the bottom: at a side, nothing rides up over the
    /// page.
    static func keyboardClearance(dock: HotbarDock, showsTextRow: Bool) -> CGFloat {
        guard dock == .bottom else { return 0 }
        var clearance = barFootprint + linesBelowCaret
        if showsTextRow {
            clearance += optionsGap + OptionsRowStyle.thickness + OptionsRowStyle.reachAmount
        }
        return clearance
    }

    /// The coordinate space drags are measured in. Named on the page, which
    /// stays still, rather than on the bar, which moves under the finger.
    static let coordinateSpace = "notePage"
}

#endif
