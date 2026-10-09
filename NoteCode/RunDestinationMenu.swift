//
//  RunDestinationMenu.swift
//  NoteCode
//
//  Choosing where this page's code blocks go to run.
//

import SwiftUI

/// The page's run destination, as a menu to nest in the header's ••• menu.
///
/// Three levels, page over folder over app-wide, and the menu says which is
/// in force rather than making the student work it out — "Default
/// (Programiz)" is a different state from "Programiz", even though both run
/// the same place, and only one of them follows the default when it changes.
struct RunDestinationMenu: View {

    /// This page's own choice, or `nil` to follow the folder or the default.
    @Binding var pageSetting: String?

    /// The page's folder, whose choice comes between the page's and the
    /// app-wide default. `nil` for a page in no folder.
    var folder: Folder?

    /// The app-wide default, used by every page that hasn't chosen.
    @Binding var appDefault: String

    /// Raised by "Another Site…". The alert it opens isn't attached here:
    /// this menu sits inside another menu's content, which is gone the
    /// moment an item is chosen, and an alert attached to a view that has
    /// gone never shows. The caller attaches `runDestinationSiteAlert` to a
    /// view that stays.
    @Binding var isNamingCustomSite: Bool

    private var defaultDestination: CodeDestination {
        RunDestinationPreference.resolve([appDefault])
    }

    /// The folder's choice, if it has one this app recognises.
    private var folderDestination: CodeDestination? {
        folder?.runDestination.flatMap(CodeDestination.init(id:))
    }

    /// Where the page runs while it hasn't chosen.
    private var inherited: CodeDestination {
        folderDestination ?? defaultDestination
    }

    private var resolved: CodeDestination {
        RunDestinationPreference.resolve([pageSetting, folder?.runDestination, appDefault])
    }

    private var inheritedTitle: String {
        if let folder, folderDestination != nil {
            "Same as \(folder.name) (\(inherited.name))"
        } else {
            "Default (\(inherited.name))"
        }
    }

    /// The custom site already in use at any level, so choosing something
    /// else doesn't make it disappear from the menu.
    private var knownCustom: CodeDestination? {
        for destination in [resolved, inherited, defaultDestination] {
            if case .custom = destination { return destination }
        }
        return nil
    }

    var body: some View {
        Menu {
            Picker("Run code blocks in", selection: $pageSetting) {
                Text(inheritedTitle).tag(String?.none)

                ForEach(CodeDestination.builtIns) { destination in
                    Text(destination.name).tag(String?.some(destination.id))
                }

                if let custom = knownCustom {
                    Text(custom.name).tag(String?.some(custom.id))
                }
            }

            Divider()

            Button("Another Site…") {
                isNamingCustomSite = true
            }

            if let folder, resolved != inherited {
                Button("Use \(resolved.name) for \(folder.name)") {
                    folder.runDestination = resolved.id
                }
            }

            if resolved != defaultDestination {
                Button("Use \(resolved.name) for New Notes") {
                    appDefault = resolved.id
                }
            }
        } label: {
            Label("Run Code In", systemImage: "play.rectangle")
        }
    }
}

extension View {
    /// The alert "Another Site…" opens, asking for a site to run code on.
    /// Sets the page's own choice, as picking one from the menu does.
    func runDestinationSiteAlert(
        isPresented: Binding<Bool>,
        pageSetting: Binding<String?>
    ) -> some View {
        modifier(RunDestinationSiteAlert(isPresented: isPresented, pageSetting: pageSetting))
    }
}

private struct RunDestinationSiteAlert: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var pageSetting: String?

    @State private var typedSite = ""

    func body(content: Content) -> some View {
        content
            .alert("Run Code On", isPresented: $isPresented) {
                TextField("example.com", text: $typedSite)
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
#endif
                    .autocorrectionDisabled()

                Button("Cancel", role: .cancel) {}

                Button("Use Site") {
                    if let custom = CodeDestination.custom(fromTyped: typedSite) {
                        pageSetting = custom.id
                    }
                }
            } message: {
                Text("The block is copied to the clipboard and the site opens, ready for you to paste it in.")
            }
            // Cleared on closing, so the next time it opens it is empty.
            .onChange(of: isPresented) { _, presented in
                if !presented { typedSite = "" }
            }
    }
}
