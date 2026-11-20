//
//  SelectionProbe.swift
//  NoteCode
//
//  Debug-only log for two unexplained things about PaperKit's selection
//  (docs/design/object-system.md, step 0): which tool or touch makes it
//  highlight a cluster of strokes, and why the hotbar moves after a lasso
//  move. Off unless launched with `-debug-selection-probe`; writes
//  `tmp/selectionprobe.log` in the app container, pulled with devicectl as
//  in the device-probe notes.
//

#if DEBUG
#if canImport(UIKit)

import PaperKit
import UIKit

@MainActor
enum SelectionProbe {

    static let isOn = ProcessInfo.processInfo.arguments.contains("-debug-selection-probe")

    private static let url = FileManager.default.temporaryDirectory.appending(path: "selectionprobe.log")
    private static var attached = false
    private static weak var canvas: DrawingCanvas?
    private static let started = ProcessInfo.processInfo.systemUptime

    static func log(_ line: @autoclosure () -> String) {
        guard isOn else { return }
        let seconds = ProcessInfo.processInfo.systemUptime - started
        let text = String(format: "%9.3f ", seconds) + line() + "\n"
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Called from the canvas once it is in a window. Installs the touch log
    /// and the keyboard observers, once per process.
    static func attach(to canvas: DrawingCanvas) {
        guard isOn else { return }
        Self.canvas = canvas
        guard !attached, let window = canvas.window else { return }
        attached = true
        log("probe attached; window \(window.frame.size), safeArea \(window.safeAreaInsets)")

        window.addGestureRecognizer(TouchLog())

        let names: [Notification.Name] = [
            UIResponder.keyboardWillShowNotification, UIResponder.keyboardWillHideNotification,
            UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification,
        ]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                let local = note.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool
                MainActor.assumeIsolated {
                    SelectionProbe.log("\(name.rawValue.replacingOccurrences(of: "UIKeyboard", with: "")) end \(end.map { "\($0)" } ?? "nil") local \(local.map(String.init) ?? "nil"); \(snapshot())")
                }
            }
        }
    }

    /// Where things are, on one line: the text view's insets and offset, the
    /// page's frame, who has the keyboard, and the canvas's tool and selection.
    static func snapshot() -> String {
        guard let canvas else { return "no canvas" }
        let textView = canvas.superview as? UIScrollView
        let page = textView?.superview
        let responder = UIResponder.currentFirstResponder
        let tool = String(describing: type(of: canvas.tool))
        let first = responder.map { String(describing: type(of: $0)) } ?? "none"
        return "tool \(tool), pkSelection \(canvas.controller.selection.count), firstResponder \(first), "
            + "textView inset \(textView?.contentInset ?? .zero) offset \(textView?.contentOffset ?? .zero), "
            + "page frame \(page?.frame ?? .zero), window safeArea \(canvas.window?.safeAreaInsets ?? .zero)"
    }

    /// Sees every touch in the window and logs where it landed and what it
    /// hit, without taking any: never begins, so nothing else is affected.
    private final class TouchLog: UIGestureRecognizer {
        override init(target: Any?, action: Selector?) {
            super.init(target: target, action: action)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        convenience init() {
            self.init(target: nil, action: nil)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            for touch in touches { record("down", touch) }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            for touch in touches { record("up", touch) }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            for touch in touches { record("cancelled", touch) }
        }

        private func record(_ phase: String, _ touch: UITouch) {
            let type: String
            switch touch.type {
            case .direct: type = "finger"
            case .pencil: type = "pencil"
            case .indirectPointer: type = "pointer"
            default: type = "other"
            }
            var chain: [String] = []
            var view = touch.view
            while let current = view, chain.count < 4 {
                chain.append(String(describing: Swift.type(of: current)))
                view = current.superview
            }
            let point = touch.location(in: nil)
            SelectionProbe.log("touch \(phase) \(type) at (\(Int(point.x)), \(Int(point.y))) taps \(touch.tapCount) on \(chain.joined(separator: " < "))")
            if phase != "down" {
                // A moment later, so what the touch caused has happened.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    MainActor.assumeIsolated { SelectionProbe.log("  after \(phase): \(SelectionProbe.snapshot())") }
                }
            }
        }
    }
}

extension DrawingCanvas {

    /// For the probe: what PaperKit tells its delegate.
    func probeDelegate(_ event: String) {
        SelectionProbe.log("\(event): \(SelectionProbe.snapshot())")
    }
}

#endif
#endif
