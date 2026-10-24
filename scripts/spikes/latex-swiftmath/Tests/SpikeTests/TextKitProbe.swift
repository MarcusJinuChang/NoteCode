//
//  TextKitProbe.swift
//  LaTeXSpike
//
//  The questions the design hangs on, asked of a real TextKit 2 UITextView:
//  can a content-storage delegate swap a formula's source for an attachment
//  plus joiners, does the attachment sit on the baseline, how tall is the
//  line, does it take the text's colour, is it crisp, does a line fragment
//  draw it (the PDF's path), and what does a multi-paragraph `$$` block do.
//
//  Two attachment kinds are compared: `.image` (a bitmap through
//  NSTextAttachment.image) and `.view` (an NSTextAttachmentViewProvider whose
//  view is SwiftMath's own MTMathUILabel, which draws vectors).

#if canImport(UIKit)
import Testing
import UIKit
import SwiftMath
@testable import Spike

enum Kind { case image, view }

/// Heights the block swap gives the paragraphs after a block's opening line.
let tinyLine: CGFloat = 1

final class FormulaAttachment: NSTextAttachment {
    let kind: Kind
    let latex: String
    let size: CGFloat
    let display: Bool
    let metrics: FormulaMetrics
    /// Space above and below a display formula, inside the attachment's bounds.
    let gap: CGFloat

    @MainActor init(kind: Kind, latex: String, size: CGFloat, display: Bool, gap: CGFloat = 0) {
        guard case .drawn(let f) = Formula.make(latex: latex, fontSize: size, display: display) else { fatalError("parse \(latex)") }
        self.kind = kind; self.latex = latex; self.size = size; self.display = display; self.metrics = f.metrics; self.gap = gap
        super.init(data: nil, ofType: nil)
        if kind == .image {
            image = f.image(color: .black, scale: 3).withRenderingMode(.alwaysTemplate)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    var box: CGRect { CGRect(x: 0, y: -(metrics.descent + gap), width: ceil(metrics.width), height: ceil(metrics.height) + 2 * gap) }

    nonisolated(unsafe) static var log: [String] = []
    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        Self.log.append("\(display ? "display" : "inline") proposed \(proposedLineFragment) → \(box)")
        return box
    }
    override func viewProvider(for parentView: UIView?, location: any NSTextLocation, textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        guard kind == .view else { return super.viewProvider(for: parentView, location: location, textContainer: textContainer) }
        return FormulaProvider(textAttachment: self, parentView: parentView, textLayoutManager: textContainer?.textLayoutManager, location: location)
    }
}

final class FormulaProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? FormulaAttachment else { return }
        let container = UIView(frame: CGRect(origin: .zero, size: attachment.box.size))
        let label = MTMathUILabel()
        label.displayErrorInline = false
        label.fontSize = attachment.size
        label.labelMode = attachment.display ? .display : .text
        label.textAlignment = .left
        label.latex = attachment.latex
        label.textColor = foreground()
        let fit = label.intrinsicContentSize
        label.frame = CGRect(x: 0, y: attachment.gap, width: fit.width, height: fit.height)
        container.addSubview(label)
        view = container
    }
    /// The run's own colour, read from the text storage at the attachment.
    private func foreground() -> UIColor {
        guard let manager = textLayoutManager, let content = manager.textContentManager as? NSTextContentStorage,
              let storage = content.textStorage else { return .black }
        let offset = content.offset(from: content.documentRange.location, to: location)
        guard offset >= 0, offset < storage.length else { return .black }
        return storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor ?? .black
    }
    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        (textAttachment as? FormulaAttachment)?.box ?? .zero
    }
}

