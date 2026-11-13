import Foundation
import Observation
import SwiftUI
import UIKit

/// Sync with the laptop: the port of `src/sync.js`. Works (picture, name, stack), the Daily Mark days and the Mine brushes travel both ways
/// through pl-cron's paint door. A work changed on one side is pulled or pushed; a work changed on BOTH sides is never overwritten, the
/// other copy arrives as "<name> (other device)". Study sessions never leave the device they were made on.
@MainActor @Observable final class NativeSync {
    static let shared = NativeSync()
    var state = "Not connected"
    var detail = ""
    var last: Date?
    var running = false
    var failed = false
    @ObservationIgnored private var again = false
    @ObservationIgnored private var timer: Task<Void, Never>?

    /// A save happened: sync soon, but not on every stroke (20 s after the last change, the laptop's rule).
    func changed(model: AppModel, canvas: NativeCanvasModel) async {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self else { return }
            await self.run(model: model, canvas: canvas)
        }
    }

    func run(model: AppModel, canvas: NativeCanvasModel?) async {
        guard let http = model.http, model.config?.key("paintSync") != nil else { state = "Not connected"; detail = "The sync key comes with your config."; return }
        if running { again = true; return }
        if let c = canvas, c.live != nil { again = true; return }
        running = true; failed = false; state = "Syncing"
        canvas?.saveNow()
        defer { running = false; if again { again = false; Task { await self.run(model: model, canvas: canvas) } } }
        do {
            var sum = Summary()
            try await syncWorks(http, canvas: canvas, &sum)
            // the days he drew: the larger count per day wins
            let daily = try await file(http, "daily.json")
            let remoteDays = ((daily as? [String: Any])?["days"] as? [String: Int]) ?? [:]
            var merged = remoteDays
            for (k, v) in NativeDaily.days { merged[k] = max(merged[k] ?? 0, v) }
            NativeDaily.merge(remoteDays)
            if NSDictionary(dictionary: merged) != NSDictionary(dictionary: remoteDays) { try await put(http, "daily.json", ["v": 1, "days": merged]) }
            // the Mine brushes: a brush on one side arrives on the other, the newer edit wins
            let mine = try await file(http, "mine.json")
            let remoteMine = ((mine as? [String: Any])?["brushes"] as? [[String: Any]]) ?? []
            let took = NativeMine.merge(remote: remoteMine)
            let outBrushes = NativeMine.brushes.map { $0.dictionary() }
            let remoteIDs = Set(remoteMine.compactMap { $0["id"] as? String })
            let needPush = outBrushes.contains { !remoteIDs.contains($0["id"] as? String ?? "") } || took
            if needPush && !outBrushes.isEmpty { try await put(http, "mine.json", ["v": 1, "brushes": outBrushes]) }
            last = .now
            var bits: [String] = []
            if sum.pushed > 0 { bits.append("\(sum.pushed) sent") }
            if sum.pulled > 0 { bits.append("\(sum.pulled) received") }
            if sum.forked > 0 { bits.append("\(sum.forked) kept as another copy") }
            if sum.removed > 0 { bits.append("\(sum.removed) removed") }
            state = "Up to date"; detail = bits.joined(separator: ", ")
            if let c = canvas, let id = c.workID, !NativeStore.loadIndex().list.contains(where: { ($0["id"] as? String) == id }) {
                if let other = NativeStore.loadIndex().list.first?["id"] as? String { c.open(id: other) } else { c.delete(id: id) }
            }
            canvas?.onChange?()
        } catch let e as HTTPClient.Failure {
            failed = true
            state = e == .unauthorized ? "The key was refused" : "Sync failed"; detail = e.message
        } catch let e as URLError {
            failed = true; state = "Offline"; detail = e.code == .notConnectedToInternet ? "It will try again when the phone is back online." : e.localizedDescription
        } catch let e as WorkFileError {
            failed = true; state = "Sync failed"; detail = e.why
        } catch { failed = true; state = "Sync failed"; detail = "\(error.localizedDescription)" }
    }

    struct Summary { var pushed = 0, pulled = 0, forked = 0, removed = 0 }

    // MARK: the door

    private func get(_ http: HTTPClient, _ path: String, timeout: TimeInterval = 60) async throws -> Data {
        try await http.send(RequestPlan(origin: "paint", path: path), timeout: timeout, cache: false)
    }
    private func file(_ http: HTTPClient, _ name: String) async throws -> Any? {
        do { return try JSONSerialization.jsonObject(with: try await get(http, "file/\(name)")) }
        catch let e as HTTPClient.Failure { if e == .http(404) { return nil }; throw e }
    }
    private func put(_ http: HTTPClient, _ name: String, _ obj: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: obj)
        _ = try await http.send(RequestPlan(origin: "paint", method: "PUT", path: "file/\(name)", headers: ["Content-Type": "application/json", "X-Updated": String(Int(Date().timeIntervalSince1970 * 1000))], body: body), idempotent: true, timeout: 60, cache: false)
    }
    private func post(_ http: HTTPClient, _ path: String, _ obj: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: obj)
        _ = try await http.send(RequestPlan(origin: "paint", method: "POST", path: path, headers: ["Content-Type": "application/json"], body: body), idempotent: true, timeout: 60, cache: false)
    }

    private func num(_ v: Any?) -> Double { (v as? Double) ?? Double(v as? Int ?? 0) }

    private func metaOf(_ e: [String: Any]) -> [String: Any] {
        ["name": e["name"] as? String ?? "Untitled", "w": e["w"] ?? 0, "h": e["h"] ?? 0, "updated": num(e["updated"]), "cu": e["cu"] != nil ? num(e["cu"]) : num(e["updated"]),
         "stack": e["stack"] as? String ?? "", "thumb": e["thumb"] as? String ?? ""]
    }

    private func pushWork(_ http: HTTPClient, _ e: inout [String: Any], blob: Bool) async throws {
        let id = e["id"] as? String ?? ""
        if blob {
            let raw = try Data(contentsOf: NativeStore.workURL(id))
            let gz = Gzip.compress(raw)
            _ = try await http.send(RequestPlan(origin: "paint", method: "PUT", path: "work/\(id)", headers: ["X-Gz": "1", "Content-Type": "application/octet-stream"], body: gz), idempotent: true, timeout: 180, cache: false)
        }
        try await post(http, "meta", ["id": id, "meta": metaOf(e)])
        e["sy"] = e["updated"]; e["scu"] = e["cu"] ?? e["updated"]; e["sn"] = (e["name"] as? String ?? "") + "|" + (e["stack"] as? String ?? "")
    }

    private func pullWork(_ http: HTTPClient, _ id: String, _ r: [String: Any], _ e: [String: Any]?, blob: Bool) async throws -> [String: Any] {
        if blob {
            let body = try await get(http, "work/\(id)", timeout: 180)
            let json = try Gzip.inflateIfNeeded(body)
            _ = try NativeDoc.validate(file: json)
            try json.write(to: NativeStore.workURL(id), options: .atomic)
        }
        var n = e ?? ["id": id]
        n["id"] = id; n["name"] = r["name"] as? String ?? "Untitled"; n["w"] = r["w"] ?? 0; n["h"] = r["h"] ?? 0
        n["thumb"] = (r["thumb"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? e?["thumb"]
        if let s = r["stack"] as? String, !s.isEmpty { n["stack"] = s } else { n.removeValue(forKey: "stack") }
        let ru = num(r["updated"])
        n["updated"] = ru; n["cu"] = r["cu"] != nil ? num(r["cu"]) : ru
        n["sy"] = ru; n["scu"] = n["cu"]; n["sn"] = (n["name"] as? String ?? "") + "|" + (n["stack"] as? String ?? "")
        return n
    }

    private func syncWorks(_ http: HTTPClient, canvas: NativeCanvasModel?, _ sum: inout Summary) async throws {
        let ix = try JSONSerialization.jsonObject(with: try await get(http, "index")) as? [String: Any] ?? [:]
        let rw = ix["works"] as? [String: [String: Any]] ?? [:]
        let rgone = ix["gone"] as? [String: Any] ?? [:]
        var L = NativeStore.loadIndex()
        // a rename or a stack change is a change, even though the picture is the same
        for k in L.list.indices {
            let e = L.list[k]
            let sn = (e["name"] as? String ?? "") + "|" + (e["stack"] as? String ?? "")
            if let was = e["sn"] as? String, was != sn, e["sy"] != nil { L.list[k]["updated"] = max(num(e["updated"]), Date().timeIntervalSince1970 * 1000) }
        }
        var ids = Set(L.list.compactMap { $0["id"] as? String })
        ids.formUnion(rw.keys); ids.formUnion(L.gone.keys); ids.formUnion(rgone.keys)
        for id in ids.sorted() {
            let ei = L.list.firstIndex { ($0["id"] as? String) == id }
            let e: [String: Any]? = ei.map { L.list[$0] }
            let r = rw[id]
            let lg = L.gone[id].map(num), rg = rgone[id].map(num)
            if let rg, e == nil || rg >= num(e?["updated"]) {
                if let ei, id != L.current { try? FileManager.default.removeItem(at: NativeStore.workURL(id)); L.list.remove(at: ei); sum.removed += 1 }
                else if let ei, id == L.current { L.list.remove(at: ei); try? FileManager.default.removeItem(at: NativeStore.workURL(id)); L.current = L.list.first?["id"] as? String; sum.removed += 1 }
                if e == nil { L.gone[id] = rg }
                continue
            }
            if let lg, r == nil || lg >= num(r?["updated"]) { try await post(http, "delete", ["id": id, "at": lg]); continue }
            if var ee = e, r == nil {
                if ee["blank"] as? Bool != false && ee["sy"] == nil { continue }   // a blank first page is not worth keeping on the other device
                try await pushWork(http, &ee, blob: true); L.list[ei!] = ee; sum.pushed += 1; continue
            }
            if e == nil, let r {
                let n = try await pullWork(http, id, r, nil, blob: true)
                L.list.insert(n, at: 0); sum.pulled += 1; continue
            }
            guard var ee = e, let r else { continue }
            let base = num(ee["sy"]), lch = num(ee["updated"]) > base, rch = num(r["updated"]) > base
            if !lch && !rch { continue }
            if lch && !rch {
                let blob = (ee["cu"] != nil ? num(ee["cu"]) : num(ee["updated"])) != num(ee["scu"])
                try await pushWork(http, &ee, blob: blob); L.list[ei!] = ee; sum.pushed += 1; continue
            }
            if !lch && rch {
                let blob = (r["cu"] != nil ? num(r["cu"]) : num(r["updated"])) != num(ee["scu"])
                let busy = canvas?.live != nil
                let n = try await pullWork(http, id, r, ee, blob: blob && !(busy && id == canvas?.workID))
                L.list[ei!] = n; sum.pulled += 1
                if id == L.current, blob, !busy { canvas?.reopenFromDisk(id: id) }
                continue
            }
            // changed on both sides: keep both
            let nid = NativeStore.newID()
            let body = try await get(http, "work/\(id)", timeout: 180)
            let json = try Gzip.inflateIfNeeded(body)
            try json.write(to: NativeStore.workURL(nid), options: .atomic)
            let now = Date().timeIntervalSince1970 * 1000
            var copy: [String: Any] = ["id": nid, "name": String(((r["name"] as? String ?? "Untitled") + " (other device)").prefix(40)), "w": r["w"] ?? 0, "h": r["h"] ?? 0, "updated": now, "cu": now, "blank": false]
            if let t = r["thumb"] as? String, !t.isEmpty { copy["thumb"] = t }
            L.list.insert(copy, at: 0)
            try await pushWork(http, &copy, blob: true); L.list[0] = copy
            if let k = L.list.firstIndex(where: { ($0["id"] as? String) == id }) { var cur = L.list[k]; try await pushWork(http, &cur, blob: true); L.list[k] = cur }
            sum.forked += 1; sum.pushed += 2
        }
        try NativeStore.saveIndex(L)
    }
}

// MARK: gzip

extension Gzip {
    /// gzip is a 10-byte header, a raw deflate stream, the CRC-32 and the length. Apple's `.zlib` writes the raw deflate stream.
    static func compress(_ d: Data) -> Data {
        guard let z = try? (d as NSData).compressed(using: .zlib) as Data else { return d }
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])
        out.append(z)
        var crc = crc32(d), size = UInt32(truncatingIfNeeded: d.count)
        out.append(Data(bytes: &crc, count: 4))
        out.append(Data(bytes: &size, count: 4))
        return out
    }
    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        d.withUnsafeBytes { p in for b in p { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) } }
        return c ^ 0xFFFFFFFF
    }
}

