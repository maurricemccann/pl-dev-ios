import SwiftUI
import UIKit

// Capture's model. Twin of pl-os `components/Intake.tsx` (four ways in: Artwork, Text, Quote, Link) and `CaptureTrail.tsx`
// ("Where it went"), with what a phone adds: it keeps working offline (the shared inbox and the send queue), takes the camera
// and the voice, and shows the numbers that wait on him.

/// The three rooms of Capture, by name, so a link, Siri, Spotlight or the widget can land on one.
enum CaptureRoom: String, CaseIterable, Identifiable {
    case add, trail, waiting
    var id: String { rawValue }
    var title: String { switch self { case .add: return "Add"; case .trail: return "Where it went"; case .waiting: return "Waiting" } }
    var line: String {
        switch self {
        case .add: return "Artwork, text, a quote or a link"
        case .trail: return "What became of each capture"
        case .waiting: return "What waits on you, and what waits to send"
        }
    }
    var symbol: String { switch self { case .add: return "plus.circle"; case .trail: return "point.topleft.down.curvedto.point.bottomright.up"; case .waiting: return "tray" } }
}

/// pl-os Intake's four modes, in its order, with its words.
enum CaptureKind: String, CaseIterable, Identifiable {
    case artwork, text, quote, link
    var id: String { rawValue }
    var title: String { switch self { case .artwork: return "Artwork"; case .text: return "Text"; case .quote: return "Quote"; case .link: return "Link" } }
    var sub: String {
        switch self {
        case .artwork: return "Image + metadata"; case .text: return "Body or essay"
        case .quote: return "Phrase · hook · caption"; case .link: return "URL → pull it in"
        }
    }
    var symbol: String { switch self { case .artwork: return "photo"; case .text: return "text.alignleft"; case .quote: return "quote.opening"; case .link: return "link" } }
    /// The type the console writes to the captures table.
    var apiType: String { self == .artwork ? "art" : rawValue }
}

/// A capture this phone made, kept so the trail can show it the instant it is saved (pl-os "Saving…" rows), before the server lists it.
struct CaptureLogEntry: Codable, Identifiable, Equatable {
    var id: String
    var kind: String
    var label: String
    var at: Date
    var sent: Bool
    var toBoard: Bool
    var thumb: Data?
}

