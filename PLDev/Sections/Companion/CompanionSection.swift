import SwiftUI
import UIKit
import UserNotifications

/// Companion: his gratitude pet, ported from the R1 app (`pl-r1-pet`). Its own state on the phone: no network, no house service, no sync
/// (his 11-08 ruling: standalone). C1 of `Plans/SPEC — COMPANION ON PL DEV (S350).md`: rules, record, and the home scene.
@MainActor enum CompanionSection: PLSection {
    static let manifest = SectionManifest(id: "companion", title: "Companion", symbol: "heart.circle", needsKeys: [], needsOrigins: [])

    static func makeRoot(model: AppModel) -> AnyView { AnyView(CompanionView(store: .shared)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] {
        [ProbeModel.Item(id: "companion.rules", title: "Companion rules", detail: "Runs the ported R1 rules and the record against their own checks: the day turns at wake, meters fall one a day, growth at 21 and 66, a gratitude credits once, the record survives a reopen.", result: .untested, run: {
            let bad = CompanionRules.selfCheck() + CompanionStore.selfCheck()
            return bad.isEmpty ? .pass("All checks hold.") : .fail(bad.joined(separator: "; "))
        })]
    }
    static func settingsRows(model: AppModel) -> AnyView? { AnyView(CompanionSettingsRows(store: .shared)) }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh { SectionRefresh(badge: nil, notify: []) }
}

// MARK: sprites

/// One baked act: a strip sheet of `frames` cells, `cols` per row (his sprites, `assets/sprites/<who>/bone-blue/`).
struct CompanionSheet {
    let image: CGImage
    let fw: Int, fh: Int, cols: Int, frames: Int
    func frame(_ i: Int) -> CGImage? {
        let f = max(0, min(frames - 1, i))
        return image.cropping(to: CGRect(x: f % cols * fw, y: f / cols * fh, width: fw, height: fh))
    }
}

@MainActor enum CompanionSprites {
    private struct Act: Decodable { let file: String; let frame_w: Int; let frame_h: Int; let cols: Int; let frames: Int }
    private struct Book: Decodable { let acts: [String: Act] }
    private static var books: [String: Book] = [:]
    private static var cache: [String: CompanionSheet] = [:]

