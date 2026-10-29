//
//  TextSizeTests.swift
//  NoteCodeTests
//
//  Phase 6 of v3: a note's text size. Seven steps, each the system's body size
//  at one Dynamic Type step, kept per note and applied everywhere a note's
//  fonts are read.
//

#if canImport(UIKit)

import PDFKit
import PaperKit
import PencilKit
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("Text size: the fonts")
@MainActor
struct TextSizeFontTests {

    static let categories: [(size: Int, category: UIContentSizeCategory)] = [
        (14, .extraSmall), (15, .small), (16, .medium), (17, .large),
        (19, .extraLarge), (21, .extraExtraLarge), (23, .extraExtraExtraLarge),
    ]

    @Test("The steps are 14, 15, 16, 17, 19, 21 and 23, and 17 is the default")
    func steps() {
        #expect(NoteTypography.sizes == [14, 15, 16, 17, 19, 21, 23])
        #expect(NoteTypography.defaultSize == 17)
        #expect(NoteTypography(bodySize: nil).bodySize == 17)
        #expect(NoteTypography(bodySize: nil) == .standard)
    }

    @Test("Every heading level is bold and smaller than the one above it, at every note size", arguments: [14, 15, 16, 17, 19, 21, 23])
    func headingLevelsDescend(size: Int) {
        let typography = NoteTypography(bodySize: size)
        let fonts = MarkdownFormatting.headingLevels.map { typography.heading(level: $0) }
        for (index, font) in fonts.enumerated() {
            #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold), "level \(index + 1) isn't bold")
            if index > 0 { #expect(font.pointSize < fonts[index - 1].pointSize, "level \(index + 1) isn't smaller than level \(index)") }
        }
    }

    @Test("A stored size that isn't a step becomes the nearest one", arguments: [(13, 14), (18, 17), (20, 19), (40, 23), (0, 14)])
    func snapping(stored: Int, snapped: Int) {
        #expect(NoteTypography(bodySize: stored).bodySize == snapped)
    }

    @Test("Stepping goes one size on, and nowhere past either end")
    func stepping() {
        let standard = NoteTypography.standard
        #expect(standard.size(steppedBy: 1) == 19)
        #expect(standard.size(steppedBy: -1) == 16)
        #expect(NoteTypography(bodySize: 23).size(steppedBy: 1) == nil)
        #expect(NoteTypography(bodySize: 14).size(steppedBy: -1) == nil)
        #expect(NoteTypography(bodySize: 14).size(steppedBy: 1) == 15)
    }

    @Test("Only the default is stored as nothing, so a note nobody resized stays as it was")
    func storedSize() {
        #expect(NoteTypography.standard.storedSize == nil)
        #expect(NoteTypography(bodySize: 19).storedSize == 19)
    }

    @Test("Every font at a size is the system's at that Dynamic Type step, leading and all")
    func fontsMatchThePreferredFonts() {
        for (size, category) in Self.categories {
            let typography = NoteTypography(bodySize: size)
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            let body = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)

            #expect(typography.prose == body, "\(size): body")
            #expect(typography.prose.pointSize == CGFloat(size), "\(size): the step's body size")
            #expect(typography.prose.lineHeight == body.lineHeight, "\(size): line height")
            #expect(typography.prose.leading == body.leading, "\(size): the system's leading, which systemFont(ofSize:) lacks")
            #expect(typography.code.pointSize == (CGFloat(size) * 15 / 17 * 2).rounded() / 2, "\(size): code is 15/17 of the body (step 10)")

            let styles: [UIFont.TextStyle] = [.largeTitle, .title1, .title2, .title3, .headline, .subheadline]
            for (index, style) in styles.enumerated() {
                let heading = typography.heading(level: index + 1)
                let system = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
                #expect(heading.pointSize == system.pointSize, "\(size): heading \(index + 1)")
                #expect(heading.fontDescriptor.symbolicTraits.contains(.traitBold))
            }
        }
    }

    @Test("A note with no size has exactly today's fonts")
    func nilIsToday() {
        let standard = NoteTypography(bodySize: nil)
        #expect(standard.prose == DocumentStyler.proseFont)
        #expect(standard.code == DocumentStyler.codeFont)
        for level in 1...6 {
            #expect(standard.heading(level: level) == DocumentStyler.headingFont(level: level))
        }
        #expect(DocumentStyler.proseFont.pointSize == 17)
        #expect(DocumentStyler.headingFont(level: 1).pointSize == 34)
    }

