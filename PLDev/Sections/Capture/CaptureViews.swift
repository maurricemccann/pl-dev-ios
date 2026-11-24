import SwiftUI
import TipKit
import UIKit

/// Capture, as pl-os shows it: the header and clock, the three rooms (Add is Intake itself, Where it went is the trail,
/// Waiting is what waits on him), all on the console ground with gold as the one accent.
struct CaptureView: View {
    let model: AppModel
    @Bindable var state: CaptureModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List { Group {
            OSHeader().captureRow()
            switch state.room {
            case .add:
                CaptureDropBox(model: model, state: state).captureRow()   // the one panel (his ruling 11-14): drop anything, a sheet asks where it goes
            case .trail:
                CaptureTrailRoom(model: model, state: state)
            case .waiting:
                CaptureWaitingRoom(model: model, state: state)
            }
        }.listRowBackground(PLRowGround()) }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom, spacing: 0) {   // his layout 11-14: the three rooms as a sticky bar at the bottom
            CaptureRoomBar(room: $state.room, badges: [.trail: state.deck.count, .waiting: model.inboxCount])
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 4)
        }
        .scrollDismissesKeyboard(.interactively)
        .osScreen()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())   // the left-edge swipe home still works with the bar hidden
        .refreshable { await state.loadAll(model: model); await model.drainInbox() }
        .task { await state.loadAll(model: model) }
        .sensoryFeedback(PLHaptic.success, trigger: state.sentTick)
        .sensoryFeedback(PLHaptic.commit, trigger: state.tick)
        .sensoryFeedback(.selection, trigger: state.kind)
        .sensoryFeedback(.selection, trigger: state.room)
        .sheet(item: $state.detail) { d in CaptureDetailSheet(detail: d) }
        .onChange(of: state.room) { _, room in if room != .add { hideKeyboard() } }
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

enum CaptureSweeps { static let text = "05:30 · 11:30 · 17:30 · 22:30" }

func detailOf(_ r: CaptureModel.TrailRow) -> CaptureModel.TrailDetail {
    CaptureModel.TrailDetail(id: r.id, label: r.label, payload: r.payload ?? "", stateLabel: r.state.label, stateDetail: r.state.detail, tone: r.state.tone,
                             meta: [r.type, r.source].compactMap { $0 }.joined(separator: " · "), created: r.created_at, promoted: r.promoted_cr)
}

/// One line of the trail: its state in a box, what it was, what became of it.
struct CaptureTrailLine: View {
    let label: String
    let badge: String
    var saving: Bool
    var tone: CaptureState.Tone
    let detail: String
    let ago: String?
    let thumb: Data?
    let image: URL?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CaptureBadge(label: badge, tone: tone, saving: saving)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(Font.pl(.subheadline)).foregroundStyle(PLOS.text(scheme)).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(detail).lineLimit(2)
                    if let ago { Text("·"); Ago(text: ago) }
                }
                .font(Font.pl(size: 11, design: .monospaced)).foregroundStyle(PLOS.dim(scheme))
            }
            Spacer(minLength: 0)
            if let thumb, let ui = UIImage(data: thumb) {
                Image(uiImage: ui).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8 * PLStyle.radius, style: .continuous))
            } else if let image {
                AsyncImage(url: image) { i in i.resizable().scaledToFill() } placeholder: { PLOS.surface2(scheme) }
                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8 * PLStyle.radius, style: .continuous))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The Where it went room