/// Swaps `$…$` in a paragraph, and the lines of a `$$` … `$$` block, for an
/// attachment then joiners: same UTF-16 length, as the real layout delegates do.
@MainActor
final class FormulaSwapper: NSObject, NSTextContentStorageDelegate {
    var kind: Kind = .view
    var size: CGFloat = 17
    var blockGap: CGFloat = 8
    let inline = try! NSRegularExpression(pattern: #"\$([^$\s][^$\n]*?)\$"#)

    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let storage = textContentStorage.textStorage else { return nil }
        let whole = storage.string as NSString
        let text = storage.attributedSubstring(from: range).mutableCopy() as! NSMutableAttributedString
        let line = (text.string as NSString).trimmingCharacters(in: .newlines)

        // A `$$` block: the opening line, source lines, the closing line.
        if let block = blockRole(of: range, in: whole) {
            let attrs = text.attributes(at: 0, effectiveRange: nil)
            let body = NSRange(location: 0, length: (line as NSString).length)
            let joiners = { (n: Int) in String(repeating: "\u{2060}", count: n) }
            switch block {
            case .open(let latex):
                let a = FormulaAttachment(kind: kind, latex: latex, size: size, display: true, gap: blockGap)
                let swapped = NSMutableAttributedString(attachment: a)
                var merged = attrs; merged.removeValue(forKey: .attachment)
                swapped.addAttributes(merged, range: NSRange(location: 0, length: 1))
                swapped.append(NSAttributedString(string: joiners(max(body.length - 1, 0)), attributes: attrs))
                text.replaceCharacters(in: body, with: swapped)
                let style = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                style.alignment = .center
                text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
            case .rest:
                text.replaceCharacters(in: body, with: joiners(body.length))
                let style = NSMutableParagraphStyle()
                style.minimumLineHeight = tinyLine; style.maximumLineHeight = tinyLine
                text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
            }
            return NSTextParagraph(attributedString: text)
        }

        let ns = text.string as NSString
        let matches = inline.matches(in: text.string, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }
        for match in matches.reversed() {
            let a = FormulaAttachment(kind: kind, latex: ns.substring(with: match.range(at: 1)), size: size, display: false)
            let swapped = NSMutableAttributedString(attachment: a)
            var attrs = text.attributes(at: match.range.location, effectiveRange: nil)
            attrs.removeValue(forKey: .attachment)
            swapped.addAttributes(attrs, range: NSRange(location: 0, length: 1))
            swapped.append(NSAttributedString(string: String(repeating: "\u{2060}", count: match.range.length - 1), attributes: attrs))
            text.replaceCharacters(in: match.range, with: swapped)
        }
        return NSTextParagraph(attributedString: text)
    }

    enum Role { case open(String), rest }

    /// A line is in a block when a line that is exactly `$$` above it has a closing `$$` below.
    func blockRole(of range: NSRange, in whole: NSString) -> Role? {
        var lines: [(NSRange, String)] = []
        whole.enumerateSubstrings(in: NSRange(location: 0, length: whole.length), options: .byLines) { s, r, _, _ in lines.append((r, s ?? "")) }
        var i = 0
        while i < lines.count {
            if lines[i].1 == "$$", let close = lines[(i + 1)...].firstIndex(where: { $0.1 == "$$" }) {
                if range.location == lines[i].0.location {
                    let latex = lines[(i + 1)..<close].map(\.1).joined(separator: "\n")
                    return .open(latex)
                }
                if range.location > lines[i].0.location && range.location <= lines[close].0.location { return .rest }
                i = close + 1
            } else { i += 1 }
        }
        return nil
    }
}

@MainActor
struct Harness {
    let view: UITextView
    let swapper = FormulaSwapper()
    let window: UIWindow

    init(text: String, kind: Kind = .view, width: CGFloat = 400, color: UIColor = .black, swapped: Bool = true, size: CGFloat = 17, align: NSTextAlignment = .natural, background: UIColor = .white) {
        view = UITextView(usingTextLayoutManager: true)
        view.frame = CGRect(x: 0, y: 0, width: width, height: 300)
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.backgroundColor = background
        swapper.kind = kind; swapper.size = size
        if swapped { (view.textLayoutManager!.textContentManager as! NSTextContentStorage).delegate = swapper }
        let style = NSMutableParagraphStyle(); style.alignment = align
        view.attributedText = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: style])
        window = UIWindow(frame: view.frame)
        window.addSubview(view)
        window.isHidden = false
        view.layoutIfNeeded()
        view.textLayoutManager!.ensureLayout(for: view.textLayoutManager!.documentRange)
        view.layoutIfNeeded()
        view.textLayoutManager!.textViewportLayoutController.layoutViewport()
    }

    var fragments: [NSTextLayoutFragment] {
        var result: [NSTextLayoutFragment] = []
        let manager = view.textLayoutManager!
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { result.append($0); return true }
        return result
    }

    struct Pixels { var data: [UInt8]; var w: Int; var h: Int; var scale: CGFloat }

    /// The view as pixels, rows from the top, at 4x.
    func pixels() -> Pixels {
        let scale: CGFloat = 4
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
        let cg = image.cgImage!
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Pixels(data: data, w: w, h: h, scale: scale)
    }

    func save(_ name: String) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { ctx in view.layer.render(in: ctx.cgContext) }
        try? image.pngData()?.write(to: out.appendingPathComponent(name))
    }

    func segmentRect(utf16 range: NSRange) -> CGRect {
        let manager = view.textLayoutManager!
        let content = manager.textContentManager as! NSTextContentStorage
        let start = content.location(content.documentRange.location, offsetBy: range.location)!
        let end = content.location(start, offsetBy: range.length)!
        var rect = CGRect.null
        manager.enumerateTextSegments(in: NSTextRange(location: start, end: end)!, type: .standard, options: []) { _, frame, _, _ in rect = rect.union(frame); return true }
        return rect
    }
}

