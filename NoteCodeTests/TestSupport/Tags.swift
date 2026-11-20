//
//  Tags.swift
//  NoteCodeTests
//
//  Every `@Suite` carries one folder tag, and the cost suites (and the
//  cost tests inside other suites) also carry `.perf`. The test plans in
//  NoteCode.xcodeproj/xcshareddata/ select on them: Fast is everything but
//  `.perf`, Perf is `.perf` only, Pro is `.pro` only, Full is all.
//  A suite's tag covers its tests.
//

import Testing

extension Tag {
    /// Parsing and formatting with no UIKit in the loop (`Text/Core`, `Formula`).
    @Tag static var pure: Self
    /// The text view, its styling and its coordinator (`Text/Editor`, `Code`).
    @Tag static var editor: Self
    /// Page and text layout on a real view (`Text/Layout`, `NotePage`).
    @Tag static var layout: Self
    /// Drawing, ink storage and the object system (`Ink`).
    @Tag static var ink: Self
    /// Notes, folders and what surrounds them: the list, the model, settings,
    /// import and export (`Library`, `Model`, `Settings`, `InOut`, `App`, `Debug`).
    @Tag static var library: Self
    /// Cost tests with absolute budgets; they stay out of the inner loop.
    @Tag static var perf: Self
    /// Pro: Run, the assistant, the store and ads (`Pro/`).
    @Tag static var pro: Self
}
