#!/usr/bin/env swift
//
//  make-icons.swift
//
//  Draws NoteCode's app icons and writes them, with their Contents.json, into
//  the asset catalog, so the icon can be rebuilt exactly instead of living as
//  PNGs nobody can trace back to a design.
//
//      swift scripts/make-icons.swift [path/to/Assets.xcassets]
//
//  Run from the repository root; the catalog defaults to NoteCode/Assets.xcassets.
//  It rewrites three icon sets and owns everything inside them:
//
//    AppIcon.appiconset         Default, a Dark variant, a Tinted variant and
//                               the macOS slots
//    AppIcon-Paper.appiconset   alternate: white background, dark brackets
//    AppIcon-Orange.appiconset  alternate: orange background, dark pencil
//
//  The geometry is the design's, on a 120 x 120 grid (the Logo board, and
//  `NoteCodeMark` in SettingsView.swift draws the same shapes). The colours
//  are `AppIconChoice`'s in AppSettings.swift, which Settings draws its
//  previews from. They are written twice, so
//  `AppIconTests.scriptAndAppAgreeOnColours` samples the PNGs this script
//  makes against `AppIconChoice`: change a colour here and it fails until the
//  other side follows (and the other way round).
//
//  The system masks the corners, so the art is a full-bleed square. The
//  default, alternate and tinted images are opaque: the App Store rejects a
//  marketing icon with an alpha channel. Only the Dark variant is transparent,
//  per Apple's guidance for dark icons (the system supplies the background).
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Colours

struct RGB {
    let red: Int, green: Int, blue: Int

    init(_ hex: Int) {
        red = (hex >> 16) & 0xFF
        green = (hex >> 8) & 0xFF
        blue = hex & 0xFF
    }

    func cgColor(in space: CGColorSpace) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255, 1])!
    }

    /// Rec. 601 luma, 0...1: the grey the Tinted variant uses, so the pencil
    /// stays darker than the brackets once the system has tinted both.
    var luma: CGFloat {
        (0.299 * CGFloat(red) + 0.587 * CGFloat(green) + 0.114 * CGFloat(blue)) / 255
    }
}

struct Palette {
    let background: RGB?
    let brackets: RGB
    let pencil: RGB
}

let near_black = 0x141416, white = 0xFFFFFF, orange = 0xFA8500

let defaultIcon = Palette(background: RGB(near_black), brackets: RGB(white), pencil: RGB(orange))
let paperIcon   = Palette(background: RGB(white), brackets: RGB(near_black), pencil: RGB(orange))
let orangeIcon  = Palette(background: RGB(orange), brackets: RGB(white), pencil: RGB(near_black))
let darkIcon    = Palette(background: nil, brackets: RGB(white), pencil: RGB(orange))

// MARK: - Drawing

enum Flavour {
    /// sRGB, no alpha channel at all.
    case opaque
    /// sRGB with alpha, for the Dark variant's transparent background.
    case transparent
    /// Greyscale, no alpha, for the Tinted variant.
    case grey
}