enum CaptureLog {
    private static let key = "capture.log"
    static func read() -> [CaptureLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CaptureLogEntry].self, from: data)) ?? []
    }
    static func write(_ entries: [CaptureLogEntry]) {
        if let data = try? JSONEncoder().encode(Array(entries.prefix(40))) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// pl-os `lib/captureLabel.ts`: art captures from the Shortcut store their payload as JSON ({title, made}); read them as a title.
func captureLabel(_ payload: String?) -> String {
    let p = payload ?? ""
    guard p.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
          let obj = try? JSONSerialization.jsonObject(with: Data(p.utf8)) as? [String: Any],
          let title = obj["title"] as? String else { return p }
    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if let made = obj["made"] as? String, !made.isEmpty { return "\(t.isEmpty ? "Untitled piece" : t) · made \(made)" }
    return t.isEmpty ? "Untitled piece" : t
}

private func squash(_ s: String) -> String {
    s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// The picture a capture carries, if any: "[image] https://..." from a link capture, or a photo's address at the end of its caption.
func captureTrailImage(_ payload: String?) -> URL? {
    guard let p = payload else { return nil }
    if let r = p.range(of: "[image] ") {
        let rest = p[r.upperBound...].prefix { !$0.isWhitespace }
        if let u = URL(string: String(rest)), u.scheme?.hasPrefix("http") == true { return u }
    }
    for word in p.split(whereSeparator: { $0.isWhitespace }).reversed() {
        let w = String(word)
        if w.hasPrefix("https://"), let u = URL(string: w),
           ["jpg", "jpeg", "png", "webp", "gif", "heic"].contains(u.pathExtension.lowercased()) { return u }
    }
    return nil
}

/// The first address in a capture that is not its picture.
func captureTrailLink(_ payload: String?) -> URL? {
    guard let p = payload else { return nil }
    let image = captureTrailImage(p)
    for word in p.split(whereSeparator: { $0.isWhitespace }) {
        let w = String(word)
        if w.hasPrefix("http"), let u = URL(string: w), u != image { return u }
    }
    return nil
}

/// What actually became of a capture, from its real columns (pl-os CaptureTrail `stateOf`), never guessed.
struct CaptureState: Equatable {
    enum Tone { case pool, plain, dim }
    let label: String, detail: String, tone: Tone
    init(status: String?, poolKey: String?) {
        if let k = poolKey, !k.isEmpty { label = "In the pool"; detail = "Fetched and indexed. The content generator can draw on it."; tone = .pool }
        else if status == "synced" { label = "In Notion"; detail = "Synced to the Notion inbox."; tone = .plain }
        else if status == "rejected" { label = "Rejected"; detail = "You rejected it in moderation. The row is kept, not deleted."; tone = .dim }
        else { label = "Waiting"; detail = "In your moderation deck. Links are picked up on the next sweep."; tone = .plain }
    }
}

/// pl-os `fetchLinkPreview`, on the phone: the page's own title, description and picture (Open Graph). Http and https only.
struct LinkPreview: Equatable {
    var title: String
    var description: String
    var image: String

    static func fetch(_ raw: String) async -> LinkPreview? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), url.scheme == "http" || url.scheme == "https" else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse).map({ $0.statusCode < 400 }) ?? true else { return nil }
        let html = String(decoding: data.prefix(512 * 1024), as: UTF8.self)
        func meta(_ prop: String) -> String {
            let p = NSRegularExpression.escapedPattern(for: prop)
            for pattern in ["<meta[^>]+(?:property|name)=[\"']\(p)[\"'][^>]+content=[\"']([^\"']*)[\"']",
                            "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+(?:property|name)=[\"']\(p)[\"']"] {
                if let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                   let r = Range(m.range(at: 1), in: html) { return decodeEntities(String(html[r])) }
            }
            return ""
        }
        var title = meta("og:title")
        if title.isEmpty, let re = try? NSRegularExpression(pattern: "<title[^>]*>([^<]*)</title>", options: .caseInsensitive),
           let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let r = Range(m.range(at: 1), in: html) {
            title = decodeEntities(String(html[r]))
        }
        var description = meta("og:description")
        if description.isEmpty { description = meta("description") }
        var image = meta("og:image")
        if !image.isEmpty, let abs = URL(string: image, relativeTo: url)?.absoluteString { image = abs }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty && image.isEmpty && description.isEmpty { return nil }
        return LinkPreview(title: String((title.isEmpty ? text : title).prefix(200)), description: String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)), image: image)
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }
}

@MainActor @Observable final class CaptureModel {
    struct Waiting: Decodable, Equatable {
        var drafts: Int?, pins: Int?, manual: Int?, ads: Int?, emails: Int?, tasks: Int?, captures: Int?, shift_open: Int?
    }
    /// A row of "Where it went" (the console's `capturetrail`).
    struct TrailRow: Decodable, Identifiable, Equatable {
        let id: String
        let type: String?, payload: String?, status: String?, source: String?, created_at: String?, pool_key: String?
        var state: CaptureState { CaptureState(status: status, poolKey: pool_key) }
        var label: String { captureLabel(payload) }
    }
    /// A capture waiting in the moderation deck (the console's `captures`).
    struct DeckRow: Decodable, Identifiable, Equatable {
        let id: String
        let type: String?, payload: String?, created_at: String?
        var label: String { captureLabel(payload) }
    }

    // where he is
    var room: CaptureRoom = .add
    var kind: CaptureKind = .artwork

    // the form (pl-os Intake)
    var title = ""
    var medium = ""
    var year = ""
    var notes = ""
    var body = ""
    var words = ""
    var attribution = ""
    var linkURL = ""
    var photo: Data?
    var photoNote: String?
    var photoText = ""   // apple lane: the words Vision read in the photo, offered to add to the notes
    var preview: LinkPreview?
    var fetching = false
    var toBoard = false
    var busy = false
    var done = false
    var doneOffline = false
    var message: String?
    var sentTick = 0
    var tick = 0

    // what the server says
    var waiting: Waiting?
    var trail: [TrailRow] = []
    var deck: [DeckRow] = []
    var trailLoaded = false
    var trailNote: String?
    var usedToday: Int?
    var cap: Int?
    var log: [CaptureLogEntry] = CaptureLog.read()
    var detail: TrailDetail?

    /// What the detail sheet opens on: a server row or one this phone made.
    struct TrailDetail: Identifiable, Equatable {
        let id: String
        let label: String, payload: String
        let stateLabel: String, stateDetail: String
        let tone: CaptureState.Tone
        let meta: String
        let created: String?
    }

