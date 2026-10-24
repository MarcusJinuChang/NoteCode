//
//  ExportAll.swift
//  NoteCode
//
//  Export All Notes: a folder with a subfolder per folder and a Markdown file
//  per note, and optionally a PDF beside each note that has ink.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A folder for `fileExporter` to write out.
///
/// **`FileDocument` is deprecated in iOS 27**, in favour of `WritableDocument`
/// (a class with a snapshot and a writer) or `Transferable`. It is used
/// anyway: a directory `FileWrapper` is the long-standing way to export a
/// folder, and neither replacement was found to say what happens to a folder.
/// The plural-`contentTypes` overload is the one with a cancellation callback.
///
/// SwiftUI's exporter takes a document, and a document that is a folder is a
/// directory `FileWrapper`. The wrapper here points at files already written
/// to a temporary directory and reads them as the exporter copies them, so a
/// semester of PDFs isn't held in memory at once.
struct ExportFolderDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    static var writableContentTypes: [UTType] { [.folder] }

    var wrapper: FileWrapper

    init(wrapper: FileWrapper = FileWrapper(directoryWithFileWrappers: [:])) {
        self.wrapper = wrapper
    }

    /// Never opened: the exporter only writes.
    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        wrapper
    }
}

/// Writes the notes into a temporary folder, one at a time, so the sheet can
/// show progress and the reader can stop it.
@MainActor
@Observable
final class NoteExportJob {

    enum State: Equatable {
        case idle
        case working(done: Int, total: Int)
        /// Written, and waiting for the reader to pick where it goes.
        case ready(notes: Int)
        case failed(String)
    }

    private(set) var state = State.idle

    /// The folder to hand to the exporter, once `state` is `.ready`.
    private(set) var document = ExportFolderDocument()

    /// The folder's name, and the exporter's suggested file name.
    private(set) var rootName = ""

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var workDirectory: URL?

    /// Which run owns the job's state. Stopping a run and starting another
    /// leaves the first still unwinding for a moment, and it must not clear
    /// the second's folder or report its own failure over it.
    @ObservationIgnored private var generation = 0

    var isWorking: Bool {
        if case .working = state { return true }
        return false
    }

    /// Starts writing `pages`, which must be live ones (`Page.live`), into a
    /// temporary folder.
    ///
    /// - Parameter includePDFs: add a PDF beside each note that has ink.
    ///   Ink is the only thing a Markdown file loses, and a text-only note's
    ///   PDF would say what its `.md` already does. Ignored on the Mac, which
    ///   can't draw one.
    func start(pages: [Page], folders: [Folder], includePDFs: Bool, now: Date = .now) {
        guard !isWorking else { return }
        cleanUp()
        generation += 1
        let run = generation
        state = .working(done: 0, total: pages.count)
        rootName = NoteExport.rootName(on: now)

        task = Task { [weak self] in
            await self?.run(run, pages: pages, folders: folders, includePDFs: includePDFs)
        }
    }

    /// Stops, and removes what was written.
    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        cleanUp()
    }

    /// Removes the temporary folder, once the exporter has copied it or the
    /// reader has given up.
    func cleanUp() {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
        workDirectory = nil
        document = ExportFolderDocument()
        state = .idle
    }

    private func run(_ run: Int, pages: [Page], folders: [Folder], includePDFs: Bool) async {
        let layout = Self.layout(of: pages, in: folders)
        let plan = layout.plan

        let work = FileManager.default.temporaryDirectory
            .appending(path: "Export \(UUID().uuidString)", directoryHint: .isDirectory)
        let root = work.appending(path: rootName, directoryHint: .isDirectory)
        workDirectory = work

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for directory in plan.directories {
                try FileManager.default.createDirectory(
                    at: root.appending(path: directory, directoryHint: .isDirectory),
                    withIntermediateDirectories: true
                )
            }

            for (done, entry) in plan.entries.enumerated() {
                try checkStillWanted(run)
                state = .working(done: done, total: plan.entries.count)
                // One note per turn of the main actor, so the progress bar
                // moves and Cancel can be tapped between notes.
                await Task.yield()

                let page = layout.pages[entry.item]
                // The note can go while the export runs; its ink can't be read
                // once its deletion is saved (AGENTS.md).
                guard page.modelContext != nil, !page.isDeleted, page.isLive else { continue }

                let directory = entry.directory.map { root.appending(path: $0, directoryHint: .isDirectory) } ?? root
                try checkStillWanted(run)
                try NoteMarkdown.data(for: page.content).write(
                    to: directory.appending(path: entry.markdownName, directoryHint: .notDirectory),
                    options: .atomic
                )
#if canImport(UIKit)
                if includePDFs, let pdf = await Self.pdf(of: page) {
                    try pdf.write(
                        to: directory.appending(path: entry.pdfName, directoryHint: .notDirectory),
                        options: .atomic
                    )
                }
#endif
            }
            try checkStillWanted(run)

            document = ExportFolderDocument(wrapper: try FileWrapper(url: root, options: []))
            state = .ready(notes: plan.entries.count)
        } catch {
            try? FileManager.default.removeItem(at: work)
            // A newer run, or a cancel, owns the state now.
            guard run == generation else { return }
            if error is CancellationError {
                cleanUp()
            } else {
                workDirectory = nil
                state = .failed("There may not be enough free space on this device. Free some up and try again.")
            }
        }
    }

    private func checkStillWanted(_ run: Int) throws {
        try Task.checkCancellation()
        if run != generation { throw CancellationError() }
    }

    /// The notes in the order they are named in (oldest first, so a
    /// re-export gives two notes of one title the same names), and the plan.
    struct Layout {
        var pages: [Page]
        var plan: NoteExport.Plan
    }

    static func layout(of pages: [Page], in folders: [Folder]) -> Layout {
        let sortedFolders = folders.live.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        var folderIndex: [PersistentIdentifier: Int] = [:]
        for (index, folder) in sortedFolders.enumerated() {
            folderIndex[folder.persistentModelID] = index
        }
        let parents = sortedFolders.map { $0.parent.flatMap { folderIndex[$0.persistentModelID] } }
        let sortedPages = pages.sorted {
            ($0.createdAt, $0.title) < ($1.createdAt, $1.title)
        }
        let items = sortedPages.map {
            NoteExport.Item(folder: $0.folder.flatMap { folderIndex[$0.persistentModelID] }, title: $0.title)
        }
        return Layout(
            pages: sortedPages,
            plan: NoteExport.plan(folderNames: sortedFolders.map(\.name), parents: parents, items: items)
        )
    }
}

