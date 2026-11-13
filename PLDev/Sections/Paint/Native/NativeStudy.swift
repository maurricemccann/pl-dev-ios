import Foundation
import Observation
import SwiftUI
import UIKit

/// The Study recorder (port of `study.js`): a record of how he draws, for learning his hand (Third Eye's hand modes, the hand model). The
/// Timelapse keeps the picture; this keeps the hand. Every stroke as the pen really moved (x, y, pressure, time, tilt), undo and redo, and
/// marks he adds by hand. Guided exercises (toolkit `study.json`) tag the strokes they ask for. Files are small chunks on this phone
/// (`study-<id>-<chunk>.json`, the session `study-<id>.json`, `study-index.json`); nothing leaves it unless he shares a session.
@MainActor @Observable final class NativeStudy {
    static let shared = NativeStudy()
    struct Exercise: Identifiable { let id: String; let name: String; let prompt: String; let target: Int; let learn: String }
    struct Session: Identifiable { let id: String; let label: String; let started: String; let strokes: Int; let ended: Bool }

    var on = false
    var strokes = 0
    var marks = 0
    var exercise: String?
    var counts: [String: Int] = [:]
    var label = ""
    var toast: String?
    @ObservationIgnored private var id = ""
    @ObservationIgnored private var t0 = Date()
    @ObservationIgnored private var events: [[String: Any]] = []
    @ObservationIgnored private var chunk = 0
    @ObservationIgnored private var started = ""
    @ObservationIgnored private var docInfo: [String: Any] = [:]

    static var exercises: [Exercise] {
        let o = (NativeToolkit.raw["study"] as? [String: Any])?["exercises"] as? [[String: Any]] ?? []
        return o.map { Exercise(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "", prompt: $0["prompt"] as? String ?? "", target: $0["target"] as? Int ?? 10, learn: $0["learn"] as? String ?? "") }
    }
    var current: Exercise? { Self.exercises.first { $0.id == exercise } }

