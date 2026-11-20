//
//  text-edit-while-ink-probe.swift
//
//  Spike for docs/design/object-system.md, step 4: ink mode makes the text view
//  non-editable and non-selectable (`EditorMode.apply`). Recolouring selected text
//  from the Select tool has to edit it anyway. Does `replace(_:withText:)`, the
//  path every formatting button uses, work then? Built for and run on the
//  simulator like object-system-probe.swift:
//
//      scripts/spikes/run-object-system-probe.sh <udid> scripts/spikes/text-edit-while-ink-probe.swift
//

import UIKit

@main
struct Probe {
    @MainActor
    static func main() {
        func attempt(_ label: String, editable: Bool, selectable: Bool, resigned: Bool) {
            let view = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
            view.text = "hello world"
            view.isEditable = editable
            view.isSelectable = selectable
            _ = resigned
            let start = view.position(from: view.beginningOfDocument, offset: 6)!
            let end = view.position(from: view.beginningOfDocument, offset: 11)!
            let range = view.textRange(from: start, to: end)!
            view.replace(range, withText: "<span>world</span>")
            let viaStorage: String
            view.textStorage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "HELLO")
            viaStorage = view.text
            print("    \(label): replace(_:withText:) -> \"\(viaStorage)\"")
        }
        print("text-edit-while-ink probe")
        attempt("editable, selectable (text mode)", editable: true, selectable: true, resigned: false)
        attempt("not editable, not selectable (ink mode)", editable: false, selectable: false, resigned: true)
        attempt("not editable, selectable (locked note)", editable: false, selectable: true, resigned: true)

        let locked = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        locked.text = "abc"
        locked.isEditable = false
        let undo = locked.undoManager
        print("    undoManager of an unattached text view: \(undo == nil ? "nil" : "present")")
    }
}
