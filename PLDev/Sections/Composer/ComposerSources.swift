import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Sources that are not in the laptop's index: his Photos (pictures and clips, copied into the app so they survive the library moving) and the
// gallery's Curve Library (the 12,862-row index the Library and Curate rooms use). Each becomes a ComposerAsset, so the shot card, the graph,
// the preview and the spec treat it like any indexed asset. A clip can carry an in and out point (the trim); the spec prints it beside the source.

enum ComposerMedia {
    /// Application Support/composer-media: the copies, the thumbnails and extras.json.
    static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("composer-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
}

/// A clip out of Photos, copied into the app on the way in (PhotosPicker hands over a temporary file).
struct ComposerMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { m in SentTransferredFile(m.url) } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = ComposerMedia.dir.appendingPathComponent("in-" + String(UUID().uuidString.prefix(8)) + "." + ext)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return ComposerMovie(url: dest)
        }
    }
}

struct ComposerExtra: Codable, Identifiable, Hashable {
    var id: String            // ph_xxxxxxxx (Photos) or cl_<vault id> (Curve Library)
    var kind: String          // media | audio | curve | model
    var name: String
    var catalog: String       // "Photos" or "Curve Library"
    var path: String          // Photos: the copy's file name in composer-media; Curve Library: the vault id
    var ext: String
    var bytes: Int
    var width: Int?
    var height: Int?
    var duration: Double?     // a clip's full length
    var video: Bool
    var trimIn: Double?
    var trimOut: Double?
    var remote: String?       // Curve Library: where the full picture or clip lives
    var made: Date

    var trimmed: Bool { trimIn != nil || trimOut != nil }
    /// What the shot gets from this clip.
    var length: Double? {
        guard let d = duration else { return nil }
        return max(0, (trimOut ?? d) - (trimIn ?? 0))
    }
    var asset: ComposerAsset {
        var note: String?
        if trimmed, let d = duration { note = "trim \(Self.sec(trimIn ?? 0))-\(Self.sec(trimOut ?? d))s" }
        return ComposerAsset(id: id, kind: kind, name: name, catalog: catalog, path: path, ext: ext, bytes: bytes, width: width, height: height, duration: length, tags: [], trim: note)
    }
    static func sec(_ v: Double) -> String { String(format: "%.1f", v) }
}

@MainActor @Observable final class ComposerExtras {
    static let shared = ComposerExtras()
    private(set) var items: [ComposerExtra] = []
    var assets: [ComposerAsset] { items.map(\.asset) }
    @ObservationIgnored private let file = ComposerMedia.dir.appendingPathComponent("extras.json")
    @ObservationIgnored private let previews = NSCache<NSString, UIImage>()

    init() { if let d = try? Data(contentsOf: file), let x = try? JSONDecoder().decode([ComposerExtra].self, from: d) { items = x } }

    private func save() { if let d = try? JSONEncoder().encode(items) { try? d.write(to: file, options: .atomic) } }
    func extra(_ id: String) -> ComposerExtra? { items.first { $0.id == id } }
    var photos: [ComposerExtra] { items.filter { $0.catalog == "Photos" }.sorted { $0.made > $1.made } }

    func thumb(_ id: String) -> UIImage? { UIImage(contentsOfFile: ComposerMedia.dir.appendingPathComponent(id + ".thumb.jpg").path) }
    /// The picture the preview shows: the medium copy of a photo, else the thumbnail (a clip's first frame, a library still).
    func preview(_ id: String) -> UIImage? {
        if let c = previews.object(forKey: id as NSString) { return c }
        let img = UIImage(contentsOfFile: ComposerMedia.dir.appendingPathComponent(id + ".jpg").path) ?? thumb(id)
        if let img { previews.setObject(img, forKey: id as NSString) }
        return img
    }
    func clipURL(_ id: String) -> URL? {
        guard let e = extra(id), e.video, e.catalog == "Photos" else { return nil }
        return ComposerMedia.dir.appendingPathComponent(e.path)
    }