    @Test("A line number is the code's size scaled down, at any size")
    func lineNumbers() {
        for size in NoteTypography.sizes {
            let typography = NoteTypography(bodySize: size)
            #expect(typography.lineNumber.pointSize == (typography.code.pointSize * 0.85 * 2).rounded() / 2)
        }
        #expect(CodeBlockLayoutFragment.lineNumberFont == NoteTypography.standard.lineNumber)
    }
}

@Suite("Text size: the debug launch option")
struct TextSizeDebugOptionTests {

    @Test("-debug-text-size takes a step, for a seeded note")
    func parses() {
        let options = DebugLaunchOptions.parse(["-debug-note", "pages", "-debug-text-size", "21"])
        #expect(options.textSize == 21)
        #expect(options.problems.isEmpty)
        #expect(options.isActive)
    }

    @Test("A size that isn't a step, or with no note to apply it to, is reported and not ignored")
    func problems() {
        let bad = DebugLaunchOptions.parse(["-debug-note", "pages", "-debug-text-size", "18"])
        #expect(bad.textSize == nil)
        #expect(bad.problems.contains { $0.contains("-debug-text-size") })

        let noNote = DebugLaunchOptions.parse(["-debug-text-size", "19"])
        #expect(noNote.problems.contains { $0.contains("add -debug-note") })
    }
}

@Suite("Text size: styling a note in it")
@MainActor
struct TextSizeStylingTests {

    static let source = "# Title\nBody with **bold** and `code`.\n- item\n\n```cpp\nint x;\n```\n"

    private func font(_ textView: UITextView, at offset: Int) -> UIFont? {
        textView.textStorage.attribute(.font, at: offset, effectiveRange: nil) as? UIFont
    }

    @Test("Prose, headings, code and inline spans take the note's size", arguments: NoteTypography.sizes)
    func stylerUsesTheSize(size: Int) {
        let typography = NoteTypography(bodySize: size)
        let textView = DocumentTextView.makeConfiguredTextView(typography: typography)
        textView.text = Self.source
        DocumentStyler.applyStyling(to: textView, rendered: false, typography: typography)

        let text = Self.source as NSString
        #expect(font(textView, at: 2) == typography.heading(level: 1))
        #expect(font(textView, at: text.range(of: "Body").location) == typography.prose)
        #expect(font(textView, at: text.range(of: "bold").location)?.pointSize == CGFloat(size))
        #expect(font(textView, at: text.range(of: "bold").location)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect(font(textView, at: text.range(of: "code`").location) == UIFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular))
        #expect(font(textView, at: text.range(of: "int x").location) == typography.code)
    }

    @Test("What is typed next takes the size too, in prose, a heading and code")
    func typingAttributesUseTheSize() {
        let typography = NoteTypography(bodySize: 21)
        let textView = DocumentTextView.makeConfiguredTextView(typography: typography)
        textView.text = Self.source
        let source = Self.source.nativeUTF8
        let blocks = DocumentParser.parse(source)
        let text = Self.source as NSString

        func typingFont(at offset: Int) -> UIFont? {
            textView.selectedRange = NSRange(location: offset, length: 0)
            DocumentStyler.applyTypingAttributes(to: textView, source: source, blocks: blocks, typography: typography)
            return textView.typingAttributes[.font] as? UIFont
        }
        #expect(typingFont(at: 3) == typography.heading(level: 1))
        #expect(typingFont(at: text.range(of: "Body").location + 2) == typography.prose)
        #expect(typingFont(at: text.range(of: "int x").location + 2) == typography.code)
    }

    @Test("A list item's hanging indent is the marker's width at the note's size")
    func listIndentFollowsTheSize() {
        let source = "- item\n"
        let block = DocumentParser.parse(source)[0]
        func indent(_ size: Int) -> CGFloat {
            DocumentStyler.listParagraphStyle(for: block, in: source, typography: NoteTypography(bodySize: size)).headIndent
        }
        #expect(indent(23) > indent(17))
        #expect(indent(17) > indent(14))
        // The cache is keyed by size: asking again gives the same widths.
        #expect(indent(23) == indent(23))
        #expect(indent(17) == DocumentStyler.listParagraphStyle(for: block, in: source).headIndent)
    }

