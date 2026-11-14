import AVFoundation
import Network
import SwiftUI

/// GlyphBot's two doors, in the same postures as the web room and the R1 app.
/// The Oracle (ask, answered from the practice) goes through the console door (the PL DEV key). The interviewer writes his
/// own words into his record, so it has a door and a key of its own ("interview"), used only for turn, speak and state.
@MainActor enum GlyphBot {
    // MARK: the Oracle

    struct Passage: Codable, Hashable, Sendable { let text: String; let source: String; let score: Double }
    struct OracleReply: Decodable { let answer: String?; let passages: [Passage]?; let via: String?; let error: String? }

    /// Asks the Oracle. Throws when it cannot be reached, so the caller can answer from memory.
    static func ask(_ question: String, model: AppModel) async throws -> (answer: String, passages: [Passage], via: String) {
        let data = try await Console.post("api/oracle", ["question": question, "top_k": 4], model: model, timeout: 60)
        let r = try JSONDecoder().decode(OracleReply.self, from: data)
        if let e = r.error { throw Console.Problem.refused(e) }
        // the Oracle may send ten passages; four are kept, each cut short, so the offline store stays small
        let kept = (r.passages ?? []).prefix(4).map { Passage(text: String($0.text.prefix(400)), source: $0.source, score: $0.score) }
        return (r.answer ?? "", Array(kept), r.via ?? "oracle")
    }

    /// One turn into the record (idempotent on the id, so a retry is safe).
    static func sync(_ t: GlyphTurn, model: AppModel) async throws {
        try await Console.post("api/glyphbot-sync", ["id": t.id, "question": t.question, "answer": t.answer, "via": t.via, "asked_at": t.askedAt], model: model)
    }

    // MARK: the interviewer

    static func interviewReady(_ model: AppModel) -> Bool { model.config?.origin("interview") != nil && model.http != nil }

    struct Settings: Sendable {
        var boldness = "light"      // light, gentle, probing
        var targetMin = 0           // 0 = open
        var deep = false            // let the deeper model ask when an answer is rich
    }

    struct Reply: Decodable { let session_id: Int?; let reply: String?; let seat: String?; let domain: String?; let done: Bool?; let error: String?; let tier: String? }

    struct StateReply: Decodable, Sendable {
        struct Bank: Decodable, Sendable { let asked: Int?; let total: Int?; let next_round: String? }
        struct Recent: Decodable, Identifiable, Sendable { let id: Int; let answer: String; let at: String?; let domain: String?; let question: String? }
        let bank: Bank?; let coverage: [String: Int]?; let recent: [Recent]?
    }

    private static func client(_ model: AppModel) throws -> HTTPClient {
        guard let http = model.http, model.config?.origin("interview") != nil else { throw Problem.noInterviewKey }
        return http
    }

    enum Problem: LocalizedError {
        case noInterviewKey
        var errorDescription: String? { "The interviewer key is not in your config yet." }
    }

    /// One turn. His words reach this call only from the Send button; nothing else on the phone calls it with an answer.
    static func turn(session: Int?, text: String, domain: String?, settings: Settings, model: AppModel) async throws -> Reply {
        var body: [String: Any] = ["text": text, "settings": ["boldness": settings.boldness, "target_min": settings.targetMin, "deep": settings.deep]]
        if let session, session > 0 { body["session_id"] = session }
        if let domain, !domain.isEmpty { body["domain"] = domain }
        let data = try await client(model).send(RequestPlan(origin: "interview", method: "POST", path: "api/r1/interview/turn", headers: ["content-type": "application/json"],
                                                            body: try JSONSerialization.data(withJSONObject: body)), idempotent: false, timeout: 120)
        let r = try JSONDecoder().decode(Reply.self, from: data)
        if let e = r.error { throw Console.Problem.refused(e) }
        return r
    }

    static func state(model: AppModel) async throws -> StateReply {
        let data = try await client(model).send(RequestPlan(origin: "interview", path: "api/r1/interview/state"), timeout: 30)
        UserDefaults.standard.set(data, forKey: "glyphbot.state")
        return try JSONDecoder().decode(StateReply.self, from: data)
    }

    static func cachedState() -> StateReply? {
        UserDefaults.standard.data(forKey: "glyphbot.state").flatMap { try? JSONDecoder().decode(StateReply.self, from: $0) }
    }

    /// GlyphBot's own voice (Cloudflare's Aura), never his. 503 means the voice is offline.
    static func speak(_ text: String, model: AppModel) async throws -> Data {
        try await client(model).send(RequestPlan(origin: "interview", method: "POST", path: "api/r1/interview/speak", headers: ["content-type": "application/json"],
                                                 body: try JSONSerialization.data(withJSONObject: ["text": String(text.prefix(600))])), idempotent: false, timeout: 60)
    }