    func add(_ e: ComposerExtra, thumb: UIImage?) {
        if let t = thumb?.composerScaled(maxSide: 360), let d = t.jpegData(compressionQuality: 0.8) { try? d.write(to: ComposerMedia.dir.appendingPathComponent(e.id + ".thumb.jpg"), options: .atomic) }
        if let i = items.firstIndex(where: { $0.id == e.id }) { items[i] = e } else { items.append(e) }
        save()
        ComposerLibrary.shared.register(e.asset)
    }

    func update(_ id: String, _ edit: (inout ComposerExtra) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var e = items[i]; edit(&e); items[i] = e; save()
        ComposerLibrary.shared.register(e.asset)
    }

    /// Takes it out of Composer and off every shot that used it. Photos itself is never touched.
    func remove(_ id: String) {
        guard let e = extra(id) else { return }
        let fm = FileManager.default
        if e.catalog == "Photos" { try? fm.removeItem(at: ComposerMedia.dir.appendingPathComponent(e.path)) }
        try? fm.removeItem(at: ComposerMedia.dir.appendingPathComponent(id + ".thumb.jpg"))
        try? fm.removeItem(at: ComposerMedia.dir.appendingPathComponent(id + ".jpg"))
        items.removeAll { $0.id == id }; save()
        let pieces = ComposerPieces.shared
        for i in pieces.entries.indices { for j in pieces.entries[i].piece.shots.indices { pieces.entries[i].piece.shots[j].sourceIds.removeAll { $0 == id } } }
    }

    // MARK: Photos

    func importPhotos(_ picks: [PhotosPickerItem]) async -> [ComposerExtra] {
        var out: [ComposerExtra] = []
        for it in picks {
            let isVideo = it.supportedContentTypes.contains { $0.conforms(to: .movie) }
            if let e = await (isVideo ? importVideo(it) : importImage(it)) { out.append(e) }
        }
        return out
    }

    private func nextName(_ prefix: String) -> String {
        let n = items.filter { $0.catalog == "Photos" && $0.name.hasPrefix(prefix) }.count + 1
        return prefix + String(format: "%02d", n)
    }

