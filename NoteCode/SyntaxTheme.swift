//
//  SyntaxTheme.swift
//  NoteCode
//
//  The code colours, as highlight.js CSS. Pure strings, so a test can read
//  them without a JavaScript round trip.
//

/// NoteCode's syntax colours for one appearance.
///
/// Every colour is 4.5:1 or better against the code panel
/// (`secondarySystemBackground`) in its appearance. The CSS is parsed by
/// `NSAttributedString`'s HTML importer, which supports far less than a
/// browser: plain class selectors and the compound and descendant forms the
/// stock themes use are fine, nothing fancier is tried here.
///
/// Weight and italic are asked for too, but `ColorRun` carries only colour,
/// so they are not drawn yet. Colour is what the design relies on.
struct SyntaxTheme: Equatable {

    /// One role: the colour, and whether highlight.js's classes for it are bold
    /// or italic.
    struct Role: Equatable {
        var hex: String
        var weight: String? = nil
        var style: String? = nil
    }

    var keyword: Role
    var type: Role
    var function: Role
    var string: Role
    var number: Role
    var comment: Role

    static let light = SyntaxTheme(
        keyword:  Role(hex: "AD5300", weight: "600"),
        type:     Role(hex: "1F63B0"),
        function: Role(hex: "00727A"),
        string:   Role(hex: "2E7D32"),
        number:   Role(hex: "7B3FC4"),
        comment:  Role(hex: "6E6E73", style: "italic")
    )

    static let dark = SyntaxTheme(
        keyword:  Role(hex: "FFAA33", weight: "600"),
        type:     Role(hex: "6CB6FF"),
        function: Role(hex: "5ED0D6"),
        string:   Role(hex: "7ED68A"),
        number:   Role(hex: "C39BFF"),
        comment:  Role(hex: "8E8E93", style: "italic")
    )

    /// The colour plain text is given in the CSS, which the adapter then drops.
    ///
    /// "Plain" is `UIColor.label`, which a CSS string can't say, and the HTML
    /// importer paints anything unstyled black, which is invisible on a dark
    /// panel. So plain text gets a colour no role uses, and a run in it is
    /// left out of the result, leaving the text at the editor's own `.label`.
    static let plainHex = "010203"

    /// highlight.js CSS for this theme.
    ///
    /// Order matters: the importer applies later rules over earlier ones of the
    /// same weight, so `title` (function) comes before the more specific class
    /// titles (type) that must win over it.
    var css: String {
        func rule(_ selectors: [String], _ role: Role) -> String {
            var body = "color:#\(role.hex)"
            if let weight = role.weight { body += ";font-weight:\(weight)" }
            if let style = role.style { body += ";font-style:\(style)" }
            return selectors.joined(separator: ",") + "{\(body)}"
        }

        return [
            ".hljs{color:#\(Self.plainHex)}",
            rule([".hljs-title", ".hljs-title.function_"], function),
            rule([".hljs-keyword", ".hljs-literal"], keyword),
            rule([".hljs-type", ".hljs-built_in", ".hljs-class .hljs-title", ".hljs-title.class_"], type),
            rule([".hljs-string"], string),
            rule([".hljs-number"], number),
            rule([".hljs-comment"], comment),
        ].joined()
    }
}

#if canImport(UIKit)
import UIKit

extension SyntaxTheme {
    static func theme(for appearance: HighlightAppearance) -> SyntaxTheme {
        switch appearance {
        case .light: .light
        case .dark:  .dark
        }
    }

    /// Whether a colour from the highlighter is the plain-text sentinel.
    static func isPlain(_ color: UIColor) -> Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        let hex = String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())
        )
        return hex == plainHex
    }
}
#endif
