//
//  ContentView.swift
//  NoteCode
//

import SwiftUI
import SwiftData

struct ContentView: View {
    /// True when the on-disk store failed and edits live only in memory.
    var storageIsEphemeral = false

    @Environment(\.modelContext) private var modelContext
    /// Spike branch only — a demo of the page-geometry decision.
    @State private var showingGeometrySpike = false
    @Query(sort: \Page.modifiedAt, order: .reverse) private var pages: [Page]

    var body: some View {
        NavigationViewWrapper {
            List {
                if storageIsEphemeral {
                    Label(
                        "Storage is unavailable, so changes made now won't be saved.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }

                ForEach(pages) { page in
                    NavigationLink {
                        PageDetailView(page: page)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(page.title)
                                .font(.headline)
                            Text(page.modifiedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deletePages)
            }
            .navigationTitle("NoteCode")
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button(action: addPage) {
                        Label("Add Page", systemImage: "plus")
                    }
                }
#if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Geometry") { showingGeometrySpike = true }
                }
#endif
            }
#if os(iOS)
            .fullScreenCover(isPresented: $showingGeometrySpike) {
                GeometrySpike()
            }
#endif
        }
    }

    private func addPage() {
        withAnimation {
            modelContext.insert(Page())
        }
    }

    private func deletePages(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(pages[index])
            }
        }
    }
}

fileprivate struct NavigationViewWrapper<Content: View>: View {
    let content: () -> Content

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            content()
        } detail: {
            Text("Select a page")
        }
#else
        NavigationStack {
            content()
        }
#endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Page.self, inMemory: true)
}
