//
//  InkCapture.swift
//  NoteCode
//
//  What the reader changed on the canvas, taken into the note's stored ink.
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import UIKit

/// Takes what the reader drew, erased or moved on the canvas into the note's
/// stored ink, which is in print coordinates (`PageView.ink`).
///
/// Pure, so `PageView` runs it off the main thread. Every operation on a
/// `MarkupOrderedSet` costs time in proportion to the set's size — a walk
/// reading each element's frame is 107ms at 5,000 strokes, an append 20ms,
/// even `count` 16ms (simulator, 10 October) — and this runs after every
/// stroke. On the main thread, a note with a lot of ink stuttered while it
/// was written and caught up seconds later.
///
/// Only what changed is converted into print coordinates. An element that
/// hasn't moved keeps the stored copy it came from, because converting out
/// of a mode with narrow breaks isn't exact: ink in a sheet's margin has no
/// place in seamless, so a round trip there and back would walk it onto the
/// next page. What changed is stored as its pieces, one per page it reaches
/// (`InkPages`), cut in the coordinates it was drawn in. Compressed and print
/// layout show only the piece a stroke was started on; the rest is its
/// overflow, kept for seamless, and it goes and comes back with that piece.
nonisolated enum InkCapture {

    typealias ElementID = MarkupOrderedSet.ElementID

    /// The stored ink, and what's needed to tell what the reader changed
    /// since it was last shown or read.
    struct State: Sendable {
        /// In print coordinates, for the note's orientation.
        var ink: PaperMarkup

        /// Where each element on the canvas sat when the canvas was last
        /// shown or read. What the reader drew, erased or moved is whatever
        /// differs from this.
        var shown: [ElementID: CGRect] = [:]

        /// `InkContent.fingerprint` of each shape, text box and image on the
        /// canvas when it was last shown or read. A frame doesn't tell these
        /// apart from what the reader did to them: a shape recoloured, a text
        /// box retyped, an image faded all leave it where it was.
        var contents: [ElementID: Int] = [:]

        /// Strokes stored cut into pieces that the canvas still holds whole.
        ///
        /// Seamless shows a stroke across a break whole, so a stroke drawn
        /// there stays as drawn on the canvas until ink is next shown — a
        /// mode switch or reopening — when the canvas takes its pieces.
        var wholeOnCanvas: Set<ElementID> = []

        /// Strokes the canvas shows as their own piece with
        /// `InkPages.shown`'s specks, so their frame there is the whole
        /// stroke's, not their piece's. Like `wholeOnCanvas`, they're put
        /// back as stored when ink is next shown: placed by that frame, they
        /// moved by half the part that's hidden (simulator, 10 October).
        var specked: Set<ElementID> = []

        /// Overflow taken out with its stroke since ink was last shown, by
        /// family, so that undoing the erase brings it back. Showing ink
        /// clears ink undo, and this with it.
        var buried: [InkPages.Family: [PKStroke]] = [:]
    }

    struct Result: Sendable {
        var state: State
        /// Whether the stored ink changed.
        var changed: Bool
        /// The lowest point of the ink as shown, or `nil` for none.
        var inkBottom: CGFloat?
        /// Strokes the canvas holds whole that it should show as their own
        /// piece only, in its coordinates: drawn or moved across a border in
        /// compressed or print layout, which don't show overflow.
        var reshow: [PKStroke] = []
        /// Where each stroke the reader just drew ended, in the canvas's
        /// coordinates: strokes with no record in `State.shown`. Moved, erased
        /// and undone ink has one, so it is never in here, which is what keeps
        /// ink moved into a page's foot from adding a page (`PageView`).
        var drawnEnds: [CGPoint] = []
    }

    /// `canvas` taken into `state`.
    ///
    /// - Parameters:
    ///   - canvas: the canvas's markup, in `layout`'s coordinates.
    ///   - layout: the layout the canvas shows, which is the one the reader
    ///     drew in.
    ///   - pageCount: the note's pages when it was drawn, for the regions
    ///     strokes are cut to.
    static func capture(_ canvas: PaperMarkup, into state: State, layout: PageLayout, pageCount: Int) -> Result {
        // One walk of the canvas, with `for`: see `PageView.frames(of:)`.
        var frames: [ElementID: CGRect] = [:]
        var contents: [ElementID: Int] = [:]
        var touched: [any Markup] = []
        var drawnEnds: [CGPoint] = []
        var bottom: CGFloat?
        for element in canvas.subelements {
            let id = element.elementID
            let frame = element.renderFrame
            frames[id] = frame
            bottom = max(bottom ?? frame.maxY, frame.maxY)
            let fingerprint = InkContent.fingerprint(of: element)
            if let fingerprint {
                contents[id] = fingerprint
            }
            // New, moved by the lasso, or (for the elements that have one)
            // edited in place. Ink nobody touched keeps its stored copy, so
            // it is never converted back from the screen. An element with no
            // record of its content is taken as unchanged: ink is always
            // shown with its record, so a missing one means a new element,
            // which its missing frame already catches.
            if state.shown[id] != frame {
                touched.append(element)
                if state.shown[id] == nil, let stroke = element as? PKStroke, let last = stroke.path.last {
                    drawnEnds.append(last.location.applying(stroke.transform))
                }
            } else if let fingerprint, let known = state.contents[id], known != fingerprint {
                touched.append(element)
            }
        }
        let gone = state.shown.keys.filter { frames[$0] == nil }
        guard !touched.isEmpty || !gone.isEmpty else {
            return Result(state: state, changed: false, inkBottom: bottom)
        }
        // Past this point something changed, and `contents` is what the next
        // capture compares against.

        let print = PageLayout(orientation: layout.orientation, mode: .print)
        let regions = layout.inkRegions(pageCount: pageCount)
        let hidesOverflow = layout.mode != .seamless
        var updated = state.ink
        var whole = state.wholeOnCanvas
        var specked = state.specked
        var buried = state.buried
        var reshow: [PKStroke] = []

        // The stored overflow pieces by family, found the first time one is
        // asked for: it takes a walk of the stored ink.
        var overflowIndex: [InkPages.Family: Set<ElementID>]?
        func overflow(of family: InkPages.Family) -> Set<ElementID> {
            if overflowIndex == nil {
                var index: [InkPages.Family: Set<ElementID>] = [:]
                for element in updated.subelements {
                    guard let stroke = element as? PKStroke, InkPages.isOverflow(stroke.id) else { continue }
                    index[InkPages.family(of: stroke.id), default: []].insert(stroke.elementID)
                }
                overflowIndex = index
            }
            return overflowIndex?[family] ?? []
        }
        /// Overflow of `family` the canvas doesn't hold, so nothing the
        /// reader did to the canvas can have touched it.
        func hidden(of family: InkPages.Family) -> [ElementID] {
            overflow(of: family).filter { frames[$0] == nil }
        }
        func remove(_ id: ElementID) -> PKStroke? {
            let stroke = updated.subelements.removeElement(for: id) as? PKStroke
            if let stroke, InkPages.isOverflow(stroke.id) {
                overflowIndex?[InkPages.family(of: stroke.id)]?.remove(id)
            }
            return stroke
        }
        func noteOverflow(_ piece: any Markup) {
            guard let stroke = piece as? PKStroke, InkPages.isOverflow(stroke.id) else { return }
            _ = overflow(of: InkPages.family(of: stroke.id))
            overflowIndex?[InkPages.family(of: stroke.id), default: []].insert(stroke.elementID)
        }

        // Erased, or undone. A markup merges rather than replaces, so leaving
        // an element out of a new set keeps it; taking it out is a call of
        // its own. A stroke's overflow the canvas doesn't hold goes with it,
        // kept aside in case the erase is undone.
        for id in gone {
            whole.remove(id)
            specked.remove(id)
            guard let stroke = remove(id), !InkPages.isOverflow(stroke.id) else { continue }
            let family = InkPages.family(of: stroke.id)
            let pieces = hidden(of: family).compactMap(remove)
            if !pieces.isEmpty {
                buried[family] = pieces
            }
        }

        // Drawn, or moved. Whatever a moved element was stored as goes, and
        // it's stored again as it is now, in the place the old copy had, so
        // the order strokes are drawn in doesn't change. New ink goes on the
        // end, in one append.
        var added: [any Markup] = []
        for element in touched {
            let id = element.elementID
            let stroke = element as? PKStroke
            let family = stroke.map { InkPages.family(of: $0.id) }
            let isOwn = stroke.map { !InkPages.isOverflow($0.id) } ?? false
            var position: Int?
            var restored: [PKStroke] = []

            if let before = state.shown[id] {
                var index = 0
                for storedID in updated.subelements.ids {
                    if storedID == id {
                        position = index
                        break
                    }
                    index += 1
                }
                _ = remove(id)
                if isOwn, let family {
                    if whole.contains(id) {
                        // The canvas had it whole, so it's cut again from
                        // scratch and its old overflow goes.
                        for old in hidden(of: family) {
                            _ = remove(old)
                        }
                    } else if hidesOverflow {
                        // What shows was moved: what doesn't goes with it.
                        let after = frames[id] ?? before
                        let shift = CGAffineTransform(translationX: after.midX - before.midX, y: after.midY - before.midY)
                        for old in hidden(of: family) {
                            if var piece = remove(old) {
                                piece.applyTransform(shift)
                                // Recoloured on the canvas: the part that
                                // isn't shown goes the same colour.
                                if let stroke, InkContent.inkSignature(of: piece) != InkContent.inkSignature(of: stroke) {
                                    piece = InkCommands.recoloured(piece, to: stroke.ink.color)
                                }
                                restored.append(piece)
                            }
                        }
                    }
                }
            }

            let pieces = InkPages.pieces(of: element, regions: regions)
            let cut = pieces.count > 1
            if isOwn, let family {
                if cut {
                    // A fresh cut replaces whatever was put aside.
                    buried[family] = nil
                } else if state.shown[id] == nil, let back = buried.removeValue(forKey: family) {
                    // An erase undone: its overflow comes back with it.
                    restored += back
                }
            }
            for piece in pieces.map({ moved($0, from: layout, to: print) }) + restored {
                noteOverflow(piece)
                if let index = position {
                    updated.subelements.insert(piece, at: index)
                    position = index + 1
                } else {
                    added.append(piece)
                }
            }

            whole.remove(id)
            if cut, isOwn {
                if hidesOverflow, let own = pieces.first(where: { $0.elementID == id }) as? PKStroke {
                    reshow.append(own)
                } else if !hidesOverflow {
                    whole.insert(id)
                }
            }
        }
        if !added.isEmpty {
            updated.subelements.append(contentsOf: added)
        }

        return Result(
            state: State(ink: updated, shown: frames, contents: contents, wholeOnCanvas: whole, specked: specked, buried: buried),
            changed: true,
            inkBottom: bottom,
            reshow: reshow,
            drawnEnds: drawnEnds
        )
    }

    /// One element at the same place on its page in another layout.
    ///
    /// An element belongs to the page its middle is on, so a stroke drawn
    /// across a page break travels whole rather than being torn in two.
    static func moved(_ element: any Markup, from old: PageLayout, to new: PageLayout) -> any Markup {
        var element = element
        let middle = element.renderFrame.midY
        if let target = old.convert(y: middle, to: new), target != middle {
            element.applyTransform(CGAffineTransform(translationX: 0, y: target - middle))
        }
        return element
    }
}