    private func importImage(_ it: PhotosPickerItem) async -> ComposerExtra? {
        guard let data = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return nil }
        let id = "ph_" + String(UUID().uuidString.prefix(8)).lowercased()
        let big = img.composerScaled(maxSide: 1920)
        guard let jpg = big.jpegData(compressionQuality: 0.85) else { return nil }
        do { try jpg.write(to: ComposerMedia.dir.appendingPathComponent(id + ".jpg"), options: .atomic) } catch { return nil }
        let e = ComposerExtra(id: id, kind: "media", name: nextName("photo-"), catalog: "Photos", path: id + ".jpg", ext: ".jpg", bytes: jpg.count,
                              width: Int(img.size.width * img.scale), height: Int(img.size.height * img.scale), duration: nil, video: false, trimIn: nil, trimOut: nil, remote: nil, made: .now)
        add(e, thumb: big)
        return e
    }

    private func importVideo(_ it: PhotosPickerItem) async -> ComposerExtra? {
        guard let m = try? await it.loadTransferable(type: ComposerMovie.self) else { return nil }
        let id = "ph_" + String(UUID().uuidString.prefix(8)).lowercased()
        let ext = m.url.pathExtension.isEmpty ? "mov" : m.url.pathExtension
        let dest = ComposerMedia.dir.appendingPathComponent(id + "." + ext)
        do { try FileManager.default.moveItem(at: m.url, to: dest) } catch { return nil }
        let asset = AVURLAsset(url: dest)
        let dur = (try? await asset.load(.duration).seconds) ?? 0
        var size = CGSize.zero
        if let track = try? await asset.loadTracks(withMediaType: .video).first, let n = try? await track.load(.naturalSize) {
            let t = (try? await track.load(.preferredTransform)) ?? .identity
            let r = n.applying(t); size = CGSize(width: abs(r.width), height: abs(r.height))
        }
        var frame: UIImage?
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1280, height: 1280)
        if let cg = try? await gen.image(at: CMTime(seconds: min(0.2, max(0, dur / 2)), preferredTimescale: 600)).image { frame = UIImage(cgImage: cg) }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
        let e = ComposerExtra(id: id, kind: "media", name: nextName("clip-"), catalog: "Photos", path: id + "." + ext, ext: "." + ext, bytes: bytes,
                              width: size.width > 0 ? Int(size.width) : nil, height: size.height > 0 ? Int(size.height) : nil, duration: dur > 0 ? dur : nil, video: true,
                              trimIn: nil, trimOut: nil, remote: nil, made: .now)
        add(e, thumb: frame)
        return e
    }

    #if targetEnvironment(simulator)
    /// Simulator only (composer-e2e): a generated picture added as a Photos source and attached to the piece's last shot, so the upload step can be driven
    /// without the system picker. Never compiled into a device build, and never touches the real Photos library.
    func seedForSimulator() {
        let id = "ph_5eed0001"
        guard extra(id) == nil else { return }
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480), format: f).image { c in
            UIColor.systemTeal.setFill(); c.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            UIColor.white.setFill(); c.fill(CGRect(x: 160, y: 120, width: 320, height: 240))
        }
        guard let jpg = img.jpegData(compressionQuality: 0.85), (try? jpg.write(to: ComposerMedia.dir.appendingPathComponent(id + ".jpg"), options: .atomic)) != nil else { return }
        let e = ComposerExtra(id: id, kind: "media", name: "photo-seed", catalog: "Photos", path: id + ".jpg", ext: ".jpg", bytes: jpg.count, width: 640, height: 480,
                              duration: nil, video: false, trimIn: nil, trimOut: nil, remote: nil, made: .now)
        add(e, thumb: img)
        let pieces = ComposerPieces.shared
        if pieces.piece.shots.isEmpty { pieces.addShot() }
        _ = pieces.attach(e.asset, to: pieces.piece.shots.last?.id)
    }
    #endif

    // MARK: Curve Library

    @discardableResult func addLibrary(_ it: LibraryItem, model: AppModel) async -> ComposerExtra {
        let id = "cl_" + it.vault_id
        if let e = extra(id) { return e }
        let m = LibraryData.shared.media(it, model: model)
        let kind: String
        switch it.class { case "audio": kind = "audio"; case "model": kind = "model"; case "svg-curve", "code-piece": kind = "curve"; default: kind = "media" }
        let full = (it.name ?? it.vault_id) as NSString
        let ext = full.pathExtension.isEmpty ? "" : "." + full.pathExtension
        let e = ComposerExtra(id: id, kind: kind, name: full.deletingPathExtension, catalog: "Curve Library", path: it.vault_id, ext: ext, bytes: 0, width: nil, height: nil,
                              duration: nil, video: m.video != nil, trimIn: nil, trimOut: nil, remote: (m.video ?? m.still)?.absoluteString, made: .now)
        var img: UIImage?
        if let u = m.still, let (d, _) = try? await URLSession.shared.data(from: u) { img = UIImage(data: d) }
        add(e, thumb: img)
        return e
    }
}

extension UIImage {
    /// Largest side at most `maxSide` points, drawn at scale 1 so the file is the size named.
    func composerScaled(maxSide: CGFloat) -> UIImage {
        let w = size.width * scale, h = size.height * scale, m = max(w, h)
        let k = m > maxSide ? maxSide / m : 1
        let target = CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size: target, format: f).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

// MARK: the Photos pane

struct ComposerPhotosPane: View {
    let targetId: String?
    @Binding var note: String?
    @State private var extras = ComposerExtras.shared
    @State private var store = ComposerPieces.shared
    @State private var picks: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var trim: ComposerExtra?
    @State private var tick = 0

