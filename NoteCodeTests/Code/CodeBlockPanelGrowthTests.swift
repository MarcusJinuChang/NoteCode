//
//  CodeBlockPanelGrowthTests.swift
//  NoteCodeTests
//
//  A block's panel stays whole when the block grows or shrinks by typing on
//  another line: a paragraph's place in its block is not fixed when TextKit
//  makes its fragment.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Code block panel as the block grows", .tags(.editor))
@MainActor
struct CodeBlockPanelGrowthTests {

    /// Types `text` one key at a time at the end of the note.
    private static func typeKeys(_ text: String, into harness: EditorHarness) {
        for character in text {
            harness.type(String(character), at: (harness.text as NSString).length)
        }
    }

    private static func codeFragments(in harness: EditorHarness) throws -> [CodeBlockLayoutFragment] {
        let manager = try #require(harness.textView.textLayoutManager)
        let content = try #require(manager.textContentManager)
        var fragments: [CodeBlockLayoutFragment] = []
        manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
            if let code = fragment as? CodeBlockLayoutFragment { fragments.append(code) }
            return true
        }
        return fragments
    }

    private static func render(_ view: UIView) -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: view.bounds.size))
            context.cgContext.translateBy(x: -view.bounds.minX, y: -view.bounds.minY)
            view.layer.render(in: context.cgContext)
        }.cgImage!
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    /// The rows of the column at `x`, from `top` to `bottom` in the text
    /// view's coordinates, whose colour isn't the panel's as drawn at `inside`.
    private static func rowsOffPanel(of view: UIView, x: CGFloat, from top: CGFloat, to bottom: CGFloat, inside: CGFloat) -> [Int] {
        let pixels = render(view)
        let width = Int(view.bounds.width * 2)
        func colour(atRow row: Int) -> Int {
            let i = (row * width + Int((x - view.bounds.minX) * 2)) * 4
            return Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])
        }
        let panel = colour(atRow: Int(((inside - view.bounds.minY) * 2).rounded(.down)))
        let rows = Int(((top - view.bounds.minY) * 2).rounded(.down))...Int(((bottom - view.bounds.minY) * 2).rounded(.up))
        return rows.filter { abs(colour(atRow: $0) - panel) > 12 }
    }

    @Test("A block typed as the note's last text draws one panel, the fence joined to the code")
    func typedAtTheEndIsOnePanel() async throws {
        let harness = EditorHarness("")
        Self.typeKeys("```cpp\nint z;", into: harness)
        // As the keyboard leaves it: no layout pass of the page asked for,
        // so a fragment view that isn't redrawn shows what it drew before.
        try await harness.settle()
        try #require(harness.text == "```cpp\nint z;")

        let fragments = try Self.codeFragments(in: harness)
        try #require(fragments.count == 2)
        let (fence, code) = (fragments[0], fragments[1])
        #expect(fence.position == .first)
        #expect(code.position == .last)
        #expect(!fence.closesBlock)

        // On screen: no seam where the fence's panel meets the code's.
        let inset = harness.textView.textContainerInset
        let seam = fence.layoutFragmentFrame.maxY + inset.top
        let x = inset.left + fence.layoutFragmentFrame.minX + harness.textView.textContainer.size.width * 0.55
        let inside = code.layoutFragmentFrame.midY + inset.top
        let off = Self.rowsOffPanel(of: harness.textView, x: x, from: seam - 4, to: seam + 2, inside: inside)
        #expect(off.isEmpty, "rows \(off) around the seam at \(seam) aren't the panel's colour")
    }

    @Test("Deleting the block's last line rounds the fence's bottom again")
    func shrinkingBackRoundsTheFence() async throws {
        let harness = EditorHarness("")
        Self.typeKeys("```cpp\nint z;", into: harness)
        try await harness.settle()
        for _ in 0..<"\nint z;".count {
            harness.textView.selectedRange = NSRange(location: (harness.text as NSString).length, length: 0)
            harness.textView.deleteBackward()
            harness.coordinator.textViewDidChange(harness.textView)
            harness.textView.layoutIfNeeded()
        }
        try await harness.settle()
        harness.layOut()
        try #require(harness.text == "```cpp")

        let fragments = try Self.codeFragments(in: harness)
        try #require(fragments.count == 1)
        #expect(fragments[0].position == .only)
    }
}

#endif
