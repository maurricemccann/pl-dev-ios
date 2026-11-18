import UIKit
import RealityKit

/// Eyes for a session (his ask 11-18: "couldn't you get eyes through the debugger"). While PL World is open and Settings > Debug is on,
/// the app asks its own debug door every 4 s for a command a session queued (pl-cron src/debug.ts, Remote inspect) and answers it:
///   shot  -> a small JPEG (base64) of the 3D view exactly as his screen shows it
///   state -> fps, area and the debug readout
/// Fixed commands only; nothing from the wire is ever run as code. Off with Debug, so nothing leaves the phone otherwise.
@MainActor final class PLWEyes {
    private var task: Task<Void, Never>?
    private struct Cmds: Decodable { struct C: Decodable { let id: Int; let cmd: String }; let cmds: [C]? }
    private struct Answer: Encodable { let id: Int; let ok: Bool; let result: String }

    func start(engine: WorldEngine, state: @escaping @MainActor () -> String) {
        task?.cancel()
        task = Task { [weak engine] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard UserDefaults.standard.bool(forKey: "pldev.debug"), let engine else { continue }
                for c in await Self.poll() {
                    switch c.cmd {
                    case "shot":
                        if let s = await Self.shot(engine) { await Self.answer(c.id, true, s) } else { await Self.answer(c.id, false, "no frame") }
                    case "state": await Self.answer(c.id, true, state())
                    default: await Self.answer(c.id, false, "unknown command " + c.cmd)
                    }
                }
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    private static func door() -> (HTTPClient, String)? {
        let m = AppModel.shared
        guard let config = m.config, let http = m.http, config.origin("cron") != nil, let key = config.key("debug") else { return nil }
        return (http, key)
    }

    private static func poll() async -> [Cmds.C] {
        guard let (http, key) = door() else { return [] }
        let plan = RequestPlan(origin: "cron", method: "GET", path: "api/debug/cmd", query: ["app": "pl-dev", "device": ""])
        guard let d = try? await http.send(plan, idempotent: true, extraHeaders: ["Authorization": "Bearer " + key], timeout: 10, cache: false) else { return [] }
        return (try? JSONDecoder().decode(Cmds.self, from: d))?.cmds ?? []
    }

    private static func answer(_ id: Int, _ ok: Bool, _ result: String) async {
        guard let (http, key) = door(), let body = try? JSONEncoder().encode(Answer(id: id, ok: ok, result: result)) else { return }
        let plan = RequestPlan(origin: "cron", method: "POST", path: "api/debug/result", headers: ["Content-Type": "application/json"], body: body)
        _ = try? await http.send(plan, idempotent: false, extraHeaders: ["Authorization": "Bearer " + key], timeout: 15)
    }

    /// The door keeps 30,000 characters of a result, so the frame shrinks until its base64 fits.
    private static func shot(_ engine: WorldEngine) async -> String? {
        guard let view = engine.view else { return nil }
        let img: UIImage? = await withCheckedContinuation { k in view.snapshot(saveToHDR: false) { k.resume(returning: $0) } }
        guard let img, img.size.width > 0 else { return nil }
        for (w, q) in [(CGFloat(360), CGFloat(0.5)), (300, 0.4), (240, 0.35), (180, 0.3)] {
            let size = CGSize(width: w, height: (w * img.size.height / img.size.width).rounded())
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            let small = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
            if let s = small.jpegData(compressionQuality: q)?.base64EncodedString(), s.count < 29_500 { return s }
        }
        return nil
    }
}