func render(_ palette: Palette, pixels: Int, flavour: Flavour) -> CGImage {
    let space: CGColorSpace
    let info: UInt32
    switch flavour {
    case .opaque:      space = CGColorSpace(name: CGColorSpace.sRGB)!;       info = CGImageAlphaInfo.noneSkipLast.rawValue
    case .transparent: space = CGColorSpace(name: CGColorSpace.sRGB)!;       info = CGImageAlphaInfo.premultipliedLast.rawValue
    case .grey:        space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!; info = CGImageAlphaInfo.none.rawValue
    }
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: info)!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    func color(_ rgb: RGB) -> CGColor {
        if flavour == .grey { return CGColor(colorSpace: space, components: [rgb.luma, 1])! }
        return rgb.cgColor(in: space)
    }

    // The grid is y-down (as the design's SVG is); Core Graphics is y-up.
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: CGFloat(pixels) / 120, y: -CGFloat(pixels) / 120)

    if let background = palette.background {
        ctx.setFillColor(color(background))
        ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
    }

    // Brackets: stroke 10, round caps and joins.
    let brackets = CGMutablePath()
    brackets.move(to: CGPoint(x: 38, y: 38))
    brackets.addLine(to: CGPoint(x: 18, y: 60))
    brackets.addLine(to: CGPoint(x: 38, y: 82))
    brackets.move(to: CGPoint(x: 82, y: 38))
    brackets.addLine(to: CGPoint(x: 102, y: 60))
    brackets.addLine(to: CGPoint(x: 82, y: 82))
    ctx.setStrokeColor(color(palette.brackets))
    ctx.setLineWidth(10)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(brackets)
    ctx.strokePath()

    // Pencil: translate(-1 0) rotate(18 60 60), filled and stroked 1.2 in one
    // colour. Body rect 55,38 10x36 rx 2; tip M55 77 H65 L60 89 Z (the 3pt gap
    // between them is the notch).
    ctx.saveGState()
    ctx.translateBy(x: -1, y: 0)
    ctx.translateBy(x: 60, y: 60)
    ctx.rotate(by: 18 * .pi / 180)
    ctx.translateBy(x: -60, y: -60)

    let pencil = CGMutablePath()
    pencil.addRoundedRect(in: CGRect(x: 55, y: 38, width: 10, height: 36), cornerWidth: 2, cornerHeight: 2)
    pencil.move(to: CGPoint(x: 55, y: 77))
    pencil.addLine(to: CGPoint(x: 65, y: 77))
    pencil.addLine(to: CGPoint(x: 60, y: 89))
    pencil.closeSubpath()
    ctx.setFillColor(color(palette.pencil))
    ctx.setStrokeColor(color(palette.pencil))
    ctx.setLineWidth(1.2)
    ctx.setLineJoin(.round)
    ctx.addPath(pencil)
    ctx.drawPath(using: .fillStroke)
    ctx.restoreGState()

    return ctx.makeImage()!
}

// MARK: - Writing

let fileManager = FileManager.default

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot create \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(url.path)") }
}

func writeContents(_ images: [[String: Any]], to directory: URL) {
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let data = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: directory.appendingPathComponent("Contents.json"))
}

/// Empties the set first, so a file this script no longer makes can't linger.
func freshDirectory(_ url: URL) {
    try? fileManager.removeItem(at: url)
    try! fileManager.createDirectory(at: url, withIntermediateDirectories: true)
}

let catalog = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "NoteCode/Assets.xcassets")
guard fileManager.fileExists(atPath: catalog.path) else {
    fatalError("no asset catalog at \(catalog.path); run from the repository root or pass its path")
}

// The Default set: three 1024 images and the macOS slots.
let primary = catalog.appendingPathComponent("AppIcon.appiconset")
freshDirectory(primary)
var primaryImages: [[String: Any]] = []

writePNG(render(defaultIcon, pixels: 1024, flavour: .opaque), to: primary.appendingPathComponent("AppIcon.png"))
primaryImages.append(["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"])

writePNG(render(darkIcon, pixels: 1024, flavour: .transparent), to: primary.appendingPathComponent("AppIcon-Dark.png"))
primaryImages.append([
    "appearances": [["appearance": "luminosity", "value": "dark"]],
    "filename": "AppIcon-Dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
])

// Tinted: the Default's art in grey. The system maps luminance onto the
// reader's tint, so the opaque dark ground becomes the tint's dark.
writePNG(render(defaultIcon, pixels: 1024, flavour: .grey), to: primary.appendingPathComponent("AppIcon-Tinted.png"))
primaryImages.append([
    "appearances": [["appearance": "luminosity", "value": "tinted"]],
    "filename": "AppIcon-Tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
])

// macOS: five sizes at 1x and 2x. Each is drawn at its own pixel size, not
// scaled down from the 1024, so the strokes stay on whole pixels' edges.
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "mac-\(points)@\(scale)x.png"
        writePNG(render(defaultIcon, pixels: points * scale, flavour: .opaque), to: primary.appendingPathComponent(name))
        primaryImages.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
writeContents(primaryImages, to: primary)

// The alternates: one image each, chosen in Settings › General › App Icon.
for (name, palette) in [("AppIcon-Paper", paperIcon), ("AppIcon-Orange", orangeIcon)] {
    let directory = catalog.appendingPathComponent("\(name).appiconset")
    freshDirectory(directory)
    writePNG(render(palette, pixels: 1024, flavour: .opaque), to: directory.appendingPathComponent("\(name).png"))
    writeContents([["filename": "\(name).png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]], to: directory)
}

print("Wrote AppIcon, AppIcon-Paper and AppIcon-Orange into \(catalog.path)")
