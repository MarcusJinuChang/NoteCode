//
//  DebugLaunchOptions.swift
//  NoteCode
//
//  Launch arguments that open a debug build in a known state, parsed from the
//  process's arguments. What they do is in DebugSeed.swift and
//  DebugSession.swift; the report of what ends up on screen is in
//  DebugStateReport.swift. Debug builds only.
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
nonisolated struct DebugLaunchOptions: Equatable, Sendable {

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
    /// The tip jar with stand-in tips, so its row and sheet can be looked at
    /// without the products in App Store Connect (`DebugTipStore`).
    var tipJar = false
    var paywall = false
    /// Pro on or off, with nothing asked of StoreKit (`DebugProStore`).
    var pro: Bool?
    /// Run answers with a canned result and the panel opens on the first
    /// block and runs it (`DebugRunStub`).
    var runStub: DebugRunStubKind?

    /// Arguments that couldn't be used. Reported rather than ignored, so a
    /// typo can't pass for a check that ran.
    var problems: [String] = []

    var isActive: Bool {
        note != nil || mode != nil || orientation != nil || textSize != nil || page != nil || thenMode != nil
            || writesReport || firstLaunch || home || tipJar || paywall || pro != nil || runStub != nil
    }

    static let current = parse(ProcessInfo.processInfo.arguments)

    static func parse(_ arguments: [String]) -> DebugLaunchOptions {
        var options = DebugLaunchOptions()
        var index = 0

        /// The argument after `flag`, if there is one that isn't another flag.
        func value(for flag: String) -> String? {
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("-") else {
                options.problems.append("\(flag) needs a value")
                return nil
            }
            index += 1
            return arguments[index]
        }

        func choice<T: RawRepresentable & CaseIterable>(_ raw: String?, for flag: String) -> T? where T.RawValue == String {
            guard let raw else { return nil }
            if let parsed = T(rawValue: raw) { return parsed }
            let expected = T.allCases.map(\.rawValue).joined(separator: ", ")
            options.problems.append("\(flag): \"\(raw)\" isn't one of \(expected)")
            return nil
        }

        func setNote(_ note: Note) {
            if options.note != nil {
                options.problems.append("more than one note given; using the last")
            }
            options.note = note
        }

        while index < arguments.count {
            let flag = arguments[index]
            switch flag {
            case "-debug-note":
                if let fixture: DebugFixture = choice(value(for: flag), for: flag) {
                    setNote(.fixture(fixture))
                }
            case "-debug-note-file":
                if let path = value(for: flag) {
                    setNote(.file(path))
                }
            case "-debug-mode":
                options.mode = choice(value(for: flag), for: flag)
            case "-debug-orientation":
                options.orientation = choice(value(for: flag), for: flag)
            case "-debug-text-size":
                if let raw = value(for: flag) {
                    if let size = Int(raw), NoteTypography.sizes.contains(size) {
                        options.textSize = size
                    } else {
                        options.problems.append("\(flag): \"\(raw)\" isn't one of \(NoteTypography.sizes.map(String.init).joined(separator: ", "))")
                    }
                }
            case "-debug-page":
                if let raw = value(for: flag) {
                    if let number = Int(raw), number >= 1 {
                        options.page = number
                    } else {
                        options.problems.append("\(flag): \"\(raw)\" isn't a page number from 1")
                    }
                }
            case "-debug-ink-file":
                options.inkFile = value(for: flag)
            case "-debug-then-mode":
                options.thenMode = choice(value(for: flag), for: flag)
            case "-debug-then-delay":
                if let raw = value(for: flag) {
                    if let seconds = Double(raw), seconds >= 0 {
                        options.thenDelay = seconds
                    } else {
                        options.problems.append("\(flag): \"\(raw)\" isn't a number of seconds")
                    }
                }
            case "-debug-report":
                options.writesReport = true
            case "-debug-first-launch":
                options.firstLaunch = true
            case "-debug-home":
                options.home = true
            case "-debug-keep-defaults":
                options.keepsDefaults = true
            case "-debug-tip-jar":
                options.tipJar = true
            case "-debug-paywall":
                options.paywall = true
            case "-debug-pro":
                if let raw = value(for: flag) {
                    switch raw {
                    case "on":  options.pro = true
                    case "off": options.pro = false
                    default:    options.problems.append("\(flag): \"\(raw)\" isn't on or off")
                    }
                }
            case "-debug-run-stub":
                options.runStub = choice(value(for: flag), for: flag)
            case "-debug-probe", "-debug-probe-snapshot", "-debug-probe-watch", "-debug-selection-probe":
                // Read by DebugProbe and SelectionProbe themselves; known
                // here only so the report doesn't call them unknown.
                break
            default:
                if flag.hasPrefix("-debug-") {
                    options.problems.append("unknown argument \(flag)")
                }
            }
            index += 1
        }

        if options.orientation != nil && options.note == nil {
            options.problems.append("-debug-orientation applies to a seeded note; add -debug-note")
        }
        if options.textSize != nil && options.note == nil {
            options.problems.append("-debug-text-size applies to a seeded note; add -debug-note")
        }
        if options.firstLaunch && options.home {
            options.problems.append("-debug-first-launch and -debug-home both given; using -debug-first-launch")
            options.home = false
        }
        if (options.firstLaunch || options.home) && options.note != nil {
            options.problems.append("-debug-first-launch and -debug-home show what is there with no note open; the note given opens instead")
            options.firstLaunch = false
            options.home = false
        }
        if arguments.contains("-debug-then-delay") && options.thenMode == nil {
            options.problems.append("-debug-then-delay does nothing without -debug-then-mode")
        }
        return options
    }
}

#endif
