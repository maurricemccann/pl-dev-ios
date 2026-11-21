import SwiftUI

/// First open of the Practice (S350, from the "One Year" teardown, App Breakdown #91): the line he just heard is planted as the first
/// entry in Wins & Noticed, so the practice is never an empty room, and one quiet sheet says what stays where. A real line, never a
/// placeholder. Once only each. The spoken line itself is untouched: it still speaks on every open (`PracticeEntry`).
@MainActor enum PracticeFirstRun {
    private static let plantedKey = "practice.firstMemory.planted"
    private static let sheetKey = "practice.firstRun.sheetSeen"

    static var sheetSeen: Bool { UserDefaults.standard.bool(forKey: sheetKey) }
    static func markSheetSeen() { UserDefaults.standard.set(true, forKey: sheetKey) }

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

/// "What stays where": non-blocking (a sheet over the open practice, swipe or button closes it), one screen, only what the code does.
struct PracticeFirstRunSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var signIn = false

    var body: some View {
        ZStack {
            Candle.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("before you begin").plHand(28, relativeTo: .title).foregroundStyle(Candle.goldHi)
                    line("Everything you write here is saved to your own practice server, the address in your config.")
                    line("No advertising or analytics company is in this app.")
                    line("Each cold start sends your server one note: that you opened it, and the hour of the day. Nothing else.")
                    line("Signing in with Google is optional. It connects the Shop, the Congregation and your orders. The practice works without it.")
                    VStack(spacing: 10) {
                        Button { signIn = true } label: { Text("Continue with Google").frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(CandleGhost())
                        Button { dismiss() } label: { Text("Got it").frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(CandleButton())
                    }
                    .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear { PracticeFirstRun.markSheetSeen() }
        .sheet(isPresented: $signIn) { NavigationStack { AccountSignInSheet(account: SiteAccount.shared) } }
    }

    private func line(_ s: String) -> some View {
        Text(s).font(.system(size: 15)).foregroundStyle(Candle.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
    }
}
