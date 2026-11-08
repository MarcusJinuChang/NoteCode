//
//  NotesRunToggle.swift
//  NoteCode
//
//  The top bar's Notes | Run switch. Split from RunPanel.swift (D4).
//

#if canImport(UIKit)

import SwiftUI
import UIKit

/// The top bar's Notes | Run control. The Run segment carries a small Pro
/// mark for a free reader.
struct NotesRunToggle: View {
    var isRun: Bool
    var showsProMark: Bool
    var onSelect: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment("Notes", selected: !isRun) { onSelect(false) }
            segment("Run", selected: isRun, mark: showsProMark) { onSelect(true) }
        }
        .padding(2)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .fixedSize()
    }

    private func segment(_ title: String, selected: Bool, mark: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.subheadline.weight(.medium))
                if mark {
                    Text("PRO")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .accentFill(in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(selected ? Color(.systemBackground) : .clear, in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mark ? "\(title), part of Pro" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#endif
