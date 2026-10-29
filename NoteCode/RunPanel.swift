//
//  RunPanel.swift
//  NoteCode
//
//  The Run panel: a block strip, Run, and Output | Input tabs. Self-contained
//  so it can be docked at the page's right edge, shown in a bottom sheet, or
//  later floated. docs/release-1.0/R-run.md › R3.
//

#if canImport(UIKit)

import SwiftUI
import UIKit

struct RunPanel: View {
    @Bindable var session: RunSession
    /// The signed transaction to send; empty for none.
    var transaction: () -> String
    /// A chip's tap: the note scrolls to the block.
    var onShow: (RunBlock) -> Void

    var body: some View {
        VStack(spacing: 0) {
            strip
            Divider()
            controls
            Divider()
            Group {
                switch session.tab {
                case .output: RunOutputView(session: session)
                case .input: RunInputView(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
    }

    // MARK: Block strip

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(session.blocks.enumerated()), id: \.element.id.ordinal) { index, block in
                    let isChosen = block.ordinal == session.chosen?.ordinal
                    Button {
                        session.choose(block)
                        onShow(block)
                    } label: {
                        Text("\(index + 1) · \(RunPanel.name(of: block.language))")
                            .font(.subheadline.weight(isChosen ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .chipFill(isChosen, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isChosen ? .isSelected : [])
                }
                if session.blocks.isEmpty {
                    Text("No code blocks to run")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: Run and tabs

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if session.isRunning { session.cancel() } else { session.run(transaction: transaction()) }
            } label: {
                Label(session.isRunning ? "Stop" : "Run", systemImage: session.isRunning ? "stop.fill" : "play.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.chosen == nil)
            .accessibilityIdentifier("runPanelRun")

            Picker("Panel", selection: $session.tab) {
                Text("Output").tag(RunSession.Tab.output)
                Text("Input").tag(RunSession.Tab.input)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    static func name(of language: CodeLanguage) -> String {
        switch language {
        case .cpp: "C++"
        case .java: "Java"
        case .python: "Python"
        case .c: "C"
        case .javascript: "JavaScript"
        case .rust: "Rust"
        case .go: "Go"
        case .sql: "SQL"
        }
    }
}

// MARK: - Output

private struct RunOutputView: View {
    var session: RunSession

    private static let error = Color(red: 1.0, green: 0.54, blue: 0.5)
    private static let code = Font.system(.callout, design: .monospaced)

    var body: some View {
        ZStack {
            Color(CodeOutputPanel.fillColor)
            if let block = session.chosen {
                content(for: block)
            } else {
                note("Add a fenced code block, tagged cpp, java, python and so on, and it appears here.")
            }
        }
    }

    @ViewBuilder
    private func content(for block: RunBlock) -> some View {
        if session.runningOrdinal == block.ordinal {
            VStack(spacing: 12) {
                ProgressView().tint(Color(CodeOutputPanel.textColor))
                Text("Running…").font(.subheadline).foregroundStyle(Color(CodeOutputPanel.labelColor))
            }
        } else if let record = session.record(for: block) {
            let stale = session.isStale(block)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if stale {
                        Label("Code changed since this run", systemImage: "clock.arrow.circlepath")
                            .font(.footnote)
                            .foregroundStyle(Color(CodeOutputPanel.controlColor))
                    }
                    outcome(record.outcome, for: block)
                        .opacity(stale ? 0.45 : 1)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                note("Press Run to see this block's output.")
                if ReadsInput.check(block.code, language: block.language), session.input(for: block).isEmpty {
                    note("This program reads input. Add it on the Input tab first.")
                }
            }
        }
    }

    @ViewBuilder
    private func outcome(_ outcome: RunOutcome, for block: RunBlock) -> some View {
        switch outcome {
        case .failure(let error):
            Label(RunPresentation.message(for: error), systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(Self.error)
            if RunPresentation.offersSite(after: error) {
                Button {
                    session.openAtSite?(block)
                } label: {
                    Label("Open on a Site Instead", systemImage: "arrow.up.right.square").font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(Color(CodeOutputPanel.controlColor))
                .accessibilityIdentifier("runPanelOpenAtSite")
            }
        case .result(let result):
            Text(RunPresentation.statusLine(result))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(result.status == .ok ? Color(CodeOutputPanel.labelColor) : Self.error)
            if let renamed = result.renamedJavaClass {
                Text("Ran with class \(renamed) renamed to Main.")
                    .font(.footnote).foregroundStyle(Color(CodeOutputPanel.labelColor))
            }
            if !result.stdout.isEmpty {
                Text(result.stdout)
                    .font(Self.code)
                    .foregroundStyle(Color(CodeOutputPanel.textColor))
                    .textSelection(.enabled)
            }
            ForEach([result.compileOutput, result.stderr].filter { !$0.isEmpty }, id: \.self) { text in
                Text(Self.linked(text, for: block))
                    .font(Self.code).foregroundStyle(Self.error).textSelection(.enabled)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == Self.lineScheme, let line = Int(url.host() ?? "") else { return .discarded }
                        session.showLine?(block, line)
                        return .handled
                    })
            }
            if result.truncated {
                Text("Output was cut short.").font(.footnote).foregroundStyle(Color(CodeOutputPanel.labelColor))
            }
            if result.stdout.isEmpty, result.stderr.isEmpty, result.compileOutput.isEmpty, result.status == .ok {
                note("The program printed nothing.")
                if ReadsInput.check(block.code, language: block.language), session.input(for: block).isEmpty {
                    note("It reads input; add some on the Input tab.")
                }
            }
            HStack(spacing: 10) {
                if !result.stdout.isEmpty {
                    Button {
                        UIPasteboard.general.string = result.stdout
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc").font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(CodeOutputPanel.controlColor))
                }
                // Not for output of code that has since changed.
                if let keep = KeepInNote.text(of: result), !session.isStale(block) {
                    Button {
                        session.keepInNote?(block.ordinal, keep)
                    } label: {
                        Label("Keep in Note", systemImage: "square.and.arrow.down").font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(CodeOutputPanel.controlColor))
                    .accessibilityIdentifier("runPanelKeepInNote")
                }
            }
        }
    }

    private static let lineScheme = "notecode-line"

    /// Compile output with each "file:line" made a link to that line of the block.
    private static func linked(_ text: String, for block: RunBlock) -> AttributedString {
        var attributed = AttributedString(text)
        let lineCount = block.code.split(separator: "\n", omittingEmptySubsequences: false).count
        for message in CompilerMessages.find(in: text, language: block.language, lineCount: lineCount) {
            guard let range = Range(message.range, in: attributed) else { continue }
            attributed[range].link = URL(string: "\(lineScheme)://\(message.line)")
            attributed[range].underlineStyle = .single
        }
        return attributed
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color(CodeOutputPanel.labelColor))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }
}

// MARK: - Input

private struct RunInputView: View {
    var session: RunSession

    var body: some View {
        if let block = session.chosen {
            VStack(alignment: .leading, spacing: 6) {
                Text("Standard input for block \(index(of: block))")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.top, 10)
                PlainInputField(
                    text: Binding(
                        get: { session.input(for: block) },
                        set: { session.setInput($0, for: block) }
                    )
                )
                .padding(.horizontal, 10)
            }
        } else {
            Text("No block chosen.").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func index(of block: RunBlock) -> Int {
        (session.blocks.firstIndex { $0.ordinal == block.ordinal } ?? 0) + 1
    }
}

/// A monospaced editor that leaves what's typed alone: no smart quotes, dashes
/// or autocorrect, which would change a program's input.
private struct PlainInputField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        view.backgroundColor = .clear
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.spellCheckingType = .no
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "runPanelInput"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PlainInputField
        init(_ parent: PlainInputField) { self.parent = parent }
        func textViewDidChange(_ view: UITextView) { parent.text = view.text }
    }
}

// MARK: - The dock

/// The panel as a pane at the page's right: a handle on its left edge to
/// drag its width, and a collapse to a thin tab. It only takes the width it
/// asks for out of the note's area; the page is never told its own size.
struct RunDock: View {
    @Bindable var session: RunSession
    var transaction: () -> String
    var onShow: (RunBlock) -> Void
    /// The window's width, for the half-window limit.
    var availableWidth: CGFloat

    @AppStorage(RunDockWidth.key) private var storedWidth = RunDockWidth.initial
    @State private var dragStart: Double?

    var body: some View {
        if session.isCollapsed {
            Button {
                withAnimation(.snappy) { session.isCollapsed = false }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 24)
                    .frame(maxHeight: .infinity)
                    .background(Color(.secondarySystemBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show Run panel")
        } else {
            let width = RunDockWidth.clamped(storedWidth, available: availableWidth)
            HStack(spacing: 0) {
                handle
                RunPanel(session: session, transaction: transaction, onShow: onShow)
                    .frame(width: width)
            }
        }
    }

    private var handle: some View {
        ZStack {
            Color(.separator).frame(width: 1)
            Capsule().fill(Color(.tertiaryLabel)).frame(width: 4, height: 36)
        }
        .frame(width: 18)
        .frame(maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { drag in
                    let start = dragStart ?? RunDockWidth.clamped(storedWidth, available: availableWidth)
                    dragStart = start
                    storedWidth = RunDockWidth.clamped(start - drag.translation.width, available: availableWidth)
                }
                .onEnded { _ in dragStart = nil }
        )
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation(.snappy) { session.isCollapsed = true }
            } label: {
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).frame(width: 18, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse Run panel")
        }
    }
}

/// The dock's width, app-wide: 360pt to start, 280pt to half the window.
nonisolated enum RunDockWidth {
    static let key = "runPanelWidth"
    static let initial = 360.0
    static let minimum = 280.0

    static func clamped(_ width: Double, available: CGFloat) -> CGFloat {
        let upper = max(minimum, Double(available) / 2)
        return CGFloat(min(max(width, minimum), upper))
    }
}

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

/// The block strip's chip: the accent when chosen (the same fill as Home's
/// buttons, so the accent setting reaches it), a quiet fill otherwise.
private struct ChipFill<S: Shape>: ViewModifier {
    let chosen: Bool
    let shape: S

    func body(content: Content) -> some View {
        if chosen {
            content.accentFill(in: shape)
        } else {
            content.foregroundStyle(.primary).background(Color(.tertiarySystemFill), in: shape)
        }
    }
}

private extension View {
    func chipFill<S: Shape>(_ chosen: Bool, in shape: S) -> some View {
        modifier(ChipFill(chosen: chosen, shape: shape))
    }
}

// MARK: - The host

/// What a note window adds for Run: the runner, the bottom sheet in a compact
/// width, the free reader's paywall, and the debug stub's autorun.
struct RunPanelHost: ViewModifier {
    var editor: NoteEditor
    var isCompact: Bool
    @Binding var showsRunIsPro: Bool
    @Binding var windowWidth: CGFloat
    var transaction: () -> String
    var pro: ProStatus?

    func body(content: Content) -> some View {
        content
            .task {
                editor.pro = pro
                editor.onRunNeedsPro = { showsRunIsPro = true }
                editor.connectRun()
                editor.run.runner = RunServiceFactory.make()
#if DEBUG
                if DebugLaunchOptions.current.runStub != nil {
                    try? await Task.sleep(for: .seconds(1))
                    editor.run.isOpen = true
                    editor.run.run(transaction: transaction())
                }
#endif
            }
            .sheet(isPresented: Binding(
                get: { editor.run.isOpen && isCompact },
                set: { if !$0 { editor.run.isOpen = false } }
            )) {
                RunPanel(session: editor.run, transaction: transaction, onShow: { editor.scroll(toBlock: $0) })
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
            .sheet(isPresented: $showsRunIsPro) {
                PaywallView(reason: "Run in the app is part of NoteCode Pro.")
            }
    }
}

#endif
