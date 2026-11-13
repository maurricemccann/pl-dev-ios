import SwiftUI
import TipKit

// MARK: - Approvals (pl-os ModerationPanel, AdApprovalsPanel, ManualPostPanel)

@MainActor @Observable final class ApprovalsModel {
    struct Draft: Decodable, Identifiable, Equatable {
        let id: String; let title: String?; var caption: String?; var media_url: String?; let media_type: String?
        let platform: String?; let created_at: String?; let similar_to: String?; let family_platforms: [String]?
    }
    struct Lane: Identifiable { let platform: String; let days: Double; var id: String { platform } }
    struct Runway: Decodable {
        let backlog: Int?; let ceiling: Int?; let generation_paused: Bool?; let next_open_slot: String?
        let lane_runway_days: [String: Double]?
    }
    struct Capture: Decodable, Identifiable, Equatable { let id: String; let type: String?; let payload: String?; let created_at: String? }
    struct Desire: Decodable, Identifiable, Equatable { let id: String; let text: String?; let created_at: String? }
    struct Report: Decodable, Identifiable, Equatable { let id: String; let refType: String; let refId: String; let reason: String?; let content: String?; let authorHandle: String?; let count: Int? }
    struct Ad: Decodable, Identifiable, Equatable { let id: String; let brand: String?; let ad_no: Int?; let name: String?; let channel: String?; let body: String?; let link: String?; let needs: String? }
    struct Manual: Decodable, Identifiable, Equatable { let id: String; let platform: String?; let title: String?; let caption: String?; let media_url: String? }

    var drafts: [Draft] = []
    var runway: Runway?
    var captures: [Capture] = []
    var desires: [Desire] = []
    var reports: [Report] = []
    var ads: [Ad] = []
    var manual: [Manual] = []
    var selection = Set<String>()
    var result: String?
    var tick = 0
    var loaded = false

    var lanes: [Lane] { (runway?.lane_runway_days ?? [:]).map { Lane(platform: $0.key, days: $0.value) }.sorted { $0.days < $1.days } }

    func load(model: AppModel) async {
        struct D: Decodable { let drafts: [Draft]? }
        struct A: Decodable { let ads: [Ad]? }
        struct M: Decodable { let posts: [Manual]? }
        async let d = try? Console.get("api/drafts/pending", D.self, model: model, query: ["limit": "40"])
        async let r = try? Console.get("run/moderation-runway", Runway.self, model: model)
        async let c = try? Console.q("captures", [Capture].self, model: model)
        async let de = try? Console.q("desires", [Desire].self, model: model)
        async let re = try? Console.q("reports", [Report].self, model: model)
        async let a = try? Console.get("api/ads/pending", A.self, model: model)
        async let m = try? Console.get("api/posts/manual-pending", M.self, model: model)
        let (d1, r1, c1, de1, re1, a1, m1) = await (d, r, c, de, re, a, m)
        drafts = d1?.drafts ?? []; runway = r1; captures = c1 ?? []; desires = de1 ?? []; reports = re1 ?? []
        ads = a1?.ads ?? []; manual = m1?.posts ?? []
        result = d1 == nil ? "Not loaded: the drafts did not answer. Pull to try again." : nil
        loaded = true
    }

    /// Optimistic: the card leaves at once and comes back if the server refuses.
    func moderate(_ d: Draft, _ action: String, model: AppModel) async {
        guard let i = drafts.firstIndex(of: d) else { return }
        drafts.remove(at: i)
        do { try await Console.post("api/drafts/moderate", ["draft_id": d.id, "action": action], model: model); tick += 1 }
        catch { drafts.insert(d, at: min(i, drafts.count)); result = "Not saved. \(error.localizedDescription)" }
    }

    func bulk(_ action: String, model: AppModel) async {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        struct R: Decodable { struct One: Decodable { let draft_id: String; let ok: Bool }; let results: [One]? }
        var done = 0
        for chunk in stride(from: 0, to: ids.count, by: 20).map({ Array(ids[$0..<min($0 + 20, ids.count)]) }) {   // the web chunks too
            if let d = try? await Console.post("api/drafts/bulk-moderate", ["draft_ids": chunk, "action": action], model: model, timeout: 45),
               let r = try? JSONDecoder().decode(R.self, from: d) {
                let ok = Set((r.results ?? []).filter(\.ok).map(\.draft_id))
                done += ok.count
                drafts.removeAll { ok.contains($0.id) }
            }
        }
        selection.removeAll()
        tick += 1
        result = done == ids.count ? "\(action == "approve" ? "Approved" : "Held") \(done)." : "Not all saved: \(done) of \(ids.count). Pull to see what is left."
    }

