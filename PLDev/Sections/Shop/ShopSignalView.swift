import SwiftUI

/// `/signal`: The Transmission. The site's page and its form, in the phone's hands: an email, the human check, "Receive the Signal".
/// The site's signup is a server action, which a native screen cannot call, so the app posts to `api/signal` (a small route that
/// wraps the same `subscribe`; the block to add is in LANES-shop.md). Until that route is on the site the form says so plainly and
/// opens the site's own page, so nobody is left with a button that does nothing.
struct SignalView: View {
    @State private var email = ""
    @State private var ballot: SiteBallot?
    @State private var sending = false
    @State private var done: String?
    @State private var line: String?
    @State private var needsSite = false
    @State private var web: WebPage?
    @State private var tick = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    private var emailOK: Bool { email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil }
    private var needsCheck: Bool { !(ballot?.siteKey ?? "").isEmpty }
    private var canSend: Bool { !sending && emailOK }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("The Transmission").siteLabel().foregroundStyle(Bone.gold)
                    Text("The work, as it is made.").font(SiteFont.display(38)).foregroundStyle(Bone.ink(scheme)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    Text("A seven-year daily practice, still running. The transmission is the record of it \u{2014} what was made, what it cost, what it turned out to mean. Sent as the work happens, not on a marketing calendar.").siteBody(16)
                }

                if let done {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(done).font(SiteFont.display(26, italic: true)).foregroundStyle(Bone.gold)
                        Text("The signal goes out as the work does. You will be the first to see what arrives.").siteBody(15)
                        Button { if let u = URL(string: "pldev://section/congregation/stream") { openURL(u) } } label: { Text("See the transmission").frame(maxWidth: 260) }.buttonStyle(SiteGhost())
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        SiteField(label: "Email", text: $email, prompt: "your@email.com", keyboard: .emailAddress, contentType: .emailAddress, capitalize: .never)
                        HumanGate(siteKey: ballot?.siteKey ?? "")
                        Button { Task { await send() } } label: {
                            HStack(spacing: 10) { Text(sending ? "Tuning in" : needsCheck ? "Continue on the site" : "Receive the Signal"); if sending { PLLoader().tint(.white) } }
                        }
                        .buttonStyle(SitePill())
                        .disabled(!canSend)
                        ResultLine(text: line)
                        if needsSite {
                            Button { if let url = Site.page("signal?src=app") { web = WebPage(url) } } label: { Text("Open the signal page on the site").siteLabel(10).frame(minHeight: 44, alignment: .leading) }.buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    SiteRule()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("For the person still making it before anyone has noticed.")
                        Text("For anyone who finishes the piece nobody asked for.")
                        Text("If you build in the hours when no one is watching, you belong here.")
                    }
                    .siteBody(14).padding(.top, 10)
                    Text("Every piece is dated. Nothing here asks for faith.").siteBody(14)
                    Text("You can leave at any time, from any transmission, in one click.").font(SiteFont.body(14)).foregroundStyle(Bone.inkFaint(scheme)).lineSpacing(5)
                    Text("Watch this.").font(SiteFont.display(30, italic: true)).foregroundStyle(Bone.gold).padding(.top, 8)
                }
            }
            .padding(24)
        }
        .siteScreen()
        .plScreenTitle("The signal")
        .scrollDismissesKeyboard(.interactively)
        .task { ballot = await SiteBallot.load() }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        .sensoryFeedback(PLHaptic.commit, trigger: tick)
    }

    private func send() async {
        if needsCheck {   // the human check runs on the site's own page, in Apple's sheet
            UIPasteboard.keep(email.trimmingCharacters(in: .whitespaces).lowercased())
            line = "Your email is copied. Paste it on the site\u{2019}s page."
            if let url = Site.page("signal?src=app") { web = WebPage(url) }
            return
        }
        sending = true; line = nil; needsSite = false
        defer { sending = false }
        do {
            let r = try await Site.call("POST", "api/signal", body: ["email": email.trimmingCharacters(in: .whitespaces).lowercased(), "source": "app"])
            if r.status == 404 {   // the route is not on the site yet
                line = "Not sent. The app's door to the signal is not open on the site yet. The site's own page works."
                needsSite = true
                return
            }
            if r.ok { done = r.message ?? "You are on the signal. Watch this."; tick += 1 }
            else { line = "Not sent. \(r.message ?? "The site said no.")" }
        } catch {
            line = "Not sent. \(error.localizedDescription)"
        }
    }
}
