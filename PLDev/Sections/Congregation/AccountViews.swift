import SwiftUI

// Me: the site account. Signed out, the site's own sign-in, in its look. Signed in, the member's own page exactly as the site gives
// the owner (Profile, Posts, Boards, Settings, Social, Games, Ask) with the bell, their orders and their pins above it. Sign-up and
// Google sign-in need a person the site can check, so they open the site in a sheet.

struct ActivityItem: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let handle: String?
    let refType: String?
    let refId: String?
    let read: Bool
    let createdAt: String?

    /// The line the site's bell shows, in words.
    var words: String {
        let who = handle.map { "@\($0)" } ?? "Someone"
        switch kind {
        case "react": return "\(who) reacted to your post."
        case "comment": return "\(who) answered your post."
        case "follow": return "\(who) followed you."
        case "repost": return "\(who) reposted you."
        case "mention": return "\(who) mentioned you."
        case "approved": return "Your \(refType ?? "post") went live."
        case "removed": return "Your \(refType ?? "post") was removed."
        default: return "\(who): \(kind)."
        }
    }
}

/// The site's bell kinds he can switch off (its Settings page has the same five). News that a post went live or was removed always shows.
enum BellKinds {
    static let all: [(key: String, label: String)] = [("follow", "Follows"), ("react", "Reactions"), ("comment", "Replies"), ("mention", "Mentions"), ("repost", "Reposts")]
    static func shows(_ kind: String) -> Bool {
        guard all.contains(where: { $0.key == kind }) else { return true }
        return UserDefaults.standard.object(forKey: "pldev.bell." + kind) as? Bool ?? true
    }
}

struct ActivityReply: Decodable {
    let unread: Int
    let items: [ActivityItem]
    var visible: [ActivityItem] { items.filter { BellKinds.shows($0.kind) } }
    var visibleUnread: Int { visible.filter { !$0.read }.count }
}

/// A row that opens a pushed screen: the site's raised card with a count and a chevron.
private struct MeRow: View {
    let title: String
    let symbol: String
    var badge: Int = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Bone.goldDim).frame(width: 26)
            Text(title).font(SiteFont.body(15)).foregroundStyle(Bone.ink(scheme))
            Spacer(minLength: 0)
            if badge > 0 { Text("\(badge)").font(SiteFont.body(12, weight: .medium)).foregroundStyle(Color(hex: 0x15120b)).padding(.horizontal, 9).frame(minHeight: 22).background(Bone.gold, in: Capsule()).monospacedDigit() }
            Image(systemName: "chevron.forward").font(.footnote).foregroundStyle(Bone.inkFaint(scheme))
        }
        .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
    }
}