// MARK: - Edits that don't move anything

/// A number for what a shape, text box or image looks like apart from where it
/// is, so `InkCapture` can tell that one was edited in place.
///
/// A stroke's is its ink and colour: PencilKit's are immutable once drawn, but
/// the Select tool can recolour one where it stands. A text box is a `ShapeMarkup` carrying `attributedText`, so one
/// hash covers shapes and text boxes alike.
///
/// Hashed rather than compared: the elements aren't `Equatable`, and keeping
/// a copy of each to compare against would keep every photo twice. The hash
/// is per process (`Hasher` is seeded), which is enough, since it lives in
/// `InkCapture.State` and is never stored.
nonisolated enum InkContent {

    static func fingerprint(of element: any Markup) -> Int? {
        if let stroke = element as? PKStroke {
            return inkSignature(of: stroke)
        }
        var hasher = Hasher()
        if let shape = element as? ShapeMarkup {
            hasher.combine(shape.shape)
            hasher.combine(components(of: shape.fillColor))
            hasher.combine(components(of: shape.strokeColor))
            hasher.combine(shape.lineWidth)
            hasher.combine(shape.opacity)
            hasher.combine(shape.startLineMarker)
            hasher.combine(shape.endLineMarker)
            hasher.combine(shape.attributedText)
            hasher.combine(shape.frame)
            hasher.combine(shape.rotation)
            return hasher.finalize()
        }
        if let image = element as? ImageMarkup {
            hasher.combine(image.opacity)
            hasher.combine(image.contentsBounds)
            hasher.combine(image.orientation)
            hasher.combine(image.frame)
            hasher.combine(image.rotation)
            return hasher.finalize()
        }
        return nil
    }

    /// What a stroke is drawn in, apart from its path: the ink's type and
    /// colour. The Select tool recolours strokes in place (same id, same
    /// frame), which a frame alone can't show.
    static func inkSignature(of stroke: PKStroke) -> Int {
        var hasher = Hasher()
        let ink = stroke.ink
        hasher.combine(inkIdentifier(of: ink))
        hasher.combine(ink.color.cgColor.components)
        return hasher.finalize()
    }

    /// The ink's identifier, such as `com.apple.ink.pen`, read without
    /// `PKInk.inkType`.
    ///
    /// PaperKit's pixel eraser doesn't cut the strokes it crosses: it adds a
    /// stroke of its own over them, in `com.apple.ink.eraser`. `PKInk.InkType`
    /// has no case for that ink, and the Swift getter traps on one rather
    /// than return nothing: the app crashed as the pen lifted from every
    /// pixel erase (simulator, 28 October). The Objective-C ink holds the
    /// identifier as a string.
    static func inkIdentifier(of ink: PKInk) -> String {
        (ink as PKInkReference).inkType.rawValue
    }

    /// A colour as numbers, or `nil` for none. `CGColor` isn't hashable.
    private static func components(of color: CGColor?) -> [CGFloat]? {
        color?.components
    }
}

#endif