    func regenerate(_ d: Draft, model: AppModel) async {
        struct R: Decodable { let caption: String?; let violations: [String]? }
        do {
            let r = try JSONDecoder().decode(R.self, from: try await Console.post("api/drafts/regenerate-caption", ["draft_id": d.id], model: model, timeout: 60))
            if let i = drafts.firstIndex(where: { $0.id == d.id }), let c = r.caption { drafts[i].caption = c }
            result = (r.violations ?? []).isEmpty ? "New caption written." : "New caption, with notes: \((r.violations ?? []).joined(separator: ", "))"
            tick += 1
        } catch { result = "Not rewritten. \(error.localizedDescription)" }
    }

    func swapImage(_ d: Draft, to url: String, model: AppModel) async {
        do {
            try await Console.post("api/drafts/update-image", ["id": d.id, "media_url": url], model: model)
            if let i = drafts.firstIndex(where: { $0.id == d.id }) { drafts[i].media_url = url }
            result = "Picture changed."; tick += 1
        } catch { result = "Not changed. \(error.localizedDescription)" }
    }

    func capture(_ c: Capture, _ action: String, model: AppModel) async {
        captures.removeAll { $0.id == c.id }
        do { try await Console.post("api/captures/moderate", ["capture_id": c.id, "action": action], model: model); tick += 1 }
        catch { captures.append(c); result = "Not saved. \(error.localizedDescription)" }
    }

    func desire(_ d: Desire, _ action: String, model: AppModel) async {
        desires.removeAll { $0.id == d.id }
        do { try await Console.post("api/pldev/x/desire", ["id": d.id, "action": action], model: model); tick += 1 }
        catch { desires.append(d); result = "Not saved. \(error.localizedDescription)" }
    }

    func report(_ r: Report, _ action: String, model: AppModel) async {
        reports.removeAll { $0.id == r.id }
        do { try await Console.post("api/pldev/x/report", ["refType": r.refType, "refId": r.refId, "action": action], model: model); tick += 1 }
        catch { reports.append(r); result = "Not saved. \(error.localizedDescription)" }
    }

    func ad(_ a: Ad, _ action: String, model: AppModel) async {
        ads.removeAll { $0.id == a.id }
        do { try await Console.post("api/ads/moderate", ["ad_id": a.id, "action": action], model: model); tick += 1 }
        catch { ads.append(a); result = "Not saved. \(error.localizedDescription)" }
    }

    func posted(_ m: Manual, url: String?, model: AppModel) async {
        manual.removeAll { $0.id == m.id }
        var body: [String: Any] = ["post_id": m.id]
        if let url, !url.isEmpty { body["external_url"] = url }
        do { try await Console.post("api/posts/mark-posted", body, model: model); tick += 1 }
        catch { manual.append(m); result = "Not saved. \(error.localizedDescription)" }
    }
}

/// The image a capture carries, if any: "[image] https://..." in its payload.
private func captureImage(_ payload: String?) -> URL? {
    guard let p = payload, let r = p.range(of: "[image] ") else { return nil }
    return URL(string: String(p[r.upperBound...]).components(separatedBy: .whitespacesAndNewlines).first ?? "")
}

struct ApprovalsView: View {
    let model: AppModel
    @State private var state = ApprovalsModel()
    @State private var editing: EditMode = .inactive
    @State private var nowTarget: ApprovalsModel.Draft?
    @State private var pictureFor: ApprovalsModel.Draft?

