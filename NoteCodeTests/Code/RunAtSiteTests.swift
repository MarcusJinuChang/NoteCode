//
//  RunAtSiteTests.swift
//  NoteCodeTests
//
//  Run with no editor features: the block opens on a compiler site, through
//  the coordinator's general path (docs/refactor/2X-seam.md › 2X5b).
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

/// A note in a text view with its coordinator connected to `editor`, and the
/// links Run opens caught instead of opened.
@MainActor
final class RunHarness {
    var stored: String
    let window: UIWindow
    let textView: DocumentUITextView
    let page: PageView
    let coordinator: DocumentTextView.Coordinator
    let editor: NoteEditor
    private(set) var opened: [URL] = []

    init(_ source: String, editor: NoteEditor? = nil) {
        stored = source
        window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 1200))
        textView = DocumentTextView.makeConfiguredTextView()
        let editor = editor ?? NoteEditor()
        self.editor = editor
        page = PageView(textView: textView)
        coordinator = DocumentTextView.Coordinator(text: Binding(get: { "" }, set: { _ in }))
        coordinator.text = Binding(get: { [unowned self] in stored }, set: { [unowned self] in stored = $0 })
        coordinator.openURL = { [unowned self] in opened.append($0) }
        textView.delegate = coordinator
        textView.textLayoutManager?.delegate = coordinator
        coordinator.observeEdits(of: textView)
        coordinator.attachOverlay(to: textView)
        textView.text = source
        coordinator.invalidateStyling()
        coordinator.restyle(textView)
        page.frame = CGRect(x: 0, y: 0, width: 872, height: 1100)
        window.addSubview(page)
        window.makeKeyAndVisible()
        editor.attach(textView, canvas: page.canvas, page: page)
        coordinator.connect(editor, to: textView)
    }

    /// The first code block, as Run is handed it.
    func firstBlock() throws -> CodeBlockTarget {
        let source = (textView.text ?? "").nativeUTF8
        return try #require(DocumentSnapshot(text: source).targets.first)
    }
}

@Suite("Run at a site, with no features")
@MainActor
struct RunAtSiteTests {

    @Test("Run on a C++ block opens its Compiler Explorer link, and nothing else")
    func cppOpensLink() throws {
        let code = "int main() { return 0; }\n"
        let harness = RunHarness("Intro\n```cpp\n\(code)```\n")
        let block = try harness.firstBlock()

        harness.coordinator.run(block, from: harness.textView)

        let expected = CodeDestination.request(for: block.code, language: .cpp)
        #expect(expected.destination == .compilerExplorer)
        #expect(harness.opened == [expected.url])
    }

    @Test("Java goes to the pasteboard and the site's page")
    func javaUsesPasteboard() throws {
        let harness = RunHarness("```java\npublic class Main { }\n```\n")
        let block = try harness.firstBlock()
        UIPasteboard.general.string = ""

        harness.coordinator.run(block, from: harness.textView)

        let expected = CodeDestination.request(for: block.code, language: .java)
        #expect(expected.pasteboardCode == block.code)
        #expect(UIPasteboard.general.string == block.code)
        #expect(harness.opened == [expected.url])
    }

    @Test("⌘R from the caret takes the same path")
    func runAtCaret() throws {
        let harness = RunHarness("Intro\n```cpp\nint x;\n```\n")
        let block = try harness.firstBlock()
        harness.textView.selectedRange = NSRange(location: block.range.location + 8, length: 0)

        harness.editor.runBlockAtCaret()

        #expect(harness.opened == [CodeDestination.request(for: block.code, language: .cpp).url])
    }

    @Test("A block whose language can't run opens nothing")
    func untagged() throws {
        let harness = RunHarness("```\nplain\n```\n")
        let block = try harness.firstBlock()
        harness.coordinator.run(block, from: harness.textView)
        #expect(harness.opened.isEmpty)
    }
}

#endif
