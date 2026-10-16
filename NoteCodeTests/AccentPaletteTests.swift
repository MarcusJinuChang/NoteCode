//
//  AccentPaletteTests.swift
//  NoteCodeTests
//
//  Roadmap step 9: the accent colour the reader can change.
//

import Foundation
import SwiftUI
import Testing
@testable import NoteCode

#if canImport(UIKit)
import UIKit
#endif

@Suite("Accent colour")
@MainActor
struct AccentPaletteTests {

    private func scratchDefaults() -> UserDefaults {
        let name = "AccentPaletteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: Stored value

    @Test("Nothing stored is the design's orange")
    func defaultIsOrange() {
        let defaults = scratchDefaults()
        #expect(AccentPalette.customHex(in: defaults) == nil)
        #expect(AccentPalette.hex(in: defaults) == 0xFA8500)
    }

    @Test("A stored colour is read back, and orange stored is the default")
    func roundTrip() {
        let defaults = scratchDefaults()
        defaults.set(AccentPalette.string(for: 0x066EE5), forKey: AccentPalette.defaultsKey)
        #expect(AccentPalette.customHex(in: defaults) == 0x066EE5)
        defaults.set(AccentPalette.string(for: 0xFA8500), forKey: AccentPalette.defaultsKey)
        #expect(AccentPalette.customHex(in: defaults) == nil)
    }

    @Test("A value that isn't six hex digits reads as nothing stored",
          arguments: ["", "FA85", "FA85000", "ZZZZZZ", "#FA8500"])
    func badValues(stored: String) {
        let defaults = scratchDefaults()
        defaults.set(stored, forKey: AccentPalette.defaultsKey)
        #expect(AccentPalette.hex(in: defaults) == AccentPalette.defaultHex)
    }

    @Test("The key is pinned: renaming it orphans what a device saved")
    func keyIsStable() {
        #expect(AccentPalette.defaultsKey == "accentColor")
    }

    // MARK: Links stay readable

    private static let chosen = [0xDA101E, 0xEBB000, 0x27A551, 0x066EE5, 0x8E22C3,
                                 0x6C6C70, 0xFFFF00, 0xFFFFFF, 0x000000, 0xFFE9CF, 0x00FFFF]

    @Test("A link is 4.5:1 on the page in both appearances, whatever the accent",
          arguments: chosen, [false, true])
    func linkContrast(hex: Int, isDark: Bool) {
        let page = isDark ? 0x000000 : 0xFFFFFF
        let text = AccentPalette.textHex(for: hex, isDark: isDark)
        let ratio = AccentPalette.contrast(text, page)
        #expect(ratio >= 4.5, "\(String(hex, radix: 16)) \(isDark ? "dark" : "light"): \(ratio):1")
    }

    @Test("The default keeps the design's own pair")
    func defaultPair() {
        #expect(AccentPalette.textHex(for: 0xFA8500, isDark: false) == 0xB85900)
        #expect(AccentPalette.textHex(for: 0xFA8500, isDark: true) == 0xFFAA33)
    }

    @Test("A colour that already reads is left as it is")
    func readableIsUntouched() {
        // Dark blue on white is well over 4.5:1.
        #expect(AccentPalette.textHex(for: 0x0A2A66, isDark: false) == 0x0A2A66)
    }

    @Test("The contrast check can fail: yellow on white is far under 4.5")
    func contrastCanFail() {
        #expect(AccentPalette.contrast(0xFFFF00, 0xFFFFFF) < 1.2)
        #expect(AccentPalette.textHex(for: 0xFFFF00, isDark: false) != 0xFFFF00)
    }

    @Test("White labels stay on the orange and go black on a pale accent")
    func labelOnFill() {
        #expect(!AccentPalette.labelOnFillIsBlack(0xFA8500))
        #expect(!AccentPalette.labelOnFillIsBlack(0x066EE5))
        #expect(AccentPalette.labelOnFillIsBlack(0xFFFF00))
        #expect(AccentPalette.labelOnFillIsBlack(0xFFE9CF))
    }

    // MARK: What the app draws

    @Test("The link colour is read from the stored accent as it is drawn")
    func linkFollowsStore() {
        let key = AccentPalette.defaultsKey
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        func resolved(_ style: UIUserInterfaceStyle) -> [Int] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            DocumentStyler.linkColor.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r, g, b].map { Int(($0 * 255).rounded()) }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(resolved(.light) == [0xB8, 0x59, 0x00])
        #expect(resolved(.dark) == [0xFF, 0xAA, 0x33])

        UserDefaults.standard.set("066EE5", forKey: key)
        let expected = AccentPalette.textHex(for: 0x066EE5, isDark: false)
        #expect(resolved(.light) == [(expected >> 16) & 0xFF, (expected >> 8) & 0xFF, expected & 0xFF])
    }

    @Test("A checked box is filled with the stored accent")
    func checkboxUsesStore() throws {
        let defaults = scratchDefaults()
        defaults.set("066EE5", forKey: AccentPalette.defaultsKey)
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        AccentPalette.drawingColor(in: defaults).getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect([r, g, b].map { Int(($0 * 255).rounded()) } == [0x06, 0x6E, 0xE5])
        #expect(AccentPalette.drawingColor(in: scratchDefaults()).cgColor.alpha == 1)
    }

    // MARK: SwiftUI follows the tint

    /// The centre pixel of a view rendered to an image.
    private func centre<V: View>(of view: V) throws -> [Int] {
        let renderer = ImageRenderer(content: view.frame(width: 20, height: 20))
        renderer.scale = 1
        let image = try #require(renderer.uiImage?.cgImage)
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = (image.height / 2) * context.bytesPerRow + (image.width / 2) * 4
        return [Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2])]
    }

    @Test("`.tint` reaches the tint shape style")
    func tintReachesShapeStyle() throws {
        let blue = Color(hex: 0x066EE5)
        #expect(try centre(of: Rectangle().fill(.tint).tint(blue)) == [0x06, 0x6E, 0xE5])
    }

    /// Why `Color.accent(stored:)` exists: this is the reason nothing in the
    /// app should use `Color.accentColor` for the reader's accent.
    @Test("`.tint` does not reach Color.accentColor, so the app doesn't use it")
    func accentColorIgnoresTint() throws {
        let blue = Color(hex: 0x066EE5)
        #expect(try centre(of: Rectangle().fill(Color.accentColor).tint(blue)) != [0x06, 0x6E, 0xE5])
    }

    @Test("Color.accent(stored:) is the stored colour, or the asset for none")
    func accentFromStored() throws {
        #expect(try centre(of: Rectangle().fill(Color.accent(stored: "066EE5"))) == [0x06, 0x6E, 0xE5])
        #expect(try centre(of: Rectangle().fill(Color.accent(stored: "")))
                == (try centre(of: Rectangle().fill(Color.accentColor))))
    }
}
