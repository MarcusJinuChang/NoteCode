//
//  Haptics.swift
//  NoteCode
//
//  The small taps the app gives.
//

#if canImport(UIKit)

import UIKit

/// The app's haptics that aren't SwiftUI's `sensoryFeedback` (the dock's snap
/// is, on the hotbar). A seam rather than a call at each site, so a test can
/// see that a copy tapped without a Taptic Engine to feel it.
@MainActor
enum Haptics {

    /// A light tap when a code block is copied, by its button, the edit menu
    /// or ⇧⌘C.
    static var copyBlock: () -> Void = {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

#endif
