//
//  NoteThumbnail.swift
//  NoteCode
//
//  A picture of a note's first page, for the list's rows and Home's cards.
//

import CryptoKit
import Foundation
import SwiftData
import SwiftUI

#if canImport(UIKit)
import PaperKit
import UIKit
#endif

// MARK: - What a thumbnail is made from

/// The pure rules of a thumbnail: how much of a note it is drawn from, and what
/// a cached picture is called.
nonisolated enum NoteThumbnail {

    /// Bumped when the picture changes for a reason other than the note, so
    /// thumbnails made the old way aren't shown. 2: phase 3's hidden
    /// markers. 3: step 10's room around code blocks. 4: code in the light
    /// theme's colours, which a thumbnail made on a dark device didn't have
    /// (16 Oct). 5: spans that nest, whose markers were drawn before (text
    /// overhaul, phase 2, 18 Oct). 6: underline, highlight, quotes and rules,
    /// which a note written before drew as their markers (phase 6, 19 Oct).
    /// 7: paper styles. 8: formulas, which the thumbnail now draws (LaTeX, step 6).
    /// 9: paper styles gone (31 Oct), and with them the cache name's ruling.
    static let version = 9

    /// Pixels per page point: a Letter page is 449 by 581.
    ///
    /// The largest place one is shown is Home's Continue card, 136pt by 176pt
    /// at two pixels to the point, so this is a little over what it needs.
    static let pixelsPerPagePoint: CGFloat = 0.55

    /// The most paragraphs, and the most characters, a thumbnail is drawn from.
    ///
    /// **A thumbnail never lays out the whole note.** TextKit lays out what it
    /// is asked for, and a 2,000-line note laid out to draw page 1 costs a
    /// second or more. So the printed text view is fed only a prefix long
    /// enough to fill one page. A page is 912pt of body in portrait; the
    /// shortest line (code in its smaller type, or a blank line) is over 17pt,
    /// so a page holds at most about 52 paragraphs, and 80 is clear of that.
    /// Characters: a full page of wrapped prose is under 6,000, and code
    /// lines clip rather than wrap, so 8,000 is clear of that too. Whichever
    /// limit comes first ends the prefix, so a single enormous paragraph can't
    /// make the prefix the whole note.
    static let maxParagraphs = 80
    static let maxCharacters = 8_000

    /// The part of `text` a thumbnail is drawn from.
    static func prefix(of text: String) -> String {
        let capped = text.prefix(maxCharacters)
        var paragraphs = 0
        var end = capped.endIndex
        for index in capped.indices where capped[index] == "\n" {
            paragraphs += 1
            if paragraphs == maxParagraphs {
                end = index
                break
            }
        }
        return String(capped[..<end])
    }

    /// What a note's cached thumbnail is called: the note, and when it last
    /// changed. A new date is a new name, so a stale picture is never read
    /// back, and no file timestamp is consulted to decide (the privacy
    /// manifest would need a reason for that).
    ///
    /// `nil` for a note that has no permanent ID yet.
    ///
    /// A note's layout is part of the name too: hiding its Markdown markers
    /// (the title menu) isn't an edit and leaves `modifiedAt` alone, but the
    /// first page looks different afterwards. So is its text size
    /// (`Page.textSize`) and its line spacing (`Page.lineSpacing`), which
    /// aren't edits either; the defaults add nothing, so a note nobody
    /// changed keeps the name it had.
    static func cacheName(
        for id: PersistentIdentifier,
        modifiedAt: Date,
        rendersMarkdown: Bool = false,
        typography: NoteTypography = .standard
    ) -> String? {
        guard let key = NoteMemory.key(for: id) else { return nil }
        let digest = SHA256.hash(data: Data(key.utf8))
        let owner = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        let milliseconds = Int((modifiedAt.timeIntervalSince1970 * 1000).rounded())
        let size = typography.bodySize == NoteTypography.defaultSize ? "" : "-t\(typography.bodySize)"
        let spacing = typography.lineSpacing == 0 ? "" : "-s\(typography.lineSpacing)"
        return "\(owner)-\(milliseconds)\(rendersMarkdown ? "-r" : "")\(size)\(spacing).png"
    }

    /// Whether the picture is shown dark: in a dark appearance, where the
    /// page itself is `systemBackground` (black), not white (`PageView.pageColor`).
    ///
    /// The picture is still made once, on light paper in the light theme
    /// (so one cached PNG serves both appearances), and shown inverted with
    /// its hues turned back by half a turn, which is the same flip of
    /// lightness the dark page applies to ink (docs/design/colour.md): white
    /// paper to black, black text to white, a red pen to a light red, a code
    /// panel to a dark one.
    static func isShownDark(colorScheme: ColorScheme) -> Bool {
        colorScheme == .dark
    }

    /// The part of a cache name that is the note's alone, to find the older
    /// pictures of the same note.
    static func owner(ofCacheName name: String) -> Substring {
        name.prefix { $0 != "-" }
    }
}

