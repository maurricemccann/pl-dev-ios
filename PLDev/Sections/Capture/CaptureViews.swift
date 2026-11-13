import PhotosUI
import SwiftUI
import TipKit
import UIKit

/// Capture, as pl-os shows it: the header and clock, the three rooms (Add is Intake itself, Where it went is the trail,
/// Waiting is what waits on him), all on the console ground with gold as the one accent.
struct CaptureView: View {
    let model: AppModel
    @Bindable var state: CaptureModel

    var body: some View {
        List {
            OSHeader().captureRow()
            CaptureRoomBar(room: $state.room, badges: [.trail: state.deck.count, .waiting: model.inboxCount]).captureRow()
            switch state.room {
            case .add:
                CaptureAddCard(model: model, state: state).captureRow()
                CaptureTrailCard(state: state).captureRow()
            case .trail:
                CaptureTrailRoom(model: model, state: state)
            case .waiting:
                CaptureWaitingRoom(model: model, state: state)
            }
        }
        .listStyle(.plain)
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

// MARK: - Add: pl-os Intake

enum DictateTarget: Sendable { case body, words }

struct CaptureAddCard: View {
    let model: AppModel
    @Bindable var state: CaptureModel
    @Environment(\.colorScheme) private var scheme
    @State private var choosing = false
    @State private var item: PhotosPickerItem?
    @State private var shooting = false
    @State private var dictating = false
    @State private var dictation = CaptureDictation()
    @State private var dictationNote: String?

    var body: some View {
        VStack(spacing: 0) {
            modeRow
            Rectangle().fill(PLOS.line(scheme)).frame(height: 0.8)
            VStack(alignment: .leading, spacing: 14) {
                if state.done { doneView } else { form }
            }
            .padding(18)
        }
        .osCard(padding: 0)
        .photosPicker(isPresented: $choosing, selection: $item, matching: .images)
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task { state.setPhoto(try? await picked.loadTransferable(type: Data.self)); item = nil }
        }
        .fullScreenCover(isPresented: $shooting) { CaptureCamera { state.setPhoto($0) }.ignoresSafeArea() }
        .onChange(of: state.kind) { _, _ in stopDictation() }
        .onDisappear { stopDictation() }
    }

    // MARK: the four modes

    private var modeRow: some View {
        HStack(spacing: 0) {
            ForEach(CaptureKind.allCases) { k in
                let on = state.kind == k
                Button { hideKeyboard(); withAnimation(.snappy) { state.switchKind(k) } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: k.symbol).font(.system(size: 16, weight: .regular))
                        Text(k.title).font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(on ? PLOS.gold : PLOS.text(scheme))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(on ? Color.white.opacity(scheme == .dark ? 0.1 : 0.3) : Color.clear)
                    .overlay(alignment: .bottom) { if on { Rectangle().fill(PLOS.gold).frame(height: 2) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(k.title), \(k.sub)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    // MARK: the form

    @ViewBuilder private var form: some View {
        switch state.kind {
        case .artwork: artwork
        case .text: text
        case .quote: quote
        case .link: link
        }
        if state.kind != .artwork, model.config?.origin("board") != nil {
            Toggle(isOn: $state.toBoard) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send to the board instead").font(.subheadline).foregroundStyle(PLOS.text(scheme))
                    Text("Goes to the board's inbox for Claude, not the intake.").font(.caption).foregroundStyle(PLOS.dim(scheme))
                }
            }
            .tint(PLOS.gold)
        }
        if let m = state.message {
            Label(m, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(PLOS.danger)
        }
        Button { hideKeyboard(); Task { await state.submit(model: model) } } label: {
            Text(state.busy ? "Adding…" : "Add to the system →")
        }
        .buttonStyle(CaptureGoldButton())
        .disabled(!state.canSubmit)
        Text(state.toBoard && state.kind != .artwork ? "Goes to the board's inbox for Claude." :
                "Goes to the intake, where your moderation deck shows it. Nothing is posted anywhere.")
            .font(.caption).foregroundStyle(PLOS.dim(scheme))
    }

    private var artwork: some View {
        VStack(alignment: .leading, spacing: 14) {
            Menu {
                Button { choosing = true } label: { Label("Choose from Photos", systemImage: "photo.on.rectangle") }
                if CaptureCamera.available { Button { shooting = true } label: { Label("Take a photo", systemImage: "camera") } }
                if state.photo != nil { Button(role: .destructive) { state.photo = nil; state.photoNote = nil } label: { Label("Remove it", systemImage: "trash") } }
            } label: { dropZone }
            .accessibilityLabel(state.photo == nil ? "Choose image or shoot" : "Photo added. Change it")
            HStack(alignment: .top, spacing: 12) {
                CaptureField(label: "Title") { TextField("", text: $state.title, prompt: Text("Untitled").foregroundStyle(PLOS.dim(scheme))).captureInput() }
                CaptureField(label: "Year") {
                    TextField("", text: $state.year, prompt: Text("2026").foregroundStyle(PLOS.dim(scheme))).keyboardType(.numberPad).captureInput()
                }
                .frame(maxWidth: 110)
            }
            CaptureField(label: "Medium") {
                TextField("", text: $state.medium, prompt: Text("Oil · fabric · digital").foregroundStyle(PLOS.dim(scheme))).captureInput()
            }
            CaptureField(label: "Notes (optional)") {
                TextField("", text: $state.notes, prompt: Text("Context, series, pricing…").foregroundStyle(PLOS.dim(scheme)), axis: .vertical)
                    .lineLimit(2...5).captureInput()
            }
        }
    }

    /// The dashed well: "Choose image or shoot", gold once a picture is in it.
    private var dropZone: some View {
        VStack(spacing: 6) {
            if let data = state.photo, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("Photo added · \(state.photoNote ?? "") · tap to change").font(.caption).foregroundStyle(PLOS.gold)
            } else {
                Image(systemName: "photo.badge.plus").font(.system(size: 26)).foregroundStyle(PLOS.goldDim(scheme))
                Text(CaptureCamera.available ? "Choose image or shoot" : "Choose image").font(.body).foregroundStyle(PLOS.text(scheme))
                Text("jpg · png · heic").osEyebrow(10).foregroundStyle(PLOS.dim(scheme))
            }
        }
        .frame(maxWidth: .infinity).padding(state.photo == nil ? 28 : 12)
        .background((state.photo == nil ? Color.clear : PLOS.gold.opacity(0.08)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(state.photo == nil ? PLOS.line(scheme) : PLOS.gold.opacity(0.5), style: StrokeStyle(lineWidth: 1.4, dash: state.photo == nil ? [6, 5] : []))
        }
    }

    private var text: some View {
        CaptureField(label: "Body") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("", text: $state.body, prompt: Text("Write or paste. Essays, reflections, process notes, plans.").foregroundStyle(PLOS.dim(scheme)), axis: .vertical)
                    .lineLimit(7...16).captureInput()
                dictateRow(into: .body)
            }
        }
    }

    private var quote: some View {
        VStack(alignment: .leading, spacing: 14) {
            CaptureField(label: "The words") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("", text: $state.words, prompt: Text("The phrase that stops you cold.").foregroundStyle(PLOS.dim(scheme)), axis: .vertical)
                        .font(.system(.title3, design: .serif).italic()).lineLimit(4...10).captureInput()
                    dictateRow(into: .words)
                }
            }
            CaptureField(label: "Attribution (optional)") {
                TextField("", text: $state.attribution, prompt: Text("Author or source").foregroundStyle(PLOS.dim(scheme))).captureInput()
            }
        }
    }

    private var link: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("", text: $state.linkURL, prompt: Text("https://").foregroundStyle(PLOS.dim(scheme)))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.go).onSubmit { Task { await state.pullLink() } }
                    .onChange(of: state.linkURL) { _, _ in state.preview = nil }
                    .captureInput()
                Button { hideKeyboard(); Task { await state.pullLink() } } label: {
                    Group { if state.fetching { ProgressView().tint(PLOS.gold) } else { Text("Pull it") } }
                        .osEyebrow(11).foregroundStyle(PLOS.goldDim(scheme)).frame(minWidth: 64, minHeight: 44)
                        .padding(.horizontal, 6)
                        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(PLOS.line(scheme), lineWidth: 0.8) }
                }
                .buttonStyle(.plain)
                .disabled(state.linkURL.trimmingCharacters(in: .whitespaces).isEmpty || state.fetching)
            }
            PasteButton(payloadType: String.self) { strings in
                guard let first = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty else { return }
                Task { @MainActor in
                    state.linkURL = first
                    if first.hasPrefix("http") { await state.pullLink() }
                }
            }
            .buttonBorderShape(.capsule).tint(PLOS.gold).labelStyle(.titleAndIcon)
            if let p = state.preview {
                VStack(alignment: .leading, spacing: 8) {
                    if let u = URL(string: p.image), !p.image.isEmpty {
                        AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
                            .frame(maxWidth: .infinity, maxHeight: 128).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)).opacity(0.85)
                    }
                    Text(p.title).font(.body).foregroundStyle(PLOS.text(scheme))
                    if !p.description.isEmpty { Text(String(p.description.prefix(200))).font(.subheadline).foregroundStyle(PLOS.dim(scheme)) }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(scheme == .dark ? 0.05 : 0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(PLOS.gold.opacity(0.3), lineWidth: 0.8) }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: the voice

    @ViewBuilder private func dictateRow(into field: DictateTarget) -> some View {
        if CaptureDictation.available {
            HStack(spacing: 8) {
                Button { dictating ? stopDictation() : startDictation(into: field) } label: {
                    Label(dictating ? "Stop" : "Speak it", systemImage: dictating ? "stop.circle.fill" : "mic")
                        .osEyebrow(11).foregroundStyle(dictating ? PLOS.danger : PLOS.goldDim(scheme))
                        .padding(.horizontal, 14).frame(minHeight: 40)
                        .glassEffect(.clear.interactive(), in: Capsule())
                        .overlay { Capsule().strokeBorder(PLOS.line(scheme), lineWidth: 0.8) }
                }
                .buttonStyle(.plain)
                .symbolEffect(.pulse, isActive: dictating)
                if let n = dictationNote { Text(n).font(.caption).foregroundStyle(PLOS.dim(scheme)) }
            }
        }
    }

    private func startDictation(into field: DictateTarget) {
        hideKeyboard()
        let base = (field == .body ? state.body : state.words).trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = base.isEmpty ? "" : base + " "
        let st = state
        dictationNote = nil; dictating = true
        let d = dictation
        Task {
            let problem = await d.start(
                onText: { heard in Task { @MainActor in if field == .body { st.body = prefix + heard } else { st.words = prefix + heard } } },
                onEnd: { Task { @MainActor in dictating = false } })
            if let problem { dictating = false; dictationNote = problem }
        }
    }

    private func stopDictation() {
        dictation.stop()
        dictating = false
    }

    // MARK: after it is added

    private var doneView: some View {
        VStack(spacing: 10) {
            Image(systemName: state.doneOffline ? "icloud.and.arrow.up" : "checkmark.seal").font(.system(size: 30)).foregroundStyle(PLOS.gold)
                .symbolEffect(.bounce, value: state.sentTick)
            Text(state.doneOffline ? "Saved on this phone." : "Added to the system.")
                .font(.system(.title2, design: .serif).italic()).foregroundStyle(PLOS.gold)
            VStack(spacing: 4) {
                if state.doneOffline {
                    Text("It goes in the next time the house answers.")
                } else {
                    Text("Notion inbox · your moderation deck")
                    Text("Links → research pool at 05:30 · 11:30 · 17:30 · 22:30")
                }
            }
            .font(.subheadline).foregroundStyle(PLOS.dim(scheme)).multilineTextAlignment(.center)
            Button { withAnimation(.snappy) { state.resetForm() } } label: { Text("Add another") }
                .buttonStyle(OSPill()).padding(.top, 8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
    }
}

// MARK: - Where it went (under Intake, as on the web)

struct CaptureTrailCard: View {
    @Bindable var state: CaptureModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ghosts = state.ghosts
        let rows = Array(state.trail.prefix(4))
        if state.trailLoaded, rows.isEmpty, ghosts.isEmpty, state.trailNote == nil {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Where it went").osEyebrow(10).foregroundStyle(PLOS.dim(scheme))
                    Spacer()
                    Text("Link sweeps \(CaptureSweeps.text)").font(.system(size: 10, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                ForEach(ghosts) { g in
                    Rectangle().fill(PLOS.line(scheme)).frame(height: 0.5)
                    CaptureTrailLine(label: g.label, badge: g.sent ? "Saving…" : "To send", saving: true, tone: .plain,
                                     detail: g.sent ? "On its way to the intake." : "On this phone. It goes in when the house answers.", ago: nil, thumb: g.thumb, image: nil)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                }
                ForEach(rows) { r in
                    Rectangle().fill(PLOS.line(scheme)).frame(height: 0.5)
                    Button { state.detail = detailOf(r) } label: {
                        CaptureTrailLine(label: r.label, badge: r.state.label, saving: false, tone: r.state.tone,
                                         detail: r.state.detail + (r.source.map { " · \($0)" } ?? ""), ago: r.created_at, thumb: nil, image: captureTrailImage(r.payload))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                if let n = state.trailNote {
                    Text(n).font(.footnote).foregroundStyle(PLOS.dim(scheme)).padding(16)
                }
                if state.trail.count > rows.count {
                    Rectangle().fill(PLOS.line(scheme)).frame(height: 0.5)
                    Button { withAnimation(.snappy) { state.room = .trail } } label: {
                        Text("See all \(state.trail.count)").osEyebrow(11).foregroundStyle(PLOS.goldDim(scheme)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .osCard(padding: 0)
        }
    }
}

enum CaptureSweeps { static let text = "05:30 · 11:30 · 17:30 · 22:30" }

func detailOf(_ r: CaptureModel.TrailRow) -> CaptureModel.TrailDetail {
    CaptureModel.TrailDetail(id: r.id, label: r.label, payload: r.payload ?? "", stateLabel: r.state.label, stateDetail: r.state.detail, tone: r.state.tone,
                             meta: [r.type, r.source].compactMap { $0 }.joined(separator: " · "), created: r.created_at)
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
                Text(label).font(.subheadline).foregroundStyle(PLOS.text(scheme)).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(detail).lineLimit(2)
                    if let ago { Text("·"); Ago(text: ago) }
                }
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(PLOS.dim(scheme))
            }
            Spacer(minLength: 0)
            if let thumb, let ui = UIImage(data: thumb) {
                Image(uiImage: ui).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if let image {
                AsyncImage(url: image) { i in i.resizable().scaledToFill() } placeholder: { PLOS.surface2(scheme) }
                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            Text("Link sweeps \(CaptureSweeps.text)").font(.system(size: 10, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .captureRow()
        if let n = state.trailNote { ResultLine(text: n).captureRow() }

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
            ProgressView().frame(maxWidth: .infinity, minHeight: 80).captureRow()
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
               status: statusLine)
            .captureRow()

        OSPanel(title: "To send from this phone", badge: "\(model.inboxCount)", owed: model.inboxCount > 0, startOpen: true) {
            Text(model.inboxCount == 0 ? "Nothing is waiting on this phone. Everything you captured has gone in." :
                    "\(model.inboxCount) \(model.inboxCount == 1 ? "capture is" : "captures are") on this phone, not sent yet. They go in by themselves when the house answers.")
                .font(.subheadline).foregroundStyle(PLOS.dim(scheme))
            if let used = state.usedToday, let cap = state.cap {
                Text("\(used) of \(cap) sent today through the phone door.").font(.system(size: 12, design: .monospaced)).foregroundStyle(PLOS.dim(scheme))
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
            line("Pins", w?.pins, "Each Pin waits for your tap", house: "approvals")
            line("Manual posts", w?.manual, "Copy ready, to post by hand", house: "approvals")
            line("Ads", w?.ads, "To approve", house: "approvals")
            line("Emails", w?.emails, "Drafts in Tempo", house: "tempo")
            line("Tasks", w?.tasks, "Open on the founder's list", house: "")
            line("New captures", w?.captures, "In your moderation deck", house: nil)
            line("Shift items open", w?.shift_open, "On today's shift", house: "")
        }
        .captureRow()

        OSPanel(title: "Where captures go") {
            Text("Text, quotes and artwork go to the Notion inbox and your moderation deck.").font(.subheadline).foregroundStyle(PLOS.text(scheme))
            Text("Links go to the research pool at \(CaptureSweeps.text).").font(.subheadline).foregroundStyle(PLOS.text(scheme))
            Text("Nothing is posted anywhere from here.").font(.subheadline).foregroundStyle(PLOS.dim(scheme))
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
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(PLOS.goldDim(scheme))
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
                    if let c = detail.created { Ago(text: c).font(.system(size: 12, design: .monospaced)).foregroundStyle(PLOS.dim(scheme)) }
                }
                if let img = captureTrailImage(detail.payload) {
                    AsyncImage(url: img) { i in i.resizable().scaledToFit() } placeholder: { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
                        .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text(detail.label).font(.body).foregroundStyle(PLOS.text(scheme)).textSelection(.enabled)
                Text(detail.stateDetail).font(.subheadline).foregroundStyle(PLOS.dim(scheme))
                if !detail.meta.isEmpty { Text(detail.meta).osEyebrow(10).foregroundStyle(PLOS.dim(scheme)) }
                HStack(spacing: 8) {
                    Button { UIPasteboard.general.string = detail.payload } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(OSPill())
                    if let u = captureTrailLink(detail.payload) {
                        Link(destination: u) { Label("Open", systemImage: "arrow.up.right").osEyebrow(11).foregroundStyle(PLOS.goldDim(scheme)).padding(.horizontal, 16).frame(minHeight: 44).frame(maxWidth: .infinity).glassEffect(.clear.interactive(), in: Capsule()).overlay { Capsule().strokeBorder(PLOS.line(scheme), lineWidth: 0.8) } }
                    }
                    ShareLink(item: detail.label) { Label("Share", systemImage: "square.and.arrow.up").osEyebrow(11).foregroundStyle(PLOS.goldDim(scheme)).padding(.horizontal, 16).frame(minHeight: 44).frame(maxWidth: .infinity).glassEffect(.clear.interactive(), in: Capsule()).overlay { Capsule().strokeBorder(PLOS.line(scheme), lineWidth: 0.8) } }
                }
            }
            .padding(18)
        }
    }
}
