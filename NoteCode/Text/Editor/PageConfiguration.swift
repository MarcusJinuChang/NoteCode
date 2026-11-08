//
//  PageConfiguration.swift
//  NoteCode
//
//  The half of `DocumentTextView`'s inputs that belong to the `PageView` it
//  makes, not to the text: layout, clearances, area, ink, reveal, resume,
//  page count, page growth and the callbacks. One value, one `apply`.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

struct PageConfiguration {

    /// The note's page orientation and the device's view mode.
    var pageLayout = PageLayout()

    /// Room to leave above the keyboard for a hotbar riding up with it. See
    /// `PageView.keyboardClearance`.
    var keyboardClearance: CGFloat = 0

    /// Room the bottom of the text keeps from the area's edge for a hotbar
    /// floating over it. See `PageView.restingClearance`.
    var restingClearance: CGFloat = 0

    /// The edges SwiftUI leaves around the page's area, for a hotbar docked
    /// at a side, and the animation the page moves with when they change, so
    /// it follows the hotbar. See `PageView.areaWillChange`.
    var areaInsets = UIEdgeInsets.zero
    var areaAnimation: Animation? = nil

    /// Loads the note's ink as the page is made, and saves it as it changes.
    /// Optional so the editor still stands alone.
    var inkSaver: DrawingSaveScheduler? = nil

    /// The search the note was opened from. Its matches are shown once, as
    /// the page is made: a new search typed while the note is open is the
    /// list's business, not the page's.
    var revealing = NoteSearch("")

    /// The page to open the note at (counted from 0): where it was last read
    /// on this device. Ignored when the note was opened from a search, which
    /// shows its match instead.
    var resumingAtPage: Int? = nil

    /// Told which page the reader is on as it changes, so the device can
    /// remember it.
    var onReadingPlaceChanged: ((NoteMemory.Place) -> Void)? = nil

    /// The fewest pages the note has (`Page.minimumPageCount`), and where a
    /// raise made by the page (Add Page, seamless's buffer) is kept.
    var minimumPageCount = 1
    var onMinimumPageCountChanged: ((Int) -> Void)? = nil

    /// Settings › Drawing › Add Pages While Drawing.
    var addsPagesWhileDrawing = SettingKeys.Drawing.addPagesWhileDrawing.defaultValue

    /// Told whenever the page scrolls, with the place it is scrolled to, for
    /// the page badge.
    var onScrolled: ((NoteMemory.Place) -> Void)? = nil

    /// Hands the configuration to a page just made, in the order
    /// `makeUIView` has always set it: layout, page count and growth,
    /// clearances and area, then the ink, then the search or the place to
    /// resume, then the callbacks.
    ///
    /// - Parameter text: the note's text, which `revealing` searches.
    @MainActor
    func apply(toNew page: PageView, text: String) {
        page.pageLayout = pageLayout
        page.minimumPageCount = minimumPageCount
        page.addsPagesWhileDrawing = addsPagesWhileDrawing
        page.onMinimumPageCountChanged = onMinimumPageCountChanged
        page.keyboardClearance = keyboardClearance
        page.restingClearance = restingClearance
        page.areaWillChange(to: areaInsets, animation: nil)
        // After the layout: stored ink is in print coordinates for the note's
        // own orientation, and the page starts out portrait.
        if let inkSaver {
            if let stored = inkSaver.loadInk() {
                page.setInk(stored)
            }
            page.onInkChanged = { [weak inkSaver] ink in inkSaver?.inkDidChange(ink) }
        }
        let matches = revealing.matches(in: text)
        if let first = matches.first {
            page.reveal(first, highlighting: matches)
        } else if let resumingAtPage {
            page.restore(toPage: resumingAtPage)
        }
        page.onReadingPlaceChanged = onReadingPlaceChanged
        page.onScrolled = onScrolled
    }

    /// Hands the configuration to the page on each SwiftUI update, in the
    /// order `updateUIView` has always set it. The page count only rises
    /// here, and the area moves with `areaAnimation`.
    @MainActor
    func apply(to page: PageView) {
        page.pageLayout = pageLayout
        page.minimumPageCount = max(minimumPageCount, page.minimumPageCount)
        page.addsPagesWhileDrawing = addsPagesWhileDrawing
        page.onMinimumPageCountChanged = onMinimumPageCountChanged
        page.keyboardClearance = keyboardClearance
        page.restingClearance = restingClearance
        page.onReadingPlaceChanged = onReadingPlaceChanged
        page.onScrolled = onScrolled
        // Before SwiftUI lays the new area out, so the page can follow the
        // hotbar from where it is now. Not the transaction's animation: the
        // dock is stored in `@AppStorage`, and its change arrives here
        // without the drop's `withAnimation` (logged, 17 Oct).
        page.areaWillChange(to: areaInsets, animation: areaAnimation)
    }
}

#endif