    @Test("The coordinator restyles the whole note when the size changes, and back to today's at 17")
    func coordinatorRestyles() {
        let box = PageSettlingTests.Box()
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.delegate = coordinator
        textView.text = Self.source
        coordinator.invalidateStyling()
        coordinator.restyle(textView)
        let before = textView.textStorage.attributedSubstring(from: NSRange(location: 0, length: textView.textStorage.length))

        coordinator.setTypography(NoteTypography(bodySize: 23), in: textView)
        #expect(font(textView, at: 12) == NoteTypography(bodySize: 23).prose)
        #expect(font(textView, at: 2) == NoteTypography(bodySize: 23).heading(level: 1))

        coordinator.setTypography(.standard, in: textView)
        let after = textView.textStorage.attributedSubstring(from: NSRange(location: 0, length: textView.textStorage.length))
        #expect(after.isEqual(to: before), "back at 17, the note is styled exactly as it was")
    }

    @Test("Two notes at two sizes are styled independently in one process")
    func notesDontShareASize() {
        func styled(_ size: Int) -> UIFont? {
            let typography = NoteTypography(bodySize: size)
            let box = PageSettlingTests.Box()
            let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
            let textView = DocumentTextView.makeConfiguredTextView(typography: typography)
            coordinator.setTypography(typography, in: textView)
            textView.text = "plain words"
            coordinator.invalidateStyling()
            coordinator.restyle(textView)
            return font(textView, at: 3)
        }
        let big = styled(23)
        let small = styled(14)
        let again = styled(23)
        #expect(big?.pointSize == 23)
        #expect(small?.pointSize == 14)
        #expect(again?.pointSize == 23)
    }
}

@Suite("Text size: re-flowing keeps the reader's place", .serialized)
@MainActor
struct TextSizeReflowTests {

    static let note = ReopenTests.note

    /// The start of the line holding `character`, with the whole note laid out
    /// from scratch at `size`: a text view that has never shown anything else.
    static func lineStart(containing character: Int, at size: Int, layout: PageLayout) -> Int? {
        let typography = NoteTypography(bodySize: size)
        let box = PageSettlingTests.Box()
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let textView = DocumentTextView.makeConfiguredTextView(typography: typography)
        textView.delegate = coordinator
        textView.textLayoutManager?.delegate = coordinator
        textView.textContainer.size = CGSize(width: layout.textWidth, height: .greatestFiniteMagnitude)
        coordinator.setTypography(typography, in: textView)
        textView.text = note
        coordinator.invalidateStyling()
        coordinator.restyle(textView)
        textView.frame = CGRect(x: 0, y: 0, width: layout.pageSize.width, height: 1100)

        guard let manager = textView.textLayoutManager, let content = manager.textContentManager else { return nil }
        manager.ensureLayout(for: manager.documentRange)
        let documentStart = content.documentRange.location
        var found: Int?
        manager.enumerateTextLayoutFragments(from: documentStart, options: [.ensuresLayout]) { fragment in
            let start = content.offset(from: documentStart, to: fragment.rangeInElement.location)
            for line in fragment.textLineFragments {
                let range = NSRange(location: start + line.characterRange.location, length: line.characterRange.length)
                if NSLocationInRange(character, range) {
                    found = range.location
                    return false
                }
            }
            return true
        }
        return found
    }

    @Test(
        "A size change keeps the line the reader was on at the top, as a note laid out from scratch has it",
        arguments: PageViewMode.allCases, [23, 14]
    )
    func keepsTheTopLine(mode: PageViewMode, size: Int) async throws {
        let layout = PageLayout(mode: mode)
        let opened = await ReopenTests.open(resumingAtPage: nil, layout: layout)
        let (coordinator, page) = (opened.coordinator, opened.page)
        page.textView.contentOffset.y = 4200
        await ReopenTests.layOut(page, over: 0.4)
        let before = try #require(PageSettlingTests.characterAtTop(of: page.textView))
        try #require(before > 1000, "the test should start deep in the note")

        page.reflow { coordinator.setTypography(NoteTypography(bodySize: size), in: page.textView) }
        await ReopenTests.layOut(page, over: 0.8)

        let expected = try #require(Self.lineStart(containing: before, at: size, layout: layout))
        let shown = try #require(PageSettlingTests.characterAtTop(of: page.textView))
        #expect(shown == expected, "\(mode), \(size)pt: the top line starts at \(shown); the line holding the reader's place starts at \(expected)")
        withExtendedLifetime(opened) {}
    }

    @Test("A size change at the top of a note stays at the top")
    func topStaysTop() async throws {
        let opened = await ReopenTests.open(resumingAtPage: nil, layout: PageLayout())
        let (coordinator, page) = (opened.coordinator, opened.page)
        page.reflow { coordinator.setTypography(NoteTypography(bodySize: 21), in: page.textView) }
        await ReopenTests.layOut(page, over: 0.5)
        #expect(page.textView.contentOffset.y == 0, "offset \(page.textView.contentOffset.y), inset \(page.textView.contentInset), top char \(String(describing: page.topLineCharacter()))")
        withExtendedLifetime(opened) {}
    }

