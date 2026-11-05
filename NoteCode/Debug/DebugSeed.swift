//
//  DebugSeed.swift
//  NoteCode
//
//  The notes and stores a debug launch opens with: the built-in fixtures, a
//  seeded note, and the stores for `-debug-first-launch` and `-debug-home`
//  with their sample notes. Debug builds only.
//

#if DEBUG

import Foundation
#if canImport(UIKit)
import SwiftData
import UIKit
#endif

// MARK: - Fixtures

/// A note a debug launch can open with.
///
/// Built in, so a check never depends on the pasteboard: on 12 September the
/// simulator synced the Mac's clipboard over a `simctl pbcopy`, and the paste
/// landed someone's own text instead of the test note.
nonisolated enum DebugFixture: String, CaseIterable, Sendable {
    /// About eight portrait pages. Headings, one-line and wrapped paragraphs,
    /// and code blocks, with descenders throughout, so page breaks land
    /// between lines, mid-paragraph and inside code. Every line is numbered,
    /// so a screenshot or report says exactly where it is.
    case pages
    /// Code in each language the run button knows, an untagged block, a line
    /// too long for the panel, and inline spans — for colour and panel checks.
    case code
    case empty

    var text: String {
        switch self {
        case .pages: Self.pagesText
        case .code:  Self.codeText
        case .empty: ""
        }
    }

    private static let pagesText: String = (1...240).flatMap { index -> [String] in
        if index % 30 == 1 {
            return ["## Section \(index / 30 + 1): gjpqy invariants"]
        }
        if index % 30 == 12 {
            return ["```cpp", "int query(gap g) {", "    return g.jump(); // line \(index), descenders: gjpqy", "}", "```"]
        }
        if index % 4 == 0 {
            return ["Line \(index): a longer paragraph that wraps across more than one line on a portrait page, so a page break can land in the middle of it and push only its later lines onto the next page."]
        }
        return ["Line \(index): the loop invariant holds before and after every iteration gjpqy."]
    }.joined(separator: "\n")

    private static let codeText = """
        # Code fixture: gjpqy
        Inline `code`, **bold**, *italic* and ~~struck~~ text.
        ```cpp
        #include <vector>
        int query(const std::vector<int>& gaps, int g) { // descenders: gjpqy
            return gaps.empty() ? -1 : gaps[g % static_cast<int>(gaps.size())];
        }
        ```
        ```java
        public class Main {
            public static void main(String[] args) { System.out.println("gjpqy"); }
        }
        ```
        ```python
        def jump(gaps, g):
            return [q for q in gaps if q > g]  # descenders: gjpqy
        ```
        ```
        untagged block: copy only, no run button
        ```
        A line of code too long for the panel:
        ```cpp
        auto veryLongIdentifierForHorizontalClipping = computeSomethingWithManyArguments(alpha, beta, gamma, delta, epsilon, zeta);
        ```
        """
}

#if canImport(UIKit)

// MARK: - Launch

@MainActor
enum DebugLaunch {

    /// A store holding one note built from the options, and that note.
    ///
    /// In memory: the simulator's own notes are left alone, and every launch
    /// starts from the same state. Returned as `.persistent` because it opened
    /// as intended — `.ephemeral` would show the storage-failure warning.
    static func seededStorage(_ options: DebugLaunchOptions, session: DebugSession) -> (storage: Storage, page: Page)? {
        guard let note = options.note else { return nil }

        let schema = NoteSchema.current
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        } catch {
            session.record("couldn't open an in-memory store: \(error.localizedDescription)")
            return nil
        }

        let title: String
        let content: String
        switch note {
        case .fixture(let fixture):
            title = "Debug: \(fixture.rawValue)"
            content = fixture.text
        case .file(let path):
            title = "Debug: \((path as NSString).lastPathComponent)"
            do {
                content = try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                session.record("couldn't read \(path): \(error.localizedDescription)")
                content = ""
            }
        }

