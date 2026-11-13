import CryptoKit
import Foundation
import Network
import SwiftUI

// Offline for every app (his ask 11-13: "all apps all pages … also offline modes"). One layer under every section:
// - every successful read (GET) is kept on the phone; when the network fails, the kept copy is served instead, and the app
//   says plainly that it is showing a saved copy and how old it is;
// - marks made in Curate and the Library while offline wait in an outbox and are sent, in order, when the connection is back.
// Nothing here holds a key: request bodies and answers only, in the app's own Caches folder.

enum OfflineCache {
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("pldev-offline", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func file(_ key: String) -> URL {
        dir.appendingPathComponent(SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined())
    }

    /// Set by the network watcher: true while the phone has no path at all (read without hopping actors).
    nonisolated(unsafe) static var offlineNow = false

    /// Forget config removes every saved copy with it (members' messages, the record, support mail must not outlive the config).
    static func clearAll() { try? FileManager.default.removeItem(at: dir); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }

    static func key(_ plan: RequestPlan) -> String {
        plan.origin + "|" + plan.path + "?" + plan.query.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    }

    /// Up to 20 MB a read (the library index is about 5 MB); larger answers are not kept.
    static func save(_ data: Data, for key: String) {
        guard data.count <= 20 << 20 else { return }
        try? data.write(to: file(key), options: .atomic)
    }

    static func load(_ key: String) -> (Data, Date)? {
        let f = file(key)
        guard let d = try? Data(contentsOf: f) else { return nil }
        let at = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return (d, at)
    }
}

/// Whether the phone is online, and the age of the oldest saved copy shown since it went offline.
@MainActor @Observable final class OfflineState {
    static let shared = OfflineState()
    private(set) var online = true
    private(set) var servedSince: Date?
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let up = path.status == .satisfied
            OfflineCache.offlineNow = !up
            Task { @MainActor in
                OfflineState.shared.online = up
                if up { OfflineState.shared.servedSince = nil; await MarkOutbox.flush(model: AppModel.shared); _ = await PracticeOutbox.flush(model: AppModel.shared) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "pldev.offline"))
    }

    nonisolated static func answeredLive() {
        Task { @MainActor in if shared.servedSince != nil { shared.servedSince = nil } }
    }

    nonisolated static func servedCopy(from date: Date) {
        Task { @MainActor in
            if let s = shared.servedSince { shared.servedSince = min(s, date) } else { shared.servedSince = date }
        }
    }
}

/// The line every screen shows while it is working from saved copies.
struct OfflineLine: View {
    @State private var state = OfflineState.shared
    var body: some View {
        if !state.online || state.servedSince != nil {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                if let s = state.servedSince { Text("Offline · showing what was saved ") + Text(s, format: .relative(presentation: .named)) }
                else { Text("Offline · showing saved copies") }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .glassEffect(.regular, in: Capsule())
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }
}

/// Curate and Library marks made offline: kept in order on the phone, sent when the connection is back.
@MainActor enum MarkOutbox {
    private static let key = "pldev.markOutbox"
    static var pending: [[String: String]] {
        get { (UserDefaults.standard.array(forKey: key) as? [[String: String]]) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func add(_ body: [String: String]) { pending.append(body) }

    private static var flushing = false

    /// Sends what waits, oldest first, one flush at a time (two at once could send one mark twice and drop the next).
    /// No network: stop and keep the rest in order. The gallery refusing a mark: count it as not saved and go on, so one bad
    /// mark never blocks the queue.
    static func flush(model: AppModel) async {
        guard !flushing, !pending.isEmpty, let http = model.http else { return }
        flushing = true; defer { flushing = false }
        let base = LibraryData.shared.base(model)
        while let body = pending.first {
            guard let data = try? JSONSerialization.data(withJSONObject: body) else { pending.removeFirst(); continue }
            do {
                _ = try await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/taste",
                                                    headers: ["content-type": "application/json", "Origin": base], body: data), idempotent: false)
                pending.removeFirst()
            } catch is URLError {
                return
            } catch {
                pending.removeFirst(); LibraryData.shared.notSaved += 1
            }
        }
    }
}
