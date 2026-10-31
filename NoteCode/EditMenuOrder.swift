//
//  EditMenuOrder.swift
//  NoteCode
//
//  Keeps Paste on the edit menu's first page.
//

#if canImport(UIKit)

import UIKit

/// The order of the edit menu's rows.
///
/// The menu puts the app's own rows (Bold, Italic, Underline, Code and Format,
/// or a code block's actions) before the system's, and the iPad's edit menu
/// shows a handful of rows a page. Five of ours filled the first page, and
/// Cut, Copy and Paste were on the second. Those three are what a reader
/// reaches for most, so they come first and the app's rows follow.
@MainActor
enum EditMenuOrder {

    /// The actions that lead the menu, in the order they lead it.
    static let leading: [Selector] = [
        #selector(UIResponderStandardEditActions.cut(_:)),
        #selector(UIResponderStandardEditActions.copy(_:)),
        #selector(UIResponderStandardEditActions.paste(_:)),
    ]

    /// `elements` with the system's Cut, Copy and Paste taken out, and those
    /// that were there, `ours` after them, then the rest. Looks inside the
    /// menus the system groups its rows in, and leaves an emptied menu out.
    static func order(ours: [UIMenuElement], system elements: [UIMenuElement]) -> [UIMenuElement] {
        var found: [Selector: UIMenuElement] = [:]
        let rest = removing(from: elements, into: &found)
        return leading.compactMap { found[$0] } + ours + rest
    }

    private static func removing(from elements: [UIMenuElement], into found: inout [Selector: UIMenuElement]) -> [UIMenuElement] {
        var kept: [UIMenuElement] = []
        for element in elements {
            if let command = element as? UICommand, leading.contains(command.action), found[command.action] == nil {
                found[command.action] = command
            } else if let menu = element as? UIMenu {
                let inner = removing(from: menu.children, into: &found)
                if inner.count == menu.children.count {
                    kept.append(menu)
                } else if !inner.isEmpty {
                    kept.append(menu.replacingChildren(inner))
                }
            } else {
                kept.append(element)
            }
        }
        return kept
    }
}

#endif
