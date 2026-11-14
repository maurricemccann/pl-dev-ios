import SwiftUI

/// `/signal`: The Transmission. The site's page and its form, in the phone's hands: an email, the human check, "Receive the Signal".
/// The site's signup is a server action, which a native screen cannot call, so the app posts to `api/signal` (a small route that
/// wraps the same `subscribe`; the block to add is in LANES-shop.md). Until that route is on the site the form says so plainly and
/// opens the site's own page, so nobody is left with a button that does nothing.
struct SignalView: View {
    @State private var email = ""
    @State private var ballot: SiteBallot?
    @State private var line: String?
    @State private var web: WebPage?
    @State private var tick = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    private var emailOK: Bool { email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil }
    private var canSend: Bool { emailOK }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("The Transmission").siteLabel().foregroundStyle(Bone.gold)
                    Text("The work, as it is made.").font(SiteFont.display(38)).foregroundStyle(Bone.ink(scheme)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    Text("A seven-year daily practice, still running. The transmission is the record of it \u{2014} what was made, what it cost, what it turned out to mean. Sent as the work happens, not on a marketing calendar.").siteBody(16)
                }

                VStack(alignment: .leading, spacing: 16) {
                    SiteField(label: "Email", text: $email, prompt: "your@email.com", keyboard: .emailAddress, contentType: .emailAddress, capitalize: .never)
                    HumanGate(siteKey: ballot?.siteKey ?? "")
                    Button { Task { await send() } } label: { Text("Continue on the site") }
                        .buttonStyle(SitePill())
                        .disabled(!canSend)
                    ResultLine(text: line)
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

    /// Sign-ups pass the site's human check, and the site has no app door for the signal (api/signal is 404, ruled 11-13), so the
    /// form copies the email and opens the site's own signal page in Apple's sheet every time, with no dead request first.
    private func send() async {
        UIPasteboard.keep(email.trimmingCharacters(in: .whitespaces).lowercased())
        line = "Your email is copied. Paste it on the site\u{2019}s page."
        if let url = Site.page("signal?src=app") { web = WebPage(url) }
        tick += 1
    }
}
