//
//  ProDebugOptionsTests.swift
//  NoteCodeTests
//
//  The App Store edition's debug launch options, and what the edition hands
//  the general debug launch and the Welcome copy.
//

#if DEBUG

import Foundation
import Testing
@testable import NoteCode

@Suite("Pro debug options", .tags(.pro))
@MainActor
struct ProDebugOptionsTests {

    private func parse(_ arguments: [String]) -> DebugLaunchOptions {
        DebugLaunchOptions.parse(["app"] + arguments, groups: [ProDebugOptions.self])
    }

    @Test("Each Pro option parses with no problem when the Pro group is given", arguments: [
        ["-debug-pro", "on"], ["-debug-pro", "off"], ["-debug-paywall"], ["-debug-tip-jar"],
        ["-debug-run-stub", "ok"], ["-debug-run-stub", "compile-error"], ["-debug-run-stub", "capped"],
    ])
    func parsesWithGroup(arguments: [String]) throws {
        let options = parse(arguments)
        #expect(options.problems.isEmpty, "\(arguments): \(options.problems)")
        #expect(options.isActive)
        let pro = try #require(options.group(ProDebugOptions.self))
        #expect(pro.isActive)
    }

    @Test("Every Pro option at once, read from the group")
    func allTogether() throws {
        let options = parse(["-debug-pro", "off", "-debug-paywall", "-debug-tip-jar", "-debug-run-stub", "time-limit", "-debug-report"])
        #expect(options.problems.isEmpty)
        #expect(options.writesReport)
        let pro = try #require(options.group(ProDebugOptions.self))
        #expect(pro.pro == false && pro.paywall && pro.tipJar && pro.runStub == .timeLimit)
    }

    @Test("A bad run stub keeps its error text, and an unknown option is still reported")
    func problemsStillReported() {
        let options = parse(["-debug-run-stub", "slow", "-debug-pr", "on"])
        #expect(options.problems == [
            "-debug-run-stub: \"slow\" isn't one of ok, compile-error, runtime-error, time-limit, capped",
            "unknown argument -debug-pr",
        ])
        #expect(options.group(ProDebugOptions.self)?.runStub == nil)
    }

    @Test("Without the group, none of the four is known")
    func unknownWithoutGroup() {
        let options = DebugLaunchOptions.parse(["app", "-debug-pro", "on", "-debug-paywall", "-debug-tip-jar", "-debug-run-stub", "ok"])
        #expect(options.problems == ["-debug-pro", "-debug-paywall", "-debug-tip-jar", "-debug-run-stub"].map { "unknown argument \($0)" })
        #expect(options.group(ProDebugOptions.self) == nil)
        #expect(!options.isActive)
    }

    @Test("This launch's options were parsed with the Pro group")
    func currentHasTheGroup() {
        #expect(DebugLaunchOptions.current.group(ProDebugOptions.self) != nil)
        #expect(!DebugLaunchOptions.current.problems.contains { $0.hasPrefix("unknown argument") })
    }

    @Test("The App Store edition's Welcome lines are the ones it has always had")
    func welcomeLines() {
        let lines = AppExtensions.appStore.runLines
        // The whole note, as it was before the Run sentence came from the edition.
        #expect(WelcomeNote.content(lines) == """
        Type here like any note. Headings, **bold**, lists and `inline code` come from the bar below, or from Markdown as you type.

        ## Code

        Three backticks and a language start a code block. With NoteCode Pro, the run button runs it beside the page and shows what it prints. Copy puts it on the clipboard.

        ```python
        def greet(name):
            return f"Hello, {name}!"

        print(greet("CS133"))
        ```

        ## Ink

        Tap the pencil in the bar to draw on the page. The Pencil always draws; a finger draws too, or scrolls, as the hand button says.

        ## Pages

        Notes are Letter pages. ••• › View shows them seamless, compressed or as printed sheets, and Share makes a PDF.
        """)
        #expect(WelcomeScreen.features(lines).first?.detail
            == "Type ``` and a language for a highlighted block. NoteCode Pro runs it beside the page.")
    }

    @Test("A first launch also clears the App Store edition's Run disclosure")
    func resetKeys() throws {
        #expect(AppExtensions.appStore.debugResetKeys == [SettingKeys.Run.disclosureAccepted.name])
#if canImport(UIKit)
        let name = "ProDebugOptionsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defaults.set(true, forKey: SettingKeys.Run.disclosureAccepted.name)
        let options = DebugLaunchOptions.parse(["app", "-debug-first-launch"])
        _ = DebugLaunch.firstLaunchOrHomeStorage(
            options, session: DebugSession(options: options),
            alsoClearing: AppExtensions.appStore.debugResetKeys, defaults: defaults)
        #expect(defaults.object(forKey: SettingKeys.Run.disclosureAccepted.name) == nil)
#endif
    }
}

#endif