    static let domains = ["philosophy", "art-design", "process", "seeds", "archive", "business", "social-content", "world", "taste", "legacy", "origin"]

    static func domainTitle(_ d: String) -> String {
        switch d {
        case "art-design": return "Art and design"; case "social-content": return "Social content"; default: return d.capitalized
        }
    }

    static func seatTitle(_ s: String?) -> String {
        switch s { case "solomon": return "Solomon"; case "vessel": return "Vessel"; case "athena": return "Athena"; case "stranger": return "Stranger"; default: return "GlyphBot" }
    }

    static func seatSymbol(_ s: String?) -> String {
        switch s { case "solomon": return "scalemass"; case "vessel": return "text.quote"; case "athena": return "safari"; case "stranger": return "person.fill.questionmark"; default: return "bubble.left" }
    }

    /// What the Oracle's "via" means, in words.
    static func viaWords(_ via: String) -> String {
        if via.contains("on-device") { return "Written on this iPhone from the record" }
        if via.contains("offline") && via.contains("cached") { return "From memory, offline" }
        if via.contains("doctrine") { return via.contains("offline") ? "From the doctrine, offline" : "From the doctrine" }
        if via.contains("cached") { return "From memory" }
        return "From the practice"
    }
}

// MARK: - One turn, kept on the phone the moment it is asked

struct GlyphTurn: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var question: String
    var answer: String
    var via: String
    var passages: [GlyphBot.Passage]
    let askedAt: String      // ISO
    var synced: Bool
}

/// The offline store: a JSON file in the app's support folder (the web room keeps the same in IndexedDB).
/// Every turn is saved the instant it is asked; the answer and the synced flag fill in once a reply lands.
@MainActor @Observable final class GlyphBotStore {
    static let shared = GlyphBotStore()
    private(set) var turns: [GlyphTurn] = []     // newest first
    private let cap = 400

    private var fileURL: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        return dir.appendingPathComponent("glyphbot-turns.json")
    }

    private init() {
        if let url = fileURL, let d = try? Data(contentsOf: url), let t = try? JSONDecoder().decode([GlyphTurn].self, from: d) { turns = t }
    }

    func save(_ t: GlyphTurn) {
        if let i = turns.firstIndex(where: { $0.id == t.id }) { turns[i] = t } else { turns.insert(t, at: 0) }
        if turns.count > cap { turns = Array(turns.prefix(cap)) }
        persist()
    }

    /// Real Oracle answers only: a stock doctrine line given offline is never written into his record as an answer.
    var unsynced: [GlyphTurn] { turns.filter { !$0.synced && !$0.answer.isEmpty && !$0.via.hasPrefix("doctrine") && !$0.via.hasPrefix("on-device") } }   // a draft by the phone is never filed as the Oracle's answer

    func markSynced(_ ids: [String]) {
        for i in turns.indices where ids.contains(turns[i].id) { turns[i].synced = true }
        persist()
    }

    /// The most recent past turn whose question closely matches (a normalised substring either way), for answering offline.
    func cached(for question: String) -> GlyphTurn? {
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }.trimmingCharacters(in: .whitespaces) }
        let q = norm(question)
        guard !q.isEmpty else { return nil }
        return turns.first { t in
            guard !t.answer.isEmpty else { return false }
            let tq = norm(t.question)
            if tq == q { return true }
            // a near match only: the shorter must be most of the longer, so "love" never answers a long question about something else
            let short = min(tq.count, q.count), long = max(tq.count, q.count)
            return long > 0 && Double(short) / Double(long) >= 0.75 && (tq.contains(q) || q.contains(tq))
        }
    }

    /// Pushes every unsynced turn to the record. Best effort: what fails stays unsynced for the next time.
    func flush(model: AppModel) async {
        var done: [String] = []
        for t in unsynced.reversed() {
            do { try await GlyphBot.sync(t, model: model); done.append(t.id) } catch { break }
        }
        if !done.isEmpty { markSynced(done) }
    }

    private func persist() {
        guard let url = fileURL, let d = try? JSONEncoder().encode(turns) else { return }
        try? d.write(to: url, options: .atomic)
    }
}

// MARK: - The doctrine, bundled: the last line of defence when offline with nothing cached

