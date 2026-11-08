//
//  EraserSettings.swift
//  NoteCode
//
//  How the eraser erases.
//

import Foundation

/// How the eraser erases: which parts of a stroke, and how wide.
nonisolated struct EraserSettings: Hashable, Sendable {
    enum Mode: String, CaseIterable, Sendable {
        /// Only what it passes over, so fixing one letter of handwriting
        /// doesn't take the rest of the word with it.
        case partial
        /// Every stroke it touches, whole.
        case wholeStroke
    }

    enum Size: String, CaseIterable, Sendable {
        case small
        case medium
        case large
        case custom
    }

    var mode = Mode.partial
    var size = Size.small

    /// The width `custom` erases at, kept when another size is chosen so the
    /// reader's own size is there to go back to.
    var customWidth: Double = 40 {
        didSet { customWidth = Self.clamped(customWidth) }
    }

    static func clamped(_ width: Double) -> Double {
        min(max(width, widthRange.lowerBound), widthRange.upperBound)
    }

    /// Widths PencilKit's fixed-width eraser takes. Read from the SDK on
    /// 26 September: PencilKit's other erasers report no width at all, and
    /// PaperKit turns the plain pixel eraser into this one, clamped to it.
    static let widthRange: ClosedRange<Double> = 16.4...80.4

    /// The narrowest is the width the eraser had before sizes existed.
    static func width(of size: Size) -> Double? {
        switch size {
        case .small:  16.4
        case .medium: 32
        case .large:  56
        case .custom: nil
        }
    }

    /// How wide the eraser is now. The whole-stroke eraser has no width, so
    /// this is only what `partial` erases at.
    var width: Double {
        Self.width(of: size) ?? customWidth
    }
}

extension EraserSettings: RawRepresentable {

    /// `mode;size;customWidth`, for `@AppStorage`. Plain text, for the reason
    /// `InkPalette.rawValue` gives.
    nonisolated var rawValue: String {
        "\(mode.rawValue);\(size.rawValue);\(customWidth)"
    }

    nonisolated init?(rawValue: String) {
        let parts = rawValue.split(separator: ";").map(String.init)
        guard parts.count == 3,
              let mode = Mode(rawValue: parts[0]),
              let size = Size(rawValue: parts[1]),
              let customWidth = Double(parts[2])
        else { return nil }
        self.init()
        self.mode = mode
        self.size = size
        // An initialiser doesn't run `didSet`.
        self.customWidth = Self.clamped(customWidth)
    }
}
