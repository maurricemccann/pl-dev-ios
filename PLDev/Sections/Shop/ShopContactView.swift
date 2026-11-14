import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A labelled field in the site's form look: the tracked-capitals label over a hairline-outlined box.
struct SiteField: View {
    let label: String
    var hint: String? = nil
    @Binding var text: String
    var prompt = ""
    var lines = 1
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var capitalize = TextInputAutocapitalization.sentences
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text(label.uppercased()).font(SiteFont.body(11, relativeTo: .caption)).tracking(3.2)
                + Text(hint.map { "  " + $0 } ?? "").font(SiteFont.body(11, relativeTo: .caption)))
                .foregroundStyle(Bone.inkFaint(scheme))
            TextField(prompt, text: $text, axis: .vertical)
                .lineLimit(lines...max(lines, lines == 1 ? 1 : 10))
                .keyboardType(keyboard).textContentType(contentType).textInputAutocapitalization(capitalize).autocorrectionDisabled(keyboard == .emailAddress)
                .font(SiteFont.body(16)).foregroundStyle(Bone.ink(scheme))
                .padding(.horizontal, 16).padding(.vertical, 13).frame(minHeight: 50, alignment: .topLeading)
                .background(Bone.raised(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Bone.line(scheme), lineWidth: 0.8) }
        }
    }
}

