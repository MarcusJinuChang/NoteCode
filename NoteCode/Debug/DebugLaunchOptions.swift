//
//  DebugLaunchOptions.swift
//  NoteCode
//
//  Launch arguments that open a debug build in a known state, parsed from the
//  process's arguments. What they do is in DebugSeed.swift and
//  DebugSession.swift; the report of what ends up on screen is in
//  DebugStateReport.swift. An edition adds its own options as a
//  `DebugOptionGroup` (the App Store's: Pro/Debug/ProDebugOptions.swift).
//  Debug builds only.
//

#if DEBUG

import Foundation

// MARK: - Options

/// What a debug launch asked for, parsed from the process's arguments.
///
/// The arguments are the app's own, never the settings keys. Passing
/// `-pageViewMode print` would set the mode with no code at all, but launch
/// arguments outrank saved settings, so choosing a mode from the view menu
/// would then appear to do nothing for the whole session.
nonisolated struct DebugLaunchOptions: Sendable {

    enum Note: Equatable, Sendable {
        case fixture(DebugFixture)
        case file(String)
    }

    /// Opens a new note, in a store that lives in memory for this launch.
    var note: Note?
    var mode: PageViewMode?
    /// The seeded note's page orientation.
    var orientation: PageOrientation?
    /// The seeded note's text size, one of `NoteTypography.sizes`.
    var textSize: Int?
    /// A page to scroll to, counted from 1 as pages are on screen.
    var page: Int?
    /// A file on the Mac holding a note's ink, as `DrawingCodec` stores it,
    /// for looking at a note with a lot of ink without drawing it.
    var inkFile: String?
    /// A view mode to switch to once the page has settled.
    var thenMode: PageViewMode?
    /// Seconds to wait after settling before switching.
    var thenDelay: Double = 1
    /// Writes `DebugStateReport` each time layout settles.
    var writesReport = false
    /// A fresh install: an empty store in memory, and the first-launch flags
    /// cleared, so the title screen and the Welcome note appear.
    var firstLaunch = false
    /// Home, over a store of sample notes and folders in memory, with the
    /// title screen already seen.
    var home = false
    /// Leave the saved flags and remembered places alone, which `-debug-home`
    /// otherwise clears: for a run on a device with someone's own notes.
    var keepsDefaults = false

    /// What the edition's groups read, one value per group passed to `parse`.
    private(set) var groups: [any DebugOptionGroup] = []

    /// Arguments that couldn't be used. Reported rather than ignored, so a
    /// typo can't pass for a check that ran.
    var problems: [String] = []

    var isActive: Bool {
        note != nil || mode != nil || orientation != nil || textSize != nil || page != nil || thenMode != nil
            || writesReport || firstLaunch || home || groups.contains { $0.isActive }
    }

    /// What `group` read, or `nil` if it wasn't passed to `parse`.
    func group<Group: DebugOptionGroup>(_ group: Group.Type) -> Group? {
        for value in groups {
            if let value = value as? Group { return value }
        }
        return nil
    }

    /// The edition's option groups. Its `@main` sets them before anything
    /// reads `current`: `TipJar.shared`, made with the App Store's
    /// extensions, reads it first, and an option whose group isn't here yet
    /// would be reported as an unknown argument.
    nonisolated(unsafe) static var editionGroups: [any DebugOptionGroup.Type]?

    static let current: DebugLaunchOptions = {
        assert(editionGroups != nil, "DebugLaunchOptions.current was read before the edition set editionGroups")
        return parse(ProcessInfo.processInfo.arguments, groups: editionGroups ?? [])
    }()

    /// Walks `arguments` once, offering each flag to the general groups and
    /// then to `groups`. A `-debug-` flag no group takes is an unknown
    /// argument.
    static func parse(_ arguments: [String], groups: [any DebugOptionGroup.Type] = []) -> DebugLaunchOptions {
        var options = DebugLaunchOptions()
        options.groups = groups.map { $0.init() }
        var reader = DebugArguments(arguments)

        while let flag = reader.flag {
            let taken = options.takeNoteOption(flag, from: &reader)
                || options.takeLayoutOption(flag, from: &reader)
                || options.takeLaunchOption(flag)
                || isProbeFlag(flag)
                || options.offerToGroups(flag, from: &reader)
            if !taken && flag.hasPrefix("-debug-") {
                reader.problems.append("unknown argument \(flag)")
            }
            reader.advance()
        }

        options.problems = reader.problems
        options.checkAcrossOptions(arguments)
        return options
    }

    // MARK: - The general groups

    /// The seeded note: which note, its orientation, text size and ink.
    private mutating func takeNoteOption(_ flag: String, from reader: inout DebugArguments) -> Bool {
        switch flag {
        case "-debug-note":
            if let fixture: DebugFixture = reader.choice(for: flag) {
                setNote(.fixture(fixture), problems: &reader.problems)
            }
        case "-debug-note-file":
            if let path = reader.value(for: flag) {
                setNote(.file(path), problems: &reader.problems)
            }
        case "-debug-orientation":
            orientation = reader.choice(for: flag)
        case "-debug-text-size":
            if let raw = reader.value(for: flag) {
                if let size = Int(raw), NoteTypography.sizes.contains(size) {
                    textSize = size
                } else {
                    reader.problems.append("\(flag): \"\(raw)\" isn't one of \(NoteTypography.sizes.map(String.init).joined(separator: ", "))")
                }
            }
        case "-debug-ink-file":
            inkFile = reader.value(for: flag)
        default:
            return false
        }
        return true
    }

    private mutating func setNote(_ note: Note, problems: inout [String]) {
        if self.note != nil {
            problems.append("more than one note given; using the last")
        }
        self.note = note
    }

    /// The view mode, the page, the switch after settling, and the report.
    private mutating func takeLayoutOption(_ flag: String, from reader: inout DebugArguments) -> Bool {
        switch flag {
        case "-debug-mode":
            mode = reader.choice(for: flag)
        case "-debug-page":
            if let raw = reader.value(for: flag) {
                if let number = Int(raw), number >= 1 {
                    page = number
                } else {
                    reader.problems.append("\(flag): \"\(raw)\" isn't a page number from 1")
                }
            }
        case "-debug-then-mode":
            thenMode = reader.choice(for: flag)
        case "-debug-then-delay":
            if let raw = reader.value(for: flag) {
                if let seconds = Double(raw), seconds >= 0 {
                    thenDelay = seconds
                } else {
                    reader.problems.append("\(flag): \"\(raw)\" isn't a number of seconds")
                }
            }
        case "-debug-report":
            writesReport = true
        default:
            return false
        }
        return true
    }

    /// A first launch, Home, and whether to leave the saved flags alone.
    private mutating func takeLaunchOption(_ flag: String) -> Bool {
        switch flag {
        case "-debug-first-launch": firstLaunch = true
        case "-debug-home":         home = true
        case "-debug-keep-defaults": keepsDefaults = true
        default:                    return false
        }
        return true
    }

    /// Read by DeviceProbe and SelectionProbe themselves; known here only so
    /// the report doesn't call them unknown.
    private static func isProbeFlag(_ flag: String) -> Bool {
        ["-debug-probe", "-debug-probe-snapshot", "-debug-probe-watch", "-debug-selection-probe"].contains(flag)
    }

    private mutating func offerToGroups(_ flag: String, from reader: inout DebugArguments) -> Bool {
        for index in groups.indices {
            if groups[index].take(flag, from: &reader) { return true }
        }
        return false
    }

    /// Checks between options of the general groups, once every argument is read.
    private mutating func checkAcrossOptions(_ arguments: [String]) {
        if orientation != nil && note == nil {
            problems.append("-debug-orientation applies to a seeded note; add -debug-note")
        }
        if textSize != nil && note == nil {
            problems.append("-debug-text-size applies to a seeded note; add -debug-note")
        }
        if firstLaunch && home {
            problems.append("-debug-first-launch and -debug-home both given; using -debug-first-launch")
            home = false
        }
        if (firstLaunch || home) && note != nil {
            problems.append("-debug-first-launch and -debug-home show what is there with no note open; the note given opens instead")
            firstLaunch = false
            home = false
        }
        if arguments.contains("-debug-then-delay") && thenMode == nil {
            problems.append("-debug-then-delay does nothing without -debug-then-mode")
        }
    }
}

