//
//  CodeBlockActionBarTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Where the run and copy buttons sit")
@MainActor
struct CodeBlockActionBarTests {

    /// The editor's real code line height — see CodeBlockPanelTests.
    private static let lineHeight: CGFloat = 20.021484375

    /// The first line of a code block on a 13-inch iPad in portrait: the panel
    /// spans the text container, and the fence line starts at the left inset.
    private static let firstLine = CGRect(x: 8, y: 12, width: 500, height: lineHeight)
    private static let panelRight: CGFloat = 816

    private static func frame(showsRun: Bool = true) -> CGRect {
        CodeBlockActionBar.frame(
            size: showsRun ? CodeBlockActionBar.size : CodeBlockActionBar.copyOnlySize,
            panelRight: panelRight,
            lineFrame: firstLine
        )
    }

    @Test("Copy ends one margin short of the panel's right edge")
    func rightAligned() {
        #expect(Self.frame().maxX == Self.panelRight - CodeBlockActionBar.margin)
    }

    /// The buttons align with the panel, not with the text. The fence line's
    /// glyphs stop after the language tag, so aligning to them would leave the
    /// bar floating in the middle of the block.
    @Test("The bar is placed against the panel, not against the glyphs")
    func ignoresTextWidth() {
        let shortLine = Self.firstLine
        let longLine = CGRect(x: 8, y: 12, width: 40, height: Self.lineHeight)

        let short = CodeBlockActionBar.frame(
            size: CodeBlockActionBar.size, panelRight: Self.panelRight, lineFrame: shortLine
        )
        let long = CodeBlockActionBar.frame(
            size: CodeBlockActionBar.size, panelRight: Self.panelRight, lineFrame: longLine
        )

        #expect(short.origin.x == long.origin.x)
    }

    @Test("The bar centres on the first line")
    func verticallyCentred() {
        #expect(Self.frame().midY == Self.firstLine.midY)
    }

    /// Overhang is deliberate: a bar sized to the 20pt line would be too small
    /// to hit. It is invisible because the panel behind it is one flat colour.
    @Test("The bar is taller than the line it sits on, symmetrically")
    func overhangsEvenly() {
        let bar = Self.frame()

        #expect(bar.height > Self.firstLine.height)
        let top = Self.firstLine.minY - bar.minY
        let bottom = bar.maxY - Self.firstLine.maxY
        #expect(abs(top - bottom) < 0.001)
    }

    @Test("Dropping the run button keeps copy in the same place")
    func copyDoesNotMoveWhenRunIsHidden() {
        #expect(Self.frame(showsRun: false).maxX == Self.frame(showsRun: true).maxX)
        #expect(Self.frame(showsRun: false).width == CodeBlockActionBar.buttonSide)
    }

    @Test("The bar stays inside the panel")
    func staysWithinThePanel() {
        let bar = Self.frame()

        #expect(bar.maxX < Self.panelRight)
        #expect(bar.minX > Self.firstLine.minX)
    }

    /// A scrolled block's line arrives with a different origin and nothing else
    /// changes, so the bar has to move exactly as far as the text did.
    @Test("The bar follows its line down the page", arguments: [0.0, 240.0, 1_980.5] as [CGFloat])
    func tracksTheLine(offset: CGFloat) {
        let moved = Self.firstLine.offsetBy(dx: 0, dy: offset)
        let bar = CodeBlockActionBar.frame(
            size: CodeBlockActionBar.size, panelRight: Self.panelRight, lineFrame: moved
        )

        #expect(bar.midY == moved.midY)
        #expect(bar.origin.x == Self.frame().origin.x)
    }

    // MARK: The view itself

    @Test("A block with no language gets copy but no run")
    func runIsHiddenWithoutALanguage() {
        let bar = CodeBlockActionBar(frame: .zero)
        bar.configure(showsRun: false)

        let buttons = bar.subviews
            .flatMap(\.subviews)
            .compactMap { $0 as? UIButton }

        #expect(buttons.count == 2)
        #expect(buttons.filter { !$0.isHidden }.count == 1)
        #expect(buttons.first { !$0.isHidden }?.accessibilityLabel == "Copy code block")
    }

    @Test("Both buttons say what they do")
    func buttonsAreLabelled() {
        let bar = CodeBlockActionBar(frame: .zero)
        bar.configure(showsRun: true)

        let labels = bar.subviews
            .flatMap(\.subviews)
            .compactMap { ($0 as? UIButton)?.accessibilityLabel }

        #expect(labels == ["Run code block", "Copy code block"])
    }

    @Test("Tapping a button runs its action")
    func tapsFireTheirActions() {
        let bar = CodeBlockActionBar(frame: .zero)
        var ran = false
        var copied = false
        bar.onRun = { ran = true }
        bar.onCopy = { copied = true }

        let buttons = bar.subviews.flatMap(\.subviews).compactMap { $0 as? UIButton }
        for button in buttons {
            button.sendActions(for: .touchUpInside)
        }

        #expect(ran)
        #expect(copied)
    }
}

#endif
