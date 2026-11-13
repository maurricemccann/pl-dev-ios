import AVFoundation
import SwiftUI

/// The daily practice's calls. The practice Worker is open by his own ruling (no key), so the "practice" origin in the
/// config carries only an address. It answers bare arrays and a bare `null` for "nothing yet", so reads tolerate both.
@MainActor enum Practice {
    enum Problem: LocalizedError {
        case notSetUp, refused(String)
        var errorDescription: String? {
            switch self {
            case .notSetUp: return "The practice address is not in your config yet."
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
        } catch { throw Problem.refused("Not saved. \(plainSentence(error))") }
        if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let why = o["error"] as? String { throw Problem.refused(why) }
        return data
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

    func toggle(_ key: String, path: String, model: AppModel) async -> String? {
        if playing == key { stop(); return nil }
        stop()
        do {
            let data = try await Practice.bytes(path, model: model)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            guard p.play() else { return "The clip would not play." }
            player = p; playing = key
            return nil
        } catch { return "The clip would not load. \(plainSentence(error))" }
    }

    func stop() { player?.stop(); player = nil; playing = nil }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = nil; self.player = nil }
    }
}