    static func sheet(_ who: String, _ act: String) -> CompanionSheet? {
        let key = who + "/" + act
        if let s = cache[key] { return s }
        if books[who] == nil, let u = Bundle.main.url(forResource: "companion-\(who)", withExtension: "json") ?? Bundle.main.url(forResource: "companion-\(who)", withExtension: "json", subdirectory: "Companion"),
           let d = try? Data(contentsOf: u) { books[who] = try? JSONDecoder().decode(Book.self, from: d) }
        guard let a = books[who]?.acts[act] else { return nil }
        let name = "companion-\(who)-" + (a.file as NSString).deletingPathExtension
        guard let u = Bundle.main.url(forResource: name, withExtension: "png") ?? Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Companion"),
              let img = UIImage(contentsOfFile: u.path)?.cgImage else { return nil }
        let s = CompanionSheet(image: img, fw: a.frame_w, fh: a.frame_h, cols: a.cols, frames: a.frames)
        cache[key] = s; return s
    }
}

// MARK: the scene

/// The pet in its state: shape, motion and light only, never a word for how it is (his S346 ruling).
struct CompanionScene: View {
    let store: CompanionStore
    var who: String? = nil       // the birth screen's preview
    private let clipMs = 3000.0  // 36 frames at 12 fps

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { ctx in
            let s = state(at: ctx.date)
            GeometryReader { g in
                ZStack {
                    Color.black
                    if let sheet = CompanionSprites.sheet(s.who, s.act), let cg = sheet.frame(s.frame) {
                        let k = CGFloat(max(1, min(8, Int(min(g.size.height * 0.8, g.size.width * 0.8) / CGFloat(max(sheet.fh, sheet.fw))))))
                        Image(decorative: cg, scale: 1).interpolation(.none).resizable()
                            .frame(width: CGFloat(sheet.fw) * k, height: CGFloat(sheet.fh) * k)
                            .rotationEffect(.degrees(s.lying ? 90 : 0))
                            .saturation(s.saturation)
                            .position(x: g.size.width / 2, y: g.size.height - (s.lying ? CGFloat(sheet.fw) * k / 2 : CGFloat(sheet.fh) * k / 2) - 18)
                    }
                    Color.black.opacity(1 - s.light).allowsHitTesting(false)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your companion")
    }

    private struct S { var who: String; var act: String; var frame: Int; var light: Double; var lying: Bool; var saturation: Double }

    private func state(at date: Date) -> S {
        let r = store.record
        let who = who ?? r?.who ?? "him"
        let stage = r?.stage ?? "baby"
        let fps = CompanionRules.animationFps(r?.animationFps ?? 12)
        if r == nil { return S(who: who, act: "baby-clap", frame: CompanionRules.spriteFrame(elapsedMs: date.timeIntervalSince1970 * 1000, fps: fps, frames: 36), light: 1, lying: false, saturation: 1) }
        let now = CompanionStore.nowMs(date)
        let age = (date.timeIntervalSince(store.eventAt)) * 1000
        let clip = !store.event.isEmpty && age >= 0 && age < clipMs
        let sleep = store.asleep(date)
        let resting = CompanionRules.resting(nowMs: now, lastActive: store.lastActive)
        let glow = CompanionRules.meter(nowMs: now, lastMs: r?.lastGratitude ?? 0)
        var away = CompanionRules.absenceLight(nowMs: now, lastActive: store.lastActive)
        if resting { away = CompanionRules.breath(away, ms: now) }
        if clip && (store.event == "gratitude" || store.event == "held") { away = CompanionRules.wake(from: 0.6, sinceMs: age) }
        var act: String
        if clip {
            act = stage == "baby"
                ? CompanionRules.babyGesture(activeDays: store.activeDays, event: store.event, roll: store.eventAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1))
                : CompanionRules.acknowledgement(stage: stage, event: store.event)
        } else if sleep {
            act = stage == "adult" ? "adult-quiet" : stage == "teen" ? "teen-headtilt" : "baby-clap"   // R1: asleep it lies down in its idle pose
        } else {
            act = stage == "baby" ? "baby-crawl" : stage == "teen" ? "teen-headtilt" : (glow == 0 ? "adult-quiet" : "adult-rest")
        }
        var frame = CompanionRules.spriteFrame(elapsedMs: clip ? age : now, fps: fps, frames: 36)
        if !clip && (sleep && stage != "adult" || (glow == 0 || resting) && stage != "adult") { frame = 0 }   // R1: still when unfed, resting or asleep
        let light = min(sleep && !clip ? 0.55 : 1, away)
        return S(who: who, act: act, frame: frame, light: light, lying: sleep && !clip, saturation: 0.35 + 0.65 * Double(glow) / 4)
    }
}

/// A meter as four marks: full the day of the act, one fewer each day after.
struct CompanionMeter: View {
    let name: String
    let value: Int
    let tint: Color
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 6) {
            Text(name).font(.footnote).foregroundStyle(PLG.dim(scheme)).frame(width: 36, alignment: .leading)
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(i < value ? tint : PLG.line(scheme)).frame(height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(value) of 4")
    }
}

// MARK: home

struct CompanionView: View {
    @Bindable var store: CompanionStore
    @State private var line = ""
    @FocusState private var typing: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if store.unreadable {
                VStack(spacing: 12) {
                    Text(store.error).foregroundStyle(PLG.ink(scheme)).multilineTextAlignment(.center)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(PLG.bg(scheme))
            } else if store.record == nil {
                birth
            } else {
                home
            }
        }
        .navigationTitle("Companion")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var birth: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Choose who keeps you company.").font(.title3).foregroundStyle(PLG.ink(scheme)).padding(.top, 24)
                HStack(spacing: 14) {
                    ForEach(["him", "her"], id: \.self) { w in
                        Button { _ = store.born(who: w, colours: ["bone-blue"]) } label: {
                            CompanionScene(store: store, who: w).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: PLG.radius))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(w == "him" ? "GlyphGuy" : "GlyphGirl")
                    }
                }
                if !store.error.isEmpty { Text(store.error).font(.footnote).foregroundStyle(PLG.red) }
            }.padding(16)
        }
        .background(PLG.bg(scheme))
    }

    private var home: some View {
        let now = CompanionStore.nowMs()
        let r = store.record!
        let today = store.day()
        let todays = r.gratitudes.filter { $0.day == today }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CompanionScene(store: store).frame(height: 320).clipShape(RoundedRectangle(cornerRadius: PLG.radius))
                VStack(spacing: 8) {
                    CompanionMeter(name: "Glow", value: CompanionRules.meter(nowMs: now, lastMs: r.lastGratitude), tint: PLG.gold)
                    CompanionMeter(name: "Pull", value: CompanionRules.meter(nowMs: now, lastMs: r.lastHeld), tint: PLG.teal)
                }
                VStack(alignment: .leading, spacing: 8) {
                    TextField("One thing you are grateful for", text: $line, axis: .vertical)
                        .lineLimit(1...4).focused($typing)
                        .padding(12).background(PLG.surface(scheme), in: RoundedRectangle(cornerRadius: 12))
                        .onChange(of: line) { _, v in if v.count > 240 { line = String(v.prefix(240)) } }
                    HStack {
                        Text("\(line.count)/240").font(.caption).monospacedDigit().foregroundStyle(PLG.dim(scheme))
                        Spacer()
                        Button("Keep it") {
                            if store.gratitude(line) { line = ""; typing = false; UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
                        }
                        .buttonStyle(.borderedProminent).tint(PLG.gold).frame(minHeight: 44)
                        .disabled(line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !store.error.isEmpty { Text(store.error).font(.footnote).foregroundStyle(PLG.red) }
                }
                if !todays.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(todays.reversed()) { g in
                            Text(g.text).plHand(20, relativeTo: .body).foregroundStyle(PLG.ink(scheme))   // his own words: his hand
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PLG.bg(scheme))
    }
}

/// Settings: the one way to start over (the record is never deleted any other way).
struct CompanionSettingsRows: View {
    @Bindable var store: CompanionStore
    @State private var confirm = false
    var body: some View {
        Button("Start the companion over", role: .destructive) { confirm = true }
            .disabled(store.record == nil && !store.unreadable)
            .confirmationDialog("Start over? Every gratitude and desire in the Companion is removed from this phone.", isPresented: $confirm, titleVisibility: .visible) {
                Button("Start over", role: .destructive) { store.reset() }
                Button("Keep it", role: .cancel) {}
            }
    }
}
