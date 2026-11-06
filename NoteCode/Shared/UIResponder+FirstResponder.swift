//
//  UIResponder+FirstResponder.swift
//  NoteCode
//
//  Who holds the keyboard, which UIKit has no public accessor for.
//

#if canImport(UIKit)

import UIKit

extension UIResponder {
    private weak static var found: UIResponder?

    /// The responder holding the keyboard, if any.
    ///
    /// UIKit has no public accessor. Sending an action to no one in
    /// particular walks the responder chain from the first responder, and the
    /// first one to answer is it.
    static var currentFirstResponder: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.noteCodeReportFirstResponder), to: nil, from: nil, for: nil)
        return found
    }

    @objc fileprivate func noteCodeReportFirstResponder() {
        Self.found = self
    }
}

#endif
