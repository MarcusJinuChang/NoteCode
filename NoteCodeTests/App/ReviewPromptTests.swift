//
//  ReviewPromptTests.swift
//  NoteCodeTests
//
//  When the app asks for an App Store rating.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Review prompt")
struct ReviewPromptTests {

    /// A defaults of its own, so a test can't read what another wrote or the
    /// simulator's real settings.
    private func freshDefaults() -> UserDefaults {
        let name = "ReviewPromptTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Days in one fixed time zone, so midnight is where the test says.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    /// 1 Nov 2026 at `hour`:`minute` in that zone, plus `days`.
    private func date(day: Int = 0, hour: Int = 12, minute: Int = 0) -> Date {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: day, to: start)!
    }

    private func prompt(_ defaults: UserDefaults) -> ReviewPrompt {
        ReviewPrompt(defaults: defaults, calendar: calendar)
    }

    @Test("Notes opened on one day count as one day, however many")
    func oneDayCountsOnce() {
        let prompt = prompt(freshDefaults())
        for hour in [9, 13, 22] {
            prompt.noteOpened(at: date(hour: hour))
        }
        #expect(prompt.days == 1)
    }

    @Test("Just before and just after midnight are two days")
    func midnight() {
        let prompt = prompt(freshDefaults())
        prompt.noteOpened(at: date(hour: 23, minute: 59))
        prompt.noteOpened(at: date(day: 1, hour: 0, minute: 1))
        #expect(prompt.days == 2)
    }

    @Test("Not due until notes were opened on three days")
    func waitsForThreeDays() {
        let prompt = prompt(freshDefaults())
        prompt.noteOpened(at: date(day: 0))
        prompt.noteOpened(at: date(day: 5))
        #expect(!prompt.isDue(version: "1.1.1", at: date(day: 5)))
        prompt.noteOpened(at: date(day: 6))
        #expect(prompt.isDue(version: "1.1.1", at: date(day: 6)))
    }

    @Test("Asked once a version: the same version never asks again, even months later")
    func onceAVersion() {
        let prompt = prompt(freshDefaults())
        for day in 0..<3 { prompt.noteOpened(at: date(day: day)) }
        prompt.markAsked(version: "1.1.1", at: date(day: 2))
        #expect(!prompt.isDue(version: "1.1.1", at: date(day: 3)))
        #expect(!prompt.isDue(version: "1.1.1", at: date(day: 400)))
    }

    @Test("A new version waits out the gap since the last ask, then asks")
    func newVersionWaitsForTheGap() {
        let prompt = prompt(freshDefaults())
        for day in 0..<3 { prompt.noteOpened(at: date(day: day)) }
        prompt.markAsked(version: "1.1.1", at: date(day: 2))
        #expect(!prompt.isDue(version: "1.2", at: date(day: 30)))
        #expect(!prompt.isDue(version: "1.2", at: date(day: 121)))
        #expect(prompt.isDue(version: "1.2", at: date(day: 122)))
    }
}