/// Bounds in points of pixels darker (or, on a dark ground, lighter) than the background, within `rect`.
func inkBounds(_ p: Harness.Pixels, in rect: CGRect, background: Int = 255) -> CGRect? {
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    let x0 = max(0, Int(rect.minX * p.scale)), x1 = min(p.w, Int(rect.maxX * p.scale))
    let y0 = max(0, Int(rect.minY * p.scale)), y1 = min(p.h, Int(rect.maxY * p.scale))
    guard x0 < x1, y0 < y1 else { return nil }
    for y in y0..<y1 { for x in x0..<x1 {
        let i = (y * p.w + x) * 4
        let lum = (Int(p.data[i]) + Int(p.data[i + 1]) + Int(p.data[i + 2])) / 3
        if abs(lum - background) > 128 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
    } }
    guard maxX >= 0 else { return nil }
    return CGRect(x: CGFloat(minX) / p.scale, y: CGFloat(minY) / p.scale, width: CGFloat(maxX + 1 - minX) / p.scale, height: CGFloat(maxY + 1 - minY) / p.scale)
}

@Suite("TextKit 2 probe", .serialized) @MainActor
struct TextKitProbe {

    @Test(arguments: [Kind.image, Kind.view])
    func inlineLayout(kind: Kind) throws {
        let src = "HHH $H$ HHH"
        let plain = Harness(text: src, swapped: false)
        let swapped = Harness(text: src, kind: kind)
        let pf = plain.fragments.first!, sf = swapped.fragments.first!
        say("A[\(kind)] inline: plain fragment h=\(pf.layoutFragmentFrame.height) swapped h=\(sf.layoutFragmentFrame.height); line attributedString.length \(sf.textLineFragments[0].attributedString.length) vs source \(src.utf16.count)")
        #expect(sf.textLineFragments[0].attributedString.length == src.utf16.count)
        swapped.save("inline-\(kind).png")
        let p = swapped.pixels()
        let first = inkBounds(p, in: CGRect(x: 0, y: 0, width: 12, height: 40))
        let seg = swapped.segmentRect(utf16: NSRange(location: 4, length: 3))
        let formula = inkBounds(p, in: seg.insetBy(dx: 0, dy: -4))
        say("A[\(kind)]: first 'H' ink \(String(describing: first)); formula segment \(seg); formula ink \(String(describing: formula))")
        let a = try #require(first), b = try #require(formula)
        say(String(format: "A[%@]: baseline delta (formula ink bottom − text ink bottom) = %.2f pt; cap heights text %.2f formula %.2f", "\(kind)", b.maxY - a.maxY, a.height, b.height))
        #expect(abs(b.maxY - a.maxY) < 1.0)
    }

    @Test(arguments: [Kind.image, Kind.view])
    func colour(kind: Kind) throws {
        for (name, colour, bg) in [("red", UIColor(red: 0.9, green: 0.28, blue: 0.3, alpha: 1), UIColor.white), ("white on black", UIColor.white, UIColor.black)] {
            let h = Harness(text: "$\\frac{a}{b}$", kind: kind, color: colour, background: bg)
            let p = h.pixels()
            // the most extreme pixels: the farthest from the background
            let bgLum = bg == .white ? 255 : 0
            var best: (dist: Int, rgb: (Int, Int, Int)) = (0, (0, 0, 0)); var strong = 0
            for i in stride(from: 0, to: p.data.count, by: 4) {
                let r = Int(p.data[i]), g = Int(p.data[i + 1]), b = Int(p.data[i + 2])
                let d = abs((r + g + b) / 3 - bgLum)
                if d > 100 { strong += 1 }
                if d > best.dist { best = (d, (r, g, b)) }
            }
            say("B[\(kind)] colour \(name): \(strong) strongly inked pixels; farthest-from-background pixel rgb \(best.rgb)")
        }
    }

