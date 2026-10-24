//
//  NoteIconTests.swift
//  NoteCode
//
//  The drawn icons: that each is there, sits on its grid, reads at the
//  hotbar's size, and stands in for the symbol the bar names.
//

import CoreGraphics
import Foundation
import Testing
@testable import NoteCode

@Suite("Drawn icons")
struct NoteIconTests {

    /// Every symbol name the hotbar and its rows hand to `HotbarIcon`.
    static let names = [
        "arrow.uturn.backward", "arrow.uturn.forward", "character.cursor.ibeam", "pencil.and.scribble",
        "pencil.tip", "highlighter", "eraser", "eraser.line.dashed", "scribble.variable", "hand.draw",
        "plus.circle", "plus.circle.dashed", "textformat", "bold", "italic", "underline", "strikethrough",
        "chevron.left.forwardslash.chevron.right", "list.bullet", "curlybraces.square", "text.quote",
        "link", "plus", "minus", "increase.indent", "decrease.indent", "lasso", "rectangle.dashed",
        "checkmark", "slider.horizontal.3", "trash", "plus.square.on.square",
    ]

    @Test("Every symbol the bar names has a drawn icon, and none shares one", arguments: names)
    func mapped(name: String) {
        #expect(NoteIcon.replacing(systemName: name) != nil, "\(name)")
    }

    @Test("Each icon is used for one symbol only")
    func distinct() {
        let icons = Self.names.compactMap { NoteIcon.replacing(systemName: $0) }
        #expect(Set(icons).count == icons.count)
        #expect(Set(icons).count == NoteIcon.allCases.count, "an icon nothing uses, or one the names lack")
    }

    @Test("Every icon has a stroke and stays on its 24-unit grid", arguments: NoteIcon.allCases)
    func onTheGrid(icon: NoteIcon) {
        let layers = icon.layers
        #expect(layers.contains { $0.kind == .stroke })
        let grid = CGRect(x: 0, y: 0, width: 24, height: 24).insetBy(dx: -0.5, dy: -0.5)
        for layer in layers {
            let box = layer.path.boundingBoxOfPath
            #expect(grid.contains(box), "\(icon): \(box)")
        }
    }

    /// How much of a 22-point square an icon inks, drawn as the app draws it.
    private func coverage(_ icon: NoteIcon, weight: IconWeight) -> Double {
        let side = 88, scale = CGFloat(side) / 24
        var data = [UInt8](repeating: 0, count: side * side * 4)
        let context = CGContext(data: &data, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(gray: 0, alpha: 1)); context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        for layer in icon.layers {
            switch layer.kind {
            case .stroke:
                context.setLineWidth(weight.lineWidth * layer.weight); context.setLineCap(.round); context.setLineJoin(.round)
                context.addPath(layer.path); context.strokePath()
            case .solid:
                context.addPath(layer.path); context.fillPath()
            case .soft:
                context.setFillColor(CGColor(gray: 0, alpha: IconLayer.softOpacity))
                context.addPath(layer.path); context.fillPath()
                context.setFillColor(CGColor(gray: 0, alpha: 1))
            }
        }
        let inked = stride(from: 3, to: data.count, by: 4).filter { data[$0] > 128 }.count
        return Double(inked) / Double(side * side)
    }

    @Test("An icon inks enough to read at hotbar size, and not a slab", arguments: NoteIcon.allCases)
    func reads(icon: NoteIcon) {
        let c = coverage(icon, weight: .regular)
        #expect(c > 0.03, "\(icon) \(c)")
        #expect(c < 0.5, "\(icon) \(c)")
    }

    @Test("Heavier weights ink more", arguments: NoteIcon.allCases)
    func weights(icon: NoteIcon) {
        let light = coverage(icon, weight: .light), regular = coverage(icon, weight: .regular), bold = coverage(icon, weight: .bold)
        #expect(light < regular && regular < bold, "\(icon)")
    }

    @Test("The style is one stored string, drawn and regular unless chosen, and Increase Contrast is a step heavier")
    func style() {
        #expect(IconStyle() == IconStyle(rawValue: "drawn.regular"))
        for drawn in [true, false] {
            for weight in IconWeight.allCases {
                let style = IconStyle(isDrawn: drawn, weight: weight)
                #expect(IconStyle(rawValue: style.rawValue) == style)
            }
        }
        #expect(IconStyle(rawValue: "neon.bold") == nil)
        #expect(IconStyle(rawValue: "drawn") == nil)
        #expect(IconStyle(isDrawn: true, weight: .light).increased.weight == .regular)
        #expect(IconStyle(isDrawn: true, weight: .regular).increased.weight == .bold)
        #expect(IconStyle(isDrawn: true, weight: .bold).increased.weight == .bold)
        #expect(IconStyle.defaultsKey == "iconStyle")
    }
}
