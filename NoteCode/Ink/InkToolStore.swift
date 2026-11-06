//
//  InkToolStore.swift
//  NoteCode
//
//  What the ink tools are set to, in one place: the pen's and the
//  highlighter's colour and width, the eraser, the Select tool's shape,
//  Finger Draws, Return to Previous Tool, and the two palettes. The hotbar
//  (through `NoteEditor.inkTool`), the swatches, the options rows and
//  Settings › Drawing all read and write this, and it reads and writes
//  `UserDefaults` under the keys in `SettingKeys.Drawing`. It replaces the
//  editor's copy, `InkToolPersistence`, and the `@AppStorage`s of
//  `InkSwatches`, `DrawingSettings` and `SelectOptions`.
//
//  Per device, like the palettes and the dock: it is how this reader likes
//  to work, not part of any note. The tool in hand (`InkToolKind`) is the
//  note's, and is not stored.
//

#if canImport(UIKit)

import Foundation
import Observation

@Observable
final class InkToolStore {

    /// What a change was to, for whoever has to act on it (`NoteEditor`
    /// hands the new tool to its canvas).
    enum Change {
        /// The pen, highlighter, eraser or Select tool's shape.
        case tool
        case fingerDraws
        case returnsToPreviousTool
        case palette
    }

    /// The device's: every note's editor, and Settings. Backed by
    /// `UserDefaults.standard`.
    static let device = InkToolStore(defaults: .standard)

    // MARK: State

    var pen: InkingSettings {
        didSet { didSetValue(pen != oldValue, .tool) { $0.set(pen, for: SettingKeys.Drawing.penSettings) } }
    }

    var highlighter: InkingSettings {
        didSet { didSetValue(highlighter != oldValue, .tool) { $0.set(highlighter, for: SettingKeys.Drawing.highlighterSettings) } }
    }

    var eraser: EraserSettings {
        didSet { didSetValue(eraser != oldValue, .tool) { $0.set(eraser, for: SettingKeys.Drawing.eraser) } }
    }

    /// Lasso or rectangle.
    var selectionKind: SelectionKind {
        didSet { didSetValue(selectionKind != oldValue, .tool) { $0.set(selectionKind, for: SettingKeys.Drawing.selectionKind) } }
    }

    /// Whether a finger draws. Stored the way the hotbar's hand button says
    /// it, so a device that has never set it reads `true`.
    var fingerDraws: Bool {
        didSet { didSetValue(fingerDraws != oldValue, .fingerDraws) { $0.set(fingerDraws, for: SettingKeys.Drawing.fingerDraws) } }
    }

    /// Whether the selection ending sends the reader back to their tool.
    var returnsToPreviousTool: Bool {
        didSet { didSetValue(returnsToPreviousTool != oldValue, .returnsToPreviousTool) { $0.set(returnsToPreviousTool, for: SettingKeys.Drawing.returnToPreviousTool) } }
    }

    private var penPalette: InkPalette {
        didSet { didSetValue(penPalette != oldValue, .palette) { $0.set(penPalette, for: SettingKeys.Drawing.penPalette) } }
    }

    private var highlighterPalette: InkPalette {
        didSet { didSetValue(highlighterPalette != oldValue, .palette) { $0.set(highlighterPalette, for: SettingKeys.Drawing.highlighterPalette) } }
    }

    /// A tool's palette. Only the pen and highlighter have one; anything
    /// else answers with the pen's.
    subscript(palette kind: InkToolKind) -> InkPalette {
        get { kind == .highlighter ? highlighterPalette : penPalette }
        set {
            if kind == .highlighter {
                highlighterPalette = newValue
            } else {
                penPalette = newValue
            }
        }
    }

    // MARK: Making one