    var body: some View {
        List(selection: $state.selection) {
            if let r = state.result { ResultLine(text: r) }
            if let rw = state.runway {
                Section {
                    LabeledContent("In the drip", value: "\(rw.backlog ?? 0) of \(rw.ceiling ?? 0)")
                    if rw.generation_paused == true { Label("New drafts paused: the drip is full", systemImage: "pause.circle") }
                    ForEach(state.lanes) { l in
                        LabeledContent(l.platform.capitalized) {
                            Text(l.days, format: .number.precision(.fractionLength(1))).monospacedDigit() + Text(" days")
                        }
                    }
                } header: { Text("Runway") } footer: {
                    if let s = rw.next_open_slot, let d = Date.pl(s) { Text("Next open slot \(d.formatted(.relative(presentation: .named))).") }
                }
            }
            Section {
                if !state.drafts.isEmpty { TipView(DraftGesturesTip()).selectionDisabled() }
                if state.loaded && state.drafts.isEmpty {
                    ContentUnavailableView("Nothing waiting", systemImage: "checkmark.seal", description: Text("No drafts need you."))
                }
                ForEach(state.drafts) { d in
                    DraftRow(d: d)
                        .tag(d.id)
                        .swipeActions(edge: .trailing) { Button("Approve") { Task { await state.moderate(d, "approve", model: model) } }.tint(.green) }
                        .swipeActions(edge: .leading) { Button("Hold") { Task { await state.moderate(d, "hold", model: model) } }.tint(.orange) }
                        .contextMenu {
                            Button("Approve", systemImage: "checkmark") { Task { await state.moderate(d, "approve", model: model) } }
                            Button("Post now", systemImage: "bolt") { nowTarget = d }
                            Button("Hold", systemImage: "pause") { Task { await state.moderate(d, "hold", model: model) } }
                            Button("Rewrite the caption", systemImage: "arrow.triangle.2.circlepath") { Task { await state.regenerate(d, model: model) } }
                            Button("Change the picture", systemImage: "photo.on.rectangle") { pictureFor = d }
                            Button("Copy caption", systemImage: "doc.on.doc") { UIPasteboard.general.string = d.caption }
                        }
                }
            } header: { Text("Drafts · \(state.drafts.count)") } footer: {
                if !state.drafts.isEmpty { Text("Swipe left to approve, right to hold. Touch and hold for Post now and Rewrite. Select for many at once.") }
            }
            if !state.captures.isEmpty {
                Section("Captures") {
                    ForEach(state.captures) { c in
                        VStack(alignment: .leading, spacing: 6) {
                            if let u = captureImage(c.payload) {
                                AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { Color.secondary.opacity(0.15).frame(height: 120) }
                                    .clipShape(RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous)).frame(maxHeight: 220)
                            }
                            Text((c.payload ?? "").replacingOccurrences(of: #"\[image\] \S+"#, with: "", options: .regularExpression)).lineLimit(6)
                            Text("\(c.type ?? "") · ").font(.caption).foregroundStyle(.secondary) + Text(Date.pl(c.created_at) ?? .now, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                        }
                        .selectionDisabled()
                        .swipeActions(edge: .trailing) { Button("Keep") { Task { await state.capture(c, "approve", model: model) } }.tint(.green) }
                        .swipeActions(edge: .leading) { Button("Reject", role: .destructive) { Task { await state.capture(c, "reject", model: model) } } }
                    }
                }
            }
            if !state.desires.isEmpty {
                Section("Desires") {
                    ForEach(state.desires) { d in
                        Text(d.text ?? "").selectionDisabled()
                            .swipeActions(edge: .trailing) { Button("Approve") { Task { await state.desire(d, "approved", model: model) } }.tint(.green) }
                            .swipeActions(edge: .leading) { Button("Hide", role: .destructive) { Task { await state.desire(d, "hidden", model: model) } } }
                    }
                }
            }
            if !state.reports.isEmpty {
                Section("Reported in the congregation") {
                    ForEach(state.reports) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.content ?? "").lineLimit(5)
                            Text("\(r.refType) · \(r.count ?? 1) flag\((r.count ?? 1) == 1 ? "" : "s")\(r.reason.map { " · \($0)" } ?? "")\(r.authorHandle.map { " · @\($0)" } ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .selectionDisabled()
                        .swipeActions(edge: .trailing) { Button("Remove", role: .destructive) { Task { await state.report(r, "remove", model: model) } } }
                        .swipeActions(edge: .leading) { Button("Dismiss") { Task { await state.report(r, "dismiss", model: model) } }.tint(.gray) }
                    }
                }
            }
            if !state.ads.isEmpty {
                Section("Ads") {
                    ForEach(state.ads) { a in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(a.brand ?? "") #\(a.ad_no ?? 0) · \(a.name ?? "")").font(.headline)
                            Text(a.body ?? "")
                            if let n = a.needs, !n.isEmpty { Text("Needs: \(n)").font(.caption).foregroundStyle(.orange) }
                            if let l = a.link, let u = URL(string: l) { Link(l, destination: u).font(.caption) }
                        }
                        .selectionDisabled()
                        .swipeActions(edge: .trailing) { Button("Approve") { Task { await state.ad(a, "approve", model: model) } }.tint(.green) }
                        .swipeActions(edge: .leading) { Button("Reject", role: .destructive) { Task { await state.ad(a, "reject", model: model) } } }
                    }
                }
            }
            if !state.manual.isEmpty {
                Section {
                    ForEach(state.manual) { m in ManualRow(m: m, model: model, state: state).selectionDisabled() }
                } header: { Text("Post by hand") } footer: { Text("Copy, post it yourself, then mark it posted.") }
            }
        }
        .environment(\.editMode, $editing)
        .navigationTitle("Approvals")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing.isEditing ? "Done" : "Select") { withAnimation { editing = editing.isEditing ? .inactive : .active; state.selection.removeAll() } }
            }
            if editing.isEditing {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Hold \(state.selection.count)") { Task { await state.bulk("hold", model: model); editing = .inactive } }
                        .disabled(state.selection.isEmpty)
                    Spacer()
                    Button("Approve \(state.selection.count)") { Task { await state.bulk("approve", model: model); editing = .inactive } }
                        .disabled(state.selection.isEmpty).bold()
                }
            }
        }
        .confirmationDialog("Post this now, ahead of the drip?", isPresented: Binding(get: { nowTarget != nil }, set: { if !$0 { nowTarget = nil } }), titleVisibility: .visible) {
            Button("Post now") { if let d = nowTarget { Task { await state.moderate(d, "approve_now", model: model) } } }
        } message: { Text("It goes out on \(nowTarget?.platform?.capitalized ?? "its platform") within minutes.") }
        .refreshable { await state.load(model: model) }
        .task { await state.load(model: model) }
        .sensoryFeedback(PLHaptic.commit, trigger: state.tick)
        .sheet(item: $pictureFor) { d in
            PicturePicker { url in pictureFor = nil; Task { await state.swapImage(d, to: url, model: model) } }
        }
    }
}

