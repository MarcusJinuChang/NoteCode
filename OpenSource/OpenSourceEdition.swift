//
//  OpenSourceEdition.swift
//  NoteCode
//
//  The open-source edition's `@main`: the general app with nothing added.
//  Outside NoteCode/, so the App Store build doesn't compile it; the public
//  build is NoteCode/ minus Pro/ plus this file (docs/refactor/2X-seam.md).
//

import SwiftUI

@main
struct NoteCodeApp: App {
    // Made once, when the app starts: the scene's init opens the store.
    private let scene = NoteCodeScene(extensions: .none)

    var body: some Scene { scene }
}