    private var dir: URL {
        let u = NativeStore.dir.appendingPathComponent("study", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private func now() -> Int { Int(Date().timeIntervalSince(t0) * 1000) }
    private func log(_ ev: [String: Any]) {
        guard on else { return }
        var e = ev; e["t"] = now(); events.append(e)
        if events.count >= 60 { flush() }
    }
    private func flush() {
        guard !events.isEmpty else { return }
        let body: [String: Any] = ["v": 1, "id": id, "chunk": chunk, "events": events]
        let name = String(format: "study-%@-%04d.json", id, chunk)
        chunk += 1; events = []
        if let d = try? JSONSerialization.data(withJSONObject: body) { try? d.write(to: dir.appendingPathComponent(name), options: .atomic) }
    }

    func start(label l: String, canvas: NativeCanvasModel, exercise first: String?) {
        guard !on else { return }
        id = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String((0..<3).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        t0 = Date(); events = []; chunk = 0; strokes = 0; marks = 0; counts = [:]; label = l
        started = ISO8601DateFormatter().string(from: .now)
        let d = canvas.doc
        docInfo = ["w": d?.w ?? 0, "h": d?.h ?? 0, "name": canvas.name]
        on = true
        log(["k": "start", "doc": docInfo, "device": ["screen": [Int(UIScreen.main.bounds.width), Int(UIScreen.main.bounds.height)], "dpr": UIScreen.main.scale, "platform": "iOS", "model": UIDevice.current.model], "label": l, "exercises": Self.exercises.map(\.id)])
        if let first { setExercise(first) }
        flush(); writeIndex(ended: nil)
    }

    func stop() {
        guard on else { return }
        log(["k": "stop"]); flush(); writeIndex(ended: ISO8601DateFormatter().string(from: .now))
        on = false
        toast = "Study saved: \(strokes) strokes."
    }

    func setExercise(_ id: String) { exercise = id; log(["k": "ex", "id": id]) }
    func next() {
        let list = Self.exercises
        if let i = list.firstIndex(where: { $0.id == exercise }), i + 1 < list.count { setExercise(list[i + 1].id) }
    }
    func mark(_ text: String) {
        let t = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard on, !t.isEmpty else { return }
        marks += 1; log(["k": "mark", "text": t, "ex": exercise ?? ""]); toast = "Marked: \(t)"
    }
    func note(_ kind: String) { log(["k": kind]) }

    /// A finished stroke, from the pen's own points (before any assist or snap changed them).
    func stroke(_ s: NativeCanvasModel.Live, doc d: NativeDoc, canvas: NativeCanvasModel) {
        guard on, s.tool != .smudge else { return }
        strokes += 1
        let ex = exercise
        if let ex { counts[ex, default: 0] += 1 }
        let pts: [[Any]] = s.raw.map { q in
            var r: [Any] = [(q.x * 10).rounded() / 10, (q.y * 10).rounded() / 10, (q.p * 1000).rounded() / 1000, Int(q.t)]
            if let t = q.tilt { r.append(Int(t.0)); r.append(Int(t.1)) }
            return r
        }
        log(["k": "stroke", "ex": ex ?? "", "tool": s.tool.rawValue, "brush": s.brush.id, "size": s.size, "color": s.color, "op": s.op, "layer": d.layerID(s.layer),
             "snapped": s.snapped, "assist": canvas.assist, "sym": canvas.sym.rawValue, "guide": canvas.guide.rawValue, "pts": pts])
        if let ex, let cur = current, cur.id == ex, counts[ex] == cur.target {
            let list = Self.exercises
            if let i = list.firstIndex(where: { $0.id == ex }), i + 1 < list.count { toast = "\(cur.name) done. Next: \(list[i + 1].name)"; setExercise(list[i + 1].id) }
            else { toast = "All exercises done. Keep drawing, or stop the study." }
        }
    }

    private func writeIndex(ended: String?) {
        let endedV: Any = ended != nil ? ended! : NSNull()
        let meta: [String: Any] = ["v": 1, "id": id, "label": label, "started": started, "ended": endedV, "chunks": chunk, "strokes": strokes, "exercises": counts, "doc": docInfo, "marks": marks]
        if let d = try? JSONSerialization.data(withJSONObject: meta) { try? d.write(to: dir.appendingPathComponent("study-\(id).json"), options: .atomic) }
        var idx: [String: Any] = ["v": 1, "sessions": [[String: Any]]()]
        if let d = try? Data(contentsOf: dir.appendingPathComponent("study-index.json")), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { idx = o }
        var list = (idx["sessions"] as? [[String: Any]] ?? []).filter { ($0["id"] as? String) != id }
        list.append(meta); idx["sessions"] = list
        if let d = try? JSONSerialization.data(withJSONObject: idx) { try? d.write(to: dir.appendingPathComponent("study-index.json"), options: .atomic) }
    }

    // MARK: past sessions

    var sessions: [Session] {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("study-index.json")), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return (o["sessions"] as? [[String: Any]] ?? []).reversed().map {
            Session(id: $0["id"] as? String ?? "", label: $0["label"] as? String ?? "", started: $0["started"] as? String ?? "", strokes: $0["strokes"] as? Int ?? 0, ended: ($0["ended"] as? String) != nil)
        }
    }

    /// One session as a single file: its meta and every chunk of events in order.
    func bundle(_ sid: String) -> URL? {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("study-\(sid)-") }.sorted()
        var events: [Any] = []
        for n in names { if let d = try? Data(contentsOf: dir.appendingPathComponent(n)), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { events += o["events"] as? [Any] ?? [] } }
        var meta: [String: Any] = [:]
        if let d = try? Data(contentsOf: dir.appendingPathComponent("study-\(sid).json")), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { meta = o }
        meta["events"] = events
        guard let data = try? JSONSerialization.data(withJSONObject: meta) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("study-\(sid).json")
        try? data.write(to: url)
        return url
    }

    func delete(_ sid: String) {
        for n in ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []) where n.hasPrefix("study-\(sid)") { try? FileManager.default.removeItem(at: dir.appendingPathComponent(n)) }
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("study-index.json")), var o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        o["sessions"] = (o["sessions"] as? [[String: Any]] ?? []).filter { ($0["id"] as? String) != sid }
        if let nd = try? JSONSerialization.data(withJSONObject: o) { try? nd.write(to: dir.appendingPathComponent("study-index.json"), options: .atomic) }
    }
}

