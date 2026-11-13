import SwiftUI

// Me: the site account. Signed out, the site's email and password sign-in. Signed in, the member's own page: who they are, their
// activity, their messages to the Founder, their orders, and their profile. Sign-up and Google sign-in need a browser, so they open
// the site in a sheet.

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

struct ActivityReply: Decodable { let unread: Int; let items: [ActivityItem] }

struct AccountTabView: View {
    @Bindable var state: CongregationModel
    private let account = SiteAccount.shared
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var line: String?
    @State private var web: WebPage?
    @State private var confirmOut = false

    var body: some View {
        Group {
            if account.signedIn, let me = account.me { signedIn(me) } else { signedOut }
        }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }

    private var signedOut: some View {
        Form {
            Section {
                TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password).textContentType(.password)
                Button {
                    busy = true; line = nil
                    Task {
                        if let err = await account.signIn(email: email, password: password) { line = "Not signed in. \(err)" } else { password = ""; state.tick += 1 }
                        busy = false
                    }
                } label: { HStack { Text("Sign in"); if busy { Spacer(); ProgressView() } }.frame(minHeight: PLMetric.touch) }
                    .disabled(busy || email.isEmpty || password.isEmpty)
                ResultLine(text: line)
            } header: { Text("Your site account") } footer: { Text("The same email and password as psychedluxuries.com. Your session stays in this phone's Keychain.") }
            Section {
                Button { if let url = Site.page("register") { web = WebPage(url) } } label: { Label("Create an account on the site", systemImage: "person.badge.plus") }
                Button { if let url = Site.page("signin") { web = WebPage(url) } } label: { Label("Forgot the password, or use Google", systemImage: "key") }
            } footer: { Text("These run on the site, which checks a person is behind them.") }
        }
        .sensoryFeedback(PLHaptic.success, trigger: account.signedIn)
    }

    private func signedIn(_ me: SiteAccount.Me) -> some View {
        List {
            Section {
                HStack(spacing: PLSpace.pad) {
                    GlyphBadge(glyph: me.glyph, color: me.brandColor, founder: me.isFounder == true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(me.firstName ?? me.handle.map { "@\($0)" } ?? "You").plTitle(.title3)
                        Text(me.isFounder == true ? "The Founder" : (me.pointsTier ?? "none").tierWord).plFont(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if me.isFounder != true, let p = me.points { Text("\(p)").plFont(.title3).monospacedDigit().contentTransition(.numericText()) }
                }
                if let h = me.handle { LabeledContent("Handle", value: "@\(h)") }
            }
            Section {
                NavigationLink { ActivityView() } label: { Label("Activity", systemImage: "bell") }
                if me.isFounder != true { NavigationLink { MessagesView() } label: { Label("Messages to the Founder", systemImage: "envelope") } }
                NavigationLink { MyOrdersView() } label: { Label("Your orders", systemImage: "receipt") }
                NavigationLink { ProfileEditView(me: me) } label: { Label("Edit your profile", systemImage: "person.text.rectangle") }
                if me.isFounder != true { IntentRow() }
            }
            if me.isFounder == true {
                Section { Label("Member messages to you are in House, under Support.", systemImage: "tray.full").foregroundStyle(.secondary) }
            }
            Section {
                Button(role: .destructive) { confirmOut = true } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
            }
        }
        .refreshable { await account.refresh() }
        .confirmationDialog("Sign out of the site?", isPresented: $confirmOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await account.signOut(); state.tick += 1 } }
        } message: { Text("This phone forgets the session. Nothing changes on the site.") }
    }
}

/// "I am here as", the site's intent declaration.
struct IntentRow: View {
    private struct Reply: Decodable { let intent: String? }
    private let options = ["buyer", "collaborator", "student", "teacher", "believer"]
    @State private var intent = ""
    @State private var line: String?

