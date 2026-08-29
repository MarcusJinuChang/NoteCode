//
//  NoteCodeApp.swift
//  NoteCode
//

import SwiftUI
import SwiftData

@main
struct NoteCodeApp: App {
    private let storage = Storage.open()

    var body: some Scene {
        WindowGroup {
            if let container = storage.container {
                ContentView(storageIsEphemeral: storage.isEphemeral)
                    .modelContainer(container)
            } else {
                StorageUnavailableView(reason: storage.reason)
            }
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
