//
//  AppStoreEdition.swift
//  NoteCode
//

import SwiftUI

/// The App Store edition: the general app with Pro, tips and ads.
/// The open-source build's `@main` is OpenSource/OpenSourceEdition.swift.
@main
struct NoteCodeApp: App {
    // Made once, when the app starts: the scene's init opens the store.
    private let scene = NoteCodeScene(extensions: .appStore)

    var body: some Scene { scene }
}

extension AppExtensions {
    static let appStore: AppExtensions = {
        var extensions = appStoreScene
#if canImport(UIKit)
        // Explain Block, the options row's Explain and Summarise Note.
        extensions.editorFeatures = [AssistantFeature.factory()]
#endif
        return extensions
    }()

    private static let appStoreScene = AppExtensions(
        start: {
            // Finishes tips that arrive outside a purchase, and asks the store
            // for the tips, so the list's foot knows whether to offer them.
            TipJar.shared.start()
            // Reads whether the reader has Pro, and listens for renewals and refunds.
            ProStatus.shared.start()
        },
        root: { content in
            AnyView(content
                .environment(TipJar.shared)
                .environment(ProStatus.shared))
        })
}