struct CaptureTrailRoom: View {
    let model: AppModel
    @Bindable var state: CaptureModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Where it went").plHand(22, relativeTo: .title3).foregroundStyle(PLOS.gold)
            Spacer()
            Text("Link sweeps \(CaptureSweeps.text)").font(Font.pl(size: 10, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .captureRow()
        if let n = state.trailNote { ResultLine(text: n).captureRow() }

        // what was captured, by kind, as one bar; and today's sends against the daily cap (his ask 11-14)
        if !state.trail.isEmpty {
            let by = Dictionary(grouping: state.trail, by: { ($0.type ?? "other").isEmpty ? "other" : ($0.type ?? "other") })
            let tones: [Color] = [PLOS.gold, PLOS.ok, PLOS.philosophy, PLOS.warn, PLOS.muted]
            HStack(alignment: .center, spacing: 14) {
                PLStageBar(stages: by.keys.sorted().enumerated().map { .init(name: $0.element, count: by[$0.element]?.count ?? 0, tint: tones[$0.offset % tones.count]) },
                           text: PLOS.text(scheme), dim: PLOS.dim(scheme))
                if let used = state.usedToday, let cap = state.cap, cap > 0 {
                    PLRing(value: Double(used) / Double(cap), center: "\(used)/\(cap)", label: "Today", tint: used >= cap ? PLOS.warn : PLOS.gold,
                           text: PLOS.text(scheme), dim: PLOS.dim(scheme), size: 62)
                }
            }
            .osCard(padding: 12).captureRow()
        }

        let ghosts = state.ghosts
        if !ghosts.isEmpty {
            ForEach(ghosts) { g in
                CaptureTrailLine(label: g.label, badge: g.sent ? "Saving…" : "To send", saving: true, tone: .plain,
                                 detail: g.sent ? "On its way to the intake." : "On this phone. It goes in when the house answers.", ago: nil, thumb: g.thumb, image: nil)
                    .osCard(padding: 12).captureRow()
            }
        }

        if !state.deck.isEmpty {
            TipView(CaptureDeckTip()).captureRow()
            HStack {
                Text("In your moderation deck").osEyebrow(10).foregroundStyle(PLOS.dim(scheme))
                Spacer()
                Text("\(state.deck.count)").osValue(14).foregroundStyle(PLOS.gold).contentTransition(.numericText())
            }
            .captureRow()
            ForEach(state.deck) { c in
                Button { state.detail = CaptureModel.TrailDetail(id: c.id, label: c.label, payload: c.payload ?? "", stateLabel: "Waiting",
                                                                 stateDetail: "In your moderation deck. Swipe to keep it or reject it.", tone: .plain,
                                                                 meta: c.type ?? "", created: c.created_at) } label: {
                    CaptureTrailLine(label: c.label, badge: "Waiting", saving: false, tone: .plain, detail: "Keep it or reject it", ago: c.created_at, thumb: nil, image: captureTrailImage(c.payload))
                        .osCard(owed: false, padding: 12)
                }
                .buttonStyle(.plain)
                .captureRow()
                .swipeActions(edge: .trailing) {
                    Button("Keep") { Task { await state.moderate(c, "approve", model: model) } }.tint(.green)
                }
                .swipeActions(edge: .leading) {
                    Button("Reject", role: .destructive) { Task { await state.moderate(c, "reject", model: model) } }
                }
                .contextMenu {
                    Button("Keep", systemImage: "checkmark") { Task { await state.moderate(c, "approve", model: model) } }
                    Button("Reject", systemImage: "xmark", role: .destructive) { Task { await state.moderate(c, "reject", model: model) } }
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = c.payload }
                }
            }
        }

        CaptureNotesBlock(model: model)

        let deckIDs = Set(state.deck.map(\.id))
        let rows = state.trail.filter { !deckIDs.contains($0.id) }
        if !rows.isEmpty {
            Text("Already sorted").osEyebrow(10).foregroundStyle(PLOS.dim(scheme)).captureRow()
            ForEach(rows) { r in
                Button { state.detail = detailOf(r) } label: {
                    CaptureTrailLine(label: r.label, badge: r.state.label, saving: false, tone: r.state.tone,
                                     detail: r.state.detail + (r.source.map { " · \($0)" } ?? ""), ago: r.created_at, thumb: nil, image: captureTrailImage(r.payload))
                        .osCard(padding: 12)
                }
                .buttonStyle(.plain)
                .captureRow()
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = r.payload }
                    if let u = captureTrailLink(r.payload) { Link(destination: u) { Label("Open the link", systemImage: "arrow.up.right") } }
                    ShareLink(item: r.label) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
        }

        if state.trailLoaded, rows.isEmpty, state.deck.isEmpty, ghosts.isEmpty, state.trailNote == nil {
            ContentUnavailableView("Nothing captured yet", systemImage: "tray", description: Text("What you capture lands here, with where it went."))
                .captureRow()
        } else if !state.trailLoaded {
            PLLoader().frame(maxWidth: .infinity, minHeight: 80).captureRow()
        }
    }
}

