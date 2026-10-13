//
//  FolderAppearanceTests.swift
//  NoteCodeTests
//
//  v3 phase 1: a folder's colour and symbol, and the editor that sets them.
//

import Foundation
import SwiftData
import Testing
@testable import NoteCode

#if canImport(UIKit)
import UIKit
#endif

@Suite("Folder appearance")
@MainActor
struct FolderAppearanceTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        let schema = NoteSchema.current
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    // MARK: Contrast

    /// WCAG relative luminance of a 24-bit sRGB value.
    private static func luminance(_ hex: Int) -> Double {
        let channels = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { byte -> Double in
            let c = Double(byte) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    private static func contrast(_ a: Int, _ b: Int) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    @Test("A symbol on its tint is 3:1 or better, in every colour and both appearances",
          arguments: FolderColor.allCases, [false, true])
    func symbolContrast(color: FolderColor, isDark: Bool) {
        let ratio = Self.contrast(color.symbol(isDark: isDark), color.tint(isDark: isDark))
        #expect(ratio >= 3, "\(color.title) \(isDark ? "dark" : "light"): \(ratio):1")
    }

    @Test("The calculation can fail: a symbol the colour of its tint is 1:1")
    func contrastCanFail() {
        #expect(Self.contrast(0xFFE9CF, 0xFFE9CF) < 1.01)
        // The base colour on its light tint is below the bar for yellow, which
        // is why the symbol has a darker value of its own.
        #expect(Self.contrast(FolderColor.yellow.base, FolderColor.yellow.tint(isDark: false)) < 3)
    }

    @Test("The eight colours are the design's, in its order, with the base colours of the ink palette")
    func colours() {
        #expect(FolderColor.allCases.map(\.rawValue) ==
            ["orange", "red", "yellow", "green", "blue", "teal", "purple", "graphite"])
        #expect(FolderColor.allCases.map(\.base) ==
            [0xFA8500, 0xDA101E, 0xEBB000, 0x27A551, 0x066EE5, 0x00727A, 0x8E22C3, 0x6C6C70])
        #expect(FolderColor.orange.tint(isDark: false) == 0xFFE9CF)
        #expect(FolderColor.orange.symbol(isDark: true) == 0xFFAA33)
        #expect(FolderColor.graphite.tint(isDark: true) == 0x2C2C2E)
        #expect(FolderColor.default == .orange)
    }

    // MARK: Symbols

    @Test("The editor offers sixteen distinct symbols, ending with the plain folder")
    func symbols() {
        #expect(FolderSymbol.all.count == 16)
        #expect(Set(FolderSymbol.all).count == 16)
        #expect(FolderSymbol.all.last == FolderSymbol.default)
        #expect(FolderSymbol.all.allSatisfy { !FolderSymbol.title(of: $0).isEmpty })
        #expect(Set(FolderSymbol.all.map(FolderSymbol.title(of:))).count == 16, "VoiceOver can tell them apart")
    }

#if canImport(UIKit)
    @Test("Every symbol exists in the system's set, so none draws as nothing")
    func symbolsExist() {
        for symbol in FolderSymbol.all {
            #expect(UIImage(systemName: symbol) != nil, "\(symbol) is not an SF Symbol on this OS")
        }
    }
#endif

    // MARK: A folder's face

    @Test("A folder that never chose is orange, with the folder symbol")
    func defaults() {
        let folder = Folder(name: "CS133")
        #expect(folder.color == .orange)
        #expect(folder.symbol == "folder")
    }

    @Test("What is stored is read back; what isn't recognised falls back instead of failing")
    func storedAndUnknown() {
        let folder = Folder(name: "CS186")
        folder.colorName = "blue"
        folder.symbolName = "cylinder"
        #expect(folder.color == .blue)
        #expect(folder.symbol == "cylinder")

        // A later build's colour, or a symbol outside the editor's set.
        folder.colorName = "magenta"
        folder.symbolName = "not.a.symbol"
        #expect(folder.color == .orange)
        #expect(folder.symbol == "folder")
    }

    // MARK: The editor's draft

    @Test("A new folder's draft starts blank, orange and plain; renaming starts from the folder")
    func draftStart() {
        let blank = FolderDraft()
        #expect(blank.name == "" && blank.color == .orange && blank.symbol == "folder")

        let folder = Folder(name: "CS186")
        folder.colorName = "blue"
        folder.symbolName = "cylinder"
        let draft = FolderDraft(editing: folder)
        #expect(draft.name == "CS186" && draft.color == .blue && draft.symbol == "cylinder")
    }

    @Test("Creating makes the folder with the name, colour and symbol chosen, and moves the note into it")
    func draftCreates() throws {
        let page = Page(title: "Lecture 1")
        context.insert(page)
        var draft = FolderDraft()
        draft.name = "  CS186 · Databases \n"
        draft.color = .blue
        draft.symbol = "cylinder"

        let folder = draft.apply(to: nil, moving: page, in: context)
        try context.save()

        #expect(folder.name == "CS186 · Databases")
        #expect(folder.colorName == "blue" && folder.symbolName == "cylinder")
        #expect(page.folder == folder)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Folder>()) == 1)
    }

    @Test("A blank name still makes a folder, named as before")
    func draftBlankName() {
        let folder = FolderDraft().apply(to: nil, in: context)
        #expect(folder.name == "Untitled Folder")
    }

    @Test("Saving a rename changes the folder in place, and its notes stay")
    func draftRenames() throws {
        let folder = Folder(name: "CS133")
        context.insert(folder)
        let page = Page(title: "Lecture 1")
        context.insert(page)
        page.folder = folder

        var draft = FolderDraft(editing: folder)
        draft.name = "CS133 · C++"
        draft.color = .teal
        draft.symbol = "terminal"
        let result = draft.apply(to: folder, in: context)

        #expect(result === folder)
        #expect(folder.name == "CS133 · C++")
        #expect(folder.color == .teal && folder.symbol == "terminal")
        #expect(folder.pages == [page])
        #expect(try context.fetchCount(FetchDescriptor<Folder>()) == 1, "no second folder was made")
    }
}