/// Pick a piece from the archive for a draft (pl-os VisualPicker, archive tab).
struct PicturePicker: View {
    let picked: (String) -> Void
    struct Piece: Decodable, Identifiable { let cr: String; let url: String; let thumb: String?; let title: String?; let shareable: Bool?; var id: String { cr } }
    struct Manifest: Decodable { let pieces: [Piece] }
    @State private var pieces: [Piece] = []
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                    ForEach(pieces.filter { search.isEmpty || ($0.title ?? $0.cr).localizedCaseInsensitiveContains(search) || $0.cr.localizedCaseInsensitiveContains(search) }) { p in
                        Button { picked(p.url) } label: {
                            AsyncImage(url: URL(string: p.thumb ?? p.url)) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.12) }
                                .frame(height: 100).clipped()
                        }
                        .accessibilityLabel(p.title ?? p.cr)
                    }
                }
                .padding(6)
            }
            .searchable(text: $search, prompt: "Title or PL number")
            .navigationTitle("Choose a picture").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
            .task {
                if let r = try? await URLSession.shared.data(from: URL(string: "https://assets.psychedluxuries.com/manifest.json")!),
                   let m = try? JSONDecoder().decode(Manifest.self, from: r.0) { pieces = m.pieces.filter { $0.shareable != false } }
            }
        }
    }
}

private struct DraftRow: View {
    let d: ApprovalsModel.Draft
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let s = d.media_url, let url = URL(string: s), (d.media_type ?? "image") != "video" {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                    .frame(height: 220).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: PLRadius.row, style: .continuous))
            } else if d.media_type == "video" {
                Label("Video", systemImage: "play.rectangle").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text((d.platform ?? "?").capitalized).font(.caption.bold())
                if let fam = d.family_platforms, !fam.isEmpty { Text("also " + fam.joined(separator: ", ")).font(.caption2) }
                Spacer()
                Ago(text: d.created_at).font(.caption2)
            }
            .foregroundStyle(.secondary)
            if let t = d.title, !t.isEmpty { Text(t).font(.headline) }
            Text(d.caption ?? "").font(.body).plReading()
            if let s = d.similar_to { Label("Close to \(s)", systemImage: "square.on.square").font(.caption).foregroundStyle(.orange) }
        }
        .padding(.vertical, 4)
    }
}

