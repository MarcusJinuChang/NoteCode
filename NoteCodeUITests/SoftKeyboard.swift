//
//  SoftKeyboard.swift
//  NoteCodeUITests
//
//  Tests that tap keys on the on-screen keyboard need it shown in full. The
//  simulator minimises it (no keys on screen, only the bar if any) once it
//  thinks a hardware keyboard is attached and the keyboard preference
//  `AutomaticMinimizationEnabled` is on. The first hardware key a test
//  presses in a boot (`typeKey`) turns that preference on, and it stays on
//  across reboots (measured 11 Nov, iOS 27.0 simulator). Turned off, the
//  keyboard is shown in full whatever is attached.
//
//  scripts/check.sh --full turns it off and runs these tests
//  (`check.sh` › `soft_keys`) in an xcodebuild run of their own, before any
//  test that presses a hardware key. Run alone, from Xcode or xcodebuild,
//  turn it off by hand first (the command is in the message below).
//

import XCTest

enum SoftKeyboard {
    static let minimisedMessage = """
        the on-screen keyboard is minimised, its keys off screen: the simulator \
        thinks a hardware keyboard is attached. Run `xcrun simctl spawn booted \
        defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled \
        -bool NO` and run again (scripts/check.sh --full does this)
        """
}