struct AccountTabView: View {
    @Bindable var state: CongregationModel
    private let account = SiteAccount.shared
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var line: String?
    @State private var web: WebPage?
    @State private var confirmOut = false
    @State private var unread = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            Group { if account.signedIn, let me = account.me { signedIn(me) } else { signedOut } }
                .padding(.bottom, 40)
        }
        .siteScreen()
        .refreshable { await account.refresh(); await loadUnread() }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        .sensoryFeedback(PLHaptic.success, trigger: account.signedIn)
        .task { await loadUnread() }
    }

    private func loadUnread() async {
        guard account.signedIn else { unread = 0; return }
        unread = (try? await Site.get("api/notifications", ActivityReply.self))?.visibleUnread ?? 0
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 18) {
            SitePageHead(eyebrow: "The congregation \u{2014} enter", lead: "Enter the", accent: "congregation.",
                         lede: "The room is open to see. To speak, react, and be witnessed, sign in with the email and password you use on psychedluxuries.com. Your session stays in this phone\u{2019}s Keychain.")
            VStack(alignment: .leading, spacing: 12) {
                TextField("Email", text: $email).siteField().textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password).siteField().textContentType(.password)
                Button {
                    busy = true; line = nil
                    Task {
                        if let err = await account.signIn(email: email, password: password) { line = "Not signed in. \(err)" } else { password = ""; state.tick += 1 }
                        busy = false
                    }
                } label: { Text(busy ? "Entering\u{2026}" : "Enter the congregation") }
                    .buttonStyle(SitePill()).disabled(busy || email.isEmpty || password.isEmpty)
                SiteNote(text: line)
            }
            .siteCard(padding: 20, radius: 20).padding(.horizontal, 20)
            VStack(spacing: 10) {
                Button { if let url = Site.page("register") { web = WebPage(url) } } label: { Text("Create an account") }.buttonStyle(SiteGhost())
                Button { if let url = Site.page("signin") { web = WebPage(url) } } label: { Text("Forgot the password, or use Google") }.buttonStyle(SiteGhost())
                Text("These run on the site, which checks a person is behind them.").siteLabel(10).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
        }
    }

    private func signedIn(_ me: SiteAccount.Me) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 0) {
                NavigationLink { ActivityView(state: state) } label: { MeRow(title: "Activity", symbol: "bell", badge: unread) }
                SiteRule()
                NavigationLink { MyOrdersView() } label: { MeRow(title: "Your orders", symbol: "receipt") }
                SiteRule()
                NavigationLink { PinsView() } label: { MeRow(title: "Pins", symbol: "pin") }
            }
            .buttonStyle(.plain)
            .background(Bone.raised(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
            .padding(.horizontal, 20).padding(.top, 20)
            if let h = me.handle, !h.isEmpty {
                MemberHub(handle: h, state: state).padding(.horizontal, 20)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose a handle").font(SiteFont.display(22)).foregroundStyle(Bone.ink(scheme))
                    Text("Your page is at your handle. Choose one and it opens.").siteBody(14)
                    SettingsPanel(handle: "", onSaved: { Task { await account.refresh() } })
                }.padding(.horizontal, 20)
            }
            Button(role: .destructive) { confirmOut = true } label: { Text("Sign out") }.buttonStyle(SiteGhost()).padding(.horizontal, 20)
        }
        .confirmationDialog("Sign out of the site?", isPresented: $confirmOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await account.signOut(); state.tick += 1 } }
        } message: { Text("This phone forgets the session. Nothing changes on the site.") }
    }
}

// MARK: - Settings (the owner's tab)

struct SettingsPanel: View {
    let handle: String
    var onSaved: () -> Void = {}
    private struct ProfileReply: Decodable { let firstName: String?; let handle: String?; let glyph: String?; let brandColor: String? }
    @State private var glyph = "smiley"
    @State private var firstName = ""
    @State private var handleInput = ""
    @State private var color: String?
    @State private var custom = Color(hex: 0xc9a84c)
    @State private var customTask: Task<Void, Never>?
    @State private var note: String?
    @State private var busy = false
    @State private var web: WebPage?
    @Environment(\.colorScheme) private var scheme
    private let account = SiteAccount.shared

