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
    var fromCamera = false               // a camera capture of a physical piece: the sheet asks its medium
    var name: String? = nil              // the on-device model's suggested title
    var medium: String? = nil            // the on-device model's suggested medium

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
    @State private var picking = false
    @State private var pickingVideo = false
    @State private var videoItem: PhotosPickerItem?
    @State private var whereRoute: CaptureRoute?
    @State private var fromCamera = false
    @State private var original: Data?        // the camera capture as taken
    @State private var straight: Data?        // the same, corners found and pulled square (nil = none found)
    @State private var read: PLIntelligence.CaptureRead?
    @State private var quality: String?
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
        if let ask = read?.ask { return ask }   // the on-device model's question about what is in the box
        if photo != nil { return ["Name this piece", "When did you make it?", "Add a line about it, then send"][hintIndex % 3] }
        if trimmed.isEmpty { return hints[hintIndex % hints.count] }
        let u = URL(string: trimmed)
        if (u?.scheme == "http" || u?.scheme == "https"), !trimmed.contains(where: { $0.isWhitespace }) {
            return ["Who is it from?", "Add why it matters", "Send it, or make it a tile"][hintIndex % 3]
        }
        return ["Add who said it", "Make it a seed", "Send it to the board"][hintIndex % 3]
    }

    private func iconCircle(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 17, weight: .medium)).foregroundStyle(PLOS.text(scheme))
            .frame(width: 44, height: 44).background(PLOS.surface2(scheme).opacity(0.8), in: Circle())
    }

    private var whereMenu: some View {
        Menu {
            Button("Auto", systemImage: "wand.and.stars") { whereRoute = nil }
            ForEach(CaptureRoute.allCases.filter { !$0.isVault }) { r in Button(r.title, systemImage: r.symbol) { whereRoute = r } }
            Section("Notes in your vault") {
                ForEach(CaptureRoute.allCases.filter(\.isVault)) { r in
                    Button("\(r.title) · \(r.vaultNote?.file ?? "")", systemImage: r.symbol) { whereRoute = r }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(whereRoute.map { "Where: " + $0.title } ?? "Where: Auto")
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.footnote.weight(.medium)).foregroundStyle(whereRoute?.isVault == true ? PLOS.vault : PLOS.text(scheme))   // a vault note reads violet
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(PLOS.surface2(scheme).opacity(0.8), in: Capsule())
            .overlay(Capsule().stroke(PLOS.vault.opacity(whereRoute?.isVault == true ? 0.7 : 0), lineWidth: 1))
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
            if photo != nil, let quality {
                Label(quality, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(PLOS.warn)
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
                    Button("Choose Photo", systemImage: "photo") { picking = true }   // a PhotosPicker inside a Menu never opens; the screen presents it
                    Button("Choose Video", systemImage: "video") { pickingVideo = true }
                } label: { iconCircle("photo") }
                .accessibilityLabel("Photo")
                if straight != nil, let original {
                    Button { photo = (photo == straight) ? original : straight } label: { iconCircle(photo == straight ? "crop" : "crop.rotate") }
                        .accessibilityLabel(photo == straight ? "Use the photo as taken" : "Crop and straighten")
                }
                Button { importing = true } label: { iconCircle("doc.text") }.accessibilityLabel("Add a file")
                Button { if let s = UIPasteboard.general.string { text = s } } label: { iconCircle("doc.on.clipboard") }.accessibilityLabel("Paste")
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
        .onAppear { PLIntelligence.warm() }
        .fullScreenCover(isPresented: $shooting) {
            CaptureCamera { shot in
                fromCamera = true
                original = shot
                photo = shot
                straight = nil
                Task {
                    let flat = await Task.detached(priority: .userInitiated) { CaptureMeta.straightened(shot) }.value
                    if original == shot { straight = flat; if let flat { photo = flat } }   // straightened by default; one tap goes back
                }
            }
            .ignoresSafeArea()
        }
        .task(id: String(trimmed.prefix(200)) + "|" + String(photo?.count ?? 0)) {
            // the on-device model reads what is in the box, after he stops typing; nothing leaves the phone
            read = nil
            quality = nil
            if let photo { quality = await CaptureMeta.qualityNote(photo) }
            guard photo != nil || trimmed.count >= 8 else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            let got = await PLIntelligence.captureRead(text: trimmed, image: photo)
            if !Task.isCancelled { read = got }
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let item, let data = try? await item.loadTransferable(type: Data.self) {
                    photo = data; fromCamera = false; original = data; straight = nil
                    // 11-18 smart capture: a library photo is straightened by default too; the crop button goes back to the original
                    let flat = await Task.detached(priority: .userInitiated) { CaptureMeta.straightened(data) }.value
                    if original == data { straight = flat; if let flat { photo = flat } }
                }
                pickerItem = nil
            }
        }
        .photosPicker(isPresented: $picking, selection: $pickerItem, matching: .images)
        .photosPicker(isPresented: $pickingVideo, selection: $videoItem, matching: .videos)
        .onChange(of: videoItem) { _, item in
            Task {
                defer { videoItem = nil }
                guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                guard data.count <= 100 * 1024 * 1024 else { state.message = "That video is over 100 MB. Trim it, then try again."; return }
                let name = trimmed.isEmpty ? "Video" : String(trimmed.prefix(120))
                if await state.enqueue(kind: "video", text: nil, note: name, file: data, label: name, toBoard: false, route: "video", model: model) {
                    text = ""; state.room = .trail
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let s = try? String(contentsOf: url, encoding: .utf8) { text = s }
        }
        .onChange(of: state.presetRoute) { _, r in
            guard let r else { return }
            whereRoute = r; focused = true; state.presetRoute = nil
        }
        .sheet(item: $pending) { p in
            CaptureWhereSheet(pending: p, state: state, model: model) { sent in
                if sent { text = ""; photo = nil; original = nil; straight = nil; fromCamera = false; read = nil; state.room = .trail }
            }
        }
    }

    private func send() {
        focused = false
        let t = trimmed
        let modelRoute = read?.route.flatMap { CaptureRoute(rawValue: $0) }
        if let photo {
            pending = DropPending(kind: "image", text: t, url: nil, photo: photo, preferred: whereRoute ?? modelRoute,
                                  fromCamera: fromCamera, name: read?.name, medium: read?.medium)
            return
        }
        let u = URL(string: t)
        let isLink = !t.contains(where: { $0.isWhitespace }) && (u?.scheme == "http" || u?.scheme == "https") && u?.host != nil
        pending = DropPending(kind: isLink ? "url" : "text", text: t, url: isLink ? t : nil, photo: nil, preferred: whereRoute ?? modelRoute)
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
    @State private var medium = ""
    @State private var working = false

    init(pending: DropPending, state: CaptureModel, model: AppModel, done: @escaping (Bool) -> Void) {
        self.pending = pending
        self.state = state
        self.model = model
        self.done = done
        _route = State(initialValue: pending.suggested)
        _extra = State(initialValue: pending.kind == "image" ? (pending.text.isEmpty ? (pending.name ?? "") : pending.text) : "")
        _medium = State(initialValue: pending.medium ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(pending.options) { r in
                        Button { route = r } label: {
                            HStack(spacing: 12) {
                                Image(systemName: r.symbol).frame(width: 26).foregroundStyle(r.isVault ? PLOS.vault : Color.primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title).font(.body.weight(.medium))
                                    Text(Self.line(r)).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if r == pending.suggested { Text("Suggested").font(.caption2).foregroundStyle(.secondary) }
                                if r == route { Image(systemName: "checkmark.circle.fill").foregroundStyle(r.isVault ? PLOS.vault : PLOS.gold) }   // an Obsidian note is violet, everything else gold
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(r == route ? .isSelected : [])
                    }
                } header: { Text("Where does it go?") }
                if let note = route.vaultNote {
                    Section {
                        NavigationLink { NoteLiveView(note: note, model: model) } label: {
                            Label("See the end of \(note.file)", systemImage: "doc.text.magnifyingglass").foregroundStyle(PLOS.vault)
                        }
                    } footer: { Text("Read only, as the house last synced it.") }
                }
                if route == .art {
                    Section {
                        TextField("Optional, your words", text: $extra)
                    } header: { Text("Name this piece") } footer: {
                        Text("The year and your signature are added to the photo for you.")
                    }
                    if pending.fromCamera {
                        Section("Medium") { TextField("Oil pastel on paper", text: $medium) }
                    }
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
                            await state.dropSend(route: route, pending: pending, extra: extra, medium: pending.fromCamera ? medium : "", model: model)
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
        case .thought: return "THOUGHTS.md, raw, for every session to read"
        case .task: return "THOUGHTS.md as a task: the next session's queue"
        case .today: return "TODAY.md, a line on the board's task list"
        case .claude: return "for-claude.md, the inbox every session drains first"
        }
    }
}

extension CaptureModel {
    /// Sends what was dropped by the route he picked, through the same inbox and drain as every other capture.
    func dropSend(route: CaptureRoute, pending p: DropPending, extra: String, medium: String = "", model: AppModel) async {
        message = nil
        let more = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        let board = model.config?.origin("board") != nil
        switch route {
        case .art:
            guard let photo = p.photo else { message = "Art needs a photo."; return }
            let m = medium.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = await enqueue(kind: "image", text: m.isEmpty ? nil : m, note: more.isEmpty ? "Untitled piece" : more, file: photo, label: more.isEmpty ? "Artwork" : more,
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
        case .thought, .task, .today, .claude:   // the vault routes (11-17): they reach their note through pl-cron and the PC sync
            _ = await enqueue(kind: route.rawValue, text: p.text, note: nil, file: nil, label: String(p.text.prefix(120)), toBoard: false, route: route.rawValue, model: model)
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
            s += [detail.promoted.map { ("checkmark.seal", "Stamped \($0)", "Named, dated and numbered by the intake", true) }
                     ?? ("photo.on.rectangle", "Art inbox", "Waiting for \"intake it\": a session scans for duplicates, names it, stamps the PL number", false),
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

/// The capture itself, drawn in its detail sheet: the picture when it has one, then what it says. An art capture's picture lives in
/// the house's public asset store under its own id; other captures carry their picture's address in the text.
struct CaptureRender: View {
    let detail: CaptureModel.TrailDetail
    @Environment(\.colorScheme) private var scheme
    @State private var index = 0

    private var isArt: Bool { detail.meta.lowercased().hasPrefix("art") }

    private var pictures: [URL] {
        var out: [URL] = []
        if let u = captureTrailImage(detail.payload) { out.append(u) }
        if isArt {
            for ext in ["jpg", "png"] {
                if let u = URL(string: "https://assets.psychedluxuries.com/art-inbox/\(detail.id).\(ext)") { out.append(u) }
            }
        }
        return out
    }

    /// A stored record reads as lines (Title, Made, Medium); anything else is shown as written.
    private var words: String {
        guard let data = detail.payload.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return detail.payload }
        let order = ["title", "made", "medium", "via"]
        let lines = order.compactMap { k -> String? in
            guard let v = o[k], !"\(v)".isEmpty else { return nil }
            return k.capitalized + ": \(v)"
        }
        return lines.isEmpty ? detail.payload : lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The capture").osEyebrow(10).foregroundStyle(PLOS.dim(scheme))
            if index < pictures.count {
                AsyncImage(url: pictures[index]) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    case .failure:
                        Color.clear.frame(height: 1).onAppear { index += 1 }   // try the next address, then none
                    default:
                        PLLoader().frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .id(index)
            } else if isArt {
                Text("The picture is not in the store any more.").font(.footnote).foregroundStyle(PLOS.dim(scheme))
            }
            Text(words).font(.callout).foregroundStyle(PLOS.text(scheme)).textSelection(.enabled)
        }
        .padding(.top, 6)
    }
}

extension PLOS {
    /// The violet of every route that writes an Obsidian note (his word 11-17: purple, not gold). The house's own purple, `philosophy`.
    static var vault: Color { philosophy }
}

/// The live end of a vault note, read-only: pl-cron holds the last 3,500 characters the PC sync pushed, behind his widget token.
struct NoteLiveView: View {
    let note: VaultNote
    let model: AppModel
    @State private var text: String?
    @State private var age: Int?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let text {
                    Text(text.isEmpty ? "Nothing synced yet. The PC pushes this on its next capture sync." : text)
                        .font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                } else if failed {
                    Text("It would not load. Pull to try again.").foregroundStyle(.secondary)
                } else { ProgressView() }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle(note.file).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let age { Text("Synced " + (age < 1 ? "just now" : age < 90 ? "\(age) min ago" : "\(age / 60) h ago")).font(.caption2).foregroundStyle(.secondary).padding(8) }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let http = model.http,
              let data = try? await http.send(RequestPlan(origin: "cron", path: "api/widget/note", query: ["t": note.key])),
              let r = try? JSONDecoder().decode(NoteTail.self, from: data) else { failed = true; return }
        failed = false; text = r.text; age = r.age_min
    }

    private struct NoteTail: Decodable { let text: String; let age_min: Int? }
}