// MARK: - The Waiting room

struct CaptureWaitingRoom: View {
    let model: AppModel
    @Bindable var state: CaptureModel
    @Environment(\.colorScheme) private var scheme
    @State private var sending = false
    @State private var result: String?

    var body: some View {
        let w = state.waiting
        OSKpis(items: [("Drafts", w?.drafts.map(String.init) ?? "…", nil), ("Pins", w?.pins.map(String.init) ?? "…", nil),
                       ("Tasks", w?.tasks.map(String.init) ?? "…", nil), ("Shift", w?.shift_open.map(String.init) ?? "…", "open")],
               status: statusLine,
               levels: [w?.drafts.map { PLStatus.waiting($0) }, w?.pins.map { PLStatus.waiting($0) }, w?.tasks.map { PLStatus.waiting($0) }, nil])   // each is a count waiting on his hand: none is clear, any is amber
            .captureRow()

        OSPanel(title: "To send from this phone", badge: "\(model.inboxCount)", owed: model.inboxCount > 0, startOpen: true) {
            Text(model.inboxCount == 0 ? "Nothing is waiting on this phone. Everything you captured has gone in." :
                    "\(model.inboxCount) \(model.inboxCount == 1 ? "capture is" : "captures are") on this phone, not sent yet. They go in by themselves when the house answers.")
                .font(Font.pl(.subheadline)).foregroundStyle(PLOS.dim(scheme))
            if let used = state.usedToday, let cap = state.cap {
                Text("\(used) of \(cap) sent today through the phone door.").font(Font.pl(size: 12, design: .monospaced)).foregroundStyle(PLOS.dim(scheme))
            }
            Button { Task { await sendNow() } } label: { Text(sending ? "Sending…" : "Send now") }
                .buttonStyle(OSPill()).disabled(model.inboxCount == 0 || sending)
            ResultLine(text: result)
        }
        .captureRow()

        OSPanel(title: "Waiting on you", badge: "\(state.owed)", owed: state.owed > 0, startOpen: true) {
            if w == nil { Text("Pull down to read.").foregroundStyle(PLOS.dim(scheme)) }
            else if state.owed == 0 { Text("Nothing waiting on you.").foregroundStyle(PLOS.dim(scheme)) }
            line("Drafts", w?.drafts, "Review them in Approvals", house: "approvals")
            line("Pins", w?.pins, "Each Pin waits for your tap", house: "pinterest")
            line("Manual posts", w?.manual, "Copy ready, to post by hand", house: "approvals")
            line("Ads", w?.ads, "To approve", house: "approvals")
            line("Emails", w?.emails, "Drafts in Tempo", house: "tempo")
            line("Tasks", w?.tasks, "Open on the founder's list", house: "founder")
            line("New captures", w?.captures, "In your moderation deck", house: nil)
            line("Shift items open", w?.shift_open, "On today's shift", house: "founder")
        }
        .captureRow()

        OSPanel(title: "Where captures go") {
            Text("Text, quotes and artwork go to the Notion inbox and your moderation deck.").font(Font.pl(.subheadline)).foregroundStyle(PLOS.text(scheme))
            Text("Links go to the research pool at \(CaptureSweeps.text).").font(Font.pl(.subheadline)).foregroundStyle(PLOS.text(scheme))
            Text("Nothing is posted anywhere from here.").font(Font.pl(.subheadline)).foregroundStyle(PLOS.dim(scheme))
        }
        .captureRow()
    }

