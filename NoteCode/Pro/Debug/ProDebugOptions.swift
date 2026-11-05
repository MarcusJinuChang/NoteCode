//
//  ProDebugOptions.swift
//  NoteCode
//
//  The App Store edition's debug launch options: Pro, the paywall, Run's
//  canned answers and the tip jar. Registered by its `@main`
//  (AppStoreEdition.swift) and read by Pro code from here, never from the
//  general options. Debug builds only.
//

#if DEBUG

import Foundation

/// `-debug-pro`, `-debug-paywall`, `-debug-run-stub` and `-debug-tip-jar`.
nonisolated struct ProDebugOptions: DebugOptionGroup {
    /// The tip jar with stand-in tips, so its row and sheet can be looked at
    /// without the products in App Store Connect (`DebugTipStore`).
    var tipJar = false
    var paywall = false
    /// Pro on or off, with nothing asked of StoreKit (`DebugProStore`).
    var pro: Bool?
    /// Run answers with a canned result and the panel opens on the first
    /// block and runs it (`DebugRunStub`).
    var runStub: DebugRunStubKind?

    var isActive: Bool { tipJar || paywall || pro != nil || runStub != nil }

    mutating func take(_ flag: String, from arguments: inout DebugArguments) -> Bool {
        switch flag {
        case "-debug-tip-jar":
            tipJar = true
        case "-debug-paywall":
            paywall = true
        case "-debug-pro":
            if let raw = arguments.value(for: flag) {
                switch raw {
                case "on":  pro = true
                case "off": pro = false
                default:    arguments.problems.append("\(flag): \"\(raw)\" isn't on or off")
                }
            }
        case "-debug-run-stub":
            runStub = arguments.choice(for: flag)
        default:
            return false
        }
        return true
    }

    /// What this launch asked of Pro.
    static var current: ProDebugOptions {
        DebugLaunchOptions.current.group(ProDebugOptions.self) ?? ProDebugOptions()
    }
}

#endif
