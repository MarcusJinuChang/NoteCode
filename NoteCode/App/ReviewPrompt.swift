//
//  ReviewPrompt.swift
//  NoteCode
//
//  When the app asks for an App Store rating: as a note closes, once the
//  reader has used it on three days, once a version. Pure, over a
//  `UserDefaults`, so the rule is tested without a view.
//

import Foundation

/// When to ask for a rating. Ratings move the App Store's search rank and
/// its page's conversion more than anything its text says, and the first
/// release never asked.
///
/// **The moment** is a note closing back to Home (`ContentView`): a piece of
/// work finished, never at launch or in the middle of writing, which Apple's
/// guidelines also ask.
///
/// **The reader** has opened notes on `engagedDays` different days, so the
/// question goes to someone who came back rather than someone trying it.
///
/// **How often:** once a version, and `minimumGap` apart. iOS has its own
/// limit on top (three times in 365 days) and may show nothing; the app can't
/// tell whether it did, so asking counts as asked.
nonisolated struct ReviewPrompt {

    /// How many days a note was opened on.
    static let daysKey = "reviewPromptDays"
    /// The last of those days, so a second note that day isn't counted.
    static let lastDayKey = "reviewPromptLastDay"
    /// The app version last asked in.
    static let askedVersionKey = "reviewPromptAskedVersion"
    /// When the app last asked.
    static let askedAtKey = "reviewPromptAskedAt"

    /// Days with a note opened before the first ask.
    static let engagedDays = 3

    /// Between two asks, whatever the versions: about four months, so at most
    /// the three a year iOS allows.
    static let minimumGap: TimeInterval = 120 * 24 * 60 * 60

    var defaults: UserDefaults
    var calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    /// Days on which a note was opened, each counted once.
    var days: Int { defaults.integer(forKey: Self.daysKey) }

    /// A note opened: counts the day of `date` unless a note was opened on
    /// it already.
    func noteOpened(at date: Date = .now) {
        if let last = defaults.object(forKey: Self.lastDayKey) as? Date,
           calendar.isDate(last, inSameDayAs: date) {
            return
        }
        defaults.set(calendar.startOfDay(for: date), forKey: Self.lastDayKey)
        defaults.set(days + 1, forKey: Self.daysKey)
    }

    /// Whether a note closing at `date` should ask, in app version `version`.
    func isDue(version: String, at date: Date = .now) -> Bool {
        guard days >= Self.engagedDays,
              defaults.string(forKey: Self.askedVersionKey) != version
        else { return false }
        if let asked = defaults.object(forKey: Self.askedAtKey) as? Date,
           date.timeIntervalSince(asked) < Self.minimumGap {
            return false
        }
        return true
    }

    func markAsked(version: String, at date: Date = .now) {
        defaults.set(version, forKey: Self.askedVersionKey)
        defaults.set(date, forKey: Self.askedAtKey)
    }

    /// The version the store shows, which is what a rating is given to.
    static func version(of bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
}