extension NativeDoc {
    /// Checks that a file is a work without keeping its pixels (the size and the layers must be sane).
    static func validate(file: Data) throws -> Bool {
        guard let d = try? JSONSerialization.jsonObject(with: file) as? [String: Any], let ls = d["layers"] as? [[String: Any]], !ls.isEmpty else { throw WorkFileError(why: "This is not a PL Paint work.") }
        let w = d["w"] as? Int ?? 0, h = d["h"] as? Int ?? 0
        guard w >= 64, h >= 64, w * h <= 16_777_216 else { throw WorkFileError(why: "This work's size is outside what PL Paint holds.") }
        return true
    }
}

extension NativeCanvasModel {
    func reopenFromDisk(id: String) {
        guard live == nil, id == workID else { return }
        dirty = false
        open(id: id)
    }
    @discardableResult func duplicateWork(id: String) -> Bool {
        do {
            let nid = NativeStore.newID()
            try FileManager.default.copyItem(at: NativeStore.workURL(id), to: NativeStore.workURL(nid))
            var ix = NativeStore.loadIndex()
            guard var e = ix.list.first(where: { ($0["id"] as? String) == id }) else { return false }
            e["id"] = nid; e["name"] = String(((e["name"] as? String ?? "Untitled") + " copy").prefix(40)); e["updated"] = Date().timeIntervalSince1970 * 1000; e["cu"] = e["updated"]
            for k in ["sy", "scu", "sn", "stack"] { e.removeValue(forKey: k) }
            ix.list.insert(e, at: 0)
            try NativeStore.saveIndex(ix)
            onChange?()
            return true
        } catch { say("Not copied."); return false }
    }
}

