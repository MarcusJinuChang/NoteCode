//
//  LayoutClass.swift
//  NoteCode
//
//  "Compact" worked out once, at the root, and read from the environment.
//

import SwiftUI

/// Whether the window is in a compact width (an iPhone, a folded Duo, Slide
/// Over) and so a stack, or in a regular one, a split view.
///
/// Set once by `.providesLayoutClass()` at the root of the scene, from the
/// horizontal size class, so ContentView, the page, Home, the Run panel and
/// the list's rows read one value instead of each asking the size class.
/// Home's extra width rule (`HomeLayout.isCompact`) stays Home's and is
/// worked out on top of this. `PageView`'s UIKit read of its trait collection
/// stays, since a UIView cannot see the environment.
enum LayoutClass: Equatable {
    case compact
    case regular

    var isCompact: Bool { self == .compact }
}

private struct LayoutClassKey: EnvironmentKey {
    static let defaultValue = LayoutClass.regular
}

extension EnvironmentValues {
    var layoutClass: LayoutClass {
        get { self[LayoutClassKey.self] }
        set { self[LayoutClassKey.self] = newValue }
    }
}

/// Reads the size class and puts the `LayoutClass` into the environment.
struct LayoutClassProvider: ViewModifier {
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var layoutClass: LayoutClass { sizeClass == .compact ? .compact : .regular }
#else
    private var layoutClass: LayoutClass { .regular }
#endif

    func body(content: Content) -> some View {
        content.environment(\.layoutClass, layoutClass)
    }
}

extension View {
    /// Call once, at the root of a window.
    func providesLayoutClass() -> some View {
        modifier(LayoutClassProvider())
    }
}
