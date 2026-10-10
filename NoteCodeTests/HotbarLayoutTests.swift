//
//  HotbarLayoutTests.swift
//  NoteCodeTests
//
//  The hotbar's options row floats over the page and reserves nothing: the page
//  doesn't move when the bar changes mode or tool or edge. These host the real
//  note page, so they see what the layout does rather than what a function says
//  it should. Where the row sits and what it reaches are in HotbarUITests, since
//  they need the accessibility tree and real taps.
//

#if canImport(UIKit)

import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("Hotbar layout", .serialized)
@MainActor
struct HotbarLayoutTests {

    /// An 11-inch iPad in landscape, the size the design fits the ink bar to.
    private static let window = CGSize(width: 1194, height: 834)

    /// A window in the test host's own scene, which is what gives SwiftUI a
    /// display link to update on. One made without a scene never re-renders.
    static func makeWindow() -> UIWindow {
        let frame = CGRect(origin: .zero, size: Self.window)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return UIWindow(frame: frame)
        }
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        return window
    }

    /// A note page in a window, driven from outside through its editor.
    @MainActor
    private final class Rig {
        let container: ModelContainer
        let editor = NoteEditor()
        let window = HotbarLayoutTests.makeWindow()
        private let savedDock: String?

        init(dock: HotbarDock) throws {
            // The page reads its dock from the device's settings.
            savedDock = UserDefaults.standard.string(forKey: HotbarDock.defaultsKey)
            UserDefaults.standard.set(dock.rawValue, forKey: HotbarDock.defaultsKey)

            container = try ModelContainer(
                for: NoteSchema.current,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let page = Page(title: "Hash tables", content: "# Hash tables\n\nA hash table keeps each key in one bucket.\n")
            container.mainContext.insert(page)

            let root = NavigationStack { PageDetailView(page: page, editor: editor) }
                .modelContainer(container)
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            settle()
        }

        deinit {
            if let savedDock {
                UserDefaults.standard.set(savedDock, forKey: HotbarDock.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: HotbarDock.defaultsKey)
            }
        }

        /// Lets SwiftUI lay out and its animations finish.
        ///
        /// The window has to be in a scene (`makeWindow`): one made without
        /// gets no display link, and SwiftUI never re-rendered after a state
        /// change. The first version of these tests passed with the page's
        /// insets made to depend on the mode, because nothing ever updated.
        func settle(_ seconds: TimeInterval = 0.8) {
            let end = Date(timeIntervalSinceNow: seconds)
            repeat {
                window.rootViewController?.view.setNeedsLayout()
                window.layoutIfNeeded()
                CATransaction.flush()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            } while Date() < end
        }

        var pageView: PageView {
            func find(in view: UIView) -> PageView? {
                if let page = view as? PageView { return page }
                for subview in view.subviews {
                    if let found = find(in: subview) { return found }
                }
                return nil
            }
            return find(in: window)!
        }

        /// Where the page is and how large it's drawn.
        struct PageGeometry {
            var page: CGRect
            var text: CGRect
            var scale: CGFloat

            func matches(_ other: PageGeometry) -> Bool {
                func close(_ a: CGRect, _ b: CGRect) -> Bool {
                    abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
                        && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
                }
                return close(page, other.page) && close(text, other.text) && abs(scale - other.scale) < 0.0001
            }
        }

        func geometry() -> PageGeometry {
            let page = pageView
            return PageGeometry(
                page: page.convert(page.bounds, to: window),
                text: page.textView.convert(page.textView.bounds, to: window),
                scale: page.displayScale
            )
        }
    }

    // MARK: The page doesn't move

    @Test("The page is the same size and in the same place in text mode, ink mode and every tool, on every edge", arguments: HotbarDock.allCases)
    func pageStaysPut(dock: HotbarDock) throws {
        let rig = try Rig(dock: dock)
        let inText = rig.geometry()

        // Sanity: the page is really there, not a zero rect that would match
        // itself in any mode.
        #expect(inText.page.width > 300)
        #expect(inText.scale > 0)

        rig.editor.setMode(.ink)
        rig.settle()
        #expect(rig.geometry().matches(inText), "ink mode, pen: \(rig.geometry()) against \(inText)")

        for kind in [InkToolKind.highlighter, .eraser, .lasso, .pen] {
            rig.editor.inkTool.kind = kind
            rig.settle()
            #expect(rig.geometry().matches(inText), "\(kind) selected")
        }

        rig.editor.setMode(.text)
        rig.settle()
        #expect(rig.geometry().matches(inText), "back in text mode")
    }

    @Test("The bar is the same size whichever mode or tool is on, with the row out or not", arguments: HotbarDock.allCases)
    func barKeepsItsSize(dock: HotbarDock) {
        let editor = NoteEditor()
        var current = dock
        let host = UIHostingController(rootView: Hotbar(
            editor: editor,
            dock: Binding(get: { current }, set: { current = $0 }),
            onDrop: { _ in }
        ))
        let window = Self.makeWindow()
        window.rootViewController = host
        window.makeKeyAndVisible()

        func size() -> CGSize {
            host.view.layoutIfNeeded()
            return host.sizeThatFits(in: Self.window)
        }
        let inText = size()
        #expect(inText.width > 40 && inText.height > 40)

        editor.setMode(.ink)
        #expect(size() == inText, "ink mode, pen: the row is out")

        for kind in [InkToolKind.highlighter, .eraser, .lasso] {
            editor.inkTool.kind = kind
            #expect(size() == inText, "\(kind) selected")
        }
    }
}

#endif
