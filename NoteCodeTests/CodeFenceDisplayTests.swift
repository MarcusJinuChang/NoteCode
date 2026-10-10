//
//  CodeFenceDisplayTests.swift
//  NoteCodeTests
//
//  A code block shows its backticks while it is being edited and hides them
//  otherwise, without moving a line.
//

#if canImport(UIKit)

import PDFKit
import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("Code fences, away and editing")
@MainActor
struct CodeFenceDisplayTests {

    static let note = "Prose before\n```cpp\nint value = query(gap);\nint other = 2;\n```\nProse after the block\nand more text\n"

    /// A text view wired the way `DocumentTextView` wires it, in its page.
    @MainActor
    final class Harness {
        var stored: String
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 1400))
        let textView = DocumentTextView.makeConfiguredTextView()
        let editor = NoteEditor()
        let page: PageView
        var coordinator: DocumentTextView.Coordinator!

        init(
            _ text: String = CodeFenceDisplayTests.note,
            style: UIUserInterfaceStyle = .light,
            layout: PageLayout = PageLayout(),
            showMarkdown: ShowMarkdown = .whileEditing
        ) {
            stored = text
            page = PageView(textView: textView)
            window.overrideUserInterfaceStyle = style
            coordinator = DocumentTextView.Coordinator(
                text: Binding(get: { [unowned self] in stored }, set: { [unowned self] in stored = $0 })
            )
            coordinator.showMarkdown = showMarkdown
            textView.delegate = coordinator
            textView.textLayoutManager?.delegate = coordinator
            coordinator.observeEdits(of: textView)
            coordinator.attachOverlay(to: textView)
            // As in the app, the bars sit beneath the ink canvas.
            coordinator.keepBars(under: page.canvas)
            textView.text = text
            coordinator.invalidateStyling()
            coordinator.restyle(textView)

            page.pageLayout = layout
            page.frame = CGRect(x: 0, y: 0, width: 872, height: 1200)
            window.addSubview(page)
            window.makeKeyAndVisible()
            editor.attach(textView, canvas: page.canvas, page: page)
            coordinator.connect(editor, to: textView)
            layOut()
        }

        func layOut() {
            for _ in 0..<3 {
                page.setNeedsLayout()
                page.layoutIfNeeded()
                textView.setNeedsLayout()
                textView.layoutIfNeeded()
            }
        }

        /// Puts the caret (or a selection) where a tap or a drag would, and
        /// lets the redraws it asks for happen.
        func select(_ range: NSRange) async throws {
            textView.selectedRange = range
            coordinator.textViewDidChangeSelection(textView)
            try await settle()
        }

        func caret(at offset: Int) async throws {
            try await select(NSRange(location: offset, length: 0))
        }

        func settle() async throws {
            textView.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            textView.layoutIfNeeded()
        }

        var source: NSString { textView.textStorage.string as NSString }

        func offset(of text: String, backwards: Bool = false) -> Int {
            source.range(of: text, options: backwards ? .backwards : []).location
        }

        /// Where a stretch of text is, in the text view's coordinates.
        func rect(of text: String, backwards: Bool = false) -> CGRect {
            let range = source.range(of: text, options: backwards ? .backwards : [])
            let start = textView.position(from: textView.beginningOfDocument, offset: range.location)!
            let end = textView.position(from: start, offset: range.length)!
            return textView.firstRect(for: textView.textRange(from: start, to: end)!)
        }

        /// The part of a line's rect that is surely on the panel: `firstRect`
        /// is a line tall, and a block's end lines have the panel's rounded
        /// corner and its gap to the next line inside that. Clear of the
        /// ring's edge too, which the first pixel mustn't land on.
        func interior(of rect: CGRect) -> CGRect {
            rect.insetBy(dx: 6, dy: 5)
        }

        var languageButton: CodeBlockLanguageButton? {
            textView.subviews.compactMap { $0 as? CodeBlockLanguageButton }.first
        }
    }

    // MARK: Pixels

    static func render(_ view: UIView, scale: CGFloat = 2) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }.cgImage!
    }

    /// Pixels in `rect` that differ from the rect's first pixel: what is
    /// drawn on the panel, text and all.
    static func inkPixels(of view: UIView, in rect: CGRect) -> Int {
        let scale: CGFloat = 2
        // A scroll view renders what is in view: its bounds begin at the offset.
        let rect = rect.offsetBy(dx: -view.bounds.minX, dy: -view.bounds.minY)
        guard let cropped = render(view, scale: scale).cropping(to: CGRect(
            x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale
        )) else { return -1 }
        let pixels = rgba(of: cropped)
        let base = (pixels[0], pixels[1], pixels[2])
        var count = 0
        for i in stride(from: 0, to: pixels.count, by: 4) where (pixels[i], pixels[i + 1], pixels[i + 2]) != base {
            count += 1
        }
        return count
    }

    static func meanColor(of view: UIView, in rect: CGRect) -> (r: Double, g: Double, b: Double) {
        let scale: CGFloat = 2
        let cropped = render(view, scale: scale).cropping(to: CGRect(
            x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale
        ))!
        let pixels = rgba(of: cropped)
        var sums = (r: 0.0, g: 0.0, b: 0.0)
        let count = Double(cropped.width * cropped.height)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sums.r += Double(pixels[i]); sums.g += Double(pixels[i + 1]); sums.b += Double(pixels[i + 2])
        }
        return (sums.r / count, sums.g / count, sums.b / count)
    }

    private static func rgba(of image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    // MARK: Hide glyphs, never lines

    /// Every laid-out line's top and height, in the order the note has them:
    /// where a line is, which is what ink is anchored to.
    static func lineFrames(of textView: UITextView) -> [CGRect] {
        guard let manager = textView.textLayoutManager else { return [] }
        manager.ensureLayout(for: manager.documentRange)
        var frames: [CGRect] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            let origin = fragment.layoutFragmentFrame.origin
            frames.append(fragment.layoutFragmentFrame)
            for line in fragment.textLineFragments {
                frames.append(line.typographicBounds.offsetBy(dx: origin.x, dy: origin.y))
            }
            return true
        }
        return frames
    }

    @Test("Every line sits where it did whether the block is being edited or away",
          arguments: [PageLayout(), PageLayout(mode: .print)])
    func linesDontMove(layout: PageLayout) async throws {
        let harness = Harness(layout: layout)

        try await harness.caret(at: 2)
        #expect(harness.coordinator.fenceVisibility.editing.isEmpty)
        let away = Self.lineFrames(of: harness.textView)

        try await harness.caret(at: harness.offset(of: "int other") + 3)
        #expect(harness.coordinator.fenceVisibility.editing == [0])
        let editing = Self.lineFrames(of: harness.textView)

        harness.editor.setMode(.ink)
        try await harness.settle()
        #expect(harness.coordinator.fenceVisibility.editing.isEmpty)
        let ink = Self.lineFrames(of: harness.textView)

        #expect(away.count > 8)
        #expect(away == editing, "lines moved when the caret went into the block")
        #expect(away == ink, "lines moved when ink mode took the fences away")
    }

    @Test("The measure sees a collapsed fence: without the fence lines the lines below move")
    func collapsingMoves() async throws {
        let withFences = Harness()
        let without = Harness(Self.note.replacingOccurrences(of: "```cpp\n", with: "").replacingOccurrences(of: "```\n", with: ""))
        let a = Self.lineFrames(of: withFences.textView)
        let b = Self.lineFrames(of: without.textView)
        let after = withFences.rect(of: "Prose after").minY
        let afterWithout = without.rect(of: "Prose after").minY
        #expect(a != b)
        #expect(afterWithout < after - 20, "two fence lines are at least two lines")
    }

    // MARK: What's drawn

    @Test("An away block draws no backticks on its closing fence; one being edited does",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func closingFence(style: UIUserInterfaceStyle) async throws {
        let harness = Harness(style: style)
        let fence = harness.interior(of: harness.rect(of: "```", backwards: true))

        try await harness.caret(at: 2)
        let away = Self.inkPixels(of: harness.textView, in: fence)

        try await harness.caret(at: harness.offset(of: "int other") + 3)
        let editing = Self.inkPixels(of: harness.textView, in: fence)

        #expect(editing > 20, "the closing fence should show its backticks, drew \(editing) pixels")
        #expect(away == 0, "the closing fence should draw nothing away, drew \(away) pixels")
    }

    @Test("The code itself is drawn the same, away or not")
    func codeStays() async throws {
        let harness = Harness()
        // A line the caret isn't on, so its pixels are only the glyphs'.
        let code = harness.interior(of: harness.rect(of: "int value = query(gap);"))
        try await harness.caret(at: 2)
        let away = Self.inkPixels(of: harness.textView, in: code)
        try await harness.caret(at: harness.offset(of: "int other") + 3)
        let editing = Self.inkPixels(of: harness.textView, in: code)
        #expect(away > 20)
        #expect(away == editing, "\(away) pixels away, \(editing) editing")
    }

    @Test("Always keeps the fences drawn with the caret elsewhere")
    func always() async throws {
        let harness = Harness(showMarkdown: .always)
        let fence = harness.interior(of: harness.rect(of: "```", backwards: true))
        try await harness.caret(at: 2)
        #expect(Self.inkPixels(of: harness.textView, in: fence) > 20)
        #expect(harness.languageButton?.isHidden != false, "no language button while the markdown shows")
    }

    /// Why the fragment draws its own fences, which the phase brief's
    /// approach (a) would have avoided. Not a test of the app: a record of
    /// what TextKit does, so a later OS that changes it shows up here.
    ///
    /// Measured 10 Oct. A clear foreground rendering attribute hides the
    /// glyphs and lays nothing out, but it follows an edit *around* its range
    /// and not one *inside* it: replacing the tag, which the language menu
    /// does, drew the new text. It would have to be set again after every
    /// edit. (A first spike said it drew nothing different; its rect began
    /// outside the panel's rounded corner, so its first pixel was the page's
    /// and every panel pixel counted as ink.)
    @Test("A clear rendering attribute hides a fence without laying out, until an edit inside it")
    func renderingAttribute() async throws {
        let harness = Harness()
        // Editing, so the fragment draws the fences itself and any change is
        // the attribute's.
        try await harness.caret(at: harness.offset(of: "int other") + 3)
        let manager = try #require(harness.textView.textLayoutManager)
        let content = try #require(manager.textContentManager)
        func range(_ r: NSRange) throws -> NSTextRange {
            let start = try #require(content.location(content.documentRange.location, offsetBy: r.location))
            let end = try #require(content.location(start, offsetBy: r.length))
            return try #require(NSTextRange(location: start, end: end))
        }

        let line = harness.interior(of: harness.rect(of: "```cpp"))
        #expect(Self.inkPixels(of: harness.textView, in: line) > 20, "drawn before")

        var viewportLayouts = 0
        harness.textView.addViewportLayoutObserver { viewportLayouts += 1 }
        let fragments = Self.fragmentIDs(harness.textView)
        manager.setRenderingAttributes([.foregroundColor: UIColor.clear], for: try range(harness.source.range(of: "```cpp\n")))
        Self.redrawAll(in: harness.textView)
        try await harness.settle()
        #expect(Self.inkPixels(of: harness.textView, in: line) == 0, "hidden by the attribute")
        #expect(Self.fragmentIDs(harness.textView) == fragments && viewportLayouts == 0, "and nothing laid out")

        harness.textView.selectedRange = NSRange(location: harness.offset(of: "cpp"), length: 3)
        harness.textView.replace(harness.textView.selectedTextRange!, withText: "python")
        harness.coordinator.textViewDidChange(harness.textView)
        try await harness.caret(at: harness.offset(of: "int other") + 3)
        Self.redrawAll(in: harness.textView)
        try await harness.settle()
        let replaced = harness.interior(of: harness.rect(of: "```python"))
        #expect(Self.inkPixels(of: harness.textView, in: replaced) > 20, "the replaced tag is drawn again")
    }

    private static func fragmentIDs(_ textView: UITextView) -> [ObjectIdentifier] {
        guard let manager = textView.textLayoutManager else { return [] }
        var ids: [ObjectIdentifier] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: []) { fragment in
            ids.append(ObjectIdentifier(fragment))
            return true
        }
        return ids
    }

    private static func redrawAll(in view: UIView) {
        if String(describing: type(of: view)).contains("TextLayoutFragmentView") { view.setNeedsDisplay() }
        view.subviews.forEach(redrawAll)
    }

    // MARK: The ring

    /// A rendered text view, read by the pixel.
    @MainActor
    struct Pixels {
        let width: Int
        let height: Int
        let scale: CGFloat
        private let data: [UInt8]

        init(of view: UIView) {
            let image = CodeFenceDisplayTests.render(view)
            width = image.width
            height = image.height
            scale = 2
            var data = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(
                data: &data, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            self.data = data
        }

        /// The accent is orange: a lot of red, little blue. The panel is grey.
        func isOrange(column x: Int, row y: Int) -> Bool {
            let i = (y * width + x) * 4
            return data[i] > 200 && data[i + 2] < 120
        }

        /// The first column in `columns` (points) with orange in the row at `y` (points).
        func orangeColumn(inRow y: CGFloat, from columns: ClosedRange<CGFloat>) -> Int? {
            let row = Int(y * scale)
            return (Int(columns.lowerBound * scale)...Int(columns.upperBound * scale)).first { isOrange(column: $0, row: row) }
        }
    }

    @Test("The block being edited has a ring in the accent colour along its edge; away it doesn't",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func ring(style: UIUserInterfaceStyle) async throws {
        let harness = Harness(style: style)
        let line = harness.rect(of: "int other = 2;")
        let columns: ClosedRange<CGFloat> = 60...140

        try await harness.caret(at: 2)
        #expect(Pixels(of: harness.textView).orangeColumn(inRow: line.midY, from: columns) == nil, "orange away")

        try await harness.caret(at: harness.offset(of: "int other") + 3)
        let column = Pixels(of: harness.textView).orangeColumn(inRow: line.midY, from: columns)
        #expect(column != nil, "no ring along the block's left edge")
        // The panel's edge, a point or so either side of the text's start.
        if let column {
            #expect(abs(CGFloat(column) / 2 - line.minX) < 8, "ring at \(CGFloat(column) / 2), code starts at \(line.minX)")
        }
    }

    @Test("The ring runs the block's whole height, top to bottom, without a gap",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func ringIsContinuous(style: UIUserInterfaceStyle) async throws {
        let harness = Harness(style: style)
        try await harness.caret(at: harness.offset(of: "int other") + 3)
        let pixels = Pixels(of: harness.textView)
        let line = harness.rect(of: "int other = 2;")
        let column = try #require(pixels.orangeColumn(inRow: line.midY, from: 60...140))

        let top = harness.rect(of: "```cpp").midY
        let bottom = harness.rect(of: "```", backwards: true).midY
        var gaps: [CGFloat] = []
        var y = top
        while y <= bottom {
            let row = Int(y * 2)
            if !(pixels.isOrange(column: column, row: row) || pixels.isOrange(column: column + 1, row: row)
                 || pixels.isOrange(column: column - 1, row: row)) {
                gaps.append(y)
            }
            y += 0.5
        }
        #expect(gaps.isEmpty, "no orange down the left edge at y = \(gaps.prefix(5))")
    }

    @Test("The ring's path is open where the panel continues")
    func ringShape() {
        let panel = CGRect(x: 0, y: 0, width: 100, height: 20)
        let middle = CodeBlockLayoutFragment.ringPath(around: panel, radius: 6, roundsTop: false, roundsBottom: false)
        // Two sides and nothing across: no point of it lies inside the panel.
        #expect(middle.bounds.width > 98)
        #expect(!middle.contains(CGPoint(x: 50, y: 10)))
        #expect(!middle.contains(CGPoint(x: 50, y: 0.5)))

        let only = CodeBlockLayoutFragment.ringPath(around: panel, radius: 6, roundsTop: true, roundsBottom: true)
        #expect(only.bounds.height > 18, "closed all round")
    }

    // MARK: The language name

    @Test("An away block has its language's name where the fence was, aligned with the code")
    func languageButton() async throws {
        let harness = Harness()
        try await harness.caret(at: 2)
        let button = try #require(harness.languageButton)
        #expect(!button.isHidden)
        #expect(button.isEnabled)
        #expect(button.configuration?.title == "C++")

        let fence = harness.rect(of: "```cpp")
        #expect(abs(button.frame.minX + CodeBlockLanguageButton.horizontalInset - fence.minX) < 1.5,
                "the name should start where the fence's glyphs did: button \(button.frame), fence \(fence)")
        #expect(abs(button.frame.midY - fence.midY) < 2, "centred on the fence line: button \(button.frame), fence \(fence)")
        #expect(button.frame.maxX <= (harness.textView.subviews.compactMap { $0 as? CodeBlockActionBar }.first?.frame.minX ?? 0),
                "it stops short of the run and copy buttons")
    }

    @Test("Editing the block takes the language name away and leaves run and copy")
    func languageButtonHidesWhileEditing() async throws {
        let harness = Harness()
        try await harness.caret(at: harness.offset(of: "int other") + 3)
        #expect(harness.languageButton?.isHidden == true)
        let bar = try #require(harness.textView.subviews.compactMap { $0 as? CodeBlockActionBar }.first)
        #expect(!bar.isHidden)
    }

    @Test("A block's name is the tag as typed when the app doesn't know it, and Plain Text when bare")
    func languageNames() async throws {
        let harness = Harness("```rust\nfn main() {}\n```\n```\nplain\n```\n")
        try await harness.caret(at: harness.source.length)
        let buttons = harness.textView.subviews.compactMap { $0 as? CodeBlockLanguageButton }
        #expect(buttons.map { $0.configuration?.title } == ["rust", "Plain Text"])
    }

    @Test("A tap on the name is the button's, not the text view's")
    func tapGoesToTheButton() async throws {
        let harness = Harness()
        try await harness.caret(at: 2)
        let button = try #require(harness.languageButton)
        let overlay = try #require(harness.textView.overlay)
        #expect(overlay.containsInteractiveElement(at: CGPoint(x: button.frame.midX, y: button.frame.midY)))
        #expect(!overlay.containsInteractiveElement(at: CGPoint(x: button.frame.maxX + 40, y: button.frame.midY)))
        let hit = harness.textView.hitTest(CGPoint(x: button.frame.midX, y: button.frame.midY), with: nil)
        #expect(hit === button || hit?.isDescendant(of: button) == true, "hit \(String(describing: hit))")
    }

    @Test("Under the ink canvas, in ink mode the canvas takes the touch")
    func belowTheCanvas() async throws {
        let harness = Harness()
        let button = try #require(harness.languageButton)
        let canvas = harness.page.canvas
        #expect(button.superview === canvas.superview)
        let order = harness.textView.subviews
        let buttonIndex = try #require(order.firstIndex(of: button))
        let canvasIndex = try #require(order.firstIndex(of: canvas))
        #expect(buttonIndex < canvasIndex)
    }

    // MARK: Choosing a language

    @Test("The menu lists the languages and plain text, ticking the block's")
    func menu() async throws {
        let harness = Harness()
        try await harness.caret(at: 2)
        let button = try #require(harness.languageButton)
        let actions = button.choices()
        #expect(actions.map(\.title) == ["C++", "Java", "Python", "Plain Text"])
        #expect(actions.map(\.state) == [.on, .off, .off, .off])
    }

    @Test("Choosing a language rewrites the fence's tag, is undoable, and Run follows")
    func choosing() async throws {
        let harness = Harness()
        try await harness.caret(at: 2)
        let button = try #require(harness.languageButton)
        let python = try #require(button.choices().first { $0.title == "Python" })
        python.performWithSender(nil, target: nil)
        try await harness.settle()

        #expect(harness.stored.hasPrefix("Prose before\n```python\nint value"), "stored: \(harness.stored.prefix(40))")
        #expect(harness.textView.text.hasPrefix("Prose before\n```python\n"))
        #expect(harness.languageButton?.configuration?.title == "Python")
        let target = CodeBlockAction.targets(in: harness.textView.text, blocks: DocumentParser.parse(harness.textView.text))[0]
        #expect(target.language == .python, "Run reads the language from the text")

        harness.textView.undoManager?.undo()
        try await harness.settle()
        #expect(harness.textView.text.hasPrefix("Prose before\n```cpp\n"), "one undo puts the tag back")
        #expect(harness.stored.hasPrefix("Prose before\n```cpp\n"))
    }

    @Test("Plain Text takes the tag off")
    func choosingPlain() async throws {
        let harness = Harness()
        try await harness.caret(at: 2)
        let button = try #require(harness.languageButton)
        let plain = try #require(button.choices().first { $0.title == "Plain Text" })
        plain.performWithSender(nil, target: nil)
        try await harness.settle()
        #expect(harness.textView.text.hasPrefix("Prose before\n```\nint value"))
        #expect(harness.languageButton?.configuration?.title == "Plain Text")
    }

    @Test("A locked note shows the name and changes nothing")
    func locked() async throws {
        let harness = Harness()
        harness.editor.setTextLocked(true)
        try await harness.caret(at: 2)
        let button = try #require(harness.languageButton)
        #expect(!button.isEnabled)
        button.onChoose?(.java)
        #expect(harness.textView.text == Self.note)
    }

    // MARK: Ink mode, edits and unclosed blocks

    @Test("Ink mode puts the language name back; text mode takes it away again")
    func inkMode() async throws {
        let harness = Harness()
        try await harness.caret(at: harness.offset(of: "int other") + 3)
        #expect(harness.languageButton?.isHidden == true)

        harness.editor.setMode(.ink)
        try await harness.settle()
        #expect(harness.languageButton?.isHidden == false)
        #expect(harness.languageButton?.isEnabled == true, "ink mode isn't a lock: the names aren't dimmed")
        let fence = harness.interior(of: harness.rect(of: "```", backwards: true))
        #expect(Self.inkPixels(of: harness.textView, in: fence) == 0)

        harness.editor.setMode(.text)
        try await harness.settle()
        // The selection was where it had been.
        #expect(harness.languageButton?.isHidden == true)
        #expect(Self.inkPixels(of: harness.textView, in: fence) > 20)
    }

    @Test("Typing a fence shows it, and the closing fence, until the caret leaves")
    func typingABlock() async throws {
        let harness = Harness("Intro\n")
        let steps = ["```", "```c", "```cpp", "```cpp\n", "```cpp\nint x;", "```cpp\nint x;\n", "```cpp\nint x;\n```"]
        for step in steps {
            harness.textView.text = "Intro\n" + step
            harness.coordinator.invalidateStyling()
            harness.coordinator.restyle(harness.textView)
            try await harness.caret(at: harness.textView.textStorage.length)
            #expect(harness.coordinator.fenceVisibility.editing == [0], "caret in the block after typing \(step.debugDescription)")
        }
        harness.textView.text += "\nmore"
        harness.coordinator.invalidateStyling()
        harness.coordinator.restyle(harness.textView)
        try await harness.caret(at: harness.textView.textStorage.length)
        #expect(harness.coordinator.fenceVisibility.editing.isEmpty, "the caret left on the line after")
        #expect(harness.languageButton?.isHidden == false)
    }

    @Test("A block pasted in whole, with the caret after it, is away")
    func pastedBlock() async throws {
        let harness = Harness("Intro\n")
        harness.textView.selectedRange = NSRange(location: 6, length: 0)
        harness.textView.insertText("```python\nprint(1)\n```\nafter")
        harness.coordinator.textViewDidChange(harness.textView)
        harness.coordinator.textViewDidChangeSelection(harness.textView)
        try await harness.settle()
        #expect(harness.coordinator.fenceVisibility.editing.isEmpty)
        #expect(harness.languageButton?.configuration?.title == "Python")
    }

    @Test("A block added above moves the one the caret is in, and the ring follows it")
    func blockAbove() async throws {
        let harness = Harness("```java\na\n```\nmiddle\n```cpp\nb\n```\n")
        try await harness.caret(at: harness.offset(of: "b\n"))
        #expect(harness.coordinator.fenceVisibility.editing == [1])

        harness.textView.selectedRange = NSRange(location: 0, length: 0)
        harness.textView.insertText("```python\nz\n```\n")
        harness.coordinator.textViewDidChange(harness.textView)
        harness.coordinator.textViewDidChangeSelection(harness.textView)
        try await harness.caret(at: harness.offset(of: "b\n"))
        #expect(harness.coordinator.fenceVisibility.editing == [2])
    }

    @Test("Moving the caret inside a block doesn't redraw it")
    func caretWithinABlock() async throws {
        let harness = Harness()
        try await harness.caret(at: harness.offset(of: "int value") + 3)
        let state = harness.coordinator.fenceVisibility
        try await harness.caret(at: harness.offset(of: "int other") + 3)
        #expect(harness.coordinator.fenceVisibility == state)
    }
}

// MARK: - Paper

@Suite("Code fences on paper")
@MainActor
struct CodeFencePDFTests {

    @Test("The PDF's text has the code and not the backticks")
    func noBackticks() async throws {
        let text = "Intro line\n```cpp\nint value = 1;\n```\nOutro line\n\n```python\nprint(2)\n```\n"
        let data = await NotePDF.render(NotePDF.Note(title: "Fences", text: text, ink: nil, orientation: .portrait))
        let pdf = try #require(PDFDocument(data: data))
        let printed = pdf.string ?? ""
        #expect(printed.contains("int value = 1;"))
        #expect(printed.contains("print(2)"))
        #expect(printed.contains("Outro line"))
        #expect(!printed.contains("```"), "the PDF printed a fence: \(printed.debugDescription)")
        #expect(!printed.contains("cpp"), "the PDF printed a tag: \(printed.debugDescription)")
    }
}

#endif
