import Foundation

/// The reverse-DNS names the app gives its own drag type, pasteboard type,
/// text attribute and log, made from its bundle id so that each edition has
/// its own: the App Store's id there, `org.example.NoteCode.…` in a public
/// build (Config/OpenSource.xcconfig). The list item's type must
/// match the `UTExportedTypeDeclarations` entry in the edition's Info.plist,
/// which the public plist writes as `$(PRODUCT_BUNDLE_IDENTIFIER).list-item`
/// (`ListDropTypeTests`).
nonisolated enum AppIdentifier {
    /// The app's bundle id. The unit tests run inside the app, so they see
    /// the same one.
    static let bundle = Bundle.main.bundleIdentifier ?? "NoteCode"

    /// `<bundle id>.<suffix>`.
    static func named(_ suffix: String) -> String { "\(bundle).\(suffix)" }
}
