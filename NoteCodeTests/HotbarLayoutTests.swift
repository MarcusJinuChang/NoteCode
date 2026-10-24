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
    nonisolated private static let window = CGSize(width: 1194, height: 834)

    /// The same iPad held upright.
    nonisolated private static let portraitWindow = CGSize(width: 834, height: 1194)

    /// A window in the test host's own scene, which is what gives SwiftUI a
    /// display link to update on. One made without a scene never re-renders.
    static func makeWindow(size: CGSize = window) -> UIWindow {
        let frame = CGRect(origin: .zero, size: size)
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
        let window: UIWindow
        private let savedDock: String?
        private let savedMode: String?

        init(dock: HotbarDock, size: CGSize = HotbarLayoutTests.window, mode: PageViewMode? = nil) throws {
            window = HotbarLayoutTests.makeWindow(size: size)
            // The page reads its dock and view mode from the device's settings.
            savedDock = UserDefaults.standard.string(forKey: HotbarDock.defaultsKey)
            UserDefaults.standard.set(dock.rawValue, forKey: HotbarDock.defaultsKey)
            savedMode = UserDefaults.standard.string(forKey: PageViewMode.defaultsKey)
            if let mode { UserDefaults.standard.set(mode.rawValue, forKey: PageViewMode.defaultsKey) }

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
            if let savedMode {
                UserDefaults.standard.set(savedMode, forKey: PageViewMode.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: PageViewMode.defaultsKey)
            }
        }

        /// The lowest point of the navigation bar, in the window: the top of
        /// the room the page has.
        var contentTop: CGFloat {
            func bar(in view: UIView) -> UINavigationBar? {
                if let bar = view as? UINavigationBar { return bar }
                for subview in view.subviews {
                    if let found = bar(in: subview) { return found }
                }
                return nil
            }
            let bottom = bar(in: window).map { $0.convert($0.bounds, to: window).maxY } ?? 0
            return max(bottom, window.safeAreaInsets.top)
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

    // MARK: The page keeps off the screen's edge

    struct Held: CustomStringConvertible, Sendable {
        let name: String
        let size: CGSize
        var description: String { name }
    }

    private static let holds = [
        Held(name: "landscape", size: window),
        Held(name: "portrait", size: portraitWindow),
    ]

    @Test("The page is Hotbar.pageBuffer from every screen edge the bar doesn't take, top included, and a bar's strip from its own",
          arguments: HotbarDock.allCases, holds)
    func pageKeepsOffTheEdges(dock: HotbarDock, held: Held) throws {
        let rig = try Rig(dock: dock, size: held.size)
        let screen = CGRect(origin: .zero, size: held.size)
        let buffer = Hotbar.pageBuffer
        // Fails now and then in a full run (not when the suite runs alone):
        // the room above the page reads 52pt taller than the page was laid
        // out against, and stays so for seconds. Not yet explained; the
        // label lists the navigation bars and the window's inset so the
        // next failure shows where the 52pt is.
        let page = rig.geometry().page
        func bars(in view: UIView) -> [String] {
            var found: [String] = []
            if let bar = view as? UINavigationBar { found.append("\(bar.convert(bar.bounds, to: rig.window))") }
            for subview in view.subviews { found += bars(in: subview) }
            return found
        }
        let label = "\(dock) bar, \(held): page \(page) in \(screen); navigation bars \(bars(in: rig.window)), window top inset \(rig.window.safeAreaInsets.top)"

        // Sanity: the page is really laid out, so a zero rect can't pass.
        #expect(page.width > 300 && page.height > 300, "\(label)")
        let side = Hotbar.footprint
        // PageView is the whole area SwiftUI gives the page, so these are
        // exact, less the system's own safe areas (the nav bar, the home
        // indicator), which the buffer is added to.
        func gap(_ actual: CGFloat, _ expected: CGFloat, _ edge: String) {
            #expect(abs(actual - expected) < 0.5, "\(edge): \(actual) against \(expected): \(label)")
        }
        gap(page.minX, dock == .left ? side : buffer, "left")
        gap(screen.maxX - page.maxX, dock == .right ? side : buffer, "right")
        gap(page.minY - rig.contentTop, buffer, "top")
        // A bar at the bottom floats over the page, which runs on under it.
        gap(screen.maxY - page.maxY - rig.window.safeAreaInsets.bottom, dock == .bottom ? 0 : buffer, "bottom")
    }

    @Test("The buffer leaves the text container at the pages' own width in every view mode", arguments: PageViewMode.allCases, HotbarDock.allCases)
    func bufferLeavesTheLayoutAlone(mode: PageViewMode, dock: HotbarDock) throws {
        let rig = try Rig(dock: dock, mode: mode)
        let page = rig.pageView
        let layout = PageLayout(orientation: .portrait, mode: mode)
        #expect(page.textView.textContainer.size.width == layout.textWidth, "\(mode), \(dock)")
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