    private var target: ComposerShot? { store.piece.shots.first { $0.id == (targetId ?? store.selected ?? store.piece.shots.last?.id) } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $picks, maxSelectionCount: 12, matching: .any(of: [.images, .videos])) {
                        Label(importing ? "Copying…" : "Choose from Photos", systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CMPPill(primary: true)).disabled(importing).accessibilityIdentifier("composer.photos.choose")
                    Text(target.map { "Pictures and clips you choose attach to \"\($0.title)\"." } ?? "Add a shot first. Then pictures and clips you choose attach to it.").font(.system(size: 11)).foregroundStyle(CMP.dim)
                    Text("Copied into Composer, so they stay when the library changes. Send the whole piece to render uploads them to the house first.").font(.system(size: 11)).foregroundStyle(CMP.muted)
                    if let n = note { Text(n).font(.system(size: 11)).foregroundStyle(CMP.goldDim).accessibilityIdentifier("composer.library.note") }
                }
                .cmpCard(padding: 12).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            }
            if extras.photos.isEmpty {
                Section { ContentUnavailableView("Nothing from Photos yet", systemImage: "photo.on.rectangle", description: Text("Pictures and clips you choose are kept here, ready to attach to any shot.")).listRowBackground(Color.clear) }
            } else {
                Section {
                    ForEach(extras.photos) { e in
                        row(e).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .swipeActions(edge: .leading) { Button(role: .destructive) { extras.remove(e.id) } label: { Label("Delete", systemImage: "trash") } }
                            .swipeActions(edge: .trailing) { Button { attach(e) } label: { Label("Attach", systemImage: "plus") }.tint(CMP.gold).disabled(target == nil) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .onChange(of: picks) { _, new in
            guard !new.isEmpty else { return }
            Task {
                importing = true
                let made = await extras.importPhotos(new)
                picks = []; importing = false
                if made.isEmpty { note = "Nothing came in. Photos did not hand the file over." }
                else { for e in made { attach(e, quiet: true) }; note = "Added \(made.count) from Photos" + (target.map { " to \"\($0.title)\"." } ?? ".") }
                tick += 1
            }
        }
        .sheet(item: $trim) { e in ComposerTrimSheet(extraId: e.id, shotId: target?.id) }
        .sensoryFeedback(PLHaptic.commit, trigger: tick)
    }

    private func attach(_ e: ComposerExtra, quiet: Bool = false) {
        guard let t = target else { note = "Add a shot first, then attach assets to it."; return }
        if t.sourceIds.contains(e.id) { if !quiet { note = "\(e.name) is already on \"\(t.title)\"." }; return }
        _ = store.attach(e.asset, to: t.id); tick += 1
        if !quiet { note = "Attached \(e.name) to \"\(t.title)\"." }
    }

    private func row(_ e: ComposerExtra) -> some View {
        let on = target?.sourceIds.contains(e.id) == true
        return Button { attach(e) } label: {
            HStack(spacing: 10) {
                Group {
                    if let img = extras.thumb(e.id) { Image(uiImage: img).resizable().scaledToFill() } else { Image(systemName: e.video ? "video" : "photo").foregroundStyle(CMP.muted) }
                }
                .frame(width: 44, height: 44).background(CMP.well).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(CMP.line, lineWidth: 0.6) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name + e.ext).font(.system(size: 14)).foregroundStyle(CMP.text).lineLimit(1)
                    Text([e.video ? "clip" : "picture", e.width.flatMap { w in e.height.map { "\(w)×\($0)" } }, e.trimmed ? "trimmed" : nil].compactMap { $0 }.joined(separator: " · ")).cmpNum(10).foregroundStyle(CMP.muted)
                }
                Spacer(minLength: 6)
                if let l = e.length, e.video { Text(composerClock(l)).cmpNum(11).foregroundStyle(CMP.goldDim) }
                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(CMP.gold).accessibilityLabel("Attached") }
            }
            .frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { attach(e) } label: { Label("Attach to the shot", systemImage: "plus") }.disabled(target == nil)
            if e.video { Button { trim = e } label: { Label("Trim the clip", systemImage: "scissors") } }
            Button(role: .destructive) { extras.remove(e.id) } label: { Label("Remove from Composer", systemImage: "trash") }
        }
        .accessibilityLabel("\(e.name), \(e.video ? "clip" : "picture")" + (on ? ", attached" : ""))
    }
}

// MARK: the trim (a clip's in and out)

struct ComposerTrimSheet: View {
    let extraId: String
    let shotId: String?
    @State private var extras = ComposerExtras.shared
    @State private var store = ComposerPieces.shared
    @Environment(\.dismiss) private var dismiss
    @State private var inP = 0.0
    @State private var outP = 1.0
    @State private var ready = false

