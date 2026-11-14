import AVFoundation
import SwiftUI

/// The daily practice's calls. The practice Worker is open by his own ruling (no key), so the "practice" origin in the
/// config carries only an address. It answers bare arrays and a bare `null` for "nothing yet", so reads tolerate both.
@MainActor enum Practice {
    enum Problem: LocalizedError {
        case notSetUp, offline, refused(String)
        var errorDescription: String? {
            switch self {
            case .notSetUp: return "The practice address is not in your config yet."
            case .offline: return "Not saved. This iPhone is offline."
            case .refused(let why): return why
            }
        }
    }

    private static func http(_ model: AppModel) throws -> HTTPClient {
        guard let http = model.http, model.config?.origin("practice") != nil else { throw Problem.notSetUp }
        return http
    }

    static func get<T: Decodable>(_ path: String, _ type: T.Type, model: AppModel, query: [String: String] = [:], timeout: TimeInterval = 25) async throws -> T {
        let data = try await http(model).send(RequestPlan(origin: "practice", path: "api/" + path, query: query), timeout: timeout)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// A read that may come back as a bare `null` (no check-in yet today, no WOOP yet).
    static func getOrNil<T: Decodable>(_ path: String, _ type: T.Type, model: AppModel) async throws -> T? {
        let data = try await http(model).send(RequestPlan(origin: "practice", path: "api/" + path), timeout: 25)
        if String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "null" { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// A write with a JSON body. Throws with the server's own sentence when it says no.
    @discardableResult
    static func post(_ path: String, _ body: [String: Any] = [:], model: AppModel, method: String = "POST", timeout: TimeInterval = 60) async throws -> Data {
        let client = try http(model)
        let data: Data
        do {
            data = try await client.send(RequestPlan(origin: "practice", method: method, path: "api/" + path, headers: ["content-type": "application/json"],
                                                     body: try JSONSerialization.data(withJSONObject: body)),
                                         idempotent: false, timeout: timeout)
        } catch {
            if Self.isOffline(error) { throw Problem.offline }
            throw Problem.refused("Not saved. \(plainSentence(error))")
        }
        if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let why = o["error"] as? String { throw Problem.refused(why) }
        return data
    }

    /// Whether a failure means "no connection" (worth queueing) rather than "the server said no".
    static func isOffline(_ error: any Error) -> Bool {
        guard let u = error as? URLError else { return false }
        // not .timedOut: a post that timed out may have landed, and queueing it would send it twice
        return [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(u.code)
    }

    /// Words written without a connection wait on the phone and go when it returns. True when sent, false when queued.
    static func postQueued(_ path: String, _ body: [String: Any], model: AppModel) async throws -> Bool {
        do { try await post(path, body, model: model); return true }
        catch Problem.offline { PracticeOutbox.add(path: path, body: body); return false }
    }

    /// A POST of raw bytes (a photo, a recording); the Worker answers JSON.
    @discardableResult
    static func upload(_ path: String, _ bytes: Data, type: String, model: AppModel, query: [String: String] = [:]) async throws -> Data {
        do {
            return try await http(model).send(RequestPlan(origin: "practice", method: "POST", path: "api/" + path, query: query, headers: ["content-type": type], body: bytes),
                                              idempotent: false, timeout: 90)
        } catch { throw Problem.refused("Not saved. \(plainSentence(error))") }
    }

    /// The bytes behind any practice path (an affirmation clip, an uploaded photo).
    static func bytes(_ pathOrURL: String, model: AppModel) async throws -> Data {
        if pathOrURL.hasPrefix("http"), let url = URL(string: pathOrURL) { return try await URLSession.shared.data(from: url).0 }
        return try await http(model).send(RequestPlan(origin: "practice", path: pathOrURL.hasPrefix("/") ? String(pathOrURL.dropFirst()) : pathOrURL), timeout: 45)
    }

    /// The photo URL for a pin or an upload: practice paths are made absolute against the configured address, never shown.
    static func imageURL(_ s: String, model: AppModel) -> URL? {
        if s.hasPrefix("http") { return URL(string: s) }
        guard let base = model.config?.origin("practice")?.base else { return nil }
        return URL(string: base + (s.hasPrefix("/") ? String(s.dropFirst()) : s))
    }
}

// MARK: - What the Worker sends

struct PracticeLesson: Decodable, Sendable {
    struct Body: Decodable, Sendable { let day: Int; let title: String; let lesson: String; let applicationPrompt: String }
    let day: Int
    let lesson: Body
}

struct PracticeCheckin: Decodable, Sendable {
    let date: String?; let mood: String?; let story: String?; let gratitude: String?
    let story_shifted: String?; let morning_at: String?; let evening_at: String?
}

struct PracticeStreak: Decodable, Sendable {
    let completedOfLast7: Int; let practisedThisMonth: Int; let practisedTotal: Int
}

struct PracticeDesire: Decodable, Identifiable, Sendable, Equatable {
    let id: String; let date: String?; let module_day: Int?; let text: String; let created_at: String?
    var priority: String?; var completed_at: String?
}

struct PracticeWoop: Decodable, Sendable { let outcome: String?; let obstacle: String?; let if_text: String?; let then_text: String? }
struct PracticeDiagram: Decodable, Sendable { let trigger_text: String?; let behavior1: String?; let behavior2: String?; let outcome: String? }

struct PracticeHabit: Decodable, Identifiable, Sendable, Equatable {
    let id: String; let cue: String?; let response: String; let reward: String?
    var tickedToday: Bool; var week: [Bool]
}

struct PracticeLog: Decodable, Identifiable, Sendable { let id: String; let kind: String; let text: String; let created_at: String? }
struct PracticeNote: Decodable, Identifiable, Sendable { let id: String; let text: String; let created_at: String? }
struct PracticePin: Decodable, Identifiable, Sendable { let url: String; let alt: String?; var id: String { url } }
struct PracticeMessage: Decodable, Identifiable, Sendable { let id: String; let role: String; let text: String; let created_at: String? }
struct PracticeReframe: Decodable, Identifiable, Sendable { let id: String; let belief: String; let reframe: String; let created_at: String? }
struct PracticeSessionRow: Decodable, Identifiable, Sendable { let id: String; let date: String?; let duration_s: Int?; let intensity: Int; let desire_text: String?; let created_at: String? }
struct PracticeReview: Decodable, Identifiable, Sendable { let date: String; let worked: String?; let adjust: String?; let celebrate: String?; let ai_summary: String?; var id: String { date } }
struct PracticeTrend: Decodable, Identifiable, Sendable { let date: String; let mood: String?; let story: String?; let gratitude: String?; let story_shifted: String?; var id: String { date } }

/// A library line (an integer id, a clip in R2) or one of his own (id "c-<uuid>", its recording optional).
struct PracticeAffirmation: Decodable, Identifiable, Sendable {
    let key: String; let text: String; let audio: String?; let mine: Bool
    var id: String { key }
    private enum K: String, CodingKey { case id, text, audio, mine }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        if let n = try? c.decode(Int.self, forKey: .id) { key = String(n) } else { key = try c.decode(String.self, forKey: .id) }
        text = try c.decode(String.self, forKey: .text)
        audio = try c.decodeIfPresent(String.self, forKey: .audio)
        mine = (try c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
    }
}
struct PracticeAffirmations: Decodable, Sendable { let items: [PracticeAffirmation] }

struct PracticeBoardImages: Decodable, Sendable {
    struct Image: Decodable, Identifiable, Sendable { let url: String; let alt: String?; var id: String { url } }
    let images: [Image]
}

// MARK: - Clips: only recordings that already exist are ever played

/// Plays the pre-generated affirmation clips (his voice, made elsewhere) and his own recordings.
/// Nothing is synthesised here, and nothing falls back to another voice: no clip means text only.
@MainActor @Observable final class PracticeClips: NSObject, AVAudioPlayerDelegate {
    static let shared = PracticeClips()
    private(set) var playing: String?
    private var player: AVAudioPlayer?
    private var playStart: Date?   // when the clip began, so the minutes he listened can be written to Health (Settings, Mindful minutes)

    func toggle(_ key: String, path: String, model: AppModel) async -> String? {
        if playing == key { stop(); return nil }
        stop()
        do {
            let data = try await Practice.bytes(path, model: model)
            try PLAudio.speaking()
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            guard p.play() else { return "The clip would not play." }
            player = p; playing = key; playStart = .now
            return nil
        } catch { return "The clip would not load. \(plainSentence(error))" }
    }

    func stop() { writeMindful(); if player != nil { PLAudio.release() }; player?.stop(); player = nil; playing = nil; onFinish = nil }

    /// Listening to an affirmation is a practice session with a length: 20 seconds or more goes to Health as mindful minutes (when he turned it on).
    private func writeMindful() {
        guard let s = playStart else { return }
        playStart = nil
        let end = Date.now
        if end.timeIntervalSince(s) >= 20 { Task { await PLHealth.logMindful(start: s, end: end) } }
    }

    /// The player bar reads these on a timeline; nothing here is observed per frame.
    var position: TimeInterval { player?.currentTime ?? 0 }
    var length: TimeInterval { player?.duration ?? 0 }
    func seek(to t: TimeInterval) { player?.currentTime = max(0, min(t, player?.duration ?? 0)) }
    /// Plays the clip and calls `done` when it ends by itself (the entry screen fades out then).
    var onFinish: (() -> Void)?

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.writeMindful(); self.playing = nil; self.player = nil; PLAudio.release(); let f = self.onFinish; self.onFinish = nil; if flag { f?() } }
    }
}

// MARK: - The outbox: what he writes offline is kept on the phone and sent in order when the connection returns

@MainActor enum PracticeOutbox {
    private static let key = "practice.outbox"
    private struct Item: Codable { let path: String; let body: String }
    private static var items: [Item] {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    static var count: Int { items.count }

    /// Saved on the phone before anything is said to him.
    static func add(path: String, body: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: body), let s = String(data: d, encoding: .utf8) else { return }
        items.append(Item(path: path, body: s))
    }

    /// Sends what is waiting, oldest first. Offline keeps it all; a refusal (4xx) will never succeed, so it is dropped rather
    /// than blocking what is behind it. Returns how many went.
    @discardableResult
    static func flush(model: AppModel) async -> Int {
        guard let http = model.http, model.config?.origin("practice") != nil else { return 0 }
        var sent = 0
        while let first = items.first {
            do {
                _ = try await http.send(RequestPlan(origin: "practice", method: "POST", path: "api/" + first.path, headers: ["content-type": "application/json"],
                                                    body: Data(first.body.utf8)), idempotent: false, timeout: 60)
            } catch let f as HTTPClient.Failure {
                if case .http(let code) = f, (400..<500).contains(code) { items.removeFirst(); continue }
                break
            } catch { break }
            items.removeFirst(); sent += 1
        }
        return sent
    }
}
