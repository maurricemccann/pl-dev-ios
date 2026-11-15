import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// The smart drop box (Plans/SPEC — PL DEV SMART CAPTURE (S348), his layout 11-14, Apple's Image Playground as the reference):
// one box that takes text, markdown, a link, a photo; a sheet asks where it goes; the Trail shows each item's flow.

/// What was dropped, waiting for the "where does it go" answer.
struct DropPending: Identifiable {
    let id = UUID()
    let kind: String        // "text" | "url" | "image"
    let text: String
    let url: String?
    let photo: Data?
    var preferred: CaptureRoute? = nil   // the "Where" pill: a destination he picked before sending (nil = Auto)

    var options: [CaptureRoute] { SmartCapture.available(kind: kind, url: url) }
    var suggested: CaptureRoute {
        if let preferred, options.contains(preferred) { return preferred }
        return SmartCapture.suggest(kind: kind, text: text, url: url)
    }
}

struct CaptureDropBox: View {
    let model: AppModel
    @Bindable var state: CaptureModel
    @Environment(\.colorScheme) private var scheme
    @State private var text = ""
    @State private var photo: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var importing = false
    @State private var pending: DropPending?
    @State private var hintIndex = 0
    @State private var shooting = false
    @State private var whereRoute: CaptureRoute?
    @FocusState private var focused: Bool

    private let hints = [
        "Drop a photo of new art",
        "Paste a link",
        "Type a quote, then who said it",
        "Write a seed line",
        "Paste markdown or add a file",
        "Paste a backend site to make a tile",
    ]
    private let tick = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { photo != nil || !trimmed.isEmpty }

    /// The hint follows what is in the box, as Image Playground's does (rules first; the on-device model comes later): a photo asks for its
    /// name and date, a link asks who it is from, a line asks who said it.
    private var hint: String {
        if photo != nil { return ["Name this piece", "When did you make it?", "Add a line about it, then send"][hintIndex % 3] }
        if trimmed.isEmpty { return hints[hintIndex % hints.count] }
        let u = URL(string: trimmed)
        if (u?.scheme == "http" || u?.scheme == "https"), !trimmed.contains(where: { $0.isWhitespace }) {
            return ["Who is it from?", "Add why it matters", "Send it, or make it a tile"][hintIndex % 3]
        }
        return ["Add who said it", "Make it a seed", "Send it to the board"][hintIndex % 3]
    }

