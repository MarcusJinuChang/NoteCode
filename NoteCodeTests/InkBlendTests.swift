import Testing
import PaperKit
import PencilKit
import UIKit

@MainActor
@Suite("Highlighter blend (a recorded probe: it prints, it asserts nothing)")
struct ProbeBlendTests {

    static func stroke(type: PKInk.InkType, color: UIColor, width: CGFloat = 20) -> PKStroke {
        let points = (0..<40).map { i in
            PKStrokePoint(location: CGPoint(x: 20 + CGFloat(i) * 5, y: 50), timeOffset: Double(i) * 0.01,
                          size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(type, color: color), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    static func pixel(backdrop: UIColor, type: PKInk.InkType, color: UIColor) async -> [Int] {
        var markup = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 300, height: 100))
        markup.subelements.updateOrAppend(stroke(type: type, color: color))
        let context = CGContext(data: nil, width: 300, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(backdrop.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 100))
        context.translateBy(x: 0, y: 100)
        context.scaleBy(x: 1, y: -1)
        await markup.draw(in: context, frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        let image = context.makeImage()!
        var px = [UInt8](repeating: 0, count: 4)
        let one = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        one.draw(image, in: CGRect(x: -150, y: -(100 - 50 - 1), width: 300, height: 100))
        return px.map(Int.init)
    }

    @Test("probe")
    func probe() async {
        let yellow = UIColor(red: 0xFC / 255.0, green: 0xDD / 255.0, blue: 0x79 / 255.0, alpha: 1)
        let backs: [(String, UIColor)] = [("white", UIColor(white: 1, alpha: 1)),
                                          ("panel", UIColor(red: 0xF2 / 255.0, green: 0xF2 / 255.0, blue: 0xF7 / 255.0, alpha: 1)),
                                          ("black", .black),
                                          ("darkpanel", UIColor(red: 0x1C / 255.0, green: 0x1C / 255.0, blue: 0x1E / 255.0, alpha: 1))]
        for (name, back) in backs {
            for type in [PKInk.InkType.marker, .pen, .monoline] {
                let p = await Self.pixel(backdrop: back, type: type, color: yellow)
                print("PROBE \(type) on \(name): \(p)")
            }
        }
        // And the colour with half alpha as a pen
        let half = yellow.withAlphaComponent(0.5)
        for (name, back) in backs {
            let p = await Self.pixel(backdrop: back, type: .pen, color: half)
            print("PROBE pen alpha.5 on \(name): \(p)")
        }
    }
}
