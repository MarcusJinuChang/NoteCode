//
//  ListDropTypeTests.swift
//  NoteCodeTests
//
//  The app's own type names come from its bundle id (`AppIdentifier`), so
//  each edition has its own; the list item's must still be the one the
//  edition's Info.plist exports, or a drag in the list carries a type the
//  system doesn't know.
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import NoteCode

@Suite("The app's own type names", .tags(.library))
struct ListDropTypeTests {

    @Test("Info.plist exports the list item's type")
    func exported() throws {
        let declared = try #require(Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]])
        let ids = declared.compactMap { $0["UTTypeIdentifier"] as? String }
        #expect(ids == [ListDrop.type.identifier])
    }

    @Test("Every name the app makes starts with its bundle id")
    func fromBundleID() throws {
        let bundle = try #require(Bundle.main.bundleIdentifier)
        #expect(ListDrop.type.identifier == "\(bundle).list-item")
        #expect(RichPaste.ownType == "\(bundle).markdown")
        #expect(NSAttributedString.Key.noteCodeSyntax.rawValue == "\(bundle).syntax")
    }
}