// MARK: - Groups

/// Options an edition adds to the general ones. `parse` offers each flag the
/// general groups don't take to every group it was given.
nonisolated protocol DebugOptionGroup: Sendable {
    init()

    /// Takes `flag` if this group owns it, reading any value from
    /// `arguments`, and returns whether it did.
    mutating func take(_ flag: String, from arguments: inout DebugArguments) -> Bool

    /// Whether any of this group's options was given.
    var isActive: Bool { get }
}

/// The arguments being parsed, where `parse` is in them, and what couldn't
/// be used: what every group needs to read its flags' values.
nonisolated struct DebugArguments {
    private let arguments: [String]
    private var index = 0
    var problems: [String] = []

    init(_ arguments: [String]) {
        self.arguments = arguments
    }

    /// The argument being looked at, or `nil` past the end.
    var flag: String? { index < arguments.count ? arguments[index] : nil }

    mutating func advance() { index += 1 }

    /// The argument after `flag`, if there is one that isn't another flag.
    mutating func value(for flag: String) -> String? {
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("-") else {
            problems.append("\(flag) needs a value")
            return nil
        }
        index += 1
        return arguments[index]
    }

    /// The argument after `flag`, as one of `T`'s cases.
    mutating func choice<T: RawRepresentable & CaseIterable>(for flag: String) -> T? where T.RawValue == String {
        guard let raw = value(for: flag) else { return nil }
        if let parsed = T(rawValue: raw) { return parsed }
        let expected = T.allCases.map(\.rawValue).joined(separator: ", ")
        problems.append("\(flag): \"\(raw)\" isn't one of \(expected)")
        return nil
    }
}

#endif
