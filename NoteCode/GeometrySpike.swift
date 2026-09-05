//
//  GeometrySpike.swift
//  NoteCode
//
//  A throwaway demo for one decision: when the available width changes —
//  because the iPad rotated, or entered Split View — should the text column
//  keep its authored width and just scale, or take the new width and re-wrap?
//
//  Not part of the app. Lives on the spike/page-geometry branch only.
//

import SwiftUI

// MARK: - Deterministic page layout

/// The demo hand-wraps its text so every character position is predictable.
///
/// The real editor lets TextKit do this. Here the only thing being shown is
/// what changes when the column width changes, and a monospaced grid makes
/// the ink coordinates exact rather than approximate — which is the whole
/// point, since the question is whether ink and text stay lined up.
enum PageLayout {
    static let fontSize: CGFloat = 16
    static let margin: CGFloat = 28

    /// A monospaced face advances at roughly 0.6 em per character.
    static var advance: CGFloat { fontSize * 0.6 }
    static var lineHeight: CGFloat { fontSize * 1.55 }

    static func columns(forWidth width: CGFloat) -> Int {
        max(20, Int((width - margin * 2) / advance))
    }

    /// Greedy word wrap — the same rule TextKit uses, minus the subtleties.
    static func wrap(_ text: String, columns: Int) -> [String] {
        var lines: [String] = []

        for paragraph in text.components(separatedBy: "\n") {
            guard !paragraph.isEmpty else { lines.append(""); continue }

            var line = ""
            for word in paragraph.split(separator: " ") {
                let candidate = line.isEmpty ? String(word) : line + " " + word
                if candidate.count <= columns {
                    line = candidate
                } else {
                    lines.append(line)
                    line = String(word)
                }
            }
            if !line.isEmpty { lines.append(line) }
        }

        return lines
    }

    /// Where a run of characters sits, in page points.
    static func rect(line: Int, column: Int, length: Int) -> CGRect {
        CGRect(
            x: margin + CGFloat(column) * advance,
            y: margin + CGFloat(line) * lineHeight,
            width: CGFloat(length) * advance,
            height: lineHeight
        )
    }

    /// Finds a word in a particular wrapped layout.
    static func locate(_ needle: String, in lines: [String]) -> CGRect {
        for (index, line) in lines.enumerated() {
            guard let range = line.range(of: needle) else { continue }
            let column = line.distance(from: line.startIndex, to: range.lowerBound)
            return rect(line: index, column: column, length: needle.count)
        }
        return rect(line: 0, column: 0, length: needle.count)
    }

    /// What text currently sits under a rect. This is how the demo proves
    /// drift: the ink never moves, so this readout changing *is* the bug.
    static func text(under rect: CGRect, in lines: [String]) -> String {
        let line = Int((rect.midY - margin) / lineHeight)
        guard lines.indices.contains(line) else { return "nothing — past the end" }

        let chars = Array(lines[line])
        let start = max(0, Int((rect.minX - margin) / advance))
        guard start < chars.count else { return "nothing — past the line end" }

        let count = max(1, Int(rect.width / advance))
        let slice = String(chars[start..<min(chars.count, start + count)])
        let trimmed = slice.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "blank space" : trimmed
    }
}

// MARK: - Sample note

private let sampleNote = """
Loop invariants — CS133 lecture 4

An invariant is a condition that holds before and after every iteration of a loop. To prove a loop correct you show three things: it is true before the first iteration, each iteration preserves it, and on exit the invariant plus the exit condition give the result you wanted.

For binary search the invariant is that if the target is in the array at all, it lies within lo...hi. Initialisation is trivial. Each iteration discards a half that cannot contain the target, so the invariant is preserved. On exit lo is greater than hi, the range is empty, and the target was never there.

The subtle part is the midpoint. Writing lo + (hi - lo) / 2 rather than (lo + hi) / 2 avoids the overflow that sat in the JDK for nine years.
"""