    @Test("Larger text makes more pages, and back at 17 the note has the pages it had")
    func largerTextMakesMorePages() async throws {
        let opened = await ReopenTests.open(resumingAtPage: nil, layout: PageLayout())
        let (coordinator, page) = (opened.coordinator, opened.page)
        let pagesAt17 = page.pageCount
        page.reflow { coordinator.setTypography(NoteTypography(bodySize: 23), in: page.textView) }
        await ReopenTests.layOut(page, over: 0.8)
        #expect(page.pageCount > pagesAt17, "\(page.pageCount) pages at 23 against \(pagesAt17) at 17")
        page.reflow { coordinator.setTypography(.standard, in: page.textView) }
        await ReopenTests.layOut(page, over: 0.8)
        #expect(page.pageCount == pagesAt17, "back at 17, the note has the pages it had: \(page.pageCount) against \(pagesAt17)")
        withExtendedLifetime(opened) {}
    }
}

@Suite("Text size: ••• › Text Size, and the question on a note with ink", .serialized)
@MainActor
struct TextSizeEditorTests {

    @MainActor
    final class Harness {
        let editor = NoteEditor()
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        let page: PageView
        let textView = DocumentTextView.makeConfiguredTextView()
        var committed: [Int?] = []

        init(withInk: Bool) {
            page = PageView(textView: textView)
            textView.text = "# Title\nsome words\n"
            page.frame = window.bounds
            window.addSubview(page)
            window.makeKeyAndVisible()
            page.layoutIfNeeded()
            editor.attach(textView, canvas: page.canvas, page: page)
            editor.settleDelay = .milliseconds(20)
            editor.commitTextSize = { [unowned self] size in
                committed.append(size)
            }
            if withInk {
                let points = (0..<10).map { i in
                    PKStrokePoint(
                        location: CGPoint(x: 100 + CGFloat(i) * 10, y: 200), timeOffset: Double(i) * 0.01,
                        size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                    )
                }
                let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
                var markup = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: page.pageLayout.pageSize.width, height: 4000))
                markup.append(contentsOf: PKDrawing(strokes: [stroke]))
                page.setInk(markup)
            }
        }

        func wait() async { try? await Task.sleep(for: .milliseconds(120)) }
    }

    @Test("A note without ink changes once the pause is over")
    func noInkChangesAtOnce() async {
        let harness = Harness(withInk: false)
        harness.editor.setTextSize(19)
        #expect(harness.editor.textSize == 19, "the menu shows the pick straight away")
        #expect(harness.committed.isEmpty, "…and the note catches up after the pause")
        await harness.wait()
        #expect(harness.committed == [19])
    }

    @Test("A run of picks lays the note out once, at the last size")
    func runOfTapsSettlesOnce() async {
        let harness = Harness(withInk: false)
        for size in [19, 21, 23, 21] { harness.editor.setTextSize(size) }
        await harness.wait()
        #expect(harness.committed == [21], "17 → 19 → 21 → 23 → 21 is one change, to 21: \(harness.committed)")
        #expect(harness.editor.textSize == 21)
    }

    @Test("Picks that end where they began change nothing")
    func backToWhereItWas() async {
        let harness = Harness(withInk: false)
        harness.editor.setTextSize(19)
        harness.editor.setTextSize(17)
        await harness.wait()
        #expect(harness.committed.isEmpty)
    }

    @Test("The default is stored as nothing")
    func defaultStoredAsNil() async {
        let harness = Harness(withInk: false)
        harness.editor.syncTextSize(to: 19)
        harness.editor.setTextSize(17)
        await harness.wait()
        #expect(harness.committed.count == 1)
        #expect(harness.committed.first == .some(nil), "17 is nil in the model: \(harness.committed)")
    }

    @Test("A note with ink changes the same way, with no question")
    func inkChangesAtOnce() async {
        let harness = Harness(withInk: true)
        harness.editor.setTextSize(19)
        await harness.wait()

        #expect(harness.committed == [19])
        #expect(harness.editor.textSize == 19)

        harness.editor.syncTextSize(to: 19)
        harness.editor.setTextSize(21)
        await harness.wait()
        #expect(harness.committed == [19, 21])
    }

    @Test("A size change is one undo step, and redo brings it back")
    func sizeUndoes() async {
        let harness = Harness(withInk: true)
        harness.window.makeKeyAndVisible()
        harness.textView.becomeFirstResponder()
        harness.editor.setTextSize(21)
        await harness.wait()
        #expect(harness.committed == [21])

        let undo = harness.textView.undoManager
        #expect(undo?.canUndo == true)
        undo?.undo()
        #expect(harness.committed == [21, nil] as [Int?], "undo goes back to 17, stored as nothing: \(harness.committed)")
        #expect(harness.editor.textSize == 17 && harness.editor.appliedTextSize == 17)
        undo?.redo()
        #expect(harness.committed.last == 21 && harness.editor.appliedTextSize == 21)
    }

    @Test("A line spacing change is one undo step")
    func spacingUndoes() {
        let harness = Harness(withInk: false)
        var committed: [Int?] = []
        harness.editor.commitLineSpacing = { committed.append($0) }
        harness.editor.setLineSpacing(6)
        harness.textView.undoManager?.undo()
        #expect(committed == [6, nil] as [Int?] && harness.editor.appliedLineSpacing == 0)
        harness.textView.undoManager?.redo()
        #expect(committed.last == 6 && harness.editor.appliedLineSpacing == 6)
    }

    @Test("A locked note's text size can't be changed")
    func lockedNote() async {
        let harness = Harness(withInk: false)
        harness.editor.setTextLocked(true)
        harness.editor.setTextSize(19)
        await harness.wait()
        #expect(harness.committed.isEmpty)
        #expect(harness.editor.textSize == 17)
    }

    @Test("Following the note's stored size doesn't undo a pick still in flight")
    func syncWaitsForTheTap() async {
        let harness = Harness(withInk: false)
        harness.editor.setTextSize(19)
        harness.editor.syncTextSize(to: nil)
        #expect(harness.editor.textSize == 19)
        await harness.wait()
        #expect(harness.committed == [19])
    }
}