    var waitingLine: String? {
        guard let w = waiting else { return nil }
        let parts: [(Int?, String)] = [(w.drafts, "drafts"), (w.pins, "Pins"), (w.tasks, "tasks"), (w.shift_open, "shift")]
        let shown = parts.compactMap { n, label in (n ?? 0) > 0 ? "\(n!) \(label)" : nil }
        return shown.isEmpty ? "Nothing waiting on you" : shown.joined(separator: " · ")
    }

    /// Everything that waits on him, as the widget's one number.
    var owed: Int {
        guard let w = waiting else { return 0 }
        return (w.drafts ?? 0) + (w.pins ?? 0) + (w.tasks ?? 0) + (w.shift_open ?? 0) + (w.captures ?? 0)
    }

    var canSubmit: Bool {
        if busy { return false }
        switch kind {
        case .artwork: return photo != nil
        case .text: return !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .quote: return !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .link: return !linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: reads

    func loadWaiting(model: AppModel) async {
        guard let http = model.http else { return }
        if let data = try? await http.send(RequestPlan(origin: "cron", path: "api/widget/waiting")),
           let w = try? JSONDecoder().decode(Waiting.self, from: data) {
            waiting = w
            model.writeSnapshot()
            publishGlance(model: model)
        }
    }

    func loadTrail(model: AppModel) async {
        async let t = try? Console.q("capturetrail", [TrailRow].self, model: model)
        async let d = try? Console.q("captures", [DeckRow].self, model: model)
        let (t1, d1) = await (t, d)
        if let t1 { trail = t1; trailNote = nil } else if trail.isEmpty {
            trailNote = model.config?.origin("console") == nil ? "The trail reads from the console. Add its address and key to your config." : "The trail would not load. Pull to try again."
        }
        if let d1 { deck = d1 }
        trailLoaded = true
    }

    func loadAll(model: AppModel) async {
        CaptureSection.install(model: model)
        async let a: Void = loadWaiting(model: model)
        async let b: Void = loadTrail(model: model)
        _ = await (a, b)
        log = CaptureLog.read()
    }

    func publishGlance(model: AppModel) {
        let w = waiting
        SharedState.writeCapture(CaptureGlance(drafts: w?.drafts ?? 0, pins: w?.pins ?? 0, tasks: w?.tasks ?? 0, shiftOpen: w?.shift_open ?? 0,
                                               captures: w?.captures ?? 0, queued: model.inboxCount,
                                               lastLabel: log.first?.label, updatedAt: .now))
    }

    // MARK: the local record

    func addLog(_ e: CaptureLogEntry) {
        log.insert(e, at: 0)
        CaptureLog.write(log)
        log = CaptureLog.read()
    }

    func markSent(_ id: String) {
        if let i = log.firstIndex(where: { $0.id == id }) { log[i].sent = true; CaptureLog.write(log) }
    }

    /// Entries the server has not listed yet: queued ones always, sent ones for half an hour (pl-os "Saving…").
    var ghosts: [CaptureLogEntry] {
        let known = Set(trail.map { squash(captureLabel($0.payload)).prefix(60).description })
        return log.filter { e in
            let key = squash(e.label).prefix(60).description
            if known.contains(key) { return false }
            if e.toBoard { return !e.sent }
            return !e.sent || Date().timeIntervalSince(e.at) < 1800
        }.prefix(5).map { $0 }
    }

    // MARK: the form

    func switchKind(_ k: CaptureKind) {
        guard k != kind else { return }
        kind = k; done = false; preview = nil; message = nil
    }

    func resetForm() {
        title = ""; medium = ""; year = ""; notes = ""; body = ""; words = ""; attribution = ""; linkURL = ""
        photo = nil; photoNote = nil; photoText = ""; preview = nil; done = false; doneOffline = false; message = nil
    }

    func setPhoto(_ data: Data?) {
        guard let data else { return }
        guard let jpeg = CaptureModel.jpeg(data) else { message = "That picture could not be read or is too large. Try another."; photo = nil; return }
        photo = jpeg; message = nil
        photoNote = ByteCountFormatter.string(fromByteCount: Int64(jpeg.count), countStyle: .file)
        photoText = ""
        Task { [weak self] in
            let read = await PLVision.text(in: jpeg)
            if let self, self.photo == jpeg { self.photoText = read }
        }
    }

    func pullLink() async {
        let t = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        fetching = true; preview = nil; message = nil
        let p = await LinkPreview.fetch(t)
        preview = p; fetching = false
        if p == nil { message = "The page gave nothing to pull. The link is still saved bare." }
    }

    /// Saves the capture into the shared inbox (the same door the share sheet uses) and drains it. True when the server took it.
    @discardableResult
    func enqueue(kind itemKind: String, text: String?, note: String?, file: Data?, label: String, toBoard board: Bool, model: AppModel) async -> Bool {
        let id = UUID().uuidString
        let item = SharedInbox.Item(id: id, createdAt: Date(), source: "app", kind: itemKind, text: text, url: nil, title: nil,
                                    fileName: file != nil ? "photo.jpg" : nil, note: note, target: board && file == nil ? "board" : "cron")
        do { try SharedInbox.add(item, file: file) } catch { message = error.localizedDescription; return false }
        addLog(CaptureLogEntry(id: id, kind: itemKind, label: label, at: Date(), sent: false, toBoard: board && file == nil, thumb: file.flatMap { CaptureModel.thumb($0) }))
        CaptureSection.install(model: model)
        await model.drainInbox()
        log = CaptureLog.read()
        publishGlance(model: model)
        return log.first(where: { $0.id == id })?.sent ?? false
    }

    func submit(model: AppModel) async {
        guard canSubmit else { return }
        busy = true; message = nil
        defer { busy = false }
        let board = toBoard && model.config?.origin("board") != nil && kind != .artwork
        let sent: Bool
        switch kind {
        case .artwork:
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let y = year.trimmingCharacters(in: .whitespacesAndNewlines)
            let m = medium.trimmingCharacters(in: .whitespacesAndNewlines)
            var caption = [t.isEmpty ? "Untitled piece" : t, m.isEmpty ? nil : m, y.isEmpty ? nil : "made \(y)"].compactMap { $0 }.joined(separator: " · ")
            if !n.isEmpty { caption += ". " + n }
            sent = await enqueue(kind: "image", text: nil, note: caption, file: photo, label: t.isEmpty ? "Artwork" : t, toBoard: false, model: model)
        case .text:
            let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
            sent = await enqueue(kind: "text", text: b, note: nil, file: nil, label: String(b.prefix(120)), toBoard: board, model: model)
        case .quote:
            let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
            let a = attribution.trimmingCharacters(in: .whitespacesAndNewlines)
            let full = a.isEmpty ? w : w + "\n— " + a
            sent = await enqueue(kind: "quote", text: full, note: nil, file: nil, label: String(w.prefix(120)), toBoard: board, model: model)
        case .link:
            let u = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
            // pl-os: the address, then the page's title, description and picture; a link whose preview failed is still saved, bare
            let full = [u, preview?.title, preview?.description, preview.flatMap { $0.image.isEmpty ? nil : "[image] " + $0.image }]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            sent = await enqueue(kind: "url", text: full, note: nil, file: nil, label: u, toBoard: board, model: model)
        }
        if message != nil { return }   // the inbox itself refused: stay on the form with its sentence
        doneOffline = !sent
        done = true
        sentTick += 1
        await loadTrail(model: model)
    }

    // MARK: moderation (the same call House makes)

    func moderate(_ row: DeckRow, _ action: String, model: AppModel) async {
        deck.removeAll { $0.id == row.id }
        do {
            try await Console.post("api/captures/moderate", ["capture_id": row.id, "action": action], model: model)
            tick += 1
            if var w = waiting, let c = w.captures, c > 0 { w.captures = c - 1; waiting = w; publishGlance(model: model) }
            await loadTrail(model: model)
        } catch {
            deck.append(row)
            trailNote = "Not saved. \(plainSentence(error))"
        }
    }

    func noteCap(from data: Data) {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let u = o["used_today"] as? Int { usedToday = u }
        if let c = o["cap"] as? Int { cap = c }
    }

    // MARK: pictures

    /// Any image the phone can read, as a JPEG under the server's 4 MB cap, longest side at most 2048.
    nonisolated static func jpeg(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = max(image.size.width, image.size.height)
        let scale = side > 2048 ? 2048 / side : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let drawn = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for q in [0.85, 0.7, 0.5] {
            if let out = drawn.jpegData(compressionQuality: q), out.count < 4 * 1024 * 1024 { return out }
        }
        return nil
    }

    /// A small preview of a photo for the local record.
    nonisolated static func thumb(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side: CGFloat = 120
        let scale = side / max(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.6)
    }
}
