//
//  HotbarIconPixelTests.swift
//  NoteCode
//
//  The bar's icons as they are drawn, on the bar's own background. The first
//  drawn icons passed every geometry test and were invisible on an iPad unless
//  selected: nothing had ever looked at their pixels.
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@MainActor
@Suite("Hotbar icons are visible")
struct HotbarIconPixelTests {

    /// Roughly what the bar's glass is over a page, per appearance.
    static func bar(_ scheme: ColorScheme) -> UIColor {
        scheme == .dark ? UIColor(red: 0.23, green: 0.23, blue: 0.24, alpha: 1) : UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    }

    /// `content` on the bar's glass, as pixels.
    static func render(_ content: some View, scheme: ColorScheme) -> (data: [UInt8], width: Int, height: Int) {
        // In the bar's own glass, which is where the first drawn icons
        // vanished: out of it they drew fine.
        let view = content
            .frame(width: 44, height: 44)
            .glassEffect(.regular, in: .capsule)
            .padding(8)
            .background(Color(uiColor: bar(scheme)))
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        let host = UIHostingController(rootView: view)
        host.view.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.overrideUserInterfaceStyle = host.view.overrideUserInterfaceStyle
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let drawn = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let image = drawn.cgImage else { return ([], 0, 0) }
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (data, width, height)
    }

    /// How many pixels `content` changes from an empty control on the same
    /// bar, by more than `threshold` in some channel.
    static func visiblePixels(_ content: some View, scheme: ColorScheme, threshold: Double = 0.3) -> Int {
        let with = render(content, scheme: scheme)
        let without = render(Color.clear, scheme: scheme)
        guard with.data.count == without.data.count, !with.data.isEmpty else { return 0 }
        var count = 0
        for pixel in stride(from: 0, to: with.data.count, by: 4) {
            var delta = 0.0
            for channel in 0..<3 {
                delta = max(delta, abs(Double(with.data[pixel + channel]) - Double(without.data[pixel + channel])) / 255)
            }
            if delta > threshold { count += 1 }
        }
        return count
    }

    enum State: CaseIterable { case unselected, selected, disabled }

    @ViewBuilder
    static func button(_ name: String, _ state: State) -> some View {
        switch state {
        case .unselected: HotbarButton("Control", name) {}
        case .selected:   HotbarButton("Control", name, isSelected: true) {}
        case .disabled:   HotbarButton("Control", name) {}.disabled(true)
        }
    }

    static let names = NoteIconTests.names

    @Test("Every drawn control shows its icon on the bar in every state, light and dark",
          arguments: names, [ColorScheme.light, .dark])
    func visible(name: String, scheme: ColorScheme) {
        for state in State.allCases {
            // A disabled control is dimmed to 30%, so it is held to a lower bar.
            let threshold = state == .disabled ? 0.05 : 0.3
            let pixels = Self.visiblePixels(Self.button(name, state), scheme: scheme, threshold: threshold)
            #expect(pixels > 40, "\(name) \(state) \(scheme): \(pixels) pixels")
        }
    }
}

#endif