#if canImport(UIKit)
import PaperKit

extension NoteExportJob {
    /// The note as a PDF, if it has ink to keep.
    ///
    /// The same PDF the Share button makes, from the stored ink (print
    /// layout's coordinates) and the note's own layout settings, so it breaks
    /// lines where the screen does.
    private static func pdf(of page: Page) async -> Data? {
        guard case .ink(let markup) = DrawingCodec.decode(page.drawingData),
              !markup.subelements.isEmpty
        else { return nil }
        let numbered = UserDefaults.standard.object(forKey: LineNumbers.defaultsKey) as? Bool
            ?? LineNumbers.enabledByDefault
        let data = await NotePDF.render(NotePDF.Note(
            title: page.title,
            text: page.content,
            ink: markup,
            orientation: page.orientation,
            minimumPages: page.minimumPageCount,
            rendersMarkdown: true,
            lineNumbers: numbered,
            typography: page.typography
        ))
        return data.isEmpty ? nil : data
    }
}
#endif

// MARK: - The sheet

/// Export All Notes as a sheet from the list's •••, with its own Cancel.
struct ExportAllSheet: View {
    var onFinished: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExportAllView(onFinished: onFinished)
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

/// The export's page: what it makes, the PDF switch, progress, and Export….
/// Shown in a sheet (`ExportAllSheet`) and as a page of Settings › Notes.
struct ExportAllView: View {
    /// Called with the number of notes exported, after the reader has chosen
    /// where they went.
    var onFinished: (Int) -> Void

    @Query private var pages: [Page]
    @Query private var folders: [Folder]

    @State private var job = NoteExportJob()
    @State private var includePDFs = true
    @State private var showsExporter = false
    @State private var errorMessage: String?

    private var livePages: [Page] { pages.live }

    var body: some View {
        Form {
            Section {
                Text("A folder with a subfolder for each of your folders and a Markdown file for each note. Notes in Recently Deleted are left out.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

#if canImport(UIKit)
            Section {
                Toggle("Include PDFs, with ink", isOn: $includePDFs)
                    .disabled(job.isWorking)
            } footer: {
                Text("A PDF is added beside each note that has ink, since Markdown can't hold a drawing. PDFs take longest.")
            }
#endif

            Section("What you'll get") {
                Text(preview)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("exportPreview")
            }

            Section {
                progress
                action
            }
        }
        .navigationTitle("Export All Notes")
        .fileExporter(
            isPresented: $showsExporter,
            document: job.document,
            contentTypes: [.folder],
            defaultFilename: job.rootName,
            onCompletion: finish,
            onCancellation: { job.cleanUp() }
        )
        .alert("Couldn't export", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: job.state) { _, state in
            switch state {
            case .ready: showsExporter = true
            case .failed(let message): errorMessage = message
            default: break
            }
        }
        // Leaving the page stops the export and removes what it wrote.
        .onDisappear {
            if job.isWorking { job.cancel() }
        }
    }

    // MARK: Pieces

    private var preview: String {
        let layout = NoteExportJob.layout(of: livePages, in: folders)
        if layout.pages.isEmpty && layout.plan.directories.isEmpty { return "There are no notes to export." }
        return NoteExport.tree(of: layout.plan, root: NoteExport.rootName(on: .now))
    }

    @ViewBuilder
    private var progress: some View {
        if case .working(let done, let total) = job.state {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Exporting \(min(done + 1, total)) of \(total)")
                    Spacer()
                    if includePDFs { Text("PDFs take longest").foregroundStyle(.secondary) }
                }
                .font(.footnote)
                ProgressView(value: Double(done), total: Double(max(total, 1)))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("exportProgress")
        }
    }

    @ViewBuilder
    private var action: some View {
        if job.isWorking {
            Button("Cancel Export", role: .destructive) { job.cancel() }
                .accessibilityIdentifier("exportCancel")
        } else {
            Button("Export…") {
                job.start(pages: livePages, folders: folders, includePDFs: includePDFs)
            }
            .disabled(livePages.isEmpty && folders.live.isEmpty)
            .accessibilityIdentifier("exportStart")
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        let count: Int
        if case .ready(let notes) = job.state { count = notes } else { count = 0 }
        job.cleanUp()
        switch result {
        case .success:
            onFinished(count)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
