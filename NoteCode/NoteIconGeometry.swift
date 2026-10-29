//
//  NoteIconGeometry.swift
//  NoteCode
//
//  The app's own tool icons, as paths on a 24-unit grid. Pure CoreGraphics,
//  so a Mac command-line sheet (scripts/icon-sheet) draws exactly what the app
//  draws, and a test can read them without a view.
//

import CoreGraphics
import Foundation

/// How heavy the strokes are. Per device (`IconStyle`).
nonisolated enum IconWeight: String, CaseIterable, Sendable {
    case light, regular, bold

    /// A stroke's width on the 24-unit grid.
    var lineWidth: CGFloat {
        switch self {
        case .light:   1.5
        case .regular: 1.8
        case .bold:    2.2
        }
    }
}

/// One layer of an icon.
nonisolated struct IconLayer {
    enum Kind {
        /// A line of the icon's weight, in the icon's colour.
        case stroke
        /// A solid shape in the icon's colour (a bullet, an arrowhead).
        case solid
        /// A soft fill in the icon's colour: the icon's second tone, so an
        /// icon reads in two weights, as SF Symbols' hierarchical ones do.
        case soft
    }

    /// How strong a `soft` layer is.
    static let softOpacity: CGFloat = 0.24

    var path: CGPath
    var kind: Kind
    /// Multiplies the weight, for the letters that are bold.
    var weight: CGFloat = 1
}

/// The hotbar's and the options rows' icons. The glyphs inside menus (a menu
/// item's `Label`) are still SF Symbols.
nonisolated enum NoteIcon: String, CaseIterable, Sendable {
    case undo, redo
    case text, draw
    case pen, highlighter, eraser, pixelEraser, objectEraser
    case fingerDraws, insert, addColour
    case style, bold, italic, underline, strikethrough, inlineCode
    case list, codeBlock, quote, link
    case plus, minus, indent, outdent
    case selectLasso, selectRectangle, done, adjust, delete, duplicate
    /// The note window's joined control: the list, and Home (W3).
    case sidebar, home

    /// The SF Symbol each stands in for, so a call site that names a symbol
    /// gets the drawn icon without being rewritten.
    static func replacing(systemName: String) -> NoteIcon? {
        switch systemName {
        case "arrow.uturn.backward": .undo
        case "arrow.uturn.forward": .redo
        case "textformat.alt", "character.cursor.ibeam": .text
        case "pencil.and.scribble": .draw
        case "pencil.tip": .pen
        case "highlighter": .highlighter
        case "eraser": .eraser
        case "eraser.line.dashed": .pixelEraser
        case "scribble.variable": .objectEraser
        case "hand.draw", "hand.draw.fill": .fingerDraws
        case "plus.circle": .insert
        case "plus.square.on.square": .duplicate
        case "lasso": .selectLasso
        case "rectangle.dashed": .selectRectangle
        case "checkmark": .done
        case "slider.horizontal.3": .adjust
        case "trash": .delete
        case "plus.circle.dashed": .addColour
        case "textformat": .style
        case "bold": .bold
        case "italic": .italic
        case "underline": .underline
        case "strikethrough": .strikethrough
        case "chevron.left.forwardslash.chevron.right": .inlineCode
        case "list.bullet": .list
        case "curlybraces.square": .codeBlock
        case "text.quote": .quote
        case "link": .link
        case "plus": .plus
        case "minus": .minus
        case "increase.indent": .indent
        case "decrease.indent": .outdent
        case "sidebar.left": .sidebar
        case "house": .home
        default: nil
        }
    }

    var layers: [IconLayer] { Self.build(self) }
}

// MARK: - Drawing

private nonisolated enum G {

    static func path(_ build: (CGMutablePath) -> Void) -> CGPath {
        let path = CGMutablePath()
        build(path)
        return path
    }

    static func line(_ points: CGPoint...) -> CGPath {
        path { p in
            p.move(to: points[0])
            for point in points.dropFirst() { p.addLine(to: point) }
        }
    }

    static func polygon(_ points: CGPoint...) -> CGPath {
        path { p in
            p.move(to: points[0])
            for point in points.dropFirst() { p.addLine(to: point) }
            p.closeSubpath()
        }
    }

    static func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    static func circle(_ centre: CGPoint, _ radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2), transform: nil)
    }

    static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// `path` turned `degrees` about the origin and moved to `origin`: for
    /// the diagonal tools, drawn along the x axis.
    static func placed(_ path: CGPath, at origin: CGPoint, turned degrees: CGFloat) -> CGPath {
        var t = CGAffineTransform(translationX: origin.x, y: origin.y).rotated(by: degrees * .pi / 180)
        return path.copy(using: &t) ?? path
    }

    static func mirrored(_ path: CGPath) -> CGPath {
        var t = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 24, ty: 0)
        return path.copy(using: &t) ?? path
    }

    /// A tool lying along +x with its tip at the origin, then turned to point
    /// down and left.
    static func diagonal(_ build: (CGMutablePath) -> Void, tip: CGPoint) -> CGPath {
        placed(path(build), at: tip, turned: -45)
    }
}