/// `/contact`: Reach the architect. The site's form, with its human check, in the phone's hands. A photo of a flaw comes from
/// the Photos picker (the site takes jpg, png, webp, heic or gif up to about 5 MB).
struct ContactView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var order = ""
    @State private var message = ""
    @State private var pick: PhotosPickerItem?
    @State private var photo: (name: String, base64: String)?
    @State private var photoNote: String?
    @State private var ballot: SiteBallot?
    @State private var web: WebPage?
    @State private var sending = false
    @State private var received: String?
    @State private var line: String?
    @State private var tick = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    private var needsCheck: Bool { !(ballot?.siteKey ?? "").isEmpty }
    private var emailOK: Bool { email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil }
    private var canSend: Bool { !sending && emailOK && message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Contact").siteLabel()
                    Text("Reach the architect.").font(SiteFont.display(40, italic: true)).foregroundStyle(Bone.gold).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    Text("For orders, the work, press, or anything else \u{2014} the door is open.").siteBody(15)
                }
                if let received {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Received").siteLabel().foregroundStyle(Bone.gold)
                        Text(received).font(SiteFont.display(22)).foregroundStyle(Bone.ink(scheme))
                    }
                    .siteCard()
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        SiteField(label: "Name", hint: "(optional)", text: $name, contentType: .name, capitalize: .words)
                        SiteField(label: "Email", text: $email, keyboard: .emailAddress, contentType: .emailAddress, capitalize: .never)
                        SiteField(label: "Order number", hint: "(if this is about an order)", text: $order, prompt: "From your confirmation email", capitalize: .characters)
                        VStack(alignment: .leading, spacing: 8) {
                            (Text("PHOTO").font(SiteFont.body(11, relativeTo: .caption)).tracking(3.2)
                                + Text("  (if something arrived wrong)").font(SiteFont.body(11, relativeTo: .caption)))
                                .foregroundStyle(Bone.inkFaint(scheme))
                            HStack(spacing: 12) {
                                PhotosPicker(selection: $pick, matching: .images) { GhostLabel(title: photo == nil ? "Choose a photo" : "Change photo") }
                                    .frame(maxWidth: 220)
                                if photo != nil {
                                    Button { photo = nil; pick = nil; photoNote = nil } label: { Text("Remove").siteLabel(10).frame(minHeight: 44) }.buttonStyle(.plain)
                                }
                            }
                            if let photo { Text("Attached: \(photo.name)").font(SiteFont.body(12)).foregroundStyle(Bone.inkFaint(scheme)) }
                            if let photoNote { Text(photoNote).font(SiteFont.body(12)).foregroundStyle(Bone.oxblood) }
                        }
                        SiteField(label: "Message", text: $message, prompt: "Orders, the work, press, or anything else.", lines: 5)
                        HumanGate(siteKey: ballot?.siteKey ?? "")
                        Button { Task { await send() } } label: {
                            HStack(spacing: 10) { Text(sending ? "Sending" : needsCheck ? "Continue on the site" : "Send"); if sending { PLLoader().tint(.white) } }
                        }
                        .buttonStyle(SitePill())
                        .disabled(!canSend)
                        ResultLine(text: line)
                        Text("Every message reaches the architect directly. Each one is read by hand; a reply follows within a few days.")
                            .font(SiteFont.body(12)).foregroundStyle(Bone.inkFaint(scheme)).lineSpacing(4)
                    }
                }
                VStack(spacing: 12) {
                    SiteRule()
                    Text("Or reach out directly \u{2014}").font(SiteFont.body(13)).foregroundStyle(Bone.inkFaint(scheme)).padding(.top, 8)
                    HStack(spacing: 12) {
                        Button("Email") { if let u = Site.base?.host().flatMap({ URL(string: "mailto:support@" + $0.replacingOccurrences(of: "www.", with: "")) }) { openURL(u) } }.buttonStyle(SiteGhost())
                        Button("Instagram") { if let u = URL(string: "https://instagram.com/psychedluxuries") { openURL(u) } }.buttonStyle(SiteGhost())
                    }
                    NavigationLink { SignalView() } label: { Text("Want the work in your inbox? Receive the signal \u{2192}").siteLabel(10).frame(minHeight: 44) }.buttonStyle(.plain)
                    Text("Watch this.").font(SiteFont.display(26, italic: true)).foregroundStyle(Bone.gold).padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .siteScreen()
        .plScreenTitle("Contact")
        .scrollDismissesKeyboard(.interactively)
        .task {
            ballot = await SiteBallot.load()
            if email.isEmpty, let mine = SiteAccount.shared.me?.email { email = mine }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task { await take(item) }
        }
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        .sensoryFeedback(PLHaptic.commit, trigger: tick)
    }

    private func take(_ item: PhotosPickerItem) async {
        photoNote = nil
        guard let data = try? await item.loadTransferable(type: Data.self) else { photo = nil; photoNote = "That photo could not be read. Pick another."; return }
        let ext = (item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg").lowercased()
        let b64 = data.base64EncodedString()
        // the site refuses anything over about 5 MB once decoded (7,000,000 characters of base64)
        guard b64.count <= 7_000_000 else { photo = nil; photoNote = "That image is over 5MB. Send a smaller one, or email it directly."; return }
        guard ["jpg", "jpeg", "png", "webp", "heic", "gif"].contains(ext) else { photo = nil; photoNote = "The site takes jpg, png, webp, heic or gif."; return }
        photo = (name: "photo.\(ext)", base64: b64)
    }

    private func send() async {
        if needsCheck {   // the human check runs on the site's own page, in Apple's sheet
            UIPasteboard.keep(message)
            line = "Your message is copied. Paste it on the site\u{2019}s page" + (photo == nil ? "." : " and attach the photo there.")
            if let url = Site.page("contact") { web = WebPage(url) }
            return
        }
        sending = true; line = nil
        defer { sending = false }
        var body: [String: Any] = ["name": name.trimmingCharacters(in: .whitespaces), "email": email.trimmingCharacters(in: .whitespaces), "message": message]
        let o = order.trimmingCharacters(in: .whitespaces)
        if !o.isEmpty { body["orderId"] = o }
        if let photo { body["photo"] = ["filename": photo.name, "content": photo.base64] }
        do {
            let r = try await Site.post("api/contact", body)
            received = r.message ?? "Every message reaches the architect directly. Each one is read by hand; a reply follows within a few days."
            tick += 1
        } catch {
            line = "Not sent. \(error.localizedDescription)"
        }
    }
}

/// The outline pill's look for a control that is not a `Button` (the Photos picker).
struct GhostLabel: View {
    let title: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(title).font(SiteFont.body(12, relativeTo: .footnote, weight: .medium)).textCase(.uppercase).tracking(2.4)
            .foregroundStyle(Bone.ink(scheme))
            .padding(.horizontal, 22).frame(minHeight: 48).frame(maxWidth: .infinity)
            .overlay { Capsule().strokeBorder(Bone.ink(scheme).opacity(0.55), lineWidth: 0.8) }
    }
}