    private var accent: Color { StorefrontColor.hex(color) ?? Bone.gold }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your glyph").siteLabel(11)
                HStack(spacing: 10) {
                    ForEach(Glyphs.all) { g in
                        let locked = !Glyphs.unlocked(g.minTier, tier: account.me?.pointsTier)
                        let active = g.key == glyph
                        Button { chooseGlyph(g) } label: {
                            GlyphMark(glyph: g.key, color: active ? accent : Bone.inkFaint(scheme), size: 30)
                                .frame(width: 56, height: 56)
                                .background(active ? Bone.raised(scheme) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(active ? Bone.gold : Bone.line(scheme), lineWidth: active ? 1.4 : 0.8) }
                                .overlay(alignment: .bottomTrailing) { if locked { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Bone.inkFaint(scheme)).padding(4) } }
                                .opacity(locked ? 0.45 : 1)
                        }
                        .buttonStyle(.plain).disabled(busy)
                        .accessibilityLabel("\(g.label)\(locked ? ", locked until \(g.minTier)" : "")\(active ? ", chosen" : "")")
                    }
                }
                if let g = Glyphs.def(glyph) { Text(g.label).siteLabel(10) }
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Your accent").siteLabel(11)
                HStack(spacing: 10) {
                    ForEach(Glyphs.palette, id: \.hex) { c in
                        let on = (color ?? "#c9a84c").lowercased() == c.hex
                        Button { saveColor(c.hex) } label: {
                            Circle().fill(StorefrontColor.hex(c.hex) ?? .gray).frame(width: 30, height: 30)
                                .overlay { Circle().strokeBorder(on ? Bone.ink(scheme) : Bone.line(scheme), lineWidth: on ? 2 : 0.8) }
                                .scaleEffect(on ? 1.12 : 1).frame(minWidth: 34, minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel(c.name)
                    }
                    ColorPicker("Custom colour", selection: $custom, supportsOpacity: false).labelsHidden()
                        .onChange(of: custom) { _, new in
                            customTask?.cancel()
                            customTask = Task { try? await Task.sleep(for: .milliseconds(700)); if !Task.isCancelled, let hex = new.hexString { saveColor(hex) } }
                        }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Your name").siteLabel(11)
                Text("@handle").siteLabel(10)
                TextField("handle", text: $handleInput).siteField().textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("First name").siteLabel(10)
                TextField("First name", text: $firstName).siteField()
                HStack(spacing: 14) {
                    Button { Task { await saveIdentity() } } label: { Text(busy ? "Saving\u{2026}" : "Save name") }.buttonStyle(SitePill()).frame(maxWidth: 180).disabled(busy)
                    SiteNote(text: note)
                }
                Text("Three to twenty letters or numbers.").siteLabel(10)
            }
            SiteRule()
            ArtworkPicker(onSaved: onSaved)
            SiteRule()
            VStack(alignment: .leading, spacing: 12) {
                Text("I am here as").siteLabel(11)
                IntentSetting()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Activity bell").siteLabel(11)
                ForEach(BellKinds.all, id: \.key) { kind in
                    Toggle(isOn: Binding(get: { BellKinds.shows(kind.key) }, set: { UserDefaults.standard.set($0, forKey: "pldev.bell." + kind.key) })) {
                        Text(kind.label).font(SiteFont.body(15)).foregroundStyle(Bone.ink(scheme))
                    }.tint(Bone.gold).frame(minHeight: 44)
                }
                Text("News that a post went live or was removed always reaches you.").siteLabel(10)
            }
            SiteRule()
            Button { if let u = URL(string: "https://pl-academy.psychedluxuries.workers.dev") { web = WebPage(u) } } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Persona Academy").siteLabel(10)
                    Text("Enter The Study \u{2197}").font(SiteFont.body(15)).foregroundStyle(Bone.ink(scheme))
                    Text("Reader \u{00B7} Oracle \u{00B7} Forge \u{00B7} Drills \u{2014} 7 sections").siteLabel(10)
                }
                .frame(maxWidth: .infinity, alignment: .leading).siteCard(padding: 16, radius: 20)
            }.buttonStyle(.plain)
        }
        .task { await load() }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        .sensoryFeedback(PLHaptic.success, trigger: note == "Saved.")
    }

    private func load() async {
        if let me = account.me { glyph = me.glyph ?? "smiley"; color = me.brandColor; handleInput = me.handle ?? handle; firstName = me.firstName ?? "" }
        if let d = try? await Site.get("api/account/profile", ProfileReply.self) {
            if let f = d.firstName { firstName = f }
            if let h = d.handle { handleInput = h }
            if let g = d.glyph { glyph = g }
            if let c = d.brandColor { color = c; if let col = StorefrontColor.hex(c) { custom = col } }
        }
    }

    private func chooseGlyph(_ g: GlyphDef) {
        guard g.key != glyph else { return }
        if !Glyphs.unlocked(g.minTier, tier: account.me?.pointsTier) { note = "Not saved. That glyph unlocks at \(g.minTier)."; return }
        let before = glyph
        glyph = g.key; busy = true; note = nil
        Task {
            do { try await Site.post("api/account/glyph", ["glyph": g.key]); await account.refresh(); onSaved() }
            catch { glyph = before; note = "Not saved. \(error.localizedDescription)" }
            busy = false
        }
    }

    private func saveColor(_ hex: String) {
        let before = color
        color = hex; note = nil
        Task {
            do { try await Site.post("api/account/profile", ["brandColor": hex]); await account.refresh(); onSaved() }
            catch { color = before; note = "Not saved. \(error.localizedDescription)" }
        }
    }

    private func saveIdentity() async {
        busy = true; note = nil
        defer { busy = false }
        var body: [String: Any] = ["firstName": firstName.trimmingCharacters(in: .whitespaces)]
        let h = handleInput.trimmingCharacters(in: .whitespaces).lowercased()
        if !h.isEmpty { body["handle"] = h }
        do { try await Site.post("api/account/profile", body); note = "Saved."; await account.refresh(); onSaved() }
        catch { note = "Not saved. \(error.localizedDescription)" }
    }
}