enum GlyphDoctrine {
    private static let keyed: [(String, String)] = [
        ("curve", "The Curve is the seven-year daily mark-making practice, every line a repetition of the same gesture toward sovereignty."),
        ("mark", "The mark is not a signature. It is a position. Every line drawn is a philosophical claim about what the body knows."),
        ("truth", "The Three Truths are sequential: Prepared for luxury. You are in control of your reality. What persists in the mind becomes your reality."),
        ("law", "The Three Truths are not affirmations. They are causal mechanics. Each one activates the next. Preparation first, always."),
        ("first", "The first Truth is Preparation. It is the most misunderstood because it is the most demanding. To be prepared is to already inhabit what you are reaching for."),
        ("second", "The second Truth is Control. You are in control of your reality, not as a declaration of power, but as a statement of responsibility for what you build."),
        ("third", "The third Truth is Persistence. What persists in the mind becomes your reality. The practice is the application of this Truth, daily."),
        ("luxury", "Luxury is not excess. It is preparation, the material form of a mind already committed to its own expansion."),
        ("prepared", "Preparation is not readiness. It is inhabitation. To be prepared is to already live inside the thing you are working toward."),
        ("sovereign", "Sovereignty is earned through practice, not declared through possession. The archive is evidence. The practice is proof."),
        ("glyph", "Each glyph is a complete philosophical position, a condensed law made visible through repetition."),
        ("practice", "The practice does not produce the work. The practice IS the work. What accumulates is evidence, not output."),
        ("archive", "The archive is not a record of what was made. It is proof of a mind that did not stop."),
        ("garment", "The garment is not clothing. It is a philosophical document worn in shared space, a position made material."),
        ("codex", "The Codex is not a style guide. It is a constitution, the philosophical ground beneath every decision the brand makes."),
        ("congregation", "The congregation is not an audience. It is the group of people for whom the brand's doctrine is not inspiration but recognition."),
        ("defiance", "The Defiance is healing through the hurt: the work made under pressure that heals by being made, and reaches those carrying the same weight. Its mark is the Golden Mend."),
        ("kintsugi", "Kintsugi is the Golden Mend: the break repaired in gold, the brokenness shown rather than hidden. The flaw becomes the most valuable line."),
        ("control", "Control is not dominance. It is authorship. You are in control of your reality means you are responsible for what you build inside it."),
        ("persistence", "Persistence closes the loop: what you hold in mind long enough becomes what you inhabit."),
    ]
    private static let pool = [
        "The Three Truths are sequential: Prepared for luxury. You are in control of your reality. What persists in the mind becomes your reality.",
        "The Curve is the seven-year daily mark-making practice, every line a repetition of the same gesture toward sovereignty.",
        "Luxury is not excess. It is preparation, the material form of a mind already committed to its own expansion.",
        "The practice does not produce the work. The practice IS the work. What accumulates is evidence, not output.",
        "The archive is not a record of what was made. It is proof of a mind that did not stop.",
        "The body is the primary document. The garment extends that document into shared space.",
        "Doctrine is not inspiration. Inspiration fades. Doctrine is a load-bearing wall: it holds regardless of mood.",
        "The brand does not sell aspiration. It documents practice. The congregation understands the difference.",
        "Commercial work funds the infrastructure that sustains the practice. All three bodies of work are interdependent.",
        "What persists in the mind becomes your reality, not metaphorically, but mechanically. The practice is proof.",
    ]

    static func pick(_ question: String) -> String {
        let q = question.lowercased()
        if let hit = keyed.first(where: { q.contains($0.0) }) { return hit.1 }
        return pool.randomElement() ?? pool[0]
    }
}

// MARK: - Whether the phone is online

@MainActor @Observable final class GlyphBotNet {
    static let shared = GlyphBotNet()
    private(set) var online = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let up = path.status == .satisfied
            Task { @MainActor in
                let was = GlyphBotNet.shared.online
                GlyphBotNet.shared.online = up
                if up, !was { await GlyphBotStore.shared.flush(model: AppModel.shared) }   // back online: push the backlog
            }
        }
        monitor.start(queue: DispatchQueue(label: "glyphbot.net"))
    }
}

// MARK: - GlyphBot's own voice (its voice, not his)

@MainActor @Observable final class GlyphBotVoice: NSObject, AVAudioPlayerDelegate {
    static let shared = GlyphBotVoice()
    private(set) var speaking = false
    private var player: AVAudioPlayer?

    func speak(_ text: String, model: AppModel) async -> String? {
        stop()
        do {
            let data = try await GlyphBot.speak(text, model: model)
            try PLAudio.speaking()
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            guard p.play() else { return "The voice would not play." }
            player = p; speaking = true
            return nil
        } catch let f as HTTPClient.Failure where f == .http(503) { return "GlyphBot's voice is offline right now." }
        catch { return "The voice would not load. \(plainSentence(error))" }
    }

    func stop() { player?.stop(); player = nil; if speaking { PLAudio.release() }; speaking = false }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.speaking = false; self.player = nil; PLAudio.release() }
    }
}
