import SwiftUI

/// The pl-os console's calls, from the phone. Every request goes to the config's "console" origin (pl-cron, signed with the
/// PL DEV key, which pl-cron accepts only for the console's own routes). Reads decode straight into the screen's types.
@MainActor enum Console {
    enum Problem: LocalizedError {
        case notSetUp, refused(String)
        var errorDescription: String? {
            switch self {
            case .notSetUp: return "The console key is not in your config yet."
            case .refused(let why): return why
            }
        }
    }

    static func get<T: Decodable>(_ path: String, _ type: T.Type, model: AppModel, query: [String: String] = [:], timeout: TimeInterval = 25) async throws -> T {
        guard let http = model.http else { throw Problem.notSetUp }
        let data = try await http.send(RequestPlan(origin: "console", path: path, query: query), timeout: timeout)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// A D1 read from the PL DEV door: { ok, data }.
    static func q<T: Decodable>(_ name: String, _ type: T.Type, model: AppModel) async throws -> T {
        try await get("api/pldev/q/\(name)", DataWrap<T>.self, model: model).data
    }

    /// A write. Throws with the server's own sentence when it says no.
    @discardableResult
    static func post(_ path: String, _ body: [String: Any] = [:], model: AppModel, method: String = "POST", timeout: TimeInterval = 30) async throws -> Data {
        guard let http = model.http else { throw Problem.notSetUp }
        let data: Data
        do {
            data = try await http.send(RequestPlan(origin: "console", method: method, path: path, headers: ["content-type": "application/json"],
                                                   body: try JSONSerialization.data(withJSONObject: body)),
                                       idempotent: false, timeout: timeout)
        } catch {
            throw Problem.refused(plainSentence(error))
        }
        if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], (o["ok"] as? Bool) == false {
            throw Problem.refused((o["error"] as? String) ?? (o["message"] as? String) ?? "The server said no.")
        }
        return data
    }

    /// A pl-cron job run on demand (the console's "run now" buttons): GET, long timeout, the reply's first line back.
    static func run(_ path: String, model: AppModel) async -> String {
        guard let http = model.http else { return Problem.notSetUp.localizedDescription }
        do {
            let d = try await http.send(RequestPlan(origin: "console", path: path), idempotent: false, timeout: 120, cache: false)   // a job run is never answered by an old copy
            if let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                return (o["message"] as? String) ?? (o["summary"] as? String) ?? ((o["ok"] as? Bool) == false ? "It reported a failure." : "Done.")
            }
            return "Done."
        } catch { return "It did not run: \(plainSentence(error))" }
    }
}

/// The PL DEV door's reply shape, { ok, data }.
struct DataWrap<T: Decodable>: Decodable { let data: T }

/// Shared bits for the console screens.
extension Date {
    /// "2026-11-13T05:15:00.000Z" or "2026-11-13 05:15:00" → a Date.
    static func pl(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] { f.dateFormat = fmt; if let d = f.date(from: s) { return d } }
        return nil
    }
}

/// "3 h ago" style, or the raw text when it is not a date.
struct Ago: View {
    let text: String?
    var body: some View {
        if let d = Date.pl(text) { Text(d, format: .relative(presentation: .named)) } else { Text(text ?? "") }
    }
}

/// A one-line result after an action, said plainly, that clears itself.
struct ResultLine: View {
    let text: String?
    var body: some View {
        if let text {
            Label(text, systemImage: text.hasPrefix("Not") || text.contains("failed") || text.contains("did not") ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// A button that asks before it acts: for anything that sends, publishes, or changes what the public sees.
struct ConfirmButton: View {
    let title: String
    let question: String
    var confirm: String? = nil
    var role: ButtonRole? = nil
    let action: () async -> Void
    @State private var asking = false
    var body: some View {
        Button(title, role: role) { asking = true }
            .confirmationDialog(question, isPresented: $asking, titleVisibility: .visible) {
                Button(confirm ?? title, role: role) { Task { await action() } }
                Button("Cancel", role: .cancel) {}
            }
    }
}

/// A screen that loads once, refreshes on pull, and shows a plain sentence when the read fails.
struct Loaded<T, Content: View>: View {
    let load: () async throws -> T
    @ViewBuilder let content: (T, @escaping () async -> Void) -> Content
    @State private var value: T?
    @State private var failure: String?

    init(load: @escaping () async throws -> T, @ViewBuilder content: @escaping (T, @escaping () async -> Void) -> Content) {
        self.load = load; self.content = content
    }

    var body: some View {
        Group {
            if let value { content(value, reload) }
            else if let failure {
                ScrollView {   // a scroll view under .refreshable, so "pull to try again" can really be pulled
                    ContentUnavailableView {
                        Label("Could not load", systemImage: "wifi.exclamationmark")
                    } description: { Text(failure) } actions: { Button("Try again") { Task { await reload() } } }
                    .padding(.top, 60)
                }
            }
            else { PLLoader().frame(maxWidth: .infinity, minHeight: 120) }
        }
        .plGround()
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        do { value = try await load(); failure = nil }
        catch { if value == nil { failure = plainSentence(error) } }
    }
}
