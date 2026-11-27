import SwiftUI

/// The cable tour (his pick 11-26, "Cable tour only"): one tap in Settings walks PL DEV through every band's Daily look and the
/// main rooms, 6 seconds a stop, with a corner label, while the PC screenshots each stop (`.claude/scripts/pl-phone-tour.py`).
/// Nothing is saved: each band is a preview (RisingScale.previewTap, never written to his log), and every look setting the tour
/// touches is put back as it was when it ends: after the last stop, by Stop, or when the app leaves the screen.
@MainActor @Observable final class PhoneTour {
    static let shared = PhoneTour()
    struct Stop { let band: Band; let place: String; let link: DeepLink }

    /// The stops, in order: Home (with the Rising panel) for each band, then the rooms under Steady. Add a room by adding a line.
    static let rooms: [(id: String, path: [String])] = [
        ("practice", []), ("practice", ["trends"]), ("gate", []), ("paint", []), ("capture", []),
        ("composer", []), ("shop", []), ("glyphbot", []), ("calendar", []),
    ]
    static let stops: [Stop] = Band.allCases.map { Stop(band: $0, place: "Home", link: .home) }
        + rooms.map { r in Stop(band: .steady, place: ([r.id] + r.path).joined(separator: "/"), link: .section(id: r.id, path: r.path, query: [:])) }

    private(set) var label: String?   // nil = not running
    @ObservationIgnored private var saved: [String: Any] = [:]
    @ObservationIgnored private var run: Task<Void, Never>?
    @ObservationIgnored private var shownBand: Band?

    /// Only the keys the look and the check-in preview write; queues, caches and his data are never touched.
    nonisolated static func touched(_ key: String) -> Bool {
        ["pldev.style", "pldev.glass.", "pldev.mix.", "pldev.theme", "pldev.palette", "pldev.titleFace", "pldev.font", "pldev.motion",
         "pldev.tileStrength", "pldev.rising.last", "pldev.rising.follow", "pldev.rising.undone", "pldev.rising.drained",
         "pldev.rising.said", "pldev.rising.turn", "pldev.rising.stamp", "pldev.rising.firstSaid", "pldev.rising.returned"].contains { key.hasPrefix($0) }
    }

    func start(model: AppModel) {
        guard label == nil else { return }
        saved = UserDefaults.standard.dictionaryRepresentation().filter { Self.touched($0.key) }
        let ready = Set(model.sections.filter { $0.readiness.isReady }.map(\.id))
        let shown = Self.stops.filter { s in if case .section(let id, _, _) = s.link { return ready.contains(id) }; return true }
        label = "0/\(shown.count) starting"
        run = Task {
            for (i, s) in shown.enumerated() {
                if Task.isCancelled { break }
                label = "\(i + 1)/\(shown.count) \(s.band.title) · \(s.place)"
                if s.band != shownBand { await preview(s.band) }
                model.open(s.link)
                try? await Task.sleep(for: .seconds(6))
            }
            finish(model: model)
        }
    }

    func stop() { finish(model: AppModel.shared) }

    private func preview(_ band: Band) async {
        let d = UserDefaults.standard
        d.set(RisingScale.shiftDay(.now) + "/\(band.rawValue)", forKey: "pldev.rising.last")
        d.set(true, forKey: "pldev.rising.follow")
        d.removeObject(forKey: "pldev.rising.undone"); d.removeObject(forKey: "pldev.rising.drained")
        RisingScale.shared.previewTap(band)
        _ = await RisingScale.preset().apply()
        shownBand = band
    }

    /// Puts every touched key back as it was, drops the preview check-ins, re-applies his own colours and type, lands on Home.
    private func finish(model: AppModel) {
        guard label != nil else { return }
        run?.cancel(); run = nil; label = nil; shownBand = nil
        let d = UserDefaults.standard
        for k in d.dictionaryRepresentation().keys where Self.touched(k) && saved[k] == nil { d.removeObject(forKey: k) }
        for (k, v) in saved { d.set(v, forKey: k) }
        saved = [:]
        RisingScale.shared.endPreview()
        let kit = HouseKit.shared
        kit.paletteName = d.string(forKey: "pldev.palette") ?? "home-screen"
        kit.titleFace = d.string(forKey: "pldev.titleFace") ?? "v1"
        kit.apply()
        PLCarry.epoch.n += 1
        model.open(.home)
    }
}

/// The tour's corner label and Stop, over everything; leaving the app ends the tour.
struct PhoneTourOverlay: View {
    @State private var tour = PhoneTour.shared
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let label = tour.label {
                HStack(spacing: 8) {
                    Text(label).font(.caption2.monospacedDigit()).foregroundStyle(.white).lineLimit(1)
                    Button("Stop") { tour.stop() }.font(.caption.bold()).foregroundStyle(.white).frame(minWidth: 44, minHeight: 44)
                }
                .padding(.horizontal, 10)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(.leading, 8)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Tour, \(label)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: phase) { _, p in if p != .active { tour.stop() } }
    }
}