    private var total: Double { extras.extra(extraId)?.duration ?? 0 }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let e = extras.extra(extraId), total > 0 {
                    Group {
                        if let img = extras.thumb(e.id) { Image(uiImage: img).resizable().scaledToFit() } else { Color.clear }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 200).background(CMP.well).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(e.name + e.ext).font(.system(size: 18, design: .serif)).foregroundStyle(CMP.text)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("in").cmpLabel(10); Spacer(); Text(String(format: "%.1f s", inP * total)).cmpNum(13).foregroundStyle(CMP.text) }
                        Slider(value: $inP, in: 0...1).tint(CMP.gold).accessibilityIdentifier("composer.trim.in").accessibilityLabel("In point")
                        HStack { Text("out").cmpLabel(10); Spacer(); Text(String(format: "%.1f s", outP * total)).cmpNum(13).foregroundStyle(CMP.text) }
                        Slider(value: $outP, in: 0...1).tint(CMP.gold).accessibilityIdentifier("composer.trim.out").accessibilityLabel("Out point")
                        Text(String(format: "%.1f s of %.1f s kept", max(0, (outP - inP) * total), total)).cmpNum(11).foregroundStyle(CMP.dim)
                    }.cmpCard()
                    if let s = shotId {
                        Button("Make the shot this long") { let d = max(0.1, (outP - inP) * total); store.patch(s) { $0.duration = (d * 10).rounded() / 10 }; save(); dismiss() }
                            .buttonStyle(CMPPill()).accessibilityIdentifier("composer.trim.fit")
                    }
                    Button("Use this trim") { save(); dismiss() }.buttonStyle(CMPPill(primary: true)).accessibilityIdentifier("composer.trim.save")
                    if e.trimmed { Button("Back to the whole clip") { extras.update(extraId) { $0.trimIn = nil; $0.trimOut = nil }; dismiss() }.buttonStyle(CMPPill()) }
                    Spacer(minLength: 0)
                } else { ContentUnavailableView("This clip has no length", systemImage: "scissors") }
            }
            .padding(PLSpace.margin)
            .cmpScreen().navigationTitle("Trim").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                guard !ready, let e = extras.extra(extraId), let d = e.duration, d > 0 else { return }
                inP = (e.trimIn ?? 0) / d; outP = (e.trimOut ?? d) / d; ready = true
            }
            .onChange(of: inP) { _, v in if v > outP - 0.02 { inP = max(0, outP - 0.02) } }
            .onChange(of: outP) { _, v in if v < inP + 0.02 { outP = min(1, inP + 0.02) } }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let t = total
        let a = (inP * t * 10).rounded() / 10, b = (outP * t * 10).rounded() / 10
        extras.update(extraId) { $0.trimIn = a <= 0.05 ? nil : a; $0.trimOut = b >= t - 0.05 ? nil : b }
    }
}

// MARK: the Curve Library pane (the gallery's index: stills, clips, archive works, curves, beds)

struct ComposerCurvePane: View {
    let model: AppModel
    let targetId: String?
    @Binding var note: String?
    @State private var data = LibraryData.shared
    @State private var extras = ComposerExtras.shared
    @State private var store = ComposerPieces.shared
    @State private var q = ""
    @State private var cls: String?
    @State private var limit = 80
    @State private var loadFailed = false
    @State private var busy: String?
    @State private var tick = 0

    private static let classes = [("still", "stills"), ("cinematic", "clips"), ("archive-work", "archive"), ("code-piece", "curves"), ("svg-curve", "svg"), ("audio", "beds"), ("model", "models")]
    private var target: ComposerShot? { store.piece.shots.first { $0.id == (targetId ?? store.selected ?? store.piece.shots.last?.id) } }
    private var needle: String { q.trimmingCharacters(in: .whitespaces).lowercased() }
    private var rows: [LibraryItem] {
        let allowed = Set(Self.classes.map(\.0))
        return data.items.filter { it in
            allowed.contains(it.class) && (cls == nil || it.class == cls)
                && (needle.isEmpty || (it.name ?? "").lowercased().contains(needle) || it.vault_id.lowercased().contains(needle) || (it.tags ?? "").lowercased().contains(needle))
        }
    }