    private var statusLine: (String, Color)? {
        if state.waiting == nil { return ("Reading…", PLOS.muted) }
        return state.owed == 0 ? ("Nothing waiting on you", PLOS.ok) : ("\(state.owed) waiting on you", PLOS.warn)
    }

    /// `house`: nil = the Where it went room here; "" = the House founder page; a name = that House room.
    @ViewBuilder private func line(_ title: String, _ n: Int?, _ meta: String, house: String?) -> some View {
        if let n, n > 0 {
            Button {
                if let house {
                    model.open(.section(id: "house", path: house.isEmpty ? [] : [house], query: [:]))
                } else { withAnimation(.snappy) { state.room = .trail } }
            } label: {
                OSRow(title: title, meta: meta) {
                    HStack(spacing: 8) {
                        Text("\(n)").osValue(18).foregroundStyle(PLOS.gold).contentTransition(.numericText())
                        Image(systemName: "chevron.right").font(Font.pl(.caption2).weight(.bold)).foregroundStyle(PLOS.goldDim(scheme))
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func sendNow() async {
        sending = true; defer { sending = false }
        CaptureSection.install(model: model)
        let before = model.inboxCount
        await model.drainInbox()
        let sent = max(0, before - model.inboxCount)
        result = model.inboxCount == 0 ? "Sent. \(sent) \(sent == 1 ? "capture" : "captures") went in." :
            "Not sent yet. \(model.inboxCount) still waiting; the house did not answer."
        state.log = CaptureLog.read()
        state.publishGlance(model: model)
        state.tick += 1
    }
}

// MARK: - The detail sheet

struct CaptureDetailSheet: View {
    let detail: CaptureModel.TrailDetail
    var body: some View {
        CaptureDetailBody(detail: detail).osScreen()   // the sheet wears the console look, so its colours read the same scheme
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
}

private struct CaptureDetailBody: View {
    let detail: CaptureModel.TrailDetail
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    CaptureBadge(label: detail.stateLabel, tone: detail.tone)
                    Spacer()
                    if let c = detail.created { Ago(text: c).font(Font.pl(size: 12, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)) }
                }
                Text(detail.label).font(Font.pl(.body)).foregroundStyle(PLOS.text(scheme)).textSelection(.enabled)
                Text(detail.stateDetail).font(Font.pl(.subheadline)).foregroundStyle(PLOS.dim(scheme))
                CaptureFlow(detail: detail)   // the flow of this intake, as a diagram
                if !detail.meta.isEmpty { Text(detail.meta).osEyebrow(10).foregroundStyle(PLOS.dim(scheme)) }
                HStack(spacing: 8) {
                    Button { UIPasteboard.general.string = detail.payload } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(OSPill())
                    if let u = captureTrailLink(detail.payload) {
                        Link(destination: u) { Label("Open", systemImage: "arrow.up.right").osEyebrow(11).foregroundStyle(PLOS.goldDim(scheme)).padding(.horizontal, 16).frame(minHeight: 44).frame(maxWidth: .infinity).glassEffect(.clear.interactive(), in: Capsule()).overlay { Capsule().strokeBorder(PLOS.line(scheme), lineWidth: 0.8) } }
                    }
                    ShareLink(item: detail.label) { Label("Share", systemImage: "square.and.arrow.up").osEyebrow(11).foregroundStyle(PLOS.goldDim(scheme)).padding(.horizontal, 16).frame(minHeight: 44).frame(maxWidth: .infinity).glassEffect(.clear.interactive(), in: Capsule()).overlay { Capsule().strokeBorder(PLOS.line(scheme), lineWidth: 0.8) } }
                }
                CaptureRender(detail: detail)   // the capture itself: its picture and what it says
            }
            .padding(18)
        }
    }
}
