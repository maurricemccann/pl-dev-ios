import Foundation
import Observation

/// What the app did, kept in memory: the last 40 lines on screen in Settings, and, only while Debug is on,
/// scrubbed events sent to the owner's own log address. Logging never throws and never blocks a caller.
@MainActor @Observable final class DebugLog {
    static let shown = 40

    private(set) var lines: [String] = []

    @ObservationIgnored private var buffer = DebugBuffer()
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    private struct Upload: Encodable {
        let app: String
        let device: String
        let events: [Wire]
    }
    /// The debug door's own field names (pl-cron src/debug.ts: t, level, kind, msg). 11-14: the app sent at/category/message,
    /// so every PL DEV event was stored blank; the buffer on the phone keeps its own shape, only the upload is translated.
    private struct Wire: Encodable {
        let t: Double, level: String, kind: String, msg: String
        init(_ e: DebugEvent) {
            t = (e.at.timeIntervalSince1970 * 1000).rounded()
            let c = e.category.lowercased()
            level = c.contains("error") || c.contains("fail") ? "error" : (c.contains("warn") ? "warn" : "info")
            kind = e.category; msg = e.message
        }
    }

    private var isOn: Bool { UserDefaults.standard.bool(forKey: "pldev.debug") }

    /// A random id made once on this install, so the log can tell two devices apart. It names nothing.
    private var device: String {
        let key = "pldev.deviceID"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let made = UUID().uuidString.lowercased()
        UserDefaults.standard.set(made, forKey: key)
        return made
    }

    /// Every message is scrubbed before it is kept, so a key or token never reaches the screen or the wire.
    func note(_ category: String, _ message: String) {
        let clean = Scrub.clean(message)
        let now = Date()
        lines.insert("\(now.formatted(date: .omitted, time: .standard)) [\(category)] \(clean)", at: 0)
        if lines.count > Self.shown { lines.removeLast(lines.count - Self.shown) }
        guard isOn else { return }
        buffer.add(DebugEvent(at: now, category: category, message: clean))
        scheduleFlush()
    }

    func clear() {
        lines.removeAll()
        _ = buffer.drain(max: DebugBuffer.cap)
    }

    /// Batches a burst of notes into one request, five seconds after the first.
    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await self?.flush()
        }
    }

    /// Sends what is waiting. A failure is dropped silently: logging about a failed log upload would loop.
    func flush() async {
        flushTask = nil
        let model = AppModel.shared
        guard isOn, let config = model.config, let http = model.http,
              config.origin("cron") != nil, let key = config.key("debug") else { return }
        let events = buffer.drain(max: 50)
        guard !events.isEmpty else { return }
        guard let body = try? JSONEncoder().encode(Upload(app: "pl-dev", device: device, events: events.map(Wire.init))) else { return }
        let plan = RequestPlan(origin: "cron", method: "POST", path: "api/debug", headers: ["Content-Type": "application/json"], body: body)
        // the debug key goes on last, over whatever key the address itself carries
        _ = try? await http.send(plan, idempotent: false, extraHeaders: ["Authorization": "Bearer " + key], timeout: 15)
    }
}
