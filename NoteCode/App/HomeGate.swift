//
//  HomeGate.swift
//  NoteCode
//

/// When Home is really in front of the reader, so an edition may start what
/// waits for it (`AppExtensions.homeAppeared`): after the launch has decided
/// whether the title screen is raised, and while it is not. Home's first
/// appearance comes before that decision and, on a first launch, under the
/// screen, so it doesn't count.
nonisolated enum HomeGate {
    static func isOpen(launchSettled: Bool, titleScreenUp: Bool) -> Bool {
        launchSettled && !titleScreenUp
    }
}
