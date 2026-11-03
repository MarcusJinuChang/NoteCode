//
//  DebugProbe.swift
//  NoteCode
//
//  `-debug-probe`: records what the system delivers to the app, in the app
//  container's `tmp/notecode-probe.log`, for a bug that only shows on the
//  iPad, where nobody can watch a console. Pull it with
//  `xcrun devicectl device copy from … --source tmp/notecode-probe.log`.
//  `-debug-probe-snapshot` also writes the window as `tmp/notecode-probe-N.png`
//  a few seconds after launch, to see what drew. Debug builds only.
//

#if DEBUG && canImport(UIKit)

import UIKit

nonisolated enum DeviceProbe {

    static let enabled = CommandLine.arguments.contains("-debug-probe")
    static let snapshots = CommandLine.arguments.contains("-debug-probe-snapshot")

    private static let queue = DispatchQueue(label: "notecode.probe")

    static var logURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notecode-probe.log")
    }

    /// Appends one timestamped line. A no-op without `-debug-probe`.
    static func log(_ line: @autoclosure () -> String) {
        guard enabled else { return }
        let text = "\(String(format: "%.3f", Date().timeIntervalSince1970)) \(line())\n"
        queue.sync {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(Data(text.utf8))
                try? handle.close()
            } else {
                try? Data(text.utf8).write(to: logURL)
            }
        }
    }

    /// Called once from the app's init. Waits for a window, then watches it.
    @MainActor static func start() {
        guard enabled else { return }
        try? FileManager.default.removeItem(at: logURL)
        log("probe start, \(UIDevice.current.systemVersion), \(UIDevice.current.model)")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard let window = keyWindow else { log("no window"); return }
            dumpInteractions(window)
            if CommandLine.arguments.contains("-debug-probe-watch") {
                let watcher = DropWatcher()
                window.rootViewController?.view.addInteraction(UIDropInteraction(delegate: watcher))
                retained.append(watcher)
                log("drop watcher on \(type(of: window.rootViewController!.view!))")
            }
            guard snapshots else { return }
            for index in 1...3 {
                try? await Task.sleep(for: .seconds(3))
                snapshot(window, index)
            }
        }
    }

    /// Every view that takes drops or starts drags: where, and who decides.
    @MainActor private static func dumpInteractions(_ view: UIView, depth: Int = 0) {
        for interaction in view.interactions where interaction is UIDropInteraction || interaction is UIDragInteraction {
            let delegate = (interaction as? UIDropInteraction)?.delegate ?? (interaction as? UIDragInteraction)?.delegate
            let frame = view.convert(view.bounds, to: nil)
            log("interaction \(type(of: interaction)) on \(type(of: view)) frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height)) enabled=\(interaction.view != nil) delegate=\(delegate.map { String(describing: type(of: $0)) } ?? "nil")")
        }
        for sub in view.subviews { dumpInteractions(sub, depth: depth + 1) }
    }

    @MainActor private static var retained: [AnyObject] = []

    @MainActor private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    @MainActor private static func snapshot(_ window: UIWindow, _ index: Int) {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notecode-probe-\(index).png")
        try? image.pngData()?.write(to: url)
        log("snapshot \(index) \(window.bounds.size)")
    }

    /// Asked about every drag that passes over the window, and takes it only
    /// where nothing deeper does: writes down what the session offers, and
    /// whether its updates reach this far.
    @MainActor private final class DropWatcher: NSObject, UIDropInteractionDelegate {
        private var updates = 0

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
            let types = session.items.map { $0.itemProvider.registeredTypeIdentifiers.joined(separator: "+") }
            DeviceProbe.log("UIKit canHandle: allowsMove=\(session.allowsMoveOperation) local=\(session.localDragSession != nil) items=\(types)")
            return true
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: any UIDropSession) {
            DeviceProbe.log("UIKit sessionDidEnter at \(session.location(in: interaction.view!))")
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession) -> UIDropProposal {
            updates += 1
            if updates % 20 == 1 { DeviceProbe.log("UIKit sessionDidUpdate #\(updates) at \(session.location(in: interaction.view!))") }
            return UIDropProposal(operation: .cancel)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: any UIDropSession) {
            DeviceProbe.log("UIKit sessionDidEnd after \(updates) updates")
        }
    }
}

#endif