    /// Does the image attachment survive a zoom? Draw the text view into a bigger bitmap by transform and measure edge softness.
    @Test(arguments: [Kind.image, Kind.view])
    func sharpWhenScaled(kind: Kind) throws {
        let h = Harness(text: "$H$", kind: kind)
        let seg = h.segmentRect(utf16: NSRange(location: 0, length: 3))
        func softness(scale: CGFloat) -> Double {
            h.view.transform = CGAffineTransform(scaleX: scale, y: scale)
            // as the app does: raise the content scale factor through the subviews
            func raise(_ v: UIView) { v.contentScaleFactor = 3 * scale; v.subviews.forEach(raise) }
            raise(h.view)
            h.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let size = CGSize(width: 120 * scale, height: 40 * scale)
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                UIColor.white.setFill(); UIRectFill(CGRect(origin: .zero, size: size))
                h.view.layer.render(in: UIGraphicsGetCurrentContext()!)
            }
            let cg = image.cgImage!; let w = cg.width, hh = cg.height
            var data = [UInt8](repeating: 0, count: w * hh * 4)
            let ctx = CGContext(data: &data, width: w, height: hh, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: hh))
            var ink = 0, soft = 0
            for i in stride(from: 0, to: data.count, by: 4) { let l = Int(data[i]); if l < 245 { ink += 1; if l > 10 { soft += 1 } } }
            return Double(soft) / Double(max(ink, 1))
        }
        _ = seg
        let one = softness(scale: 1), four = softness(scale: 4)
        say(String(format: "C[%@] share of soft (anti-aliased) ink pixels: zoom 1x %.3f, zoom 4x %.3f (a bitmap blown up has a wider soft edge, so a higher share at 4x)", "\(kind)", one, four))
    }

    @Test(arguments: [Kind.image, Kind.view])
    func heights(kind: Kind) throws {
        let tall = Harness(text: "a $\\frac{\\sum_{i=1}^{n} i}{n}$ b", kind: kind)
        let plain = Harness(text: "a x b", swapped: false)
        say("D[\(kind)] line heights: plain \(plain.fragments[0].layoutFragmentFrame.height) vs fraction-with-sum \(tall.fragments[0].layoutFragmentFrame.height)")
        let three = Harness(text: "before\nline $x$ with small formula\nafter", kind: kind)
        say("D[\(kind)] small inline formula keeps the line height? " + three.fragments.map { String(format: "%.2f", $0.layoutFragmentFrame.height) }.joined(separator: ", "))
        FormulaAttachment.log = []
        let block = Harness(text: "before\n$$\n\\sum_{i=1}^{n} i\n$$\nafter", kind: kind)
        say("D[\(kind)] attachmentBounds calls: " + FormulaAttachment.log.joined(separator: " ; "))
        block.save("block-\(kind).png")
        say("D[\(kind)] $$ block (before, open, source, close, after) heights " + block.fragments.map { String(format: "%.2f", $0.layoutFragmentFrame.height) }.joined(separator: ", ") + String(format: " | total %.2f", block.fragments.last!.layoutFragmentFrame.maxY))
        if let open = block.fragments.dropFirst().first {
            let line = open.textLineFragments[0]
            var hasAttachment = false
            line.attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: line.attributedString.length)) { v, _, _ in if v != nil { hasAttachment = true } }
            say("D[\(kind)] opening line: attributedString '\(line.attributedString.string.debugDescription)' has attachment \(hasAttachment), typographicBounds \(line.typographicBounds), glyphOrigin \(line.glyphOrigin)")
            let f = FormulaAttachment(kind: kind, latex: "\\sum_{i=1}^{n} i", size: 17, display: true, gap: 8)
            say(String(format: "D[%@] expected opening line ≈ ascent+descent+2·gap = %.2f; got %.2f", "\(kind)", f.metrics.height + 16, open.layoutFragmentFrame.height))
        }
    }

    /// Does a text line fragment draw an attachment when drawn on its own (the PDF and thumbnail path)?
    @Test(arguments: [Kind.image, Kind.view])
    func lineFragmentDrawsAttachment(kind: Kind) throws {
        let h = Harness(text: "$\\frac{a}{b}$", kind: kind)
        let line = h.fragments[0].textLineFragments[0]
        let w = 200, hh = 80
        var data = [UInt8](repeating: 0, count: w * hh * 4)
        let ctx = CGContext(data: &data, width: w, height: hh, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(UIColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: hh))
        ctx.translateBy(x: 0, y: CGFloat(hh)); ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        line.draw(at: CGPoint(x: 10, y: 10), in: ctx)
        UIGraphicsPopContext()
        var ink = 0
        for i in stride(from: 0, to: data.count, by: 4) where Int(data[i]) < 128 { ink += 1 }
        say("E[\(kind)] NSTextLineFragment.draw alone: dark pixels \(ink) (0 = draws nothing, so PDF must draw formulas itself)")
    }
}
#endif
