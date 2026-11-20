//
//  object-system-probe.swift
//
//  Spike for docs/design/object-system.md: can the app own selection, move and
//  recolour of ink objects while PaperKit stays the renderer and the store?
//  Standalone, command-line binary on the iOS 27 simulator:
//
//  PaperKit 27's element API is not on a macOS 26 host, so it is built for the
//  iOS Simulator and spawned there (no app, no UI):
//
//      scripts/spikes/run-object-system-probe.sh
//
//  Each question prints its answer as "Qn ..." so the note can quote it.
//

import Foundation
#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif
import PaperKit
import PencilKit

typealias ElementID = MarkupOrderedSet.ElementID

func time<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
    let start = ContinuousClock.now
    let result = try body()
    let elapsed = ContinuousClock.now - start
    let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    print(String(format: "    %-52@ %8.1f ms", label as NSString, ms))
    return result
}

/// A scribble of `points` control points near `origin`.
func makeStroke(at origin: CGPoint, points: Int = 24, color: PlatformColor = .black) -> PKStroke {
    var controls: [PKStrokePoint] = []
    for i in 0..<points {
        let t = CGFloat(i)
        let location = CGPoint(x: origin.x + t * 3, y: origin.y + sin(t / 3) * 6)
        controls.append(PKStrokePoint(
            location: location, timeOffset: TimeInterval(i) * 0.01,
            size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
    }
    let path = PKStrokePath(controlPoints: controls, creationDate: Date(timeIntervalSince1970: 0))
    return PKStroke(ink: PKInk(.pen, color: color), path: path)
}

func redComponent(_ color: PlatformColor) -> CGFloat {
    var r: CGFloat = -1, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    #if canImport(UIKit)
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    #else
    color.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
    #endif
    return r
}

/// A copy of `stroke` in another colour: same path, transform, mask and seed.
func recolour(_ stroke: PKStroke, _ color: PlatformColor, keepingID: Bool) -> PKStroke {
    var copy = PKStroke(
        ink: PKInk(stroke.ink.inkType, color: color), path: stroke.path,
        transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
    if keepingID { copy.id = stroke.id }
    return copy
}

func makeNote(strokes count: Int) -> PaperMarkup {
    var markup = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 816, height: 10_560))
    var strokes: [any Markup] = []
    strokes.reserveCapacity(count)
    for i in 0..<count {
        let x = CGFloat(i % 40) * 20
        let y = CGFloat(i / 40) * 80
        strokes.append(makeStroke(at: CGPoint(x: x, y: y)))
    }
    markup.subelements.append(contentsOf: strokes)
    return markup
}

@main
struct Probe {
    static func main() async throws {
        print("PaperKit object-system probe, \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // ---------------------------------------------------------------
        print("\nQ1  Does a stroke keep its identity through the edits an object system makes?")
        let original = makeStroke(at: CGPoint(x: 10, y: 10), color: .black)
        var moved = original
        moved.applyTransform(CGAffineTransform(translationX: 50, y: 0))
        print("    after applyTransform:  elementID equal = \(moved.elementID == original.elementID), stroke id equal = \(moved.id == original.id)")
        print("    renderFrame \(original.renderFrame.integral) -> \(moved.renderFrame.integral)")

        let recoloured = recolour(original, .red, keepingID: true)
        print("    recoloured by rebuild with strokeID: elementID equal = \(recoloured.elementID == original.elementID)")
        let recolouredNoID = recolour(original, .red, keepingID: false)
        print("    recoloured by plain rebuild:         elementID equal = \(recolouredNoID.elementID == original.elementID)")

        // ---------------------------------------------------------------
        print("\nQ2  Does updateOrAppend replace a moved or recoloured stroke in place (same z position)?")
        var small = makeNote(strokes: 5)
        let third = small.subelements[2] as! PKStroke
        var thirdMoved = third
        thirdMoved.applyTransform(CGAffineTransform(translationX: 100, y: 100))
        small.subelements.updateOrAppend(thirdMoved)
        print("    count after moved updateOrAppend = \(small.subelements.count) (5 = replaced), index of it = \(small.subelements.firstIndex(of: thirdMoved).map(String.init) ?? "nil") (2 = same z)")
        let thirdRed = recolour(third, .red, keepingID: true)
        small.subelements.updateOrAppend(thirdRed)
        let afterRed = small.subelements[2] as! PKStroke
        print("    after recolour updateOrAppend: count \(small.subelements.count), ink colour at index 2 = \(redComponent(afterRed.ink.color)) red component (1 = recoloured), frame kept \(afterRed.renderFrame.integral == third.renderFrame.integral)")

        // ---------------------------------------------------------------
        print("\nQ3  Can PaperKit be told a stroke may not be selected, and does that persist?")
        var locked = makeStroke(at: .zero)
        print("    default allowedInteractions rawValue = \(locked.allowedInteractions.rawValue)")
        locked.allowedInteractions = []
        var one = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        one.subelements.append(locked)
        let bytes = try await one.dataRepresentation()
        let back = try PaperMarkup(dataRepresentation: bytes)
        let backStroke = back.subelements.first as! PKStroke
        print("    set to [] then saved and read back: rawValue = \(backStroke.allowedInteractions.rawValue) (so it IS stored in the ink bytes: \(backStroke.allowedInteractions.rawValue == 0))")
        var unselectable = makeStroke(at: .zero)
        unselectable.allowedInteractions = [.move, .delete, .style, .resize, .rotate]
        print("    all but .select accepted on a stroke, reads back as rawValue \(unselectable.allowedInteractions.rawValue) (all = \(MarkupInteractions.all.rawValue))")

        // ---------------------------------------------------------------
        for count in [500, 5_000] {
            print("\nQ4  Cost at \(count) strokes (iOS 27 simulator, release build)")
            let note = time("build, one append") { makeNote(strokes: count) }

            // Rectangular select: renderFrame prefilter, then any path point in the rect.
            let rect = CGRect(x: 100, y: 800, width: 300, height: 400)
            var hit: [ElementID] = []
            time("rect select, frame test only (walk with for)") {
                hit = []
                for element in note.subelements where element.renderFrame.intersects(rect) {
                    hit.append(element.elementID)
                }
            }
            var exact = 0
            time("rect select, frame then path points (interpolated)") {
                exact = 0
                for element in note.subelements where element.renderFrame.intersects(rect) {
                    guard let stroke = element as? PKStroke else { continue }
                    var found = false
                    for point in stroke.path.interpolatedPoints(by: .distance(4)) {
                        let p = point.location.applying(stroke.transform)
                        if rect.contains(p) { found = true; break }
                    }
                    if found { exact += 1 }
                }
            }
            print("    frame hits \(hit.count), exact hits \(exact)")

            // Move the selection: three ways of putting transformed copies back.
            let chosen = Set(hit)
            let shift = CGAffineTransform(translationX: 40, y: 30)
            var a = note
            time("move \(chosen.count): updateOrAppend per element") {
                var pending: [any Markup] = []
                for element in note.subelements where chosen.contains(element.elementID) {
                    var copy = element
                    copy.applyTransform(shift)
                    pending.append(copy)
                }
                for copy in pending { a.subelements.updateOrAppend(copy) }
            }
            var b = PaperMarkup(bounds: note.bounds)
            time("move \(chosen.count): rebuild whole set, one append") {
                var all: [any Markup] = []
                all.reserveCapacity(note.subelements.count)
                for element in note.subelements {
                    if chosen.contains(element.elementID) {
                        var copy = element
                        copy.applyTransform(shift)
                        all.append(copy)
                    } else {
                        all.append(element)
                    }
                }
                b.subelements.append(contentsOf: all)
            }
            print("    same result both ways: count \(a.subelements.count) vs \(b.subelements.count)")

            var c = note
            time("delete \(chosen.count): removeElement per element") {
                for id in chosen { _ = c.subelements.removeElement(for: id) }
            }
            print("    count after delete = \(c.subelements.count)")

            // The frame table InkCapture.State.shown already keeps: selecting
            // from it never touches PaperKit's set.
            var table: [ElementID: CGRect] = [:]
            time("build frame table (one walk, done once per capture)") {
                for element in note.subelements { table[element.elementID] = element.renderFrame }
            }
            var fromTable = 0
            time("rect select from the frame table") {
                fromTable = 0
                for (_, frame) in table where frame.intersects(rect) { fromTable += 1 }
            }
            print("    table hits \(fromTable) (= frame hits \(hit.count))")

            var d = PaperMarkup(bounds: note.bounds)
            time("recolour \(chosen.count): rebuild whole set, one append") {
                var all: [any Markup] = []
                all.reserveCapacity(note.subelements.count)
                for element in note.subelements {
                    if chosen.contains(element.elementID), let stroke = element as? PKStroke {
                        all.append(recolour(stroke, .red, keepingID: true))
                    } else {
                        all.append(element)
                    }
                }
                d.subelements.append(contentsOf: all)
            }
            var e = note
            time("translate the whole note (transformContent)") {
                e.transformContent(shift)
            }

            let start = ContinuousClock.now
            let data = try await note.dataRepresentation()
            let elapsed = ContinuousClock.now - start
            print("    save: \(data.count / 1024) KB in \(elapsed)")
        }

        // ---------------------------------------------------------------
        print("\nQ5  A container in Page.drawingData: our header + PaperKit bytes, old bytes still read")
        let note = makeNote(strokes: 50)
        let legacy = try await note.dataRepresentation()
        let wrapped = Container.wrap(objects: Data("{\"v\":1}".utf8), paper: legacy)
        let unwrapped = Container.unwrap(wrapped)
        print("    legacy bytes read as legacy:   \(Container.unwrap(legacy).isLegacy), paper bytes intact = \(Container.unwrap(legacy).paper == legacy)")
        print("    wrapped bytes read as wrapped: \(!unwrapped.isLegacy), paper bytes intact = \(unwrapped.paper == legacy), sidecar = \(String(decoding: unwrapped.objects ?? Data(), as: UTF8.self))")
        print("    PaperKit refuses wrapped bytes (an old build leaves them alone as unreadable): \((try? PaperMarkup(dataRepresentation: wrapped)) == nil)")
        print("    PaperKit accepts legacy bytes: \((try? PaperMarkup(dataRepresentation: legacy)) != nil)")
    }
}

/// `NCOB` + version byte + sidecar length (UInt32 LE) + sidecar JSON + PaperKit bytes.
/// Anything not starting with the magic is a legacy PaperMarkup blob.
enum Container {
    static let magic = Data("NCOB".utf8)

    static func wrap(objects: Data, paper: Data) -> Data {
        var out = magic
        out.append(1)
        var length = UInt32(objects.count).littleEndian
        out.append(Data(bytes: &length, count: 4))
        out.append(objects)
        out.append(paper)
        return out
    }

    static func unwrap(_ data: Data) -> (isLegacy: Bool, objects: Data?, paper: Data) {
        guard data.count >= 9, data.prefix(4) == magic else { return (true, nil, data) }
        let length = Int(data.subdata(in: 5..<9).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
        let start = 9
        guard data.count >= start + length else { return (true, nil, data) }
        return (false, data.subdata(in: start..<start + length), data.subdata(in: (start + length)..<data.count))
    }
}
