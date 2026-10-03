//
//  InkPaletteTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Ink palette")
struct InkPaletteTests {

    private let yellow = InkColor(red: 1, green: 0.8, blue: 0)
    private let purple = InkColor(red: 0.5, green: 0, blue: 0.5)
    private let teal = InkColor(red: 0, green: 0.5, blue: 0.5)

    @Test("A new colour goes on the end and is the one returned")
    func addsAtTheEnd() {
        var palette = InkPalette([.black, yellow])

        let added = palette.add(purple)

        #expect(added == purple)
        #expect(palette.colors == [.black, yellow, purple])
    }

    @Test("A colour already there, to 8 bits a channel, isn't added twice")
    func noNearDuplicates() {
        var palette = InkPalette([.black, yellow])
        let almostBlack = InkColor(red: 0.000_001, green: 0, blue: 0.000_002)

        let added = palette.add(almostBlack)

        #expect(added == .black)
        #expect(palette.colors == [.black, yellow])
    }

    @Test("Removing a colour hands back the one that took its place")
    func removeHandsBackItsNeighbour() {
        var palette = InkPalette([.black, yellow, purple])

        #expect(palette.remove(yellow) == purple)
        #expect(palette.colors == [.black, purple])
        // At the end, the one before it.
        #expect(palette.remove(purple) == .black)
        #expect(palette.colors == [.black])
    }

    @Test("The last colour can't be removed")
    func keepsOneColour() {
        var palette = InkPalette([yellow])

        #expect(palette.remove(yellow) == nil)
        #expect(palette.colors == [yellow])
        #expect(InkPalette([]).colors == [.black])
    }

    @Test("A dragged colour takes the place of the one it's dropped on, either way")
    func moveIntoPlace() {
        var palette = InkPalette([.black, yellow, purple, teal])

        palette.move(.black, to: purple)
        #expect(palette.colors == [yellow, purple, .black, teal])

        palette.move(teal, to: yellow)
        #expect(palette.colors == [teal, yellow, purple, .black])
    }

    @Test("Moving by a step stops at the ends")
    func moveByStep() {
        var palette = InkPalette([.black, yellow, purple])

        palette.move(yellow, by: 1)
        #expect(palette.colors == [.black, purple, yellow])
        palette.move(yellow, by: 1)
        #expect(palette.colors == [.black, purple, yellow])
        palette.move(.black, by: -1)
        #expect(palette.colors == [.black, purple, yellow])
    }

    @Test("Repeats are dropped when a palette is made")
    func noRepeats() {
        #expect(InkPalette([.black, yellow, .black]).colors == [.black, yellow])
    }

    @Test("A palette survives storage exactly, and anything else reads as no palette")
    func storage() {
        let palette = InkPalette([.black, InkColor(red: 1.0746, green: -0.0226, blue: 0.1, alpha: 1), teal])

        #expect(InkPalette(rawValue: palette.rawValue) == palette)
        #expect(InkPalette(rawValue: "") == nil)
        #expect(InkPalette(rawValue: "[]") == nil)
        #expect(InkPalette(rawValue: "[[1, 0]]") == nil)
    }
}

@Suite("Eraser settings")
struct EraserSettingsTests {

    @Test("Settings survive storage, and a bad value reads as none")
    func storage() {
        var settings = EraserSettings()
        settings.mode = .wholeStroke
        settings.size = .custom
        settings.customWidth = 44.5

        #expect(EraserSettings(rawValue: settings.rawValue) == settings)
        #expect(EraserSettings(rawValue: "partial;huge;20") == nil)
        #expect(EraserSettings(rawValue: "") == nil)
    }

    @Test("A custom width stays inside what PencilKit takes, however it's set")
    func customWidthClamped() {
        var settings = EraserSettings()
        settings.customWidth = 500
        #expect(settings.customWidth == EraserSettings.widthRange.upperBound)
        settings.customWidth = 1
        #expect(settings.customWidth == EraserSettings.widthRange.lowerBound)

        #expect(EraserSettings(rawValue: "partial;custom;500")?.customWidth == EraserSettings.widthRange.upperBound)
    }

    @Test("The size in use sets the width; the custom width waits its turn")
    func widthFollowsSize() {
        var settings = EraserSettings()
        settings.customWidth = 70
        settings.size = .medium
        #expect(settings.width == EraserSettings.width(of: .medium))
        settings.size = .custom
        #expect(settings.width == 70)
    }
}