    var body: some View {
        Group {
            Picker("I am here as", selection: $intent) {
                Text("Not said").tag("")
                ForEach(options, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .onChange(of: intent) { _, v in
                guard !v.isEmpty else { return }
                Task { do { _ = try await Site.post("api/congregation/intent", ["intent": v]); line = nil } catch { line = "Not saved. \(error.localizedDescription)" } }
            }
            ResultLine(text: line)
        }
        .task { intent = (try? await Site.get("api/congregation/intent", Reply.self))?.intent ?? "" }
    }
}

struct ActivityView: View {
    var body: some View {
        Loaded(load: { try await Site.get("api/notifications", ActivityReply.self) }) { reply, reload in
            List {
                if reply.items.isEmpty { ContentUnavailableView("Nothing yet", systemImage: "bell", description: Text("Reactions, answers and follows appear here.")).listRowBackground(Color.clear) }
                ForEach(reply.items) { i in
                    HStack(alignment: .top, spacing: PLSpace.pad) {
                        Circle().fill(i.read ? Color.clear : PLTone.accent).frame(width: 8, height: 8).padding(.top, 7).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.words).plFont(.body)
                            Ago(text: i.createdAt).plFont(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("\(i.read ? "" : "New. ")\(i.words)")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark read") { Task { _ = try? await Site.post("api/notifications", [:]); await reload() } }.disabled(reply.unread == 0)
                }
            }
        }
        .plScreenTitle("Activity")
    }
}

struct MessagesView: View {
    struct Message: Decodable, Identifiable { let id: String; let sender: String; let body: String; let createdAt: String? }
    struct DMThread: Decodable { var messages: [Message] }
    @State private var draft = ""
    @State private var sent: [Message] = []
    @State private var line: String?
    @State private var sending = false

    var body: some View {
        Loaded(load: { try await Site.get("api/dm", DMThread.self).messages }) { messages, reload in
            List {
                let all = messages + sent.filter { s in !messages.contains { $0.id == s.id } }
                if all.isEmpty { ContentUnavailableView("No messages", systemImage: "envelope", description: Text("Write to the Founder below. His replies appear here.")).listRowBackground(Color.clear) }
                ForEach(all) { m in
                    VStack(alignment: m.sender == "member" ? .trailing : .leading, spacing: 2) {
                        Text(m.body).plReading().padding(PLSpace.pad)
                            .background(m.sender == "member" ? PLTone.accent.opacity(0.22) : PLTone.well, in: RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
                        Ago(text: m.createdAt).plFont(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: m.sender == "member" ? .trailing : .leading)
                    .listRowSeparator(.hidden)
                }
                Section {
                    TextField("Message", text: $draft, axis: .vertical).lineLimit(1...6)
                    Button {
                        let t = draft; sending = true
                        Task {
                            do {
                                let r = try await Site.post("api/dm", ["body": t])
                                if let m = r.json?["message"] as? [String: Any], let id = m["id"] as? String {
                                    sent.append(Message(id: id, sender: "member", body: (m["body"] as? String) ?? t, createdAt: m["createdAt"] as? String))
                                }
                                draft = ""; line = nil
                            } catch { line = "Not sent. \(error.localizedDescription)" }
                            sending = false
                        }
                    } label: { Label("Send", systemImage: "paperplane").frame(minHeight: PLMetric.touch) }
                        .disabled(sending || draft.trimmingCharacters(in: .whitespaces).count < 2)
                    ResultLine(text: line)
                }
            }
            .refreshable { await reload() }
        }
        .plScreenTitle("Messages")
    }
}

struct ProfileEditView: View {
    let me: SiteAccount.Me
    @State private var firstName = ""
    @State private var handle = ""
    @State private var color = ""
    @State private var line: String?
    @State private var busy = false

    var body: some View {
        Form {
            Section("Name") { TextField("First name", text: $firstName) }
            Section {
                TextField("handle", text: $handle).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("Handle") } footer: { Text("Three to twenty letters or numbers.") }
            Section {
                HStack {
                    TextField("#c9a84c", text: $color).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if let c = StorefrontColor.hex(color) { Circle().fill(c).frame(width: 22, height: 22).accessibilityHidden(true) }
                }
            } header: { Text("Colour") } footer: { Text("A six-digit hex, or empty for none.") }
            Section {
                Button {
                    busy = true
                    Task { await save(); busy = false }
                } label: { HStack { Text("Save"); if busy { Spacer(); ProgressView() } }.frame(minHeight: PLMetric.touch) }.disabled(busy)
                ResultLine(text: line)
            }
        }
        .plScreenTitle("Profile")
        .onAppear { firstName = me.firstName ?? ""; handle = me.handle ?? ""; color = me.brandColor ?? "" }
        .sensoryFeedback(PLHaptic.success, trigger: line == "Saved.")
    }

    private func save() async {
        var body: [String: Any] = ["firstName": firstName, "brandColor": color]
        if handle != (me.handle ?? "") { body["handle"] = handle }
        do { _ = try await Site.post("api/account/profile", body); line = "Saved."; await SiteAccount.shared.refresh() }
        catch { line = "Not saved. \(error.localizedDescription)" }
    }
}