extension Color {
    /// "#rrggbb", or nil when the colour cannot be read as RGB.
    var hexString: String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

/// "I am here as", the site's intent declaration.
struct IntentSetting: View {
    private struct Reply: Decodable { let intent: String? }
    private let options = ["buyer", "collaborator", "student", "teacher", "believer"]
    @State private var intent = ""
    @State private var loaded = false
    @State private var line: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("I am here as", selection: $intent) {
                Text("Not said").tag("")
                ForEach(options, id: \.self) { Text($0 == "buyer" ? "Collector" : $0.capitalized).tag($0) }
            }
            .pickerStyle(.menu).tint(Bone.goldDim)
            .onChange(of: intent) { old, v in
                guard !v.isEmpty, loaded, v != old else { return }   // the value that just arrived from the site is not a choice
                Task { do { try await Site.post("api/congregation/intent", ["intent": v]); line = nil } catch { line = "Not saved. \(error.localizedDescription)" } }
            }
            SiteNote(text: line)
        }
        .task { intent = (try? await Site.get("api/congregation/intent", Reply.self))?.intent ?? ""; loaded = true }
    }
}

// MARK: - Activity

struct ActivityView: View {
    var state: CongregationModel? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var reply: ActivityReply?
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("The room, answering").plHand(24).foregroundStyle(Bone.gold)
                    Text("Activity").font(SiteFont.display(36)).foregroundStyle(Bone.ink(scheme)).accessibilityAddTraits(.isHeader)
                }
                if let reply {
                    if reply.visible.isEmpty { SiteEmpty(title: "Nothing yet.", detail: "Speak in the room and it begins.") }
                    else {
                        VStack(spacing: 0) {
                            ForEach(Array(reply.visible.enumerated()), id: \.element.id) { i, item in
                                Button { open(item) } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Circle().fill(item.read ? Color.clear : Bone.gold).frame(width: 8, height: 8).padding(.top, 7).accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.words).font(SiteFont.body(15)).foregroundStyle(Bone.ink(scheme)).multilineTextAlignment(.leading)
                                            if let d = Date.pl(item.createdAt) { Text(d.formatted(.dateTime.month(.abbreviated).day())).siteLabel(10) }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 14).padding(.horizontal, 4).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(item.read ? Color.clear : Bone.raised(scheme).opacity(0.5)).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).accessibilityLabel("\(item.read ? "" : "New. ")\(item.words)")
                                if i < reply.visible.count - 1 { SiteRule() }
                            }
                        }
                        .overlay(alignment: .top) { SiteRule() }.overlay(alignment: .bottom) { SiteRule() }
                    }
                } else if let failure { SiteEmpty(title: "Could not load your activity", detail: failure, actionTitle: "Try again") { Task { await load() } } }
                else { SitePulse() }
            }
            .padding(20)
        }
        .siteScreen()
        .refreshable { await load() }
        .task { await load() }
        .plScreenTitle("Activity")
    }

    private func load() async {
        do {
            reply = try await Site.get("api/notifications", ActivityReply.self); failure = nil
            // the site marks the bell read on view
            if (reply?.unread ?? 0) > 0 { _ = try? await Site.post("api/notifications", ["read": true]) }
        } catch { if reply == nil { failure = error.localizedDescription } }
    }

    /// A follow opens the follower's page; the rest open the room, where the post is.
    private func open(_ item: ActivityItem) {
        guard let state else { return }
        if item.kind == "follow", let h = item.handle { state.memberHandle = h }
        else { state.tab = .room; dismiss() }
    }
}

