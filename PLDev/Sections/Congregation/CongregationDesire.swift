import SwiftUI

// "State your reality": the congregation wall (the third truth made participatory), its three steps and four rules, and the form
// that speaks a desire into it; and the one-tap "Why are you here?" the stream asks a member once. Both are the site's own, in its words.

/// The wall's form. The site's human check runs in the form (`TurnstileView`); the post goes to the site's wall route. A desire is
/// held until the Founder has seen it, and the site's own sentence says so.
struct DesireSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var text = ""
    @State private var name = ""
    @State private var anon = true
    @State private var token = ""
    @State private var phase: Phase = .idle
    @State private var message = ""
    @State private var web: WebPage?

    enum Phase { case idle, sending, done, failed }

    private let steps: [(n: String, h: String, b: String)] = [
        ("I", "Name it in the present", "Not \u{201C}I want.\u{201D} State it as already true. The language configures the perception before the thing arrives."),
        ("II", "Hold it, don\u{2019}t grip it", "Persistence, not intensity. What you return to becomes structural. The wall is your return."),
        ("III", "Let it be witnessed", "A desire spoken in a congregation is harder to abandon. You are held to it \u{2014} kindly."),
    ]
    private let rules: [(n: String, h: String, b: String)] = [
        ("I", "Speak in the present.", "State it as already true. \u{201C}I am,\u{201D} not \u{201C}I want.\u{201D} The room runs on declaration, not wishing."),
        ("II", "Build. Never tear down.", "This is a room for becoming \u{2014} not for contempt, mockery, or correction. Not of others. Not of yourself."),
        ("III", "Honor the anonymous.", "A name withheld is still a declaration. Every voice on the wall carries equal weight, signed or not."),
        ("IV", "The wall is held.", "Every desire is seen before it appears. Nothing cruel reaches the wall. Moderation is care, not censorship."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("The Congregation").siteLabel()
                        SiteHeadline(lead: "State your", accent: "reality.", size: 38)
                        Text("The third truth made participatory. To name a desire \u{2014} to hold it in the open, in the present tense \u{2014} is to begin building it. Speak it here, anonymously or in your name. The wall is the congregation: proof that you are not the only one becoming.").siteBody(15)
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(s.n).plHand(32).foregroundStyle(Bone.gold)
                                Text(s.h).font(SiteFont.display(20)).foregroundStyle(Color(hex: 0xf1ece1))
                                Text(s.b).font(SiteFont.body(14)).foregroundStyle(Color(hex: 0x9b937f)).lineSpacing(5)
                            }
                        }
                    }
                    .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x0e0c08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("The rules of the room").siteLabel()
                        VStack(spacing: 0) {
                            ForEach(Array(rules.enumerated()), id: \.offset) { i, r in
                                HStack(alignment: .top, spacing: 16) {
                                    Text(r.n).plHand(22).foregroundStyle(Bone.gold).frame(width: 30, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(r.h).font(SiteFont.display(18)).foregroundStyle(Bone.ink(scheme))
                                        Text(r.b).siteBody(14)
                                    }
                                }
                                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                if i < rules.count - 1 { SiteRule() }
                            }
                        }
                        .background(Bone.ground(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
                    }

                    if phase == .done { done } else { form }
                }
                .padding(20)
            }
            .siteScreen()
            .navigationTitle("State your reality").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
            .sensoryFeedback(PLHaptic.success, trigger: phase == .done)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(message).font(SiteFont.display(24, italic: true)).foregroundStyle(Bone.gold).lineSpacing(4)
            HStack(spacing: 24) {
                SiteAction(title: "State another \u{2192}", tone: .faint) { phase = .idle; token = ""; text = "" }
                SiteAction(title: "Close") { dismiss() }
            }
        }
        .siteCard(padding: 24, radius: 20)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("State your desire").siteLabel()
            TextField("What persists in your mind? Name it plainly, in the present.", text: $text, axis: .vertical).lineLimit(3...6).siteField()
                .onChange(of: text) { _, v in if v.count > 280 { text = String(v.prefix(280)) } }
            HStack {
                Toggle(isOn: $anon) { Text("Post anonymously").font(SiteFont.body(14)).foregroundStyle(Bone.inkSoft(scheme)) }.tint(Bone.gold)
                Spacer()
                Text("\(text.count) of 280").siteLabel(10).monospacedDigit()
            }
            if !anon { TextField("Name or handle", text: $name).siteField().textInputAutocapitalization(.never).autocorrectionDisabled() }
            TurnstileView { token = $0 }.frame(height: 70)
            Button { Task { await submit() } } label: { Text(phase == .sending ? "Holding\u{2026}" : "Speak it") }.buttonStyle(SitePill())
                .disabled(phase == .sending || text.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || token.isEmpty)
            if phase == .failed { SiteNote(text: "Not sent. \(message)") }
            Text("Be kind. Be respectful. This is a room for becoming, not for tearing down. Desires are seen before they appear on the wall.").siteLabel(10).tracking(0.8)
        }
        .siteCard(padding: 20, radius: 20)
    }

    private func submit() async {
        phase = .sending
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let r = try await Site.call("POST", "api/congregation/desire", body: ["text": clean, "name": anon ? "" : name, "anon": anon, "token": token])
            if r.status == 404 {   // the wall's route is not on the site yet: its own form takes it
                message = "The wall\u{2019}s form opens on the site for now."
                phase = .failed
                if let url = Site.page("congregation#state-your-reality") { web = WebPage(url) }
            } else if r.ok { message = r.message ?? "Your desire is held. Once seen, it joins the wall. Watch this."; phase = .done; text = "" }
            else { message = r.message ?? "Something interrupted it. Try again."; phase = .failed; token = "" }
        } catch { message = error.localizedDescription; phase = .failed }
    }
}