// MARK: - Reading a note's ink

/// Reads `Page.drawingData` without the main actor (F7).
///
/// The attribute is external storage, so reading it is a file read, and for a
/// note with thousands of strokes a megabyte or more. It is read through a
/// context of its own, made on the thread that asks: a `Page` belongs to the
/// main context, and its attributes can't be read from anywhere else.
///
/// **A note that is gone reads as empty.** A fetch finds only rows the store
/// still has, so a note whose deletion has been saved never has its ink
/// touched (AGENTS.md › Implementation requirements); the caller checks the
/// page on the main actor before asking and again after.
nonisolated enum NoteInk {

    /// Reads a note's ink bytes: the container and the note's ID in, the bytes
    /// out. Tests pass their own to see where the read happens.
    typealias Loader = @Sendable (ModelContainer, PersistentIdentifier) async -> Data

    /// The ink as the store has it, read off the main actor.
    static let load: Loader = { container, id in
        await Task.detached(priority: .userInitiated) {
            read(container: container, id: id)
        }.value
    }

    /// Told, for tests, whether each read ran on the main thread.
    nonisolated(unsafe) static var observeRead: (@Sendable (_ onMain: Bool) -> Void)?

    /// Synchronous, for the thread it is called on.
    static func read(container: ModelContainer, id: PersistentIdentifier) -> Data {
        observeRead?(Thread.isMainThread)
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Page>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first)?.drawingData ?? Data()
    }
}

// MARK: - Drawing

#if canImport(UIKit)

extension NoteThumbnail {

    /// What a thumbnail is drawn from, read off the note on the main actor.
    struct Source {
        var text: String
        var orientation: PageOrientation
        var drawingData: Data
        var rendersMarkdown = false
        var typography = NoteTypography.standard
    }

    /// The first page of a note, drawn the way the PDF draws a sheet
    /// (`PrintedNote`, `NotePDF.drawInk`) in light appearance, at
    /// `pixelsPerPagePoint`.
    ///
    /// Paper is white, always: one picture is made and cached for both
    /// appearances, and a dark one is shown inverted (`isShownDark`).
    @MainActor
    static func render(_ source: Source) async -> UIImage? {
        let printed = await PrintedNote(
            text: prefix(of: source.text),
            orientation: source.orientation,
            rendersMarkdown: source.rendersMarkdown,
            typography: source.typography
        )
        // The prefix's own pages: enough bands for its lines to fall where
        // they would in the whole note, which is all page 1 needs.
        let pageCount = printed.paginate(inkBottom: nil, startingAt: 1)
        let layout = printed.layout
        let sheet = layout.sheet(ofPage: 0)
        let paragraphs = printed.paragraphsByPage(pageCount: pageCount)[0]

        let scale = pixelsPerPagePoint
        let width = Int((sheet.width * scale).rounded())
        let height = Int((sheet.height * scale).rounded())
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // UIKit's way up, in page points, origin at the sheet's top left: the
        // PDF flips its context the same way.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)

        printed.draw(paragraphs, onSheet: sheet, in: context)

        // Only the ink that touches page 1 is decoded into the sheet; the
        // rest of a long note's strokes are walked once to find it.
        // Decoding is PaperKit parsing a blob, so it is done off the main actor.
        let data = source.drawingData
        let loaded = data.isEmpty ? .none : await Task.detached(priority: .userInitiated) { DrawingCodec.decode(data) }.value
        if case .ink(let markup) = loaded, !markup.subelements.isEmpty {
            // One sheet: every element is filed under it, then kept only if
            // its frame reaches it.
            let first = NotePDF.sheetsInk(markup, layout: layout, pageCount: 1)[0]
            if !first.isEmpty {
                await NotePDF.drawInk(first, onSheet: sheet, in: context, pixelsPerPagePoint: scale)
            }
        }

        return context.makeImage().map { UIImage(cgImage: $0, scale: 1, orientation: .up) }
    }
}