private struct ManualRow: View {
    let m: ApprovalsModel.Manual
    let model: AppModel
    let state: ApprovalsModel
    @State private var url = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((m.platform ?? "").capitalized).font(.caption.bold()).foregroundStyle(.secondary)
            if let t = m.title { Text(t).font(.headline) }
            Text(m.caption ?? "").lineLimit(6)
            HStack {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = [m.title, m.caption].compactMap { $0 }.joined(separator: "\n\n") }
                if let compose = URL(string: m.platform == "tumblr" ? "https://www.tumblr.com/new" : "https://www.\(m.platform ?? "tumblr").com") {
                    Button("Open \((m.platform ?? "").capitalized)", systemImage: "arrow.up.forward.app") { openURL(compose) }
                }
            }
            .buttonStyle(.bordered).font(.caption)
            TextField("Link to the post (optional)", text: $url).textContentType(.URL).keyboardType(.URL).font(.caption)
            Button("Mark posted") { Task { await state.posted(m, url: url, model: model) } }.buttonStyle(.borderedProminent).font(.caption)
        }
    }
}

// MARK: - Make a draft (DraftComposer, CraftPanel, FeedDoorway)

struct MakeView: View {
    let model: AppModel
    @State private var caption = ""
    @State private var platform = "instagram"
    @State private var media = ""
    @State private var result: String?
    @State private var busy = false
    @State private var tick = 0
    private let platforms = ["instagram", "threads", "bluesky", "tumblr", "facebook", "linkedin", "pinterest"]

    @State private var intakeKind = "text"
    @State private var intakeText = ""

