//
//  UITextView+Ranges.swift
//  NoteCode
//
//  An NSRange as the UITextRange a text view edits through, once.
//

#if canImport(UIKit)
import UIKit

extension UITextView {
    /// The `UITextRange` for a UTF-16 range of the text, `nil` when it falls
    /// outside the text.
    func textRange(for range: NSRange) -> UITextRange? {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length)
        else { return nil }
        return textRange(from: start, to: end)
    }
}
#endif