    /// - Parameter defaults: where the settings are kept. `nil` keeps them in
    ///   memory only, which is what an editor made without a device has, so a
    ///   test's tool changes reach no real settings.
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        pen = Self.read(SettingKeys.Drawing.penSettings, from: defaults)
        highlighter = Self.read(SettingKeys.Drawing.highlighterSettings, from: defaults)
        eraser = Self.read(SettingKeys.Drawing.eraser, from: defaults)
        selectionKind = Self.read(SettingKeys.Drawing.selectionKind, from: defaults)
        fingerDraws = Self.read(SettingKeys.Drawing.fingerDraws, from: defaults)
        returnsToPreviousTool = Self.read(SettingKeys.Drawing.returnToPreviousTool, from: defaults)
        penPalette = Self.read(SettingKeys.Drawing.penPalette, from: defaults)
        highlighterPalette = Self.read(SettingKeys.Drawing.highlighterPalette, from: defaults)

        if let defaults {
            observer = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Listening

    private struct Listener {
        weak var owner: AnyObject?
        let run: (AnyObject, Change) -> Void
    }

    @ObservationIgnored private var listeners: [Listener] = []

    /// Calls `run` with every change from now on, until `owner` is gone.
    /// Called as the value is set, so what it reads is already new.
    func listen<Owner: AnyObject>(_ owner: Owner, _ run: @escaping (Owner, Change) -> Void) {
        listeners.removeAll { $0.owner == nil }
        listeners.append(Listener(owner: owner) { owner, change in
            if let owner = owner as? Owner { run(owner, change) }
        })
    }

    // MARK: Keeping

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var observer: NSObjectProtocol?
    /// While `refresh` sets values the defaults already hold, so they are not
    /// written back.
    @ObservationIgnored private var refreshing = false

    private func didSetValue(_ changed: Bool, _ change: Change, write: (InkToolStore) -> Void) {
        guard changed else { return }
        if !refreshing { write(self) }
        for listener in listeners {
            if let owner = listener.owner { listener.run(owner, change) }
        }
    }

    private func set<Value: RawRepresentable>(_ value: Value, for key: SettingKey<Value>) where Value.RawValue == String {
        defaults?.set(value.rawValue, forKey: key.name)
    }

    private func set(_ value: Bool, for key: SettingKey<Bool>) {
        defaults?.set(value, forKey: key.name)
    }

    /// What is stored, or the entry's default where nothing is or what is
    /// there isn't a value (as `@AppStorage` reads it).
    private static func read<Value: RawRepresentable>(_ key: SettingKey<Value>, from defaults: UserDefaults?) -> Value where Value.RawValue == String {
        defaults?.string(forKey: key.name).flatMap(Value.init(rawValue:)) ?? key.defaultValue
    }

    private static func read(_ key: SettingKey<Bool>, from defaults: UserDefaults?) -> Bool {
        defaults?.object(forKey: key.name) as? Bool ?? key.defaultValue
    }

    /// Settings, a colour set or a reset wrote the defaults. Takes in what
    /// reaches an open note: the eraser, Finger Draws, Return to Previous
    /// Tool, the highlighter and the palettes.
    ///
    /// Not the pen or the Select tool's shape, which nothing in Settings
    /// writes: a pen written under an open note does not reach it (pinned by
    /// `InkToolPersistenceTests`, as found).
    private func refresh() {
        refreshing = true
        defer { refreshing = false }
        let eraser = Self.read(SettingKeys.Drawing.eraser, from: defaults)
        if self.eraser != eraser { self.eraser = eraser }
        let fingerDraws = Self.read(SettingKeys.Drawing.fingerDraws, from: defaults)
        if self.fingerDraws != fingerDraws { self.fingerDraws = fingerDraws }
        let returns = Self.read(SettingKeys.Drawing.returnToPreviousTool, from: defaults)
        if returnsToPreviousTool != returns { returnsToPreviousTool = returns }
        let highlighter = Self.read(SettingKeys.Drawing.highlighterSettings, from: defaults)
        if self.highlighter != highlighter { self.highlighter = highlighter }
        let penPalette = Self.read(SettingKeys.Drawing.penPalette, from: defaults)
        if self.penPalette != penPalette { self.penPalette = penPalette }
        let highlighterPalette = Self.read(SettingKeys.Drawing.highlighterPalette, from: defaults)
        if self.highlighterPalette != highlighterPalette { self.highlighterPalette = highlighterPalette }
    }
}

#endif
