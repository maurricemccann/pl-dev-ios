import SwiftUI

/// Settings → Changes the app made: what the app changed on his Yes, newest first, each with Undo that restores the setting before it.
struct ChangesMadeSection: View {
    @AppStorage("pldev.todayLead") private var todayLead = ""
    @AppStorage("pldev.appliedChanges") private var appliedJSON = "[]"

    var body: some View {
        let log = (try? JSONDecoder().decode([ProposalRules.Change].self, from: Data(appliedJSON.utf8))) ?? []
        Section {
            if log.isEmpty {
                Text("Nothing yet. The app proposes at most one change a week, in This week, honestly.").plFont(.footnote).foregroundStyle(.secondary)
            }
            ForEach(log.reversed()) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.text).plFont(.callout)
                        Text(c.at).plFont(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Undo") {
                        guard let r = ProposalRules.undo(log, id: c.id) else { return }
                        todayLead = r.restore
                        if let d = try? JSONEncoder().encode(r.rest), let j = String(data: d, encoding: .utf8) { appliedJSON = j }
                    }
                    .buttonStyle(.bordered).frame(minWidth: 44, minHeight: 44)
                }
            }
        } header: {
            Text("Changes the app made")
        } footer: {
            Text("Layout only: the order of Captures and the drip on Today. It never changes a number.").plFont(.footnote)
        }
    }
}
