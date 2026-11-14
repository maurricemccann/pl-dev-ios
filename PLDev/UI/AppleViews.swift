import SwiftUI

// The apple lane's screens (11-13): the Settings rows for each Apple door, the card Siri shows, the Handoff activity,
// and the sheet for a caption drafted on the phone.

/// Settings rows, placed under House's rows: Health, Calendar, haptics, Apple Intelligence.
struct AppleSettingsRows: View {
    @AppStorage("pldev.health.mindful") private var health = false
    @AppStorage("pldev.haptics") private var haptics = true
    @AppStorage("pldev.intel") private var intel = true
    @State private var note: String?
    @State private var busy = false

    var body: some View {
        Group {
            Toggle(isOn: $health) { SettingsLabel("Mindful minutes in Health", "heart.text.square", IOS27.SystemColors.pink) }
                .onChange(of: health) { _, on in
                    guard on else { return }
                    Task {
                        if let problem = await PLHealth.enable() { health = false; note = problem } else { note = "Rehearsals now write mindful minutes to Health." }
                    }
                }
            Button { Task { busy = true; note = await PLCalendar.addShifts(model: AppModel.shared); busy = false } } label: {
                SettingsLabel("Add my shift days to Calendar", "calendar.badge.plus", IOS27.SystemColors.red)
            }.disabled(busy)
            Button { Task { busy = true; note = await PLCalendar.addDrops(model: AppModel.shared); busy = false } } label: {
                SettingsLabel("Add drop dates to Calendar", "calendar.badge.clock", IOS27.SystemColors.orange)
            }.disabled(busy)
            Toggle(isOn: $haptics) { SettingsLabel("Haptics for keep, cut and crown", "hand.tap", IOS27.SystemColors.indigo) }
            Toggle(isOn: $intel) { SettingsLabel("Draft on this iPhone with Apple Intelligence", "apple.intelligence", IOS27.SystemColors.purple) }
            Text(PLIntelligence.statusLine + " Drafts are shown to you and never posted until you approve them. A Focus can hold these notices: add the PL DEV filter in Settings, Focus.")
                .plFont(.footnote).foregroundStyle(.secondary)
            if let note { Text(note).plFont(.footnote).foregroundStyle(.secondary) }
        }
    }
}

/// The card Siri shows under its spoken answer: a title and a few label/value rows.
struct AppleCard: View {
    let title: String
    let rows: [(String, String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1).font(.subheadline.monospacedDigit().weight(.semibold))
                }
            }
        }
        .padding()
    }
}

/// Handoff and Siri suggestions: the screen he is on is an activity another device (or Siri) can pick up again.
struct AppleActivity: ViewModifier {
    static let type = "com.psychedluxuries.dev.open"
    let model: AppModel

    func body(content: Content) -> some View {
        content
            .userActivity(Self.type) { a in
                let link = model.route?.url.absoluteString ?? "pldev://home"
                a.title = model.route.flatMap { Self.title($0) } ?? "PL DEV"
                a.userInfo = ["link": link]
                a.isEligibleForHandoff = true
                a.isEligibleForSearch = true
                a.isEligibleForPrediction = true
                a.persistentIdentifier = link
                a.suggestedInvocationPhrase = "Open PL DEV"
            }
            .onContinueUserActivity(Self.type) { a in
                if let text = a.userInfo?["link"] as? String, let url = URL(string: text), let link = DeepLink(url: url) { model.open(link) }
            }
    }

    private static func title(_ link: DeepLink) -> String? {
        if case .section(let id, _, _) = link { return "PL DEV \u{00B7} " + id.capitalized }
        return nil
    }
}

extension View {
    func appleActivity(model: AppModel) -> some View { modifier(AppleActivity(model: model)) }
}

/// A caption written by Apple Intelligence on this phone, from the draft he long-pressed. A draft only: copy it or close it.
struct AppleCaptionSheet: View {
    let seed: String
    let platform: String?
    @State private var text: String?
    @State private var working = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if working { ProgressView("Writing on this iPhone") }
                else if let text {
                    Text(text).plFont(.body).textSelection(.enabled)
                    Button { UIPasteboard.general.string = text } label: { Label("Copy the draft", systemImage: "doc.on.doc") }.buttonStyle(.borderedProminent)
                    Text("A draft from Apple Intelligence, on this phone. Nothing is posted.").plFont(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(PLIntelligence.isReady ? "It could not write a caption in the house voice this time. Try again." : PLIntelligence.statusLine).plFont(.body).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Offline draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { text = await PLIntelligence.captionDraft(seed: seed, platform: platform); working = false }
        }
    }
}