nonisolated extension NoteIcon {

    fileprivate static func build(_ icon: NoteIcon) -> [IconLayer] {
        typealias L = IconLayer
        let p = G.p
        switch icon {

        case .undo:
            return [L(path: G.path { s in
                s.move(to: p(9.5, 6.5)); s.addLine(to: p(5, 11)); s.addLine(to: p(9.5, 15.5))
                s.move(to: p(5.5, 11)); s.addLine(to: p(14, 11))
                s.addCurve(to: p(14, 19), control1: p(19.2, 11), control2: p(19.2, 19))
                s.addLine(to: p(9, 19))
            }, kind: .stroke)]
        case .redo:
            return NoteIcon.undo.layers.map { L(path: G.mirrored($0.path), kind: $0.kind, weight: $0.weight) }

        case .text:
            return [
                L(path: G.line(p(8, 4.6), p(8, 19.4)), kind: .stroke),
                L(path: G.line(p(5.4, 4.6), p(10.6, 4.6)), kind: .stroke),
                L(path: G.line(p(5.4, 19.4), p(10.6, 19.4)), kind: .stroke),
                L(path: G.line(p(14, 8.5), p(21, 8.5)), kind: .stroke),
                L(path: G.line(p(14, 12.5), p(21, 12.5)), kind: .stroke),
                L(path: G.line(p(14, 16.5), p(18.5, 16.5)), kind: .stroke),
            ]

        case .draw:
            let body = G.diagonal({ s in
                s.move(to: p(0, 0)); s.addLine(to: p(3.4, -2)); s.addLine(to: p(13, -2))
                s.addLine(to: p(13, 2)); s.addLine(to: p(3.4, 2)); s.closeSubpath()
            }, tip: p(6.5, 15.5))
            let tipFill = G.diagonal({ s in
                s.move(to: p(0, 0)); s.addLine(to: p(3.4, -2)); s.addLine(to: p(3.4, 2)); s.closeSubpath()
            }, tip: p(6.5, 15.5))
            let band = G.placed(G.line(p(10.6, -2), p(10.6, 2)), at: p(6.5, 15.5), turned: -45)
            return [
                L(path: tipFill, kind: .soft),
                L(path: body, kind: .stroke),
                L(path: band, kind: .stroke),
                L(path: G.path { s in
                    s.move(to: p(3.5, 20.5))
                    s.addCurve(to: p(10.5, 19.5), control1: p(6, 17.5), control2: p(7, 22.5))
                    s.addCurve(to: p(17, 20.5), control1: p(13, 17), control2: p(14.5, 22))
                }, kind: .stroke),
            ]

        case .pen:
            return [
                L(path: G.path { s in
                    s.move(to: p(12, 21)); s.addLine(to: p(7.6, 11))
                    s.addCurve(to: p(12, 3), control1: p(7.6, 7.6), control2: p(10.2, 5))
                    s.addCurve(to: p(16.4, 11), control1: p(13.8, 5), control2: p(16.4, 7.6))
                    s.closeSubpath()
                }, kind: .soft),
                L(path: G.path { s in
                    s.move(to: p(12, 21)); s.addLine(to: p(7.6, 11))
                    s.addCurve(to: p(12, 3), control1: p(7.6, 7.6), control2: p(10.2, 5))
                    s.addCurve(to: p(16.4, 11), control1: p(13.8, 5), control2: p(16.4, 7.6))
                    s.closeSubpath()
                }, kind: .stroke),
                L(path: G.line(p(12, 21), p(12, 13)), kind: .stroke),
                L(path: G.circle(p(12, 10.4), 1.5), kind: .stroke),
            ]

        case .highlighter:
            let body = G.diagonal({ s in
                s.move(to: p(0, 2.2)); s.addLine(to: p(3.6, -2.8)); s.addLine(to: p(14, -2.8))
                s.addLine(to: p(14, 2.8)); s.addLine(to: p(3.6, 2.8)); s.closeSubpath()
            }, tip: p(5.6, 17))
            let nib = G.diagonal({ s in
                s.move(to: p(0, 2.2)); s.addLine(to: p(3.6, -2.8)); s.addLine(to: p(3.6, 2.8)); s.closeSubpath()
            }, tip: p(5.6, 17))
            let band = G.placed(G.line(p(9.4, -2.8), p(9.4, 2.8)), at: p(5.6, 17), turned: -45)
            return [
                L(path: nib, kind: .soft),
                L(path: body, kind: .stroke),
                L(path: band, kind: .stroke),
                L(path: G.line(p(3.2, 21), p(10.4, 21)), kind: .stroke),
            ]

        case .eraser:
            let block = G.placed(G.rounded(CGRect(x: -7.5, y: -4.2, width: 15, height: 8.4), 2.4), at: p(11.6, 12.2), turned: -45)
            let rubber = G.placed(G.rounded(CGRect(x: -7.5, y: -4.2, width: 6.2, height: 8.4), 2.4), at: p(11.6, 12.2), turned: -45)
            let split = G.placed(G.line(p(-1.3, -4.2), p(-1.3, 4.2)), at: p(11.6, 12.2), turned: -45)
            return [
                L(path: rubber, kind: .soft),
                L(path: block, kind: .stroke),
                L(path: split, kind: .stroke),
                L(path: G.line(p(12.5, 20.5), p(20.5, 20.5)), kind: .stroke),
            ]
        case .pixelEraser:
            let block = G.placed(G.rounded(CGRect(x: -7.5, y: -4.2, width: 15, height: 8.4), 2.4), at: p(11.6, 10.6), turned: -45)
            let rubber = G.placed(G.rounded(CGRect(x: -7.5, y: -4.2, width: 6.2, height: 8.4), 2.4), at: p(11.6, 10.6), turned: -45)
            let split = G.placed(G.line(p(-1.3, -4.2), p(-1.3, 4.2)), at: p(11.6, 10.6), turned: -45)
            let dashed = G.line(p(3.5, 20), p(20.5, 20)).copy(dashingWithPhase: 0, lengths: [3, 3.2])
            return [
                L(path: rubber, kind: .soft),
                L(path: block, kind: .stroke),
                L(path: split, kind: .stroke),
                L(path: dashed, kind: .stroke),
            ]
        case .objectEraser:
            return [
                L(path: G.circle(p(15.6, 12.4), 5.4), kind: .soft),
                L(path: G.circle(p(15.6, 12.4), 5.4), kind: .stroke),
                L(path: G.path { s in
                    s.move(to: p(3, 16.5))
                    s.addCurve(to: p(8.5, 10), control1: p(3.8, 11.5), control2: p(6.2, 7.8))
                    s.addCurve(to: p(12.8, 15.8), control1: p(10.6, 12), control2: p(10.4, 17.2))
                }, kind: .stroke),
            ]

        case .fingerDraws:
            return [
                L(path: G.path { s in
                    s.move(to: p(9.2, 13.2)); s.addLine(to: p(9.2, 6.2))
                    s.addCurve(to: p(13, 6.2), control1: p(9.2, 3.9), control2: p(13, 3.9))
                    s.addLine(to: p(13, 11.5))
                    s.addCurve(to: p(16.4, 11.5), control1: p(13, 9.6), control2: p(16.4, 9.6))
                    s.addLine(to: p(16.4, 12.4))
                    s.addCurve(to: p(19.8, 12.4), control1: p(16.4, 10.8), control2: p(19.8, 10.8))
                    s.addLine(to: p(19.8, 16.5))
                    s.addCurve(to: p(14.8, 21.5), control1: p(19.8, 19.2), control2: p(17.6, 21.5))
                    s.addLine(to: p(12.8, 21.5))
                    s.addCurve(to: p(8.4, 19), control1: p(10.8, 21.5), control2: p(9.4, 20.6))
                    s.addLine(to: p(4.8, 14.6))
                    s.addCurve(to: p(7.2, 13.4), control1: p(4.1, 13.5), control2: p(6, 12.4))
                    s.addLine(to: p(9.2, 15.2))
                }, kind: .stroke),
                L(path: G.line(p(13, 11.5), p(13, 14.5)), kind: .stroke),
                L(path: G.line(p(16.4, 12.4), p(16.4, 14.5)), kind: .stroke),
            ]

        case .insert:
            return [
                L(path: G.circle(p(15.2, 8.8), 5.2), kind: .soft),
                L(path: G.circle(p(15.2, 8.8), 5.2), kind: .stroke),
                L(path: G.rounded(CGRect(x: 3.6, y: 10.2, width: 10.4, height: 10.2), 2.6), kind: .stroke),
            ]

        case .addColour:
            return [
                L(path: G.circle(p(12, 12), 8.6).copy(dashingWithPhase: 0, lengths: [3.4, 2.9]), kind: .stroke),
                L(path: G.line(p(12, 8), p(12, 16)), kind: .stroke),
                L(path: G.line(p(8, 12), p(16, 12)), kind: .stroke),
            ]

        case .style:
            return [
                L(path: G.line(p(2.8, 19), p(8.6, 5), p(14.4, 19)), kind: .stroke),
                L(path: G.line(p(4.9, 14.2), p(12.3, 14.2)), kind: .stroke),
                L(path: G.path { s in
                    s.move(to: p(20.6, 13.4))
                    s.addCurve(to: p(15.6, 15.8), control1: p(19.4, 12.3), control2: p(15.6, 12.8))
                    s.addCurve(to: p(20.6, 19), control1: p(15.6, 18.6), control2: p(19.4, 19.6))
                    s.addLine(to: p(20.6, 13.4))
                    s.move(to: p(20.6, 19)); s.addLine(to: p(20.8, 19.2))
                }, kind: .stroke),
            ]
        case .bold:
            return [L(path: G.path { s in
                s.move(to: p(7.5, 4.8)); s.addLine(to: p(7.5, 19.2))
                s.move(to: p(7.5, 4.8)); s.addLine(to: p(12.6, 4.8))
                s.addCurve(to: p(12.6, 11.5), control1: p(16.2, 4.8), control2: p(16.2, 11.5))
                s.addLine(to: p(7.5, 11.5))
                s.move(to: p(12.6, 11.5))
                s.addCurve(to: p(13.2, 19.2), control1: p(18, 11.5), control2: p(18, 19.2))
                s.addLine(to: p(7.5, 19.2))
            }, kind: .stroke, weight: 1.35)]
        case .italic:
            return [L(path: G.path { s in
                s.move(to: p(10.5, 5)); s.addLine(to: p(17.5, 5))
                s.move(to: p(6.5, 19)); s.addLine(to: p(13.5, 19))
                s.move(to: p(14.9, 5)); s.addLine(to: p(9.1, 19))
            }, kind: .stroke)]
        case .underline:
            return [
                L(path: G.path { s in
                    s.move(to: p(7, 4.5)); s.addLine(to: p(7, 11))
                    s.addCurve(to: p(17, 11), control1: p(7, 17), control2: p(17, 17))
                    s.addLine(to: p(17, 4.5))
                }, kind: .stroke),
                L(path: G.line(p(5, 20.3), p(19, 20.3)), kind: .stroke),
            ]
        case .strikethrough:
            return [
                L(path: G.path { s in
                    s.move(to: p(16.2, 7.2))
                    s.addCurve(to: p(12, 4.6), control1: p(15.4, 5.6), control2: p(13.8, 4.6))
                    s.addCurve(to: p(8, 7.4), control1: p(9.6, 4.6), control2: p(8, 5.8))
                    s.addCurve(to: p(10.4, 10.6), control1: p(8, 8.8), control2: p(8.8, 9.8))
                    s.move(to: p(13.6, 13.4))
                    s.addCurve(to: p(16, 16.6), control1: p(15.2, 14.2), control2: p(16, 15.2))
                    s.addCurve(to: p(12, 19.4), control1: p(16, 18.2), control2: p(14.4, 19.4))
                    s.addCurve(to: p(7.8, 16.8), control1: p(10, 19.4), control2: p(8.5, 18.4))
                }, kind: .stroke),
                L(path: G.line(p(4, 12), p(20, 12)), kind: .stroke),
            ]
        case .inlineCode:
            return [
                L(path: G.line(p(8.4, 7), p(3.6, 12), p(8.4, 17)), kind: .stroke),
                L(path: G.line(p(15.6, 7), p(20.4, 12), p(15.6, 17)), kind: .stroke),
                L(path: G.line(p(13.4, 5.2), p(10.6, 18.8)), kind: .stroke),
            ]
        case .list:
            return [
                L(path: G.circle(p(5.2, 7), 1.35), kind: .solid),
                L(path: G.circle(p(5.2, 12), 1.35), kind: .solid),
                L(path: G.circle(p(5.2, 17), 1.35), kind: .solid),
                L(path: G.line(p(10, 7), p(20, 7)), kind: .stroke),
                L(path: G.line(p(10, 12), p(20, 12)), kind: .stroke),
                L(path: G.line(p(10, 17), p(20, 17)), kind: .stroke),
            ]
        case .codeBlock:
            let left = G.path { s in
                s.move(to: p(10.4, 8.2))
                s.addCurve(to: p(8.8, 9.8), control1: p(9.4, 8.2), control2: p(8.8, 8.8))
                s.addLine(to: p(8.8, 10.8))
                s.addCurve(to: p(7.4, 12), control1: p(8.8, 11.5), control2: p(8.3, 12))
                s.addCurve(to: p(8.8, 13.2), control1: p(8.3, 12), control2: p(8.8, 12.5))
                s.addLine(to: p(8.8, 14.2))
                s.addCurve(to: p(10.4, 15.8), control1: p(8.8, 15.2), control2: p(9.4, 15.8))
            }
            return [
                L(path: G.rounded(CGRect(x: 3.5, y: 3.8, width: 17, height: 16.4), 3.4), kind: .soft),
                L(path: G.rounded(CGRect(x: 3.5, y: 3.8, width: 17, height: 16.4), 3.4), kind: .stroke),
                L(path: left, kind: .stroke),
                L(path: G.mirrored(left), kind: .stroke),
            ]
        case .quote:
            return [
                L(path: G.line(p(4.6, 5), p(4.6, 19)), kind: .stroke, weight: 1.35),
                L(path: G.line(p(9.5, 7), p(20, 7)), kind: .stroke),
                L(path: G.line(p(9.5, 12), p(20, 12)), kind: .stroke),
                L(path: G.line(p(9.5, 17), p(15.5, 17)), kind: .stroke),
            ]
        case .link:
            let capsule = G.rounded(CGRect(x: -5.2, y: -2.8, width: 10.4, height: 5.6), 2.8)
            return [
                L(path: G.placed(capsule, at: p(9.4, 14.6), turned: -45), kind: .stroke),
                L(path: G.placed(capsule, at: p(14.6, 9.4), turned: -45), kind: .stroke),
                L(path: G.line(p(10.6, 13.4), p(13.4, 10.6)), kind: .stroke),
            ]
        case .plus:
            return [
                L(path: G.line(p(12, 5), p(12, 19)), kind: .stroke),
                L(path: G.line(p(5, 12), p(19, 12)), kind: .stroke),
            ]
        case .minus:
            return [L(path: G.line(p(5, 12), p(19, 12)), kind: .stroke)]
        case .indent:
            return [
                L(path: G.line(p(3.5, 5.5), p(20.5, 5.5)), kind: .stroke),
                L(path: G.line(p(11, 10.2), p(20.5, 10.2)), kind: .stroke),
                L(path: G.line(p(11, 14.2), p(20.5, 14.2)), kind: .stroke),
                L(path: G.line(p(3.5, 18.5), p(20.5, 18.5)), kind: .stroke),
                L(path: G.polygon(p(3.6, 9.6), p(7.8, 12.2), p(3.6, 14.8)), kind: .solid),
            ]
        case .outdent:
            return [
                L(path: G.line(p(3.5, 5.5), p(20.5, 5.5)), kind: .stroke),
                L(path: G.line(p(11, 10.2), p(20.5, 10.2)), kind: .stroke),
                L(path: G.line(p(11, 14.2), p(20.5, 14.2)), kind: .stroke),
                L(path: G.line(p(3.5, 18.5), p(20.5, 18.5)), kind: .stroke),
                L(path: G.polygon(p(7.8, 9.6), p(3.6, 12.2), p(7.8, 14.8)), kind: .solid),
            ]
        case .selectLasso:
            return [
                L(path: G.path { s in
                    s.addEllipse(in: CGRect(x: 3.5, y: 3.8, width: 17, height: 11.2))
                }.copy(dashingWithPhase: 0, lengths: [3.6, 2.8]), kind: .stroke),
                L(path: G.path { s in
                    s.move(to: p(8.4, 14.2))
                    s.addCurve(to: p(10.2, 19.8), control1: p(7.2, 16.6), control2: p(8, 19.2))
                    s.addCurve(to: p(13.2, 19.6), control1: p(11.2, 20.4), control2: p(12.4, 20.2))
                }, kind: .stroke),
                L(path: G.circle(p(14.3, 19.3), 1.3), kind: .solid),
            ]
        case .selectRectangle:
            return [
                L(path: G.rounded(CGRect(x: 4, y: 5, width: 16, height: 14), 2.2), kind: .soft),
                L(path: G.rounded(CGRect(x: 4, y: 5, width: 16, height: 14), 2.2).copy(dashingWithPhase: 0, lengths: [3.6, 2.8]), kind: .stroke),
            ]
        case .done:
            return [L(path: G.line(p(5, 12.6), p(10, 17.4), p(19.2, 7)), kind: .stroke)]
        case .adjust:
            return [
                L(path: G.line(p(4, 6.5), p(20, 6.5)), kind: .stroke),
                L(path: G.line(p(4, 12), p(20, 12)), kind: .stroke),
                L(path: G.line(p(4, 17.5), p(20, 17.5)), kind: .stroke),
                L(path: G.circle(p(9, 6.5), 2.4), kind: .soft),
                L(path: G.circle(p(15.5, 12), 2.4), kind: .soft),
                L(path: G.circle(p(8, 17.5), 2.4), kind: .soft),
                L(path: G.circle(p(9, 6.5), 2.4), kind: .stroke),
                L(path: G.circle(p(15.5, 12), 2.4), kind: .stroke),
                L(path: G.circle(p(8, 17.5), 2.4), kind: .stroke),
            ]
        case .delete:
            let body = G.path { s in
                s.move(to: p(6.4, 7.4)); s.addLine(to: p(7.5, 19.2))
                s.addCurve(to: p(8.6, 20.4), control1: p(7.55, 19.9), control2: p(8, 20.4))
                s.addLine(to: p(15.4, 20.4))
                s.addCurve(to: p(16.5, 19.2), control1: p(16, 20.4), control2: p(16.45, 19.9))
                s.addLine(to: p(17.6, 7.4))
            }
            return [
                L(path: body, kind: .soft),
                L(path: body, kind: .stroke),
                L(path: G.line(p(4.2, 7.4), p(19.8, 7.4)), kind: .stroke),
                L(path: G.line(p(9.4, 7.2), p(9.4, 4.4), p(14.6, 4.4), p(14.6, 7.2)), kind: .stroke),
                L(path: G.line(p(10.3, 11), p(10.3, 16.6)), kind: .stroke),
                L(path: G.line(p(13.7, 11), p(13.7, 16.6)), kind: .stroke),
            ]
        case .duplicate:
            return [
                L(path: G.rounded(CGRect(x: 9, y: 9, width: 11, height: 11), 2.8), kind: .soft),
                L(path: G.rounded(CGRect(x: 9, y: 9, width: 11, height: 11), 2.8), kind: .stroke),
                L(path: G.path { s in
                    s.move(to: p(13.2, 4.2)); s.addLine(to: p(7.2, 4.2))
                    s.addCurve(to: p(4.2, 7.2), control1: p(5.5, 4.2), control2: p(4.2, 5.5))
                    s.addLine(to: p(4.2, 13.2))
                }, kind: .stroke),
            ]
        case .sidebar:
            let panel = G.rounded(CGRect(x: 3.5, y: 5, width: 17, height: 14), 3)
            return [
                L(path: G.path { s in
                    s.move(to: p(9.5, 5)); s.addLine(to: p(6.5, 5))
                    s.addCurve(to: p(3.5, 8), control1: p(4.8, 5), control2: p(3.5, 6.3))
                    s.addLine(to: p(3.5, 16))
                    s.addCurve(to: p(6.5, 19), control1: p(3.5, 17.7), control2: p(4.8, 19))
                    s.addLine(to: p(9.5, 19)); s.closeSubpath()
                }, kind: .soft),
                L(path: panel, kind: .stroke),
                L(path: G.line(p(9.5, 5), p(9.5, 19)), kind: .stroke),
            ]
        case .home:
            let body = G.line(p(5.8, 10.4), p(5.8, 18.2), p(6.9, 19.5), p(17.1, 19.5), p(18.2, 18.2), p(18.2, 10.4))
            return [
                L(path: G.polygon(p(5.8, 10.4), p(12, 5.2), p(18.2, 10.4), p(18.2, 19.5), p(5.8, 19.5)), kind: .soft),
                L(path: body, kind: .stroke),
                L(path: G.line(p(3.4, 11.6), p(12, 4.4), p(20.6, 11.6)), kind: .stroke),
                L(path: G.line(p(10, 19.5), p(10, 14.6), p(14, 14.6), p(14, 19.5)), kind: .stroke),
            ]
        }
    }
}