        let page = Page(title: title, content: content)
        if let orientation = options.orientation {
            page.orientation = orientation
        }
        if let size = options.textSize {
            page.textSize = NoteTypography(bodySize: size).storedSize
        }
        if let path = options.inkFile {
            if let data = FileManager.default.contents(atPath: path) {
                page.drawingData = data
            } else {
                session.record("couldn't read ink from \(path)")
            }
        }
        container.mainContext.insert(page)
        return (.persistent(container), page)
    }

    /// The store for `-debug-first-launch` and `-debug-home`: in memory, so the
    /// simulator's own notes are left alone. Empty for a first launch, which
    /// also clears the flags a first launch is decided by; for Home, a few
    /// weeks of a student's notes, with the title screen marked as seen.
    ///
    /// The flags live in the simulator's defaults, so clearing them is felt by
    /// the next normal launch: its store isn't empty, so no Welcome note is made
    /// (`WelcomeNote.makeOnFirstLaunch`), but the title screen shows once more.
    ///
    /// - Parameter defaults: where the flags and remembered places live; a
    ///   test passes its own, so it doesn't clear the device's.
    static func firstLaunchOrHomeStorage(
        _ options: DebugLaunchOptions,
        session: DebugSession,
        defaults: UserDefaults = .standard
    ) -> Storage? {
        guard options.firstLaunch || options.home else { return nil }

        let schema = NoteSchema.current
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        } catch {
            session.record("couldn't open an in-memory store: \(error.localizedDescription)")
            return nil
        }

        if !options.keepsDefaults {
            for key in [WelcomeScreen.shownKey, WelcomeNote.madeKey, NoteMemory.lastOpenedKey, NoteMemory.placesKey,
                        RunDisclosure.key] {
                defaults.removeObject(forKey: key)
            }
            if options.home {
                defaults.set(true, forKey: WelcomeScreen.shownKey)
                defaults.set(true, forKey: WelcomeNote.madeKey)
            }
        }
        if options.home {
            // The sample notes are remembered as the last opened: into a
            // scratch suite when the real flags are to be left alone.
            let remembered = options.keepsDefaults ? UserDefaults(suiteName: "notecode.debug.scratch") ?? defaults : defaults
            seedHome(in: container.mainContext, session: session, defaults: remembered)
        }
        return .persistent(container)
    }

    /// Notes shaped like the `Home` board: a note to continue, a week's more,
    /// and three folders.
    private static func seedHome(in context: ModelContext, session: DebugSession, defaults: UserDefaults) {
        let cs133 = Folder(name: "CS133")
        cs133.symbolName = "chevron.left.forwardslash.chevron.right"
        let practice = Folder(name: "Algorithm practice")
        practice.colorName = FolderColor.blue.rawValue
        practice.symbolName = "function"
        let discrete = Folder(name: "Discrete math")
        discrete.colorName = FolderColor.purple.rawValue
        discrete.symbolName = "point.3.connected.trianglepath.dotted"
        // A folder inside a folder, so the list's nesting can be looked at.
        let labs = Folder(name: "Labs")
        labs.symbolName = "testtube.2"
        labs.colorName = FolderColor.green.rawValue
        for folder in [cs133, practice, discrete, labs] {
            context.insert(folder)
        }
        labs.parent = cs133

        let now = Date.now
        func note(_ title: String, _ content: String, in folder: Folder?, ago: TimeInterval) -> Page {
            let page = Page(title: title, content: content, createdAt: now.addingTimeInterval(-ago - 3600))
            page.modifiedAt = now.addingTimeInterval(-ago)
            context.insert(page)
            page.folder = folder
            return page
        }

        let prose = "\n\n" + DebugFixture.pages.text
        let hash = note(
            "Week 6 · Hash tables",
            "A hash table keeps each key in one of m buckets, picked by a hash function.\n\n## Chaining\n\n```cpp\nstruct Node { int key; Node* next; };\nint bucket(int key, int m) { return key % m; }\n```" + prose,
            in: cs133, ago: 600
        )
        _ = note("Lab 3 · Linked lists", "A singly linked list, then a doubly linked one.\n\n```cpp\nstruct Node {\n    int value;\n    Node* next;\n};\n```", in: labs, ago: 100_000)
        _ = note("Two pointers", "Sorted input and a pair that sums to a target.\n\n```python\ndef pair(nums, target):\n    lo, hi = 0, len(nums) - 1\n```", in: practice, ago: 110_000)
        _ = note("Exam 1 review", "Everything from weeks 1 to 5 on one page.\n\n## Topics\n\nArrays, pointers, classes, linked lists.", in: cs133, ago: 4 * 86_400)
        _ = note("Big-O cheat sheet", "O(1), O(log n), O(n), O(n log n), O(n²).", in: nil, ago: 21 * 86_400)
        _ = note("Week 5 · Binary search trees", "Insert, find and remove in a BST.\n\n```java\nclass Tree { Node root; }\n```", in: cs133, ago: 14 * 86_400)
        _ = note("Proof by induction", "Base case, hypothesis, step.", in: discrete, ago: 9 * 86_400)

        // Saved so the notes have permanent IDs to be remembered by.
        do {
            try context.save()
        } catch {
            session.record("couldn't save the sample notes: \(error.localizedDescription)")
        }
        if let id = hash.settledID {
            let memory = NoteMemory(defaults: defaults)
            memory.setLastOpened(id)
            memory.setPlace(NoteMemory.Place(page: 2, of: 5), of: id)
        }
    }
}

#endif
#endif