/// The word the handwritten annotation was drawn around.
private let annotatedWord = "preserved"

// MARK: - The spike

struct GeometrySpike: View {
    enum Mode: String, CaseIterable, Identifiable {
        case scale  = "Two display scales"
        case reflow = "Two layout widths"
        var id: String { rawValue }
    }

    /// The single width the document is authored at, in the scale reading.
    static let referenceWidth: CGFloat = 700

    @State private var mode: Mode = .scale
    @State private var deviceWidth: CGFloat = 1032

    @Environment(\.dismiss) private var dismiss

    // The width the text actually wraps to.
    private var layoutWidth: CGFloat {
        mode == .scale ? Self.referenceWidth : deviceWidth
    }

    // How much the whole page — text and ink together — is magnified.
    private var scale: CGFloat {
        mode == .scale ? deviceWidth / Self.referenceWidth : 1
    }

    private var lines: [String] {
        PageLayout.wrap(sampleNote, columns: PageLayout.columns(forWidth: layoutWidth))
    }

    /// Where the ink was drawn, recorded once against the authored layout and
    /// then never touched again. This is what "stored in page coordinates"
    /// means, and why re-wrapping the text strands it.
    private var inkRect: CGRect {
        let authored = PageLayout.wrap(
            sampleNote,
            columns: PageLayout.columns(forWidth: Self.referenceWidth)
        )
        return PageLayout.locate(annotatedWord, in: authored)
    }

    private var underTheInk: String {
        PageLayout.text(under: inkRect, in: lines)
    }

    private var isAligned: Bool { underTheInk == annotatedWord }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                Divider()
                page
            }
            .navigationTitle("Page geometry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Reading", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Text("Screen width")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $deviceWidth, in: 700...1376)
                Button("Portrait") { withAnimation { deviceWidth = 1032 } }
                    .buttonStyle(.bordered)
                Button("Landscape") { withAnimation { deviceWidth = 1376 } }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 26) {
                readout("Screen", "\(Int(deviceWidth))pt")
                readout("Text wraps at", "\(Int(layoutWidth))pt")
                readout("Magnified", String(format: "%.2f×", scale))
                readout("Lines", "\(lines.count)")
            }

            HStack(spacing: 8) {
                Image(systemName: isAligned ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text("Under the ink: ")
                    + Text("\u{201C}\(underTheInk)\u{201D}").bold()
                    + Text("  ·  drawn around \u{201C}\(annotatedWord)\u{201D}")
            }
            .font(.callout)
            .foregroundStyle(isAligned ? Color.green : Color.orange)
        }
        .padding()
    }

    private func readout(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .monospacedDigit()
        }
    }

    // MARK: The page itself

    private var pageHeight: CGFloat {
        PageLayout.margin * 2 + CGFloat(lines.count) * PageLayout.lineHeight
    }

    private var page: some View {
        ScrollView([.vertical, .horizontal]) {
            ZStack(alignment: .topLeading) {
                Color(uiColor: .secondarySystemBackground)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: PageLayout.fontSize, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize()
                            .frame(height: PageLayout.lineHeight, alignment: .leading)
                    }
                }
                .padding(.leading, PageLayout.margin)
                .padding(.top, PageLayout.margin)

                ink
            }
            .frame(width: layoutWidth, height: pageHeight, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: layoutWidth * scale, height: pageHeight * scale, alignment: .topLeading)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    /// A stand-in for a PKDrawing stroke: a hand-drawn ring around a word,
    /// stored in page coordinates and rendered exactly where it was drawn.
    private var ink: some View {
        Ellipse()
            .stroke(Color.purple.opacity(0.85), lineWidth: 2.5)
            .frame(width: inkRect.width + 20, height: inkRect.height + 12)
            .offset(x: inkRect.minX - 10, y: inkRect.minY - 6)
    }
}

#Preview {
    GeometrySpike()
}
