import SwiftUI

/// First open of the Practice (S350, from the "One Year" teardown, App Breakdown #91): the line he just heard is planted as the first
/// entry in Wins & Noticed, so the practice is never an empty room, and the Practice gets its own settings: his account (Google, the
/// site's own flow) and what stays where. A real line, never a placeholder. The spoken line itself is untouched: it still speaks on every open.
@MainActor enum PracticeFirstRun {
    private static let plantedKey = "practice.firstMemory.planted"

    /// Plants `line` as a "noticed" entry, once, and only when his log holds nothing yet (a returning user is never touched).
    /// Offline it queues like any other entry. The flag is set only after the server (or the queue) took it.
    static func plant(line: String, model: AppModel) async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: plantedKey), !line.isEmpty else { return }
        if let logs = try? await Practice.get("logs", [PracticeLog].self, model: model), !logs.isEmpty {
            defaults.set(true, forKey: plantedKey)
            return
        }
        if (try? await Practice.postQueued("logs", ["kind": "noticed", "text": line], model: model)) != nil {
            defaults.set(true, forKey: plantedKey)
        }
    }
}

/// The Practice's own settings. Opens only from the gear at the top left of the Practice (his pick 11-21, "Open on the practice":
/// the first open goes straight to the practice, no sheet in the way). Two things only: the account, and what stays where.
struct PracticeSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var account = SiteAccount.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Candle.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        accountBlock
                        VStack(alignment: .leading, spacing: 14) {
                            Text("what stays where").plHand(24, relativeTo: .title2).foregroundStyle(Candle.goldHi)
                            line("Everything you write here is saved to your own practice server, the address in your config.")
                            line("No advertising or analytics company is in this app.")
                            line("Each cold start sends your server one note: that you opened it, and the hour of the day. Nothing else.")
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Practice settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.frame(minWidth: 44, minHeight: 44) } }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { if !account.checked { await account.refresh() } }
    }

    private var accountBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("your account").plHand(24, relativeTo: .title2).foregroundStyle(Candle.goldHi)
            if account.signedIn {
                line(account.me?.handle.map { "Signed in to Psyched Luxuries as @" + $0 } ?? account.me?.email ?? "Signed in to Psyched Luxuries")
                Button { Task { await account.signOut() } } label: { Text("Sign out").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(CandleGhost())
            } else {
                line("Sign in once with Google: the Shop, the Congregation and your orders use it. The practice works without it.")
                NavigationLink { AccountSignInSheet(account: account) } label: { Text("Continue with Google").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(CandleButton())
            }
        }
    }

    private func line(_ s: String) -> some View {
        Text(s).font(Font.pl(size: 15)).foregroundStyle(Candle.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
    }
}
