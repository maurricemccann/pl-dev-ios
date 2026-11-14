import Foundation

// A whole piece to the house (S348 composer3). The phone's Photos sources go up first, one file at a time, through the Composer Worker's
// keyed door (POST api/media, into R2); then the piece's spec goes as one card (POST api/board, kind "spec"). The PC pulls both, renders
// the spec with compose_render.py and files the clip to /curate, the same as every other card. A source that already went up (same id, same
// size) is skipped, so a failed send resumes where it stopped instead of starting over.

enum ComposerUpload {
    /// The Worker's cap: Cloudflare Workers take a request body of 100 MB on the Free and Pro plans.
    static let maxBytes = 100 * 1024 * 1024
    /// The door takes jpg, png, mov and mp4. A phone clip is mov or mp4 (m4v is the same container as mp4).
    static func ext(_ fileExt: String) -> String? {
        switch fileExt.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
        case "jpg", "jpeg": return "jpg"
        case "png": return "png"
        case "mov": return "mov"
        case "mp4", "m4v": return "mp4"
        default: return nil
        }
    }
    static func megabytes(_ n: Int) -> String { String(format: "%.0f MB", Double(n) / 1_048_576) }
}

@MainActor @Observable final class ComposerRender {
    static let shared = ComposerRender()
    struct Step: Equatable { var text: String; var done: Int; var total: Int; var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 } }
    enum Result { case sent(id: String, uploaded: Int), queued(String), refused(String) }

    private(set) var step: Step?
    private(set) var busy = false
    @ObservationIgnored private let key = "composer.uploaded"   // id -> bytes of the copy that went up

    private var uploaded: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Photos sources of the piece, each once, in shot order.
    static func phoneSources(of piece: ComposerPiece, extras: ComposerExtras) -> [ComposerExtra] {
        var seen = Set<String>(); var out: [ComposerExtra] = []
        for id in piece.shots.flatMap(\.sourceIds) where seen.insert(id).inserted { if let e = extras.extra(id), e.catalog == "Photos" { out.append(e) } }
        return out
    }

    func send(piece: ComposerPiece, model: AppModel) async -> Result {
        guard !busy else { return .refused("Already sending this piece.") }
        busy = true; defer { busy = false; step = nil }
        let name = piece.piece.trimmingCharacters(in: .whitespaces)
        if piece.shots.isEmpty { return .refused("Not sent. The piece has no shots.") }
        if name.isEmpty || name.count > 120 { return .refused("Not sent. Name the piece (120 characters at most).") }
        guard let http = model.http else { return .queued("Waiting for the house. The phone has no config loaded.") }
        let extras = ComposerExtras.shared
        let ids = piece.shots.flatMap(\.sourceIds)
        let curve = Set(ids).compactMap { extras.extra($0) }.filter { $0.catalog == "Curve Library" }
        if !curve.isEmpty {
            return .refused("Not sent. " + curve.map(\.name).sorted().joined(separator: ", ") + " come from the Curve Library, which the renderer cannot find by id. Swap them for sources from the library index or from Photos.")
        }
        let phone = Self.phoneSources(of: piece, extras: extras)
        let todo = phone.filter { uploaded[$0.id] != $0.bytes || $0.bytes == 0 }
        var went = 0
        for (i, e) in todo.enumerated() {
            step = Step(text: "Uploading \(e.name) (\(i + 1) of \(todo.count))", done: i, total: todo.count + 1)
            guard let ext = ComposerUpload.ext(e.ext) else { return .refused("Not sent. \(e.name)\(e.ext) is not a type the house takes (jpg, png, mov, mp4).") }
            let url = ComposerMedia.dir.appendingPathComponent(e.path)
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), !data.isEmpty else { return .refused("Not sent. This phone's copy of \(e.name) is missing. Remove it from Composer and add it again.") }
            if data.count > ComposerUpload.maxBytes { return .refused("Not sent. \(e.name) is \(ComposerUpload.megabytes(data.count)); the house takes 100 MB at most. Use a shorter clip.") }
            do {
                _ = try await http.send(RequestPlan(origin: "composer", method: "POST", path: "api/media", query: ["id": e.id, "ext": ext], headers: ["content-type": "application/octet-stream"], body: data),
                                        idempotent: true, timeout: 600, cache: false)
                var u = uploaded; u[e.id] = data.count; uploaded = u; went += 1
            } catch let f as HTTPClient.Failure {
                let why: String
                switch f {
                case .unauthorized: why = "The composer key was refused (401). Load your config again."
                case .http(413): why = "\(e.name) is too large for the house (100 MB at most)."
                case .http(let c): why = "The house answered \(c) while taking \(e.name)."
                case .badAddress: why = f.message
                }
                return .refused("Not sent. " + why + (went > 0 ? " The \(went) already uploaded stay there; send again to carry on." : ""))
            } catch {
                return .refused("Not sent. The phone could not reach the house while uploading \(e.name)." + (went > 0 ? " The \(went) already uploaded stay there; send again to carry on." : " Send again when it can."))
            }
        }
        step = Step(text: "Sending the piece", done: todo.count, total: todo.count + 1)
        let body: [String: Any] = ["kind": "spec", "piece": name, "spec": ComposerSpec.emit(piece, assets: ComposerLibrary.shared.allAssets), "media": phone.map(\.id)]
        switch await ComposerOutbox.shared.send(body: body, model: model) {
        case .made(let id): return .sent(id: id, uploaded: went)
        case .queued(let why): return .queued(why)
        case .refused(let why):
            var u = uploaded; for e in phone { u[e.id] = nil }; uploaded = u   // a refusal may mean the house lost an upload: the next send puts them back
            return .refused(why)
        }
    }
}
