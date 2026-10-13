//
//  Toast.swift
//  NoteCode
//
//  The brief message that follows an action, with an Undo where there is one.
//

import SwiftUI

/// One message, and the action it offers.
struct Toast: Identifiable, Equatable {
    struct Action: Equatable {
        let title: String
        /// The handler is left out of equality: two toasts are the same toast
        /// by `id`, and closures can't be compared.
        let handler: @MainActor () -> Void

        static func == (lhs: Action, rhs: Action) -> Bool { lhs.title == rhs.title }
    }

    let id = UUID()
    let message: String
    var action: Action?
}

/// Shows one toast at a time, and takes it away after four seconds.
///
/// A new toast replaces the one showing and restarts the clock, so deleting
/// three notes in a row leaves one message, not a stack. `ContentView` owns
/// the center and puts it in the environment; the list and the open note's
/// page each draw `current` where they have room (`ToastView`).
///
/// VoiceOver is told when a toast appears, since it vanishes by itself and
/// the reader may never land on it.
@MainActor
@Observable
final class ToastCenter {
    /// How long a toast stays: four seconds.
    static let defaultDuration: Duration = .seconds(4)

    private(set) var current: Toast?

    private let duration: Duration

    /// - Parameter duration: how long a toast stays. Tests pass a short one.
    init(duration: Duration = ToastCenter.defaultDuration) {
        self.duration = duration
    }

    private var dismissal: Task<Void, Never>?

    /// Shows `message`, with a button if `actionTitle` is given.
    func show(_ message: String, actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        let toast = Toast(
            message: message,
            action: actionTitle.flatMap { title in action.map { Toast.Action(title: title, handler: $0) } }
        )
        current = toast
        AccessibilityNotification.Announcement(
            [message, actionTitle].compactMap { $0 }.joined(separator: ". ")
        ).post()

        dismissal?.cancel()
        dismissal = Task { [weak self, duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, self?.current?.id == toast.id else { return }
            self?.current = nil
        }
    }

    /// Takes the toast away now, as pressing its button does.
    func dismiss() {
        dismissal?.cancel()
        current = nil
    }

    /// Runs the toast's action, then takes it away.
    func performAction() {
        guard let handler = current?.action?.handler else { return }
        dismiss()
        handler()
    }
}

/// The toast as a capsule: 40pt tall, 15pt text, a material that stays
/// readable over a page of any colour, and a pill-shaped button for the action.
struct ToastView: View {
    let toast: Toast
    var onAction: () -> Void

    static let height: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.system(size: 15))
                .lineLimit(1)
            if let action = toast.action {
                Button(action: onAction) {
                    Text(action.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Color.accentColor.opacity(0.14), in: .capsule)
                        // The pill looks 28pt; the button is the toast's full
                        // height, so a finger doesn't have to find it.
                        .frame(height: Self.height)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toastAction")
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, toast.action == nil ? 18 : 6)
        .frame(height: Self.height)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(Color(white: 0.5).opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}

/// Where a toast is drawn: a bottom-centred overlay that animates a toast in
/// and out, with a fade under Reduce Motion.
struct ToastOverlay: View {
    var center: ToastCenter
    /// How far above the bottom edge the toast sits.
    var bottomInset: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast = center.current {
                ToastView(toast: toast, onAction: center.performAction)
                    .padding(.bottom, bottomInset)
                    .padding(.horizontal, 16)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy, value: center.current?.id)
        // No background and no content shape: only the toast takes touches,
        // and the rest of the overlay lets them through to what is beneath.
    }
}