    var body: some View {
        Form {
            Section {
                Picker("Kind", selection: $intakeKind) { Text("Text").tag("text"); Text("Quote").tag("quote"); Text("Link").tag("link") }.pickerStyle(.segmented)
                TextField(intakeKind == "link" ? "URL → pull it in" : intakeKind == "quote" ? "Phrase · hook · caption" : "Body or essay", text: $intakeText, axis: .vertical)
                    .lineLimit(2...8).keyboardType(intakeKind == "link" ? .URL : .default)
                Button("Add to the system →") { Task { await go { try await Console.post("api/pldev/x/intake", ["type": intakeKind, "note": intakeText], model: model); intakeText = ""; return "Captured. The system will sort it." } } }
                    .disabled(intakeText.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            } header: { Text("Capture into the system") } footer: { Text("Artwork with a picture: use Capture on Home, which sends photos.") }
            Section {
                TextField("Caption", text: $caption, axis: .vertical).lineLimit(4...12)
                Picker("Platform", selection: $platform) { ForEach(platforms, id: \.self) { Text($0.capitalized).tag($0) } }
                TextField("Image or video address (optional)", text: $media).keyboardType(.URL).textInputAutocapitalization(.never)
                Button(busy ? "Saving…" : "Add to Approvals") { Task { await create() } }
                    .disabled(caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            } header: { Text("New draft") } footer: { Text("It waits in Approvals like every other draft.") }
            Section {
                Button("Craft 3 more drafts", systemImage: "wand.and.stars") { Task { await go { try await Console.post("api/craft-batch", ["count": 3], model: model, timeout: 90); return "Crafted. They are in Approvals." } } }
                Button("Run the content wave", systemImage: "water.waves") { Task { await go { await Console.run("run/content-wave", model: model) } } }
            } header: { Text("Let the house make more") }
            if let result { Section { ResultLine(text: result) } }
        }
        .navigationTitle("Make")
        .disabled(busy)
        .sensoryFeedback(PLHaptic.commit, trigger: tick)
    }

    private func create() async {
        await go {
            var body: [String: Any] = ["id": "pldev-\(UUID().uuidString.prefix(8).lowercased())", "caption": caption, "platform": platform]
            if !media.isEmpty { body["media_url"] = media; body["media_type"] = media.lowercased().hasSuffix(".mp4") ? "video" : "image" }
            try await Console.post("api/drafts/create", body, model: model)
            caption = ""; media = ""
            return "Added. It is waiting in Approvals."
        }
    }

    private func go(_ work: () async throws -> String) async {
        busy = true; defer { busy = false }
        do { result = try await work(); tick += 1 } catch { result = "Not done. \(error.localizedDescription)" }
    }
}

// MARK: - Site controls (SiteControlsPanel, BetaTesterPanel)

struct SiteControlsView: View {
    let model: AppModel
    struct Config: Decodable {
        var maintenance_mode: Bool?; var outbound_paused: Bool?; var founder_note: String?; var founder_ledger_banner: Bool?
        var shop_enabled: Bool?; var shipping_note: String?; var promo_banner: String?; var contact_email: String?; var contact_sla: String?
    }
    struct Ledger: Decodable { let sealed: Int?; let total: Int? }
    @State private var c: Config?
    @State private var ledger: Ledger?
    @State private var result: String?
    @State private var confirmMaintenance = false
    @State private var beta = ""
    @State private var tick = 0

    var body: some View {
        Form {
            if let r = result { ResultLine(text: r) }
            if c != nil {
                Section {
                    Toggle("Shop open", isOn: bool(\.shop_enabled, "shop_enabled"))
                    Toggle("Pause outbound posting", isOn: bool(\.outbound_paused, "outbound_paused"))
                    Toggle("Maintenance mode", isOn: Binding(get: { c?.maintenance_mode ?? false }, set: { v in
                        if v { confirmMaintenance = true } else { Task { await set("maintenance_mode", false) } }
                    }))
                    Toggle("Founder ledger banner", isOn: bool(\.founder_ledger_banner, "founder_ledger_banner"))
                    if let l = ledger { LabeledContent("Founder ledger", value: "\(l.sealed ?? 0) of \(l.total ?? 0) sealed") }
                } header: { Text("Switches") } footer: { Text("Maintenance mode closes the site and turns the creator signal to do not disturb.") }
                Section("Words on the site") {
                    text("Founder note", \.founder_note, "founder_note")
                    text("Promo banner", \.promo_banner, "promo_banner")
                    text("Shipping note", \.shipping_note, "shipping_note")
                    text("Contact email", \.contact_email, "contact_email")
                    text("Reply promise", \.contact_sla, "contact_sla")
                }
            }
            Section {
                TextField("Email", text: $beta).keyboardType(.emailAddress).textInputAutocapitalization(.never).textContentType(.emailAddress)
                Button("Grant beta access") { Task { await invite() } }.disabled(beta.isEmpty)
            } header: { Text("Beta tester") } footer: { Text("Gives them Kin access and puts them on the signal. A founder or member keeps their role.") }
        }
        .navigationTitle("Site controls")
        .task { await load() }
        .refreshable { await load() }
        .sensoryFeedback(PLHaptic.commit, trigger: tick)
        .confirmationDialog("Close the whole site?", isPresented: $confirmMaintenance, titleVisibility: .visible) {
            Button("Turn on maintenance", role: .destructive) { Task { await set("maintenance_mode", true) } }
        } message: { Text("Visitors see the maintenance page until you turn it off.") }
    }

    private func load() async {
        c = try? await Console.get("api/site-config", Config.self, model: model)
        ledger = try? await Console.get("api/founder-ledger/count", Ledger.self, model: model)
        if c == nil { result = "Not loaded: the site settings did not answer." }
    }

    private func set(_ key: String, _ value: Any) async {
        do { try await Console.post("api/site-config", ["key": key, "value": value], model: model); result = "Saved."; tick += 1 }
        catch { result = "Not saved. \(error.localizedDescription)" }
        await load()
    }

    private func bool(_ kp: WritableKeyPath<Config, Bool?>, _ key: String) -> Binding<Bool> {
        Binding(get: { c?[keyPath: kp] ?? false }, set: { v in c?[keyPath: kp] = v; Task { await set(key, v) } })
    }

    private func text(_ label: String, _ kp: WritableKeyPath<Config, String?>, _ key: String) -> some View {
        TextField(label, text: Binding(get: { c?[keyPath: kp] ?? "" }, set: { c?[keyPath: kp] = $0 }), axis: .vertical)
            .onSubmit { Task { await set(key, c?[keyPath: kp] ?? "") } }
            .submitLabel(.done)
    }

    private func invite() async {
        struct R: Decodable { let message: String? }
        do {
            let d = try await Console.post("api/pldev/x/beta", ["email": beta], model: model)
            result = (try? JSONDecoder().decode(R.self, from: d))?.message ?? "Added."; beta = ""; tick += 1
        } catch { result = "Not added. \(error.localizedDescription)" }
    }
}
