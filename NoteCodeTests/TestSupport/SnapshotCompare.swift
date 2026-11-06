//
//  SnapshotCompare.swift
//  NoteCodeTests
//
//  Rendering checks against a committed reference image, with a tolerance,
//  in the manner of `HotbarIconPixelTests`: a view is drawn in a window and
//  its pixels are read. The references are in `NoteCodeTests/Snapshots/`, drawn
//  on the iPad Pro 13-inch (M5) simulator at 2x; another model or scale draws
//  text a pixel off, so the checks skip themselves elsewhere rather than fail.
//
//  To record or replace them, run the suite with
//  `TEST_RUNNER_NOTECODE_RECORD_SNAPSHOTS=1` set; it writes the images into
//  the source tree and fails each test once, so a recording is never green.
//  Look at the images before committing them.
//

#if canImport(UIKit)

import Testing
import UIKit

/// A drawn view as RGBA bytes.
struct SnapshotPixels {
    var data: [UInt8]
    var width: Int
    var height: Int
}

enum Snapshot {

    /// The model the references were drawn on.
    static let model = "iPad Pro 13-inch (M5)"

    /// A channel differing by more than this (of 255) is a different pixel.
    /// Anti-aliasing and font smoothing move edge pixels by far less than a
    /// colour does, and a missing panel or a misplaced line moves them by far more.
    static let channelTolerance = 24
    /// The fraction of pixels allowed to differ.
    static let pixelTolerance = 0.002

    /// Whether this run is on the model the references come from, which is
    /// known by its screen: the simulator's name is a copy's own in a lane.
    @MainActor static var onReferenceModel: Bool {
        do {
            let screen = UIScreen.main
            return screen.scale == 2 && max(screen.bounds.width, screen.bounds.height) == 1376
                && min(screen.bounds.width, screen.bounds.height) == 1032
        }
    }

    nonisolated static var recording: Bool {
        ProcessInfo.processInfo.environment["NOTECODE_RECORD_SNAPSHOTS"] != nil
    }

    /// `region` of `window`, drawn at 2x.
    @MainActor static func image(of window: UIWindow, region: CGRect) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: region.size, format: format).image { _ in
            window.drawHierarchy(in: CGRect(origin: CGPoint(x: -region.minX, y: -region.minY), size: window.bounds.size),
                                 afterScreenUpdates: true)
        }
    }

    @MainActor static func pixels(of image: UIImage) -> SnapshotPixels {
        guard let cg = image.cgImage else { return SnapshotPixels(data: [], width: 0, height: 0) }
        let width = cg.width, height = cg.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return SnapshotPixels(data: data, width: width, height: height)
    }

    /// The fraction of pixels of `a` that differ from `b`, or 1 when the sizes do.
    static func difference(_ a: SnapshotPixels, _ b: SnapshotPixels) -> Double {
        guard a.width == b.width, a.height == b.height, !a.data.isEmpty else { return 1 }
        var differing = 0
        for pixel in stride(from: 0, to: a.data.count, by: 4) {
            for channel in 0..<4 where abs(Int(a.data[pixel + channel]) - Int(b.data[pixel + channel])) > channelTolerance {
                differing += 1
                break
            }
        }
        return Double(differing) / Double(a.width * a.height)
    }

    static func directory() -> URL {
        TestPaths.repoRoot.appendingPathComponent("NoteCodeTests/Snapshots", isDirectory: true)
    }

    /// Checks `region` of `window` against the reference called `name`.
    @MainActor static func verify(_ window: UIWindow, region: CGRect, named name: String, sourceLocation: SourceLocation = #_sourceLocation) {
        // Off the reference model the text lands a pixel off; skip, as the
        // suite says it does.
        guard recording || onReferenceModel else { return }
        let drawn = image(of: window, region: region)
        let file = directory().appendingPathComponent("\(name).png")

        if recording {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? drawn.pngData()?.write(to: file)
            Issue.record("Recorded \(file.path); look at it, commit it, and run again without recording", sourceLocation: sourceLocation)
            return
        }

        guard let reference = UIImage(contentsOfFile: file.path) else {
            Issue.record("No reference image at \(file.path); record one (see SnapshotCompare.swift)", sourceLocation: sourceLocation)
            return
        }
        let fraction = difference(pixels(of: drawn), pixels(of: reference))
        if fraction > pixelTolerance {
            // What was drawn goes beside the log, for looking at.
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-actual.png")
            try? drawn.pngData()?.write(to: out)
            Issue.record("\(name): \(String(format: "%.2f", fraction * 100))% of pixels differ (allowed \(pixelTolerance * 100)%); drawn: \(out.path)",
                         sourceLocation: sourceLocation)
        }
    }
}

#endif