/// "Why are you here?": one tap, no wrong answer, the record holds it. Shown once to a signed-in member who has not said.
struct DeclareIntentCard: View {
    private struct Reply: Decodable { let intent: String? }
    private let options: [(v: String, label: String, sub: String)] = [
        ("believer", "A believer", "the philosophy speaks to me"),
        ("buyer", "A collector", "I want to hold a piece"),
        ("collaborator", "A collaborator", "I want to build with you"),
        ("student", "A student", "I want to learn this"),
        ("teacher", "A teacher", "I want to carry this to others"),
    ]
    @State private var phase: Phase = .loading
    @State private var busy: String?
    @State private var line: String?
    @Environment(\.colorScheme) private var scheme

    enum Phase { case loading, show, hidden, done }

    var body: some View {
        Group {
            switch phase {
            case .loading, .hidden: EmptyView()
            case .done:
                HStack(spacing: 6) {
                    Text("Held. The record knows you now.").siteBody(14)
                    Text("Watch this.").plHand(20).foregroundStyle(Bone.gold)
                }.siteCard(padding: 20, radius: 20)
            case .show:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Why are you here?").font(SiteFont.display(21)).foregroundStyle(Bone.ink(scheme))
                    Text("One tap. No wrong answer \u{2014} the record simply holds it.").siteBody(14)
                    FlowPills(options: options.map { ($0.v, $0.label) }, busy: busy) { v in Task { await declare(v) } }
                    SiteNote(text: line)
                }.siteCard(padding: 20, radius: 20)
            }
        }
        .task { phase = await load() }
        .animation(.snappy, value: phase)
    }

    private func load() async -> Phase {
        guard let r = try? await Site.get("api/congregation/intent", Reply.self) else { return .hidden }
        return r.intent == nil ? .show : .hidden
    }

    private func declare(_ v: String) async {
        busy = v
        do { try await Site.post("api/congregation/intent", ["intent": v]); phase = .done; line = nil }
        catch { line = "Not saved. \(error.localizedDescription)" }
        busy = nil
    }
}

/// Outlined capsule options that wrap onto as many lines as they need.
struct FlowPills: View {
    let options: [(String, String)]
    var busy: String?
    let pick: (String) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                Button { pick(o.0) } label: {
                    Text(o.1).font(SiteFont.body(12, relativeTo: .footnote, weight: .medium)).textCase(.uppercase).tracking(2)
                        .foregroundStyle(Bone.ink(scheme)).padding(.horizontal, 16).frame(minHeight: 44)
                        .overlay { Capsule().strokeBorder(Bone.ink(scheme).opacity(0.3), lineWidth: 0.9) }
                }
                .buttonStyle(.plain).disabled(busy != nil).opacity(busy != nil && busy != o.0 ? 0.4 : 1)
            }
        }
    }
}

/// Lays its children left to right and wraps to the next line when the row is full.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
