//
//  AIFeatures.swift
//  NoteCode
//
//  The vocabulary of the two on-device assistant features, Explain Code and
//  Summarise Note: what is asked, what the model must offer, and the settings.
//  Pure, so everything but the model itself is testable (docs/design/ai-features.md).
//

import Foundation

/// What the reader asked for.
nonisolated enum AIAction: String, Equatable, Sendable {
    case explainBlock
    case summariseNote

    var title: String {
        switch self {
        case .explainBlock: "Explain Code"
        case .summariseNote: "Summarise Note"
        }
    }

    /// The name in a menu: a free reader's is marked Pro, as the Run
    /// control's is, since choosing it opens the paywall.
    func menuTitle(marksPro: Bool) -> String {
        marksPro ? "\(title) (Pro)" : title
    }

    var systemImage: String {
        switch self {
        case .explainBlock: "sparkles"
        case .summariseNote: "text.append"
        }
    }
}

/// How long an answer should be. A request asks for it in words and caps it in
/// tokens, so a model that ignores the words is still bounded.
nonisolated enum AIAnswerLength: String, CaseIterable, Sendable, Identifiable {
    case brief
    case standard
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brief: "Brief"
        case .standard: "Standard"
        case .detailed: "Detailed"
        }
    }

    /// How the instructions put the length.
    var guide: String {
        switch self {
        case .brief: "two or three sentences"
        case .standard: "one paragraph of four to six sentences"
        case .detailed: "up to three short paragraphs"
        }
    }

    /// The most the model may write.
    var maximumResponseTokens: Int {
        switch self {
        case .brief: 160
        case .standard: 350
        case .detailed: 700
        }
    }
}

/// What "Insert below" writes.
nonisolated enum AIInsertStyle: String, CaseIterable, Sendable, Identifiable {
    case quote
    case output

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quote: "Quote"
        case .output: "Output Block"
        }
    }
}

/// Settings › Writing › On-Device Assistant, as the assistant needs them: one
/// value and one `apply(to:)`, so none can be set on its own and forgotten.
nonisolated struct AIFeatureSettings: Equatable, Sendable {

    static let enabledKey = "aiEnabled"
    static let lengthKey = "aiAnswerLength"
    static let insertStyleKey = "aiInsertStyle"

    /// On, where the model exists. The switch only ever turns the features
    /// off; it can't make an unavailable model available.
    var isEnabled = true
    var length = AIAnswerLength.standard
    var insertStyle = AIInsertStyle.quote

    init(isEnabled: Bool = true, length: AIAnswerLength = .standard, insertStyle: AIInsertStyle = .quote) {
        self.isEnabled = isEnabled
        self.length = length
        self.insertStyle = insertStyle
    }

    /// From the stored values `@AppStorage` holds. A value the pickers
    /// couldn't have written reads as the default.
    init(isEnabled: Bool, length: String, insertStyle: String) {
        self.init(
            isEnabled: isEnabled,
            length: AIAnswerLength(rawValue: length) ?? .standard,
            insertStyle: AIInsertStyle(rawValue: insertStyle) ?? .quote
        )
    }

    init(defaults: UserDefaults) {
        self.init(
            isEnabled: defaults.object(forKey: Self.enabledKey) as? Bool ?? true,
            length: defaults.string(forKey: Self.lengthKey) ?? "",
            insertStyle: defaults.string(forKey: Self.insertStyleKey) ?? ""
        )
    }
}

/// Why the assistant can't answer, in words for the reader.
nonisolated enum AIUnavailableReason: Equatable, Sendable {
    /// Settings › Writing › On-Device Assistant is off.
    case switchedOff
    /// This device can't run Apple Intelligence.
    case deviceNotEligible
    /// Apple Intelligence is off in the system's Settings.
    case appleIntelligenceOff
    /// The model is still downloading or preparing.
    case modelNotReady
    /// The model doesn't support the device's language.
    case languageNotSupported

    var message: String {
        switch self {
        case .switchedOff:
            "The on-device assistant is switched off in Settings › Writing."
        case .deviceNotEligible:
            "This \(AppInfo.deviceName) can't run Apple Intelligence, which the assistant uses."
        case .appleIntelligenceOff:
            "Turn on Apple Intelligence in the system's Settings to use the assistant."
        case .modelNotReady:
            "The on-device model is still getting ready. Try again in a little while."
        case .languageNotSupported:
            "Apple Intelligence doesn't support this device's language yet."
        }
    }

    /// Whether the menus leave the items out. A switch the reader turned off
    /// or a device that never can offer nothing worth tapping; the other
    /// reasons can change, so the item stays and the sheet says why.
    var hidesMenuItems: Bool {
        self == .switchedOff || self == .deviceNotEligible
    }
}

nonisolated enum AIAvailability: Equatable, Sendable {
    case available
    case unavailable(AIUnavailableReason)
}

/// One call to the model: the standing instructions, the text it works on, and
/// a cap on what it may write.
nonisolated struct AIRequest: Equatable, Sendable {
    var instructions: String
    var prompt: String
    var maximumResponseTokens: Int
}

/// What a client can fail with, in terms the sheet can word.
nonisolated enum AIClientError: Error, Equatable, Sendable {
    /// The request didn't fit the model's context.
    case contextTooLong
    /// A guardrail or refusal: the model won't answer this.
    case declined
    case languageNotSupported
    case timedOut
    case failed
}

/// The model, as the assistant sees it. The app's is `SystemTextModelClient`
/// (Apple's on-device model); tests use a deterministic fake, so everything
/// but the model is tested without one.
nonisolated protocol TextModelClient: Sendable {
    var availability: AIAvailability { get }

    /// The model's context window in tokens, for the prompt's budget.
    var contextTokens: Int { get }

    /// Streams the answer; each element is the whole answer so far, not a
    /// delta. Finishes by returning, fails by throwing (`AIClientError`), and
    /// stops when the task consuming it is cancelled.
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error>
}

extension AIFeatureSettings {
    /// Hands the settings to the assistant, which acts on them as a run starts.
    @MainActor
    func apply(to assistant: AIAssistant) {
        if assistant.settings != self { assistant.settings = self }
    }
}
