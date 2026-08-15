//
//  ContentView.swift
//  NoteCode
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Page.modifiedAt, order: .reverse) private var pages: [Page]

    var body: some View {
        NavigationViewWrapper {
            List {
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
            }
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