// MARK: sheets

struct NativeSyncSheet: View {
    let model: AppModel
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    private let sync = NativeSync.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("State", value: sync.state)
                    if !sync.detail.isEmpty { Text(sync.detail).font(.footnote).foregroundStyle(.secondary) }
                    if let l = sync.last { LabeledContent("Last sync", value: l.formatted(.relative(presentation: .named))) }
                    LabeledContent("Works on this phone", value: "\(NativeStore.loadIndex().list.count)")
                    LabeledContent("Streak", value: "\(NativeDaily.streak) days")
                    Button { Task { await sync.run(model: model, canvas: canvas) } } label: { HStack { Text("Sync now"); Spacer(); if sync.running { ProgressView() } } }.disabled(sync.running)
                } footer: { Text("Works, the Daily Mark and your own brushes go both ways. A work changed on both sides is kept as two copies; nothing is overwritten.") }
                Section("This device") {
                    LabeledContent("Key", value: model.config?.key("paintSync") != nil ? "Set, from your config" : "Missing")
                }
            }
            .navigationTitle("Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A finished piece to /curate or the archive: the whole picture as a PNG, through the paint door's outbox. The PC files it.
struct NativeSendSheet: View {
    let model: AppModel
    let canvas: NativeCanvasModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var busy = false
    @State private var result: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Button { send("curate") } label: { Label("Send to Curate", systemImage: "square.stack") }.disabled(busy)
                    Button { send("archive") } label: { Label("Send to the Archive", systemImage: "archivebox") }.disabled(busy)
                } footer: { Text("Sends the whole picture as a PNG; if the background is hidden it stays transparent. It is filed on the PC at the next open. Publishing to the public archive stays your call.") }
                if let r = result { Section { ResultLine(text: r) } }
            }
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { title = canvas.name }
        }
        .presentationDetents([.medium])
    }

    private func send(_ dest: String) {
        guard let http = model.http, let d = canvas.doc else { result = "Not sent. Load your config first."; return }
        busy = true; result = "Sending…"
        canvas.saveNow()
        guard let png = d.flatPNG() else { busy = false; result = "Not sent. The picture could not be made."; return }
        let t = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : title
        let body: [String: Any] = ["title": t, "dest": dest, "w": d.w, "h": d.h, "png_b64": png.base64EncodedString()]
        Task {
            do {
                let data = try JSONSerialization.data(withJSONObject: body)
                _ = try await http.send(RequestPlan(origin: "paint", method: "POST", path: "send", headers: ["Content-Type": "application/json"], body: data), idempotent: false, timeout: 120, cache: false)
                result = dest == "curate" ? "Sent to Curate. It is filed on the PC at the next open." : "Sent to the Archive. It is stamped with the next PL number on the PC at the next open."
            } catch let e as HTTPClient.Failure { result = "Not sent. \(e.message)" }
            catch { result = "Not sent. The phone could not reach the door." }
            busy = false
        }
    }
}
