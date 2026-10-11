//
//  AppIconTests.swift
//  NoteCodeTests
//
//  The app icons come from `scripts/make-icons.swift`, and Settings offers
//  the alternates by name and draws each from `AppIconChoice`'s colours.
//  Three things can drift apart without a build noticing: the names Settings
//  hands the system, the icon sets the target declares, and the colours the
//  script drew. These tests tie them together, and check what an upload
//  checks of the art itself.
//

import Foundation
import ImageIO
import Testing
@testable import NoteCode

@Suite("App icon")
struct AppIconTests {

    @Test("A name the system reports maps back to its choice, and an unknown one to the Default")
    func namesRoundTrip() {
        for choice in AppIconChoice.allCases {
            #expect(AppIconChoice(alternateIconName: choice.alternateIconName) == choice)
        }
        #expect(AppIconChoice.standard.alternateIconName == nil)
        #expect(AppIconChoice(alternateIconName: "AppIcon-Neon") == .standard)
        #expect(Set(AppIconChoice.allCases.map(\.title)).count == AppIconChoice.allCases.count)
    }

#if canImport(UIKit)
    @Test("Every alternate Settings offers is one the built app declares")
    func alternatesAreDeclared() throws {
        let icons = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let declared = try #require(icons["CFBundleAlternateIcons"] as? [String: Any])
        let offered = AppIconChoice.allCases.compactMap(\.alternateIconName)
        #expect(Set(declared.keys) == Set(offered))
    }

    // Switching itself isn't unit-tested: iOS puts up a "You have changed the
    // icon" alert and setAlternateIconName waits for someone to tap OK, which
    // hangs an unattended run (found 10 Oct). Settings › General › App Icon is
    // checked by hand, in the simulator and on the iPad.
#endif

    // MARK: The art

    /// Where each choice's 1024 image is in the source catalog.
    private static func source(_ choice: AppIconChoice) -> URL {
        let set = choice == .standard ? "AppIcon" : choice.alternateIconName!
        return catalog.appendingPathComponent("\(set).appiconset/\(set).png")
    }

    private static let catalog = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("NoteCode/Assets.xcassets")

    @Test("Each icon's art is full-bleed in the colours Settings draws it in")
    func scriptAndAppAgreeOnColours() throws {
        // The grid is 120 units over 1024 pixels. Three points that are solid
        // colour whatever the antialiasing: the corner (the background), the
        // left bracket's vertex (18, 60), and the middle of the pencil's body,
        // (60, 56) turned 18 degrees about (60, 60) and shifted 1 left.
        let turn = 18.0 * .pi / 180
        let pencil = (x: 60 + 4 * sin(turn) - 1, y: 60 - 4 * cos(turn))

        for choice in AppIconChoice.allCases {
            let image = try Self.pixels(at: Self.source(choice))
            #expect(image.width == 1024 && image.height == 1024, "\(choice.title)")
            #expect(image.rgb(atGrid: (2, 2)) == choice.background, "\(choice.title) background")
            #expect(image.rgb(atGrid: (18, 60)) == choice.brackets, "\(choice.title) brackets")
            #expect(image.rgb(atGrid: pencil) == choice.pencil, "\(choice.title) pencil")
        }
    }

    @Test("The App Store gets opaque icons, and the Dark variant is the one transparent image")
    func alpha() throws {
        let primary = Self.catalog.appendingPathComponent("AppIcon.appiconset")
        let opaque = AppIconChoice.allCases.map(Self.source) + [primary.appendingPathComponent("AppIcon-Tinted.png")]
        for url in opaque {
            #expect(try Self.properties(of: url).hasAlpha == false, "\(url.lastPathComponent) has an alpha channel")
        }
        let dark = try Self.properties(of: primary.appendingPathComponent("AppIcon-Dark.png"))
        #expect(dark.hasAlpha)
        #expect(dark.alphaAtCorner == 0, "the Dark icon's background should be transparent")
    }

    @Test("The Tinted icon is greyscale, since the system supplies its colour")
    func tintedIsGrey() throws {
        let url = Self.catalog.appendingPathComponent("AppIcon.appiconset/AppIcon-Tinted.png")
        let image = try Self.pixels(at: url)
        for point in [(2.0, 2.0), (18, 60), (60.2, 56.2)] {
            let (r, g, b) = image.channels(atGrid: point)
            #expect(r == g && g == b, "tinted icon has colour at \(point)")
        }
    }

    @Test("Every slot in the Default set has its image, at its size")
    func slotsAreFilled() throws {
        let set = Self.catalog.appendingPathComponent("AppIcon.appiconset")
        let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: set.appendingPathComponent("Contents.json"))) as? [String: Any]
        let images = try #require(contents?["images"] as? [[String: Any]])
        #expect(images.count == 13, "iOS default, dark, tinted and ten macOS sizes")

        for slot in images {
            let file = try #require(slot["filename"] as? String, "a slot has no image: \(slot)")
            let points = try #require((slot["size"] as? String).flatMap { Int($0.split(separator: "x")[0]) })
            let scale = (slot["scale"] as? String).flatMap { Int($0.dropLast()) } ?? 1
            let properties = try Self.properties(of: set.appendingPathComponent(file))
            #expect(properties.pixels == points * scale, "\(file) should be \(points * scale) pixels")
        }
    }

    // MARK: Reading PNGs

    private struct Properties {
        let pixels: Int
        let hasAlpha: Bool
        let alphaAtCorner: UInt8
    }

    private static func properties(of url: URL) throws -> Properties {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "cannot read \(url.lastPathComponent)")
        let info = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let alpha = (info[kCGImagePropertyHasAlpha] as? Bool) ?? false
        let corner = alpha ? try pixels(at: url).rgba(atPixel: (1, 1)).alpha : 255
        return Properties(pixels: image.width, hasAlpha: alpha, alphaAtCorner: corner)
    }

    /// A PNG drawn into sRGB RGBA, so any source colour space reads the same.
    private struct Raster {
        let width: Int, height: Int
        let data: [UInt8]

        func rgba(atPixel point: (Int, Int)) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
            let i = (point.1 * width + point.0) * 4
            return (data[i], data[i + 1], data[i + 2], data[i + 3])
        }

        private func pixel(atGrid point: (Double, Double)) -> (Int, Int) {
            (Int(point.0 / 120 * Double(width)), Int(point.1 / 120 * Double(height)))
        }

        func channels(atGrid point: (Double, Double)) -> (UInt8, UInt8, UInt8) {
            let p = rgba(atPixel: pixel(atGrid: point))
            return (p.red, p.green, p.blue)
        }

        func rgb(atGrid point: (Double, Double)) -> Int {
            let (r, g, b) = channels(atGrid: point)
            return Int(r) << 16 | Int(g) << 8 | Int(b)
        }
    }

    private static func pixels(at url: URL) throws -> Raster {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "cannot read \(url.lastPathComponent)")
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return Raster(width: image.width, height: image.height, data: data)
    }
}
