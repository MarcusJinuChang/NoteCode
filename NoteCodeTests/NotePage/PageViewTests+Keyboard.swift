//
//  PageViewTests+Keyboard.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

extension PageViewTests {

    @Suite("Keyboard")
    @MainActor
    struct Keyboard: PageViewSuite {

        // MARK: Keyboard

        @Test("The keyboard insets the text view and leaves the page where it was")
        func keyboardInsetsWithoutResizing() throws {
            let harness = PageHarness()
            let page = harness.page
            // A real window fills its screen; the harness's is larger, and frames
            // don't round-trip between a window and a smaller screen.
            harness.window.frame = harness.window.screen.bounds
            page.windowFrameForScreenFrame = { frame, _ in frame }
            page.layoutIfNeeded()

            let before = (page.textView.frame, page.displayScale, page.textView.bounds.size)
            #expect(page.textView.contentInset.bottom == 0)

            // A docked keyboard covering the bottom 300 points of the page's area.
            let window = harness.window
            let areaOnScreen = page.convert(page.bounds, to: window)
            let keyboardTop = areaOnScreen.maxY - 300
            let keyboard = CGRect(x: 0, y: keyboardTop, width: window.bounds.width, height: 400)
            NotificationCenter.default.post(
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                userInfo: [UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: keyboard)]
            )
            page.layoutIfNeeded()

            // The inset is in the text view's own points: the screen distance over the scale.
            #expect(abs(page.textView.contentInset.bottom - 300 / page.displayScale) < 0.5)
            #expect(page.textView.frame == before.0)
            #expect(page.displayScale == before.1)
            #expect(page.textView.bounds.size == before.2)

            // And taken back off when the keyboard goes.
            NotificationCenter.default.post(
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                userInfo: [UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: CGRect(x: 0, y: window.bounds.height, width: window.bounds.width, height: 0))]
            )
            #expect(page.textView.contentInset.bottom == 0)
        }

        @Test("A hotbar docked at the bottom adds its height to what the text keeps clear")
        func keyboardClearanceFollowsTheHotbar() throws {
            let harness = PageHarness()
            let page = harness.page
            harness.window.frame = harness.window.screen.bounds
            page.windowFrameForScreenFrame = { frame, _ in frame }
            page.layoutIfNeeded()

            let window = harness.window
            let areaOnScreen = page.convert(page.bounds, to: window)
            let keyboard = CGRect(x: 0, y: areaOnScreen.maxY - 300, width: window.bounds.width, height: 400)
            NotificationCenter.default.post(
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                userInfo: [UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: keyboard)]
            )
            let bare = page.textView.contentInset.bottom

            // Docking the bar at the bottom while the keyboard is up.
            page.keyboardClearance = 80
            #expect(abs(page.textView.contentInset.bottom - (bare + 80 / page.displayScale)) < 0.5)

            page.keyboardClearance = 0
            #expect(abs(page.textView.contentInset.bottom - bare) < 0.5)
        }

        @Test("The text view clears the code-keys row too: it is part of the keyboard's frame")
        func keyboardInsetIncludesTheCodeKeysRow() throws {
            let harness = PageHarness()
            let page = harness.page
            harness.window.frame = harness.window.screen.bounds
            page.windowFrameForScreenFrame = { frame, _ in frame }
            page.layoutIfNeeded()

            let window = harness.window
            let areaOnScreen = page.convert(page.bounds, to: window)
            func post(_ keyboard: CGRect) {
                NotificationCenter.default.post(
                    name: UIResponder.keyboardWillChangeFrameNotification,
                    object: nil,
                    userInfo: [UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: keyboard)]
                )
            }

            // A keyboard 300pt over the page, as in the tests above; then the
            // row comes onto it, which makes its frame taller and higher by the
            // row's height.
            let bare = CGRect(x: 0, y: areaOnScreen.maxY - 300, width: window.bounds.width, height: 400)
            post(bare)
            let withoutRow = page.textView.contentInset.bottom

            post(CGRect(x: 0, y: bare.minY - CodeKeysRow.height, width: bare.width, height: bare.height + CodeKeysRow.height))
            let withRow = page.textView.contentInset.bottom
            #expect(abs((withRow - withoutRow) - CodeKeysRow.height / page.displayScale) < 0.5)

            // And back, as the caret leaves the code.
            post(bare)
            #expect(abs(page.textView.contentInset.bottom - withoutRow) < 0.5)
        }
    }
}

#endif
