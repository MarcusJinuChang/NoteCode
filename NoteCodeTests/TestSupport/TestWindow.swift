//
//  TestWindow.swift
//  NoteCodeTests
//
//  One way for tests to make a window.
//

#if canImport(UIKit)

import UIKit

/// A window of `frame`, in the test host's own scene.
///
/// `UIWindow(frame:)` and `UIWindow()` are deprecated, and a window made
/// outside a scene gets no display link and ignores `overrideUserInterfaceStyle`
/// when drawing (AGENTS.md › Pages). Tests run inside the app, which has a
/// scene by the time any of them does; without one there is nothing to make.
@MainActor
func makeTestWindow(frame: CGRect) -> UIWindow {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
        preconditionFailure("the test host has no window scene")
    }
    let window = UIWindow(windowScene: scene)
    window.frame = frame
    return window
}

/// A window with no scene, for the few tests that rely on it behaving that way:
/// it has no display link, so layout happens only when the test asks for it
/// (`PageSettlingTests.settle`), and UIKit applies no smart punctuation to an
/// edit made in code. In a scene both change and those tests see different
/// numbers (TextRegionSelectionTests, PageSettlingTests.openNote). The one
/// remaining `UIWindow(frame:)` deprecation warning is here, on purpose.
@MainActor
func makeSceneLessTestWindow(frame: CGRect) -> UIWindow {
    UIWindow(frame: frame)
}

#endif