// MARK: - Messages to the Founder

struct MessagesPanel: View {
    var title = "Message the Founder"
    struct Message: Decodable, Identifiable { let id: String; let sender: String; let body: String; let createdAt: String? }
    private struct Convo: Decodable { let messages: [Message] }
    @State private var messages: [Message] = []
    @State private var loaded = false
    @State private var failure: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var line: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).siteLabel(11)
            if !loaded {
                if let failure { SiteEmpty(title: "Could not load the thread", detail: failure, actionTitle: "Try again") { Task { await load() } } } else { SitePulse() }
            } else if messages.isEmpty {
                Text("A private line to the Founder. Say what you need to say.").siteBody(14)
            }
            VStack(spacing: 10) {
                ForEach(messages) { m in
                    let founder = m.sender == "founder"
                    HStack {
                        if !founder { Spacer(minLength: 40) }
                        VStack(alignment: .leading, spacing: 4) {
                            if founder { Text("The Founder").siteLabel(10).foregroundStyle(Bone.gold) }
                            Text(m.body).font(SiteFont.body(15)).foregroundStyle(founder ? Color(hex: 0xf1ece1) : Bone.ground(scheme)).lineSpacing(4)
                            if let d = Date.pl(m.createdAt) { Text(d, format: .relative(presentation: .named)).font(SiteFont.body(10)).foregroundStyle((founder ? Color(hex: 0xf1ece1) : Bone.ground(scheme)).opacity(0.5)) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(founder ? Color(hex: 0x0e0c08) : Bone.ink(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .leading) { if founder { Rectangle().fill(Bone.gold).frame(width: 2) } }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        if founder { Spacer(minLength: 40) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                TextField("Write to the Founder\u{2026}", text: $draft, axis: .vertical).lineLimit(2...6).siteField()
                HStack {
                    SiteNote(text: line)
                    Spacer()
                    SiteAction(title: sending ? "\u{2026}" : "Send") { Task { await send() } }
                        .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
            }
        }
        .siteCard(padding: 20, radius: 20)
        .task { await load() }
        .sensoryFeedback(PLHaptic.commit, trigger: messages.count)
    }

    private func load() async {
        do { messages = try await Site.get("api/dm", Convo.self).messages; loaded = true; failure = nil }
        catch { if !loaded { failure = error.localizedDescription } }
    }

    private func send() async {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        defer { sending = false }
        do {
            let r = try await Site.post("api/dm", ["body": t])
            if let m = r.json?["message"] as? [String: Any], let id = m["id"] as? String {
                messages.append(Message(id: id, sender: "member", body: (m["body"] as? String) ?? t, createdAt: m["createdAt"] as? String))
            } else { await load() }
            draft = ""; line = nil
        } catch { line = "Not sent. \(error.localizedDescription)" }
    }
}

/// The pushed page for the Messages room (a link, Siri or Spotlight lands on it by name).
struct MessagesView: View {
    var body: some View {
        ScrollView { MessagesPanel().padding(20) }
            .siteScreen().plScreenTitle("Messages")
    }
}

/// The pushed page for the profile room: the same settings the owner's tab holds.
struct ProfileEditView: View {
    let me: SiteAccount.Me
    var body: some View {
        ScrollView { SettingsPanel(handle: me.handle ?? "").padding(20) }
            .siteScreen().plScreenTitle("Profile")
    }
}

// MARK: - Pins

/// Pins a piece of the archive to the signed-in account, as the site's pin does.
struct PinButton: View {
    let cr: String
    private struct PinState: Decodable { let pinned: Bool? }
    @State private var pinned = false
    @State private var line: String?

    var body: some View {
        Group {
            Button {
                let was = pinned
                pinned.toggle()
                Task {
                    do { _ = try await Site.post("api/account/pins", ["cr": cr, "action": was ? "unpin" : "pin"]); line = nil }
                    catch { pinned = was; line = "Not saved. \(error.localizedDescription)" }
                }
            } label: { Label(pinned ? "Pinned" : "Pin to your page", systemImage: pinned ? "pin.fill" : "pin").symbolEffect(.bounce, value: pinned) }
            ResultLine(text: line)
        }
        .task { pinned = (try? await Site.get("api/account/pins", PinState.self, query: ["cr": cr]))?.pinned ?? false }
    }
}

/// The pieces pinned to his page, as pictures: the archive's own thumbnail for each, with the site's page one tap away.
struct PinsView: View {
    private struct Pins: Decodable { let pins: [String] }
    private let manifest = ArchiveManifest.shared
    @State private var pins: [String]?
    @State private var failure: String?
    @State private var removed: Set<String> = []
    @State private var line: String?
    @State private var web: WebPage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Pinned").font(SiteFont.display(34)).foregroundStyle(Bone.ink(scheme)).accessibilityAddTraits(.isHeader)
                if let pins {
                    let shown = pins.filter { !removed.contains($0) }
                    if shown.isEmpty { SiteEmpty(title: "Nothing pinned.", detail: "Pin a piece from the archive and it appears here.") }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(shown, id: \.self) { cr in
                            let piece = manifest.pieces.first { $0.cr.caseInsensitiveCompare(cr) == .orderedSame }
                            Button { if let u = Site.page("catalogue/\(cr.lowercased())") { web = WebPage(u) } } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    Color(Bone.raised(scheme)).aspectRatio(1, contentMode: .fit).overlay {
                                        AsyncImage(url: piece.flatMap { URL(string: $0.thumb) }) { p in
                                            if case .success(let i) = p { i.resizable().scaledToFill() } else { Image(systemName: "pin").foregroundStyle(Bone.inkFaint(scheme)) }
                                        }
                                    }.clipped()
                                    Text(piece?.title ?? cr).font(SiteFont.body(13)).foregroundStyle(Bone.ink(scheme)).lineLimit(1).padding(10)
                                }
                                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { unpin(cr) } label: { Label("Unpin", systemImage: "pin.slash") }
                            }
                            .accessibilityLabel("\(piece?.title ?? cr). Touch and hold to unpin.")
                        }
                    }
                    if !shown.isEmpty { Text("Touch and hold a piece to unpin it.").siteLabel(10) }
                    SiteNote(text: line)
                } else if let failure { SiteEmpty(title: "Could not load your pins", detail: failure, actionTitle: "Try again") { Task { await load() } } }
                else { SitePulse() }
            }
            .padding(20)
        }
        .siteScreen()
        .refreshable { await load() }
        .task { await manifest.load(); await load() }
        .plScreenTitle("Pins")
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }

    private func load() async {
        do { pins = try await Site.get("api/account/pins", Pins.self).pins; failure = nil }
        catch { if pins == nil { failure = error.localizedDescription } }
    }

    private func unpin(_ cr: String) {
        removed.insert(cr)
        Task {
            do { _ = try await Site.post("api/account/pins", ["cr": cr, "action": "unpin"]); line = nil }
            catch { removed.remove(cr); line = "Not saved. \(error.localizedDescription)" }
        }
    }
}