    private var whereMenu: some View {
        Menu {
            Button("Auto", systemImage: "wand.and.stars") { whereRoute = nil }
            ForEach(CaptureRoute.allCases) { r in Button(r.title, systemImage: r.symbol) { whereRoute = r } }
        } label: {
            HStack(spacing: 4) {
                Text(whereRoute.map { "Where: " + $0.title } ?? "Where: Auto")
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.footnote.weight(.medium)).foregroundStyle(PLOS.text(scheme))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(PLOS.surface2(scheme).opacity(0.8), in: Capsule())
        }
        .accessibilityLabel("Where it goes")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Spacer(minLength: 0); whereMenu }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(6)
                if text.isEmpty {
                    Text(hint)
                        .foregroundStyle(PLOS.dim(scheme).opacity(0.7))
                        .padding(.horizontal, 12).padding(.vertical, 14)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            if !text.isEmpty {
                Label(hint, systemImage: "sparkles").font(.footnote).foregroundStyle(PLOS.dim(scheme))
            }
            if let photo, let img = UIImage(data: photo) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button { self.photo = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .padding(6)
                    .accessibilityLabel("Remove the photo")
                }
            }
            HStack(spacing: 10) {
                Menu {
                    if CaptureCamera.available { Button("Take Photo", systemImage: "camera") { shooting = true } }
                    PhotosPicker(selection: $pickerItem, matching: .images) { Label("Choose Photo", systemImage: "photo") }
                } label: { Label("Photo", systemImage: "photo") }
                .buttonStyle(OSPill())
                Button { importing = true } label: { Label("File", systemImage: "doc.text") }.buttonStyle(OSPill())
                Button { if let s = UIPasteboard.general.string { text = s } } label: { Label("Paste", systemImage: "doc.on.clipboard") }.buttonStyle(OSPill())
                Spacer(minLength: 0)
                Button { send() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 44, height: 44).background(PLOS.gold, in: Circle())
                }
                .disabled(!canSend).opacity(canSend ? 1 : 0.35)
                .accessibilityLabel("Send")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(PLOS.surface2(scheme).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(PLOS.line(scheme), lineWidth: 0.8))
        .onReceive(tick) { _ in withAnimation { hintIndex = (hintIndex + 1) % 60 } }
        .fullScreenCover(isPresented: $shooting) { CaptureCamera { photo = $0 }.ignoresSafeArea() }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let item, let data = try? await item.loadTransferable(type: Data.self) { photo = data }
                pickerItem = nil
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let s = try? String(contentsOf: url, encoding: .utf8) { text = s }
        }
        .sheet(item: $pending) { p in
            CaptureWhereSheet(pending: p, state: state, model: model) { sent in
                if sent { text = ""; photo = nil; state.room = .trail }
            }
        }
    }

    private func send() {
        focused = false
        let t = trimmed
        if let photo { pending = DropPending(kind: "image", text: t, url: nil, photo: photo, preferred: whereRoute); return }
        let u = URL(string: t)
        let isLink = !t.contains(where: { $0.isWhitespace }) && (u?.scheme == "http" || u?.scheme == "https") && u?.host != nil
        pending = DropPending(kind: isLink ? "url" : "text", text: t, url: isLink ? t : nil, photo: nil, preferred: whereRoute)
    }
}

/// The sheet that asks where it goes: the likely answer is already selected, one tap changes it.
struct CaptureWhereSheet: View {
    let pending: DropPending
    @Bindable var state: CaptureModel
    let model: AppModel
    let done: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var route: CaptureRoute
    @State private var extra = ""
    @State private var working = false

    init(pending: DropPending, state: CaptureModel, model: AppModel, done: @escaping (Bool) -> Void) {
        self.pending = pending
        self.state = state
        self.model = model
        self.done = done
        _route = State(initialValue: pending.suggested)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(pending.options) { r in
                        Button { route = r } label: {
                            HStack(spacing: 12) {
                                Image(systemName: r.symbol).frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title).font(.body.weight(.medium))
                                    Text(Self.line(r)).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if r == pending.suggested { Text("Suggested").font(.caption2).foregroundStyle(.secondary) }
                                if r == route { Image(systemName: "checkmark.circle.fill").foregroundStyle(PLOS.gold) }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(r == route ? .isSelected : [])
                    }
                } header: { Text("Where does it go?") }
                if route == .art {
                    Section("Name this piece") { TextField("Optional, your words", text: $extra) }
                } else if route == .quote {
                    Section("Who said it?") { TextField("Optional", text: $extra) }
                }
                if let m = state.message { Section { Text(m).foregroundStyle(.red) } }
            }
            .navigationTitle("Where does it go?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(working ? "Sending" : "Send") {
                        working = true
                        Task {
                            await state.dropSend(route: route, pending: pending, extra: extra, model: model)
                            working = false
                            let ok = state.message == nil
                            done(ok)
                            if ok { dismiss() }
                        }
                    }
                    .disabled(working)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    static func line(_ r: CaptureRoute) -> String {
        switch r {
        case .board: return "The board's inbox, for Claude"
        case .quote: return "The intake, as a quote"
        case .seed: return "The board's inbox, tagged SEED"
        case .art: return "The art inbox: name, PL number, your verdict"
        case .tile: return "A new tile on the Backend page"
        }
    }
}

