//
//  ConsentGate.swift
//  NoteCode
//

/// When Home is really in front of the reader, so an edition may start what
/// waits for it (the App Store's ad consent, `AppExtensions.homeAppeared`):
/// after the launch has decided whether the title screen is raised, and while
/// it is not. Home's first appearance comes before that decision and, on a
/// first launch, under the screen; counting that as the first visit put
/// Google's form, and its tracking explainer, over the title screen
/// (docs/design/shipping.md › Ads).
nonisolated enum ConsentGate {
    static func isOpen(launchSettled: Bool, titleScreenUp: Bool) -> Bool {
        launchSettled && !titleScreenUp
    }
}