// MARK: - The cache

/// Makes thumbnails one at a time and keeps them: in memory for the session,
/// and as PNGs in Caches, which the system may empty whenever it likes.
///
/// **One per turn of the main actor.** Making one means a text view, a
/// layout and a syntax highlight, all on the main actor. A list of fifty
/// notes asking at once would hold the main thread for seconds, so requests
/// queue (`Gate`) and each yields before it starts: scrolling and typing get
/// their turn between pictures. A card that scrolls away cancels its request,
/// and a cancelled request is skipped when its turn comes.
@MainActor
final class ThumbnailStore {

    static let shared = ThumbnailStore()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let gate = Gate()
    private let inkLoader: NoteInk.Loader

    /// - Parameters:
    ///   - directory: where pictures are kept. Tests pass their own.
    ///   - inkLoader: how a note's ink is read; off the main actor by default.
    init(directory: URL? = nil, inkLoader: @escaping NoteInk.Loader = NoteInk.load) {
        self.inkLoader = inkLoader
        self.directory = directory ?? (FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appending(path: "NoteThumbnails-v\(NoteThumbnail.version)", directoryHint: .isDirectory)
        memory.countLimit = 120
    }

    /// How many pictures have been drawn (not read back) since launch, for
    /// tests to see whether a request was served from the cache.
    private(set) var rendered = 0

    /// The picture for `page` as it is now, if one is already kept.
    func existing(for page: Page) -> UIImage? {
        guard let name = Self.name(for: page) else { return nil }
        return stored(name)
    }

    /// The picture for `page`, made if it isn't kept. `nil` when the task is
    /// cancelled first, or the note has gone.
    func thumbnail(for page: Page) async -> UIImage? {
        guard let name = Self.name(for: page) else { return nil }
        if let kept = stored(name) { return kept }

        await gate.enter()
        defer { gate.leave() }
        // Offscreen by now, or made by whoever was ahead in the queue.
        guard !Task.isCancelled else { return nil }
        if let kept = stored(name) { return kept }
        await Task.yield()
        guard !Task.isCancelled else { return nil }

        // The note can go while a request waits. Reading the ink of a note
        // whose deletion has been saved traps (AGENTS.md).
        guard let container = page.modelContext?.container, !page.isDeleted, page.isLive,
              let id = page.settledID(), Self.name(for: page) == name
        else { return nil }

        // That context sees only what is saved, and a stroke sets the ink and
        // `modifiedAt` without saving (`DrawingSaveScheduler`). Read before
        // the autosave, the old ink was drawn and kept under the new date's
        // name, and every launch after served it (list-x1). So the note is
        // saved first, as autosave would within seconds (`settledID` does
        // the same).
        if page.hasChanges, let context = page.modelContext {
            Storage.save(context, reason: "save a note before reading its ink for a thumbnail")
        }

        // The ink is read off the main actor (F7), through a context of its
        // own, so a purge that lands during the read can't trap this one.
        let ink = await inkLoader(container, id)
        guard !Task.isCancelled else { return nil }
        // Gone, or edited, while the read ran.
        guard page.modelContext != nil, !page.isDeleted, page.isLive,
              Self.name(for: page) == name
        else { return nil }

        let source = NoteThumbnail.Source(
            text: page.content,
            orientation: page.orientation,
            drawingData: ink,
            rendersMarkdown: true,
            typography: page.typography
        )
        guard let image = await NoteThumbnail.render(source) else { return nil }
        rendered += 1
        keep(image, as: name)
        return image
    }

    // MARK: Files

    private static func name(for page: Page) -> String? {
        guard page.modelContext != nil, !page.isDeleted,
              let id = page.settledID()
        else { return nil }
        return NoteThumbnail.cacheName(
            for: id,
            modifiedAt: page.modifiedAt,
            rendersMarkdown: true,
            typography: page.typography
        )
    }

    private func stored(_ name: String) -> UIImage? {
        if let image = memory.object(forKey: name as NSString) { return image }
        // A missing file is a nil image; nothing asks the file system first.
        guard let data = try? Data(contentsOf: directory.appending(path: name, directoryHint: .notDirectory)),
              let image = UIImage(data: data)
        else { return nil }
        memory.setObject(image, forKey: name as NSString)
        return image
    }

    private func keep(_ image: UIImage, as name: String) {
        memory.setObject(image, forKey: name as NSString)
        guard let data = image.pngData() else { return }
        let files = FileManager.default
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appending(path: name, directoryHint: .notDirectory), options: .atomic)

        // The note's older pictures are no use to anyone.
        let owner = NoteThumbnail.owner(ofCacheName: name)
        for other in (try? files.contentsOfDirectory(atPath: directory.path)) ?? []
        where other != name && NoteThumbnail.owner(ofCacheName: other) == owner {
            memory.removeObject(forKey: other as NSString)
            try? files.removeItem(at: directory.appending(path: other, directoryHint: .notDirectory))
        }
    }

