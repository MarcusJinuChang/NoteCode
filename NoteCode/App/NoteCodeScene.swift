//
//  NoteCodeScene.swift
//  NoteCode
//

import SwiftUI
import SwiftData

/// The app's one scene, with nothing sold in it. An edition's `@main`
/// (Pro/AppStoreEdition.swift, OpenSource/OpenSourceEdition.swift) makes it
/// once, with what that edition adds.
struct NoteCodeScene: Scene {
    private let extensions: AppExtensions
    private let storage: Storage

#if DEBUG
    /// A note to open on launch. Only debug launch arguments set one.
    private let openedPage: Page?
#else
    private var openedPage: Page? { nil }
#endif

    init(extensions: AppExtensions) {
        self.extensions = extensions
#if canImport(UIKit)
        AppInfo.deviceName = UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"
        // So the menu bar's bare-letter shortcuts know when a field is typing.
        TextInputActivity.shared.start()
#else
        AppInfo.deviceName = "Mac"
#endif
        // The edition's own start: the App Store's starts the tip jar, then Pro.
        extensions.start()
#if DEBUG && canImport(UIKit)
        // See DebugSeed.swift and DebugSession.swift. A no-op unless a -debug- argument was passed.
        let session = DebugSession.shared
        DebugLaunch.applyViewMode(session.options)
        DeviceProbe.start()
        if let fresh = DebugLaunch.firstLaunchOrHomeStorage(
            session.options, session: session, alsoClearing: extensions.debugResetKeys) {
            storage = fresh
            openedPage = nil
            return
        }
        if let seeded = DebugLaunch.seededStorage(session.options, session: session) {
            storage = seeded.storage
            openedPage = seeded.page
            return
        }
#endif
        storage = Storage.open()
#if DEBUG
        openedPage = nil
#endif
    }

    var body: some Scene {
        WindowGroup {
            if let container = storage.container {
                extensions.root(AnyView(
                    ContentView(storageIsEphemeral: storage.isEphemeral, openedPage: openedPage)
                        .modelContainer(container)))
                    .environment(\.appExtensions, extensions)
                    .modifier(AppearanceModifier())
#if DEBUG
                    .modifier(DebugRoot(wrap: extensions.debugRoot))
#endif
            } else {
                StorageUnavailableView(reason: storage.reason)
                    .modifier(AppearanceModifier())
            }
        }
        .commands {
            SettingsCommands()
            NoteCommands()
        }
    }
}

/// Shown when no store could be opened at all.
///
/// Rare, but the alternative is a launch crash that tells the user nothing.
struct StorageUnavailableView: View {
    let reason: String?

    var body: some View {
        ContentUnavailableView {
            Label("Notes Unavailable", systemImage: "externaldrive.badge.xmark")
        } description: {
            Text("NoteCode couldn't open its storage, so your notes can't be loaded. Restarting may help; if it doesn't, freeing up space on the device usually does.")
        } actions: {
            if let reason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

#if DEBUG
/// The edition's `debugRoot`, outside everything else on the root view.
private struct DebugRoot: ViewModifier {
    let wrap: @MainActor @Sendable (AnyView) -> AnyView

    func body(content: Content) -> some View {
        wrap(AnyView(content))
    }
}
#endif
