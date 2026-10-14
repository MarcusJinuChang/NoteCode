//
//  NoteOutlineView.swift
//  NoteCode
//
//  The outline popover, and the page badge that shows where the reader is.
//

#if canImport(UIKit)

import SwiftUI

/// The note's headings, indented by level, with the one the reader is under
/// marked. A tap goes there.
struct NoteOutlineView: View {
    var entries: [NoteOutline.Entry]
    /// Index into `entries`.
    var current: Int?
    var onSelect: (NoteOutline.Entry) -> Void

    /// How far each level indents, from the note's highest.
    private static let indent: CGFloat = 14

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Headings",
                    systemImage: "list.bullet.indent",
                    description: Text("Lines that start with # appear here.")
                )
            } else {
                list
            }
        }
        .frame(width: 320, height: min(CGFloat(max(entries.count, 3)) * 44 + 24, 420))
        .presentationCompactAdaptation(.popover)
    }

    private var list: some View {
        let top = NoteOutline.topLevel(of: entries)
        return ScrollViewReader { proxy in
            List {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        HStack(spacing: 8) {
                            Text(entry.title.isEmpty ? "Untitled" : entry.title)
                                .font(entry.level == top ? .body.weight(.semibold) : .body)
                                .foregroundStyle(entry.title.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if index == current {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.leading, CGFloat(entry.level - top) * Self.indent)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(index == current ? .isSelected : [])
                    .accessibilityHint("Scrolls to this heading")
                    .id(entry.id)
                }
            }
            .listStyle(.plain)
            .onAppear {
                if let current { proxy.scrollTo(entries[current].id, anchor: .center) }
            }
        }
    }
}

/// "2 / 5", top centre of the page, while the note scrolls.
struct PageBadge: View {
    var place: NoteMemory.Place?
    var isVisible: Bool

    var body: some View {
        if let place {
            Text("\(place.number) / \(place.of)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: .capsule)
                .overlay { Capsule().strokeBorder(.separator, lineWidth: 0.5) }
                .opacity(isVisible ? 1 : 0)
                // Said by the page, not read out on every scroll.
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

#endif