extension CaptureModel {
    /// Sends what was dropped by the route he picked, through the same inbox and drain as every other capture.
    func dropSend(route: CaptureRoute, pending p: DropPending, extra: String, model: AppModel) async {
        message = nil
        let more = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        let board = model.config?.origin("board") != nil
        switch route {
        case .art:
            guard let photo = p.photo else { message = "Art needs a photo."; return }
            _ = await enqueue(kind: "image", text: nil, note: more.isEmpty ? "Untitled piece" : more, file: photo, label: more.isEmpty ? "Artwork" : more,
                              toBoard: false, route: route.rawValue, model: model)
        case .quote:
            let full = more.isEmpty ? p.text : p.text + "\n— " + more
            _ = await enqueue(kind: "quote", text: full, note: nil, file: nil, label: String(p.text.prefix(120)), toBoard: false, route: route.rawValue, model: model)
        case .seed:
            _ = await enqueue(kind: "text", text: SmartCapture.seedText(p.text), note: nil, file: nil, label: String(p.text.prefix(120)),
                              toBoard: board, route: route.rawValue, model: model)
        case .board:
            _ = await enqueue(kind: p.kind == "url" ? "url" : "text", text: p.text, note: nil, file: nil, label: String(p.text.prefix(120)),
                              toBoard: board, route: route.rawValue, model: model)
        case .tile:
            guard let t = BackendTemplates.template(for: p.url ?? p.text, title: nil) else { message = "That is not an https address."; return }
            let line = BackendStore.shared.add(t)
            addLog(CaptureLogEntry(id: UUID().uuidString, kind: "tile", label: line, at: Date(), sent: true, toBoard: false, thumb: nil, route: route.rawValue))
        }
        sentTick += 1
    }
}

/// The flow of one intake, drawn as a vertical diagram: what the phone and the house know, then what follows for that kind.
struct CaptureFlow: View {
    let detail: CaptureModel.TrailDetail
    @Environment(\.colorScheme) private var scheme

    private var kind: String { detail.meta.components(separatedBy: " · ").first?.lowercased() ?? "" }

    private var steps: [(symbol: String, title: String, line: String, done: Bool)] {
        var s: [(String, String, String, Bool)] = [
            ("tray.and.arrow.down", "Captured", detail.created.map { "At \($0)" } ?? "On this phone", true),
            ("paperplane", detail.stateLabel == "Waiting" ? "Waiting" : "Landed", detail.stateLabel + ". " + detail.stateDetail, true),
        ]
        switch kind {
        case "art":
            s += [("photo.on.rectangle", "Art inbox", "Waiting for \"intake it\": a session scans for duplicates, names it, stamps the PL number", false),
                  ("hand.thumbsup", "Your verdict", "KEEP or CUT in the /curate archive deck", false),
                  ("globe", "Published", "On the site and available to generations", false)]
        case "quote":
            s += [("tray.full", "Moderation deck", "Your keep or reject", false), ("quote.opening", "Quotes", "Kept quotes join the house's quotes", false)]
        case "link", "url", "text":
            s += [("tray.and.arrow.up", "Board or deck", "Read by a session, then filed or answered", false)]
        default:
            s += [("tray.full", "Intake", "The house takes it from here", false)]
        }
        return s.map { (symbol: $0.0, title: $0.1, line: $0.2, done: $0.3) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Image(systemName: step.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(step.done ? Color.black : PLOS.dim(scheme))
                            .frame(width: 30, height: 30)
                            .background(step.done ? PLOS.gold : PLOS.surface2(scheme).opacity(0.6), in: Circle())
                        if i < steps.count - 1 {
                            Rectangle().fill(PLOS.line(scheme)).frame(width: 1.5).frame(maxHeight: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).font(.subheadline.weight(.semibold)).foregroundStyle(step.done ? PLOS.text(scheme) : PLOS.dim(scheme))
                        Text(step.line).font(.footnote).foregroundStyle(PLOS.dim(scheme)).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 14)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Flow of this intake")
    }
}
