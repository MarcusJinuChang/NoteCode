//
//  StoredPropertyTrapTests.swift
//  NoteCodeTests
//
//  `DocumentUITextView`'s initialiser skips property initialisers (see its
//  `layoutObservers`), so a stored property that isn't Optional, and isn't a
//  scalar for which zeroed memory is valid, is garbage until set: a crash on
//  first read. T8 of the refactor plan.
//

#if canImport(UIKit)

import CoreGraphics
import Testing
import UIKit
@testable import NoteCode

@Suite("DocumentUITextView stored properties", .tags(.editor))
@MainActor
struct StoredPropertyTrapTests {

    @Test("Every stored property is Optional or a scalar that zeroed memory reads as a value")
    func storedPropertiesAreSafeWhenInitialisersSkipped() {
        let textView = DocumentTextView.makeConfiguredTextView()
        var offenders: [String] = []

        for child in Mirror(reflecting: textView).children {
            let value = child.value
            if Mirror(reflecting: value).displayStyle == .optional { continue }
            switch value {
            case is Bool, is Int, is Double, is CGFloat, is CGPoint, is CGSize, is CGRect, is CFTimeInterval:
                continue
            default:
                offenders.append("\(child.label ?? "?"): \(type(of: value))")
            }
        }

        #expect(offenders.isEmpty, "not Optional: \(offenders)")
    }
}

#endif