/// The bar under the toolbar while a study records: what to draw, how far along, next and stop.
struct NativeStudyBar: View {
    @Bindable var study = NativeStudy.shared
    @State private var marking = false
    @State private var note = ""
    var body: some View {
        if study.on {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(study.current.map { "\($0.name): \($0.prompt)" } ?? "Free study: draw as you normally do.").font(.caption).lineLimit(2)
                        Text(study.current.map { "\(min(study.counts[$0.id] ?? 0, $0.target)) of \($0.target)" } ?? "\(study.strokes) strokes").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    Button { marking = true } label: { Image(systemName: "flag") }.accessibilityLabel("Mark this moment")
                    Button { study.next() } label: { Image(systemName: "forward.end") }.accessibilityLabel("Next exercise")
                    Button { study.stop() } label: { Image(systemName: "stop.circle") }.accessibilityLabel("Stop the study")
                }
                if let t = study.toast { Text(t).font(.caption2).foregroundStyle(.secondary).onTapGesture { study.toast = nil } }
            }
            .padding(8).glassControl(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .alert("What did you just do?", isPresented: $marking) {
                TextField("A few words", text: $note)
                Button("Mark it") { study.mark(note); note = "" }
                Button("Cancel", role: .cancel) { note = "" }
            }
        }
    }
}

struct NativeStudySheet: View {
    let canvas: NativeCanvasModel
    @Bindable var study = NativeStudy.shared
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var share: URL?
    @State private var sessions: [NativeStudy.Session] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("State", value: study.on ? "Recording: \(study.strokes) strokes" : "Not recording")
                    if !study.on { TextField("A name for this session", text: $label) }
                    Button { if study.on { study.stop() } else { study.start(label: label, canvas: canvas, exercise: NativeStudy.exercises.first?.id); dismiss() } } label: {
                        Label(study.on ? "Stop the study" : "Start the study", systemImage: study.on ? "stop.circle" : "record.circle")
                    }
                } footer: { Text("Records how you draw: every stroke as the pen really moved, with pressure, tilt and timing. It stays on this iPhone unless you share a session.") }
                Section("Exercises") {
                    ForEach(NativeStudy.exercises) { e in
                        Button {
                            guard study.on else { return }
                            study.setExercise(e.id); dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) { Text(e.name); Text("Teaches: \(e.learn)").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Text(study.on ? "\(min(study.counts[e.id] ?? 0, e.target)) / \(e.target)" : "\(e.target)").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .tint(study.exercise == e.id ? Wallpaper.line : .primary)
                    }
                }
                if !sessions.isEmpty {
                    Section("Past sessions") {
                        ForEach(sessions) { s in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) { Text(s.label.isEmpty ? "Session" : s.label); Text("\(s.strokes) strokes\(s.ended ? "" : " · not closed")").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Button { share = study.bundle(s.id) } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(.plain)
                            }
                            .swipeActions { Button("Delete", role: .destructive) { study.delete(s.id); sessions = study.sessions } }
                        }
                    }
                }
            }
            .navigationTitle("Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: Binding(get: { share.map { StudyURL(url: $0) } }, set: { if $0 == nil { share = nil } })) { ShareSheet(items: [$0.url]) }
            .task { sessions = study.sessions }
        }
    }
    private struct StudyURL: Identifiable { let url: URL; var id: String { url.path } }
}
