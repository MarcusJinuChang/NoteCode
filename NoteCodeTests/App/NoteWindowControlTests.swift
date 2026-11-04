//
//  NoteWindowControlTests.swift
//  NoteCode
//
//  The joined control's two icons draw something in both appearances (the
//  invisible-icon bug of colour.md), and the way home aims at the right card.
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@MainActor
@Suite("Note window control")
struct NoteWindowControlTests {

    @Test("The sidebar and home icons draw pixels, light and dark", arguments: [NoteIcon.sidebar, .home], ColorScheme.allCases)
    func drawn(icon: NoteIcon, scheme: ColorScheme) {
        let pixels = HotbarIconPixelTests.visiblePixels(
            NoteIconView(icon: icon).frame(width: 22, height: 22), scheme: scheme)
        #expect(pixels > 40, "\(icon) \(scheme): \(pixels)")
    }

    @Test("A card's centre and size become the anchor and scale")
    func launch() {
        let launch = HomeLaunch(card: CGRect(x: 100, y: 200, width: 200, height: 100), container: CGSize(width: 1000, height: 800))
        #expect(launch.anchor == UnitPoint(x: 0.2, y: 0.3125))
        #expect(abs(launch.scale - 0.2) < 0.0001)
    }

    @Test("No size to measure against shrinks to the middle")
    func noSize() {
        #expect(HomeLaunch(card: .zero, container: .zero) == .centre)
    }
}

#endif