    /// A queue of one: whoever asks first goes first, the rest wait their turn
    /// in order.
    ///
    /// A class: `enter` suspends, and a struct held across a suspension would
    /// be an exclusive access to the store's property that every other request
    /// then trips over.
    @MainActor
    private final class Gate {
        private var busy = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func enter() async {
            if !busy {
                busy = true
                return
            }
            await withCheckedContinuation { waiting.append($0) }
        }

        func leave() {
            if waiting.isEmpty {
                busy = false
            } else {
                waiting.removeFirst().resume()
            }
        }
    }
}

#endif

// MARK: - The view

/// A note's first page, as a small picture: the list's 30 by 39 and Home's
/// larger cards.
///
/// Shows the last picture it had while a newer one is made, so a note edited
/// while its row is on screen doesn't flash to blank, and waits for typing to
/// pause before it asks for the new one.
struct NoteThumbnailView: View {
    let page: Page

    /// How the picture sits in its box: the whole page, or the top of it filling
    /// the width (Home's Recent cards show the top of the page).
    enum Fit { case whole, top }
    var fit: Fit = .whole

    /// What a picture is of, for the task that makes it to start over on.
    private struct Picture: Hashable {
        var modifiedAt: Date
        var textSize: Int?
        var lineSpacing: Int?
    }

    /// How long the note must be left alone before its new picture is made.
    static let settleDelay: Duration = .milliseconds(600)

#if canImport(UIKit)
    @State private var image: UIImage?
#endif

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        paper
            .modifier(DarkPaper(isDark: NoteThumbnail.isShownDark(colorScheme: colorScheme)))
            .overlay {
                // The page's edge, so a sheet reads on a row of its own colour.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
#if canImport(UIKit)
            // `modifiedAt` as the id: a new date is a new picture. So is a
            // new text size, which leaves the date alone.
            .task(id: Picture(modifiedAt: page.modifiedAt, textSize: page.textSize, lineSpacing: page.lineSpacing)) { await refresh() }
#endif
    }

    /// The picture in a dark appearance (`NoteThumbnail.isShownDark`).
    private struct DarkPaper: ViewModifier {
        let isDark: Bool
        func body(content: Content) -> some View {
            if isDark {
                content.colorInvert().hueRotation(.degrees(180))
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var paper: some View {
#if canImport(UIKit)
        if let image {
            switch fit {
            case .whole:
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            case .top:
                Color.white
                    .overlay(alignment: .top) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
            }
        } else {
            Color.white
        }
#else
        Color.white
            .overlay {
                Image(systemName: "doc.text")
                    .foregroundStyle(.tertiary)
            }
#endif
    }

#if canImport(UIKit)
    private func refresh() async {
        let store = ThumbnailStore.shared
        // Already made: no wait.
        if let kept = store.existing(for: page) {
            image = kept
            return
        }
        // Edits come a keystroke at a time, each with a new date.
        if image != nil {
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
        }
        if let made = await store.thumbnail(for: page) {
            image = made
        }
    }
#endif
}
