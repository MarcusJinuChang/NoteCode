// Draws every NoteIcon, at the sizes the hotbar uses and larger, in both
// appearances and three weights, to a PNG:
//   swiftc NoteCode/NoteIconGeometry.swift scripts/icon-sheet/main.swift -o /tmp/icon-sheet
//   /tmp/icon-sheet out.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-sheet.png"
let icons = NoteIcon.allCases
let cell: CGFloat = 76, columns = 9
let rows = Int((Double(icons.count) / Double(columns)).rounded(.up))
let panelHeight = CGFloat(rows) * cell + 30
let width = CGFloat(columns) * cell + 24
let height = panelHeight * 4 + 20

let scale: CGFloat = 2
let context = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.scaleBy(x: scale, y: scale)
context.translateBy(x: 0, y: height); context.scaleBy(x: 1, y: -1)

func draw(_ icon: NoteIcon, in rect: CGRect, weight: IconWeight, color: CGColor) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.minY)
    let s = rect.width / 24
    context.scaleBy(x: s, y: s)
    for layer in icon.layers {
        context.setFillColor(color); context.setStrokeColor(color)
        switch layer.kind {
        case .stroke:
            context.setLineWidth(weight.lineWidth * layer.weight)
            context.setLineCap(.round); context.setLineJoin(.round)
            context.addPath(layer.path); context.strokePath()
        case .solid:
            context.addPath(layer.path); context.fillPath()
        case .soft:
            context.setFillColor(color.copy(alpha: 0.24)!)
            context.addPath(layer.path); context.fillPath()
        }
    }
    context.restoreGState()
}

let panels: [(bg: CGColor, fg: CGColor, weight: IconWeight, size: CGFloat)] = [
    (CGColor(gray: 1, alpha: 1), CGColor(gray: 0.1, alpha: 1), .regular, 22),
    (CGColor(gray: 0, alpha: 1), CGColor(gray: 0.95, alpha: 1), .regular, 22),
    (CGColor(gray: 1, alpha: 1), CGColor(gray: 0.1, alpha: 1), .light, 44),
    (CGColor(gray: 1, alpha: 1), CGColor(gray: 0.1, alpha: 1), .bold, 44),
]
for (n, panel) in panels.enumerated() {
    let top = 10 + CGFloat(n) * panelHeight
    context.setFillColor(panel.bg)
    context.fill(CGRect(x: 0, y: top, width: width, height: panelHeight))
    for (i, icon) in icons.enumerated() {
        let col = i % columns, row = i / columns
        let x = 12 + CGFloat(col) * cell + (cell - panel.size) / 2
        let y = top + 14 + CGFloat(row) * cell + (cell - panel.size) / 2
        draw(icon, in: CGRect(x: x, y: y, width: panel.size, height: panel.size), weight: panel.weight, color: panel.fg)
    }
}
let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("wrote \(output)")
