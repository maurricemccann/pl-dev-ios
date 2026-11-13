import AppIntents

// These compile into the app and every extension. The two that open something bring the app to the
// foreground, so the system runs them in the app's process, where IntentBridge.open is set.

/// Opens a section by id. "home" and "settings" open those screens.
struct OpenSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open a Section"
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Section", default: "home") var section: String

    init() {}

    init(section: String) {
        self.section = section
    }

    static func link(for section: String) -> DeepLink {
        switch section {
        case "", "home": return .home
        case "settings": return .settings
        default: return .section(id: section, path: [], query: [:])
        }
    }

    @MainActor func perform() async throws -> some IntentResult {
        let link = OpenSectionIntent.link(for: section)
        try await IntentBridge.whenReady { IntentBridge.open?(link) }
        return .result()
    }
}

/// Opens the capture section. Until that section exists the app lands on Home with the inbox chip.
struct OpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Capture"
    static let supportedModes: IntentModes = .foreground

    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "capture", path: [], query: [:])) }
        return .result()
    }
}

/// Says how many items are waiting to be sent. Reads only what is already on the phone.
struct InboxCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Inbox Count"
    static let description: IntentDescription? = "Says how many items are waiting to be sent."

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The app's last count covers its send queue; the folder count covers what arrived since.
        let count = max(SharedState.readSnapshot()?.inboxCount ?? 0, SharedInbox.all().count)
        let line: String
        switch count {
        case 0: line = "Nothing is waiting."
        case 1: line = "One item is waiting."
        default: line = "\(count) items are waiting."
        }
        return .result(dialog: "\(line)")
    }
}
