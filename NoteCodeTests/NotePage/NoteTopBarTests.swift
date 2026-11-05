//
//  NoteTopBarTests.swift
//  NoteCodeTests
//
//  The note's top bar as the page draws it: what is on its right with
//  nothing an edition adds (`AppExtensions.none`). Run's item, which the
//  App Store edition adds through the editor's features, is checked in
//  NoteTopBarTests+Run.swift.
//

#if canImport(UIKit)

import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("Note top bar", .serialized, .tags(.layout))
@MainActor
struct NoteTopBarTests {

    /// A note page in a navigation stack, in a window the size of an
    /// 11-inch iPad in landscape, wide enough for every item to show in the
    /// bar rather than its overflow menu.
    @MainActor
    final class Rig {
        let container: ModelContainer
        let window: UIWindow
        private let device = TestDefaults("NoteTopBar")

        init(editor: NoteEditor) throws {
            window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 1194, height: 834))
            container = try ModelContainer(
                for: NoteSchema.current,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            editor.defaults = device.defaults
            let page = Page(title: "Hash tables", content: "# Hash tables\n\nA hash table keeps each key in one bucket.\n")
            container.mainContext.insert(page)
            let root = NavigationStack { PageDetailView(page: page, editor: editor) }
                .modelContainer(container)
                .defaultAppStorage(device.defaults)
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
        }

        func settle(_ seconds: TimeInterval = 0.8) {
            let end = Date(timeIntervalSinceNow: seconds)
            repeat {
                window.rootViewController?.view.setNeedsLayout()
                window.layoutIfNeeded()
                CATransaction.flush()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            } while Date() < end
        }

        /// The accessibility labels of what the bar's right side shows, in
        /// its order.
        var trailingItems: [String] {
            func bar(in view: UIView) -> UINavigationBar? {
                if let bar = view as? UINavigationBar { return bar }
                for subview in view.subviews {
                    if let found = bar(in: subview) { return found }
                }
                return nil
            }
            // SwiftUI puts each `.primaryAction` item in a trailing group of
            // its own, leading to trailing, titled as it is read out.
            guard let item = bar(in: window)?.topItem else { return [] }
            return item.trailingItemGroups.flatMap(\.barButtonItems).map { $0.title ?? "?" }
        }

        func close() {
            window.rootViewController = nil
            window.isHidden = true
        }
    }

    @Test("With nothing added, the bar's right side is Share and ••• only")
    func shareAndMoreOnly() throws {
        let rig = try Rig(editor: NoteEditor())
        defer { rig.close() }
        rig.settle()
        #expect(rig.trailingItems == ["Share", "More"])
    }
}

#endif