    var body: some View {
        let shown = rows
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Curve Library").cmpLabel(11)
                        Spacer()
                        Text("\(shown.count.formatted()) of \(data.items.count.formatted())").cmpNum(11).foregroundStyle(CMP.muted)
                    }
                    Text(target.map { "tap a piece: attaches to \"\($0.title)\"" } ?? "add a shot to attach pieces").font(.system(size: 11)).foregroundStyle(target == nil ? CMP.muted : CMP.goldDim)
                    if let n = note { Text(n).font(.system(size: 11)).foregroundStyle(CMP.dim).accessibilityIdentifier("composer.library.note") }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            CMPChip(title: "all", on: cls == nil) { cls = nil }
                            ForEach(Self.classes, id: \.0) { c in
                                let n = data.items.filter { $0.class == c.0 }.count
                                if n > 0 { CMPChip(title: c.1, count: n, on: cls == c.0) { cls = (cls == c.0) ? nil : c.0 } }
                            }
                        }
                    }
                }
                .cmpCard(padding: 12).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            }
            if data.items.isEmpty {
                Section {
                    if loadFailed { ContentUnavailableView { Label("The Curve Library did not load", systemImage: "wifi.exclamationmark") } description: { Text("Pull to try again.") } }
                    else { ProgressView("Reading the Curve Library…").frame(maxWidth: .infinity, minHeight: 160).tint(CMP.gold) }
                }.listRowBackground(Color.clear)
            } else if shown.isEmpty {
                Section { ContentUnavailableView.search(text: q).listRowBackground(Color.clear) }
            } else {
                Section {
                    ForEach(shown.prefix(limit)) { it in
                        row(it).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                    if shown.count > limit {
                        Button { limit += 80 } label: { Text("Show more: \((shown.count - limit).formatted()) not shown").font(.system(size: 13)).foregroundStyle(CMP.gold).frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(.plain).listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $q, prompt: "Filter the Curve Library")
        .onChange(of: q) { limit = 80 }
        .onChange(of: cls) { limit = 80 }
        .refreshable { await load(force: true) }
        .task { await load(force: false) }
        .sensoryFeedback(PLHaptic.commit, trigger: tick)
    }

    private func load(force: Bool) async {
        loadFailed = false
        do { try await data.load(model: model, force: force) }
        catch { if data.items.isEmpty { loadFailed = true } }   // the marks can fail after the index arrived; the index is all this pane needs
    }

    private func attach(_ it: LibraryItem) async {
        guard let t = target else { note = "Add a shot first, then attach assets to it."; return }
        busy = it.vault_id
        let e = await extras.addLibrary(it, model: model)
        busy = nil
        if t.sourceIds.contains(e.id) { note = "\(e.name) is already on \"\(t.title)\"."; return }
        _ = store.attach(e.asset, to: t.id); tick += 1
        note = "Attached \(e.name) to \"\(t.title)\"."
    }

    private func row(_ it: LibraryItem) -> some View {
        let id = "cl_" + it.vault_id
        let on = target?.sourceIds.contains(id) == true
        let still = data.media(it, model: model).still
        return Button { Task { await attach(it) } } label: {
            HStack(spacing: 10) {
                Group {
                    if let u = still { AsyncImage(url: u) { p in if let i = p.image { i.resizable().scaledToFill() } else { Color.clear } } }
                    else { Text(String(it.class.prefix(3))).font(.system(size: 9, design: .monospaced)).textCase(.uppercase).foregroundStyle(CMP.muted) }
                }
                .frame(width: 44, height: 44).background(CMP.well).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(CMP.line, lineWidth: 0.6) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(it.name ?? it.vault_id).font(.system(size: 14)).foregroundStyle(CMP.text).lineLimit(1)
                    Text([it.class, it.origin, it.vault_id].compactMap { $0 }.joined(separator: " · ")).cmpNum(10).foregroundStyle(CMP.muted).lineLimit(1)
                }
                Spacer(minLength: 6)
                if busy == it.vault_id { PLLoader().tint(CMP.gold) }
                else if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(CMP.gold).accessibilityLabel("Attached") }
            }
            .frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(it.name ?? it.vault_id), \(it.class)" + (on ? ", attached" : ""))
        .accessibilityHint("Attaches it to the selected shot")
    }
}
