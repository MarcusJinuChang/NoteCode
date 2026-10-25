//
//  FolderBadgeRenderTests.swift
//  NoteCodeTests
//
//  The picture on a folder's row, drawn and looked at: a symbol the system
//  doesn't know draws as nothing, with no error, so the names are checked by
//  counting the pixels the symbol leaves on its tint.
//

#if canImport(UIKit)

import SwiftUI
import UIKit
import Testing
@testable import NoteCode

@Suite("Folder badges draw their symbol")
@MainActor
struct FolderBadgeRenderTests {

    /// How many pixels of the badge are the symbol's colour. The tint behind
    /// it is another colour, so a badge with no symbol has none.
    private func symbolPixels(color: FolderColor, symbol: String, isDark: Bool) throws -> Int {
        let diameter: CGFloat = 52
        let renderer = ImageRenderer(
            content: FolderBadge(color: color, symbol: symbol, diameter: diameter)
                .environment(\.colorScheme, isDark ? .dark : .light)
                .frame(width: diameter, height: diameter)
        )
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "nothing rendered")
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)

        let target = color.symbol(isDark: isDark)
        let (r, g, b) = ((target >> 16) & 0xFF, (target >> 8) & 0xFF, target & 0xFF)
        var count = 0
        for pixel in 0..<(width * height) {
            let at = pixel * 4
            guard bytes[at + 3] > 200 else { continue }
            if abs(Int(bytes[at]) - r) < 24, abs(Int(bytes[at + 1]) - g) < 24, abs(Int(bytes[at + 2]) - b) < 24 {
                count += 1
            }
        }
        return count
    }

    @Test("every symbol the editor offers draws, in every colour and both appearances", arguments: FolderSymbol.all)
    func everySymbolDraws(symbol: String) throws {
        for color in FolderColor.allCases {
            for isDark in [false, true] {
                let pixels = try symbolPixels(color: color, symbol: symbol, isDark: isDark)
                #expect(pixels > 30, "\(symbol) in \(color) (dark: \(isDark)) left \(pixels) pixels")
            }
        }
    }

    @Test("the check can see an icon missing: a name the system doesn't know leaves none")
    func missingSymbolIsSeen() throws {
        #expect(try symbolPixels(color: .blue, symbol: "no.such.symbol.name", isDark: false) == 0)
    }

    @Test("a folder stores any name, and shows its own symbol only when it is one the editor offers")
    func unknownStoredNameFallsBack() throws {
        let folder = Folder(name: "x")
        folder.symbolName = "no.such.symbol.name"
        #expect(folder.symbol == FolderSymbol.default)
        #expect(try symbolPixels(color: folder.color, symbol: folder.symbol, isDark: false) > 30)
    }

    @Test("the symbols the list's other rows draw all exist")
    func rowSymbolsExist() {
        for name in ["chevron.right", "lock.fill", "trash", "pin", "pin.slash", "exclamationmark.triangle.fill",
                     "heart", "lightbulb", "envelope", "hand.raised", "gearshape", "ellipsis", "plus"] {
            #expect(UIImage(systemName: name) != nil, "\(name) is not a symbol")
        }
    }
}

#endif