@Suite("Text size: paper and thumbnails")
@MainActor
struct TextSizePaperTests {

    /// Enough lines that a size's line height shows in the page count: a page
    /// holds 48 lines at 14pt and 41 at 17, so 600 lines are 13 pages and 15.
    static let text = (1...600).map { "Line \($0): the loop invariant holds before and after every iteration gjpqy." }.joined(separator: "\n")

    private func pages(at size: Int?) async throws -> Int {
        let data = await NotePDF.render(NotePDF.Note(
            title: "T", text: Self.text, orientation: .portrait,
            typography: NoteTypography(bodySize: size)
        ))
        return try #require(PDFDocument(data: data)).pageCount
    }

    @Test("The PDF breaks lines and pages at the note's size")
    func pdfUsesTheSize() async throws {
        let small = try await pages(at: 14)
        let standard = try await pages(at: nil)
        let large = try await pages(at: 23)
        #expect(small < standard, "\(small) pages at 14, \(standard) at 17, \(large) at 23")
        #expect(standard < large, "\(standard) pages at 17, \(large) at 23")
        #expect(try await pages(at: 17) == standard, "no size and 17 are the same")
    }

    @Test("A thumbnail is drawn at the note's size")
    func thumbnailUsesTheSize() async throws {
        func png(_ size: Int?) async throws -> Data {
            let source = NoteThumbnail.Source(
                text: Self.text, orientation: .portrait, drawingData: Data(), typography: NoteTypography(bodySize: size)
            )
            return try #require(await NoteThumbnail.render(source)?.pngData())
        }
        let standard = try await png(nil)
        #expect(try await png(23) != standard)
        #expect(try await png(14) != standard)
        #expect(try await png(17) == standard)
    }

    @Test("A resized note's picture has a name of its own, and an untouched note keeps the one it had")
    func cacheNamesFollowTheSize() throws {
        let schema = NoteSchema.current
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let page = Page(title: "A", content: "x")
        context.insert(page)
        try context.save()
        let id = try #require(page.settledID)
        let date = Date(timeIntervalSince1970: 1_791_800_000)

        let plain = try #require(NoteThumbnail.cacheName(for: id, modifiedAt: date))
        let explicit = try #require(NoteThumbnail.cacheName(for: id, modifiedAt: date, typography: .standard))
        let large = try #require(NoteThumbnail.cacheName(for: id, modifiedAt: date, typography: NoteTypography(bodySize: 21)))
        #expect(plain == explicit, "17 adds nothing to the name")
        #expect(large != plain)
        #expect(large.hasSuffix("-t21.png"))
        #expect(NoteThumbnail.owner(ofCacheName: large) == NoteThumbnail.owner(ofCacheName: plain), "the older pictures of the note are found by its owner")
    }
}

#endif
