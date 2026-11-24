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
    static func refresh(model: AppModel) async -> SectionRefresh { CompanionStore.shared.scheduleNudge(); return SectionRefresh(badge: nil, notify: []) }
}

// MARK: sprites

/// One baked act: a strip sheet of `frames` cells, `cols` per row (his sprites, `assets/sprites/<who>/bone-blue/`).
struct CompanionSheet {
    let image: CGImage
    let fw: Int, fh: Int, cols: Int, frames: Int
    var ox = 0, oy = 0          // offset_in_160x224: where this strip sits in the shared cell
    func frame(_ i: Int) -> CGImage? {
        let f = max(0, min(frames - 1, i))
        return image.cropping(to: CGRect(x: f % cols * fw, y: f / cols * fh, width: fw, height: fh))
    }
}

@MainActor enum CompanionSprites {
    private struct Act: Decodable { let file: String; let frame_w: Int; let frame_h: Int; let cols: Int; let frames: Int; let offset_in_160x224: [Int]? }
    private struct Book: Decodable { let acts: [String: Act] }
    private struct Props: Decodable { let layers: [String: Act] }
    private static var books: [String: Book] = [:]
    private static var props: [String: Props] = [:]
    private static var cache: [String: CompanionSheet?] = [:]

    private static func url(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext) ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Companion")
    }
    private static func make(_ a: Act, _ name: String) -> CompanionSheet? {
        guard let u = url(name, "png"), let img = UIImage(contentsOfFile: u.path)?.cgImage else { return nil }
        let o = a.offset_in_160x224 ?? [0, 0]
        return CompanionSheet(image: img, fw: a.frame_w, fh: a.frame_h, cols: a.cols, frames: a.frames, ox: o.first ?? 0, oy: o.count > 1 ? o[1] : 0)
    }
    /// A wardrobe item baked for this act (`props/props.json`, key "item:act"), or nil when it has none.
    static func layer(_ who: String, _ item: String, _ act: String) -> CompanionSheet? {
        let key = who + "/prop/" + item + ":" + act
        if let s = cache[key] { return s }
        if props[who] == nil, let u = url("companion-\(who)-props", "json"), let d = try? Data(contentsOf: u) { props[who] = try? JSONDecoder().decode(Props.self, from: d) }
        let s = props[who]?.layers[item + ":" + act].flatMap { make($0, "companion-\(who)-prop-" + ($0.file as NSString).deletingPathExtension) }
        cache[key] = s; return s
    }

    static func sheet(_ who: String, _ act: String) -> CompanionSheet? {
        let key = who + "/" + act
        if let s = cache[key] { return s }
        if books[who] == nil, let u = url("companion-\(who)", "json"), let d = try? Data(contentsOf: u) { books[who] = try? JSONDecoder().decode(Book.self, from: d) }
        let s = books[who]?.acts[act].flatMap { make($0, "companion-\(who)-" + ($0.file as NSString).deletingPathExtension) }
        cache[key] = s; return s
    }
}

// MARK: the scene

/// The pet in its state: shape, motion and light only, never a word for how it is (his S346 ruling).
struct CompanionScene: View {
    let store: CompanionStore
    var who: String? = nil       // the birth screen's preview
    var tapForLights = false     // home only: a tap turns the lights out (and on)
    private let clipMs = 3000.0  // 36 frames at 12 fps

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { ctx in
            let s = state(at: ctx.date)
            GeometryReader { g in
                ZStack {
                    Color.black
                    if s.shine > 0 {   // his ruling 11-08: desires and Helds give the glow; a Held or a came-true swells it for 3 s
                        RadialGradient(colors: [PLG.gold.opacity(0.43 * s.shine), .clear], center: UnitPoint(x: 0.5, y: 0.75), startRadius: 0, endRadius: g.size.width * 0.55)
                    }
                    if s.who == "both" {
                        figure("him", s, s.frame, x: g.size.width / 4, room: g.size.width / 2, g)
                        figure("her", s, (s.frame + 7) % 36, x: g.size.width * 3 / 4, room: g.size.width / 2, g)
                    } else {
                        figure(s.who, s, s.frame, x: g.size.width / 2, room: g.size.width, g)
                    }
                    Color.black.opacity(1 - s.light).allowsHitTesting(false)
                }
            }
        }
        .lightsTap(tapForLights && store.record != nil) { store.lightsOut.toggle() }   // home only: elsewhere the scene takes no taps (his 11-19 "hard click" on the choose screen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your companion")
        .accessibilityAddTraits(tapForLights ? .isButton : [])
        .accessibilityHint(tapForLights ? "Turns the lights out or on" : "")
    }

    @ViewBuilder private func figure(_ who: String, _ s: S, _ frame: Int, x: CGFloat, room: CGFloat, _ g: GeometryProxy) -> some View {
        if let sheet = CompanionSprites.sheet(who, s.act), let cg = sheet.frame(frame) {
            let k = CGFloat(max(1, min(8, Int(min(g.size.height * 0.8, room * 0.8) / CGFloat(max(sheet.fh, sheet.fw))))))
            Image(decorative: cg, scale: 1).interpolation(.none).resizable()
                .frame(width: CGFloat(sheet.fw) * k, height: CGFloat(sheet.fh) * k)
                .overlay(alignment: .topLeading) {
                    ForEach(s.worn, id: \.self) { item in
                        if let L = CompanionSprites.layer(who, item, s.act), let lc = L.frame(frame) {
                            Image(decorative: lc, scale: 1).interpolation(.none).resizable()
                                .frame(width: CGFloat(L.fw) * k, height: CGFloat(L.fh) * k)
                                .offset(x: CGFloat(L.ox - sheet.ox) * k, y: CGFloat(L.oy - sheet.oy) * k)
                        }
                    }
                }
                .rotationEffect(.degrees(s.lying ? 90 : 0))
                .saturation(s.saturation)
                .position(x: x, y: g.size.height - (s.lying ? CGFloat(sheet.fw) * k / 2 : CGFloat(sheet.fh) * k / 2) - 18)
        }
    }

    private struct S { var who: String; var act: String; var frame: Int; var light: Double; var lying: Bool; var saturation: Double; var shine: Double = 0; var worn: [String] = [] }

    private func state(at date: Date) -> S {
        let r = store.record
        let who = who ?? r?.who ?? "him"
        let stage = store.shownStage
        let fps = CompanionRules.animationFps(r?.animationFps ?? 12)
        if r == nil { return S(who: who, act: "baby-clap", frame: CompanionRules.spriteFrame(elapsedMs: date.timeIntervalSince1970 * 1000, fps: fps, frames: 36), light: 1, lying: false, saturation: 1) }
        let now = CompanionStore.nowMs(date)
        let age = (date.timeIntervalSince(store.eventAt)) * 1000
        let clip = !store.event.isEmpty && age >= 0 && age < clipMs
        let sleep = store.lightsOut || store.asleep(date)
        let resting = CompanionRules.resting(nowMs: now, lastActive: store.lastActive)
        let glow = CompanionRules.meter(nowMs: now, lastMs: r?.lastGratitude ?? 0)
        var away = CompanionRules.absenceLight(nowMs: now, lastActive: store.lastActive)
        if resting { away = CompanionRules.breath(away, ms: now) }
        if clip && (store.event == "gratitude" || store.event == "held") { away = CompanionRules.wake(from: 0.6, sinceMs: age) }
        var act: String
        if clip {
            act = stage == "baby"
                ? CompanionRules.babyGesture(activeDays: store.shownDays, event: store.event, roll: store.eventAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1))
                : CompanionRules.acknowledgement(stage: stage, event: store.event)
        } else if sleep {
            act = stage == "adult" ? "adult-quiet" : stage == "teen" ? "teen-headtilt" : "baby-clap"   // R1: asleep it lies down in its idle pose
        } else {
            act = stage == "baby" ? "baby-crawl" : stage == "teen" ? "teen-headtilt" : (glow == 0 ? "adult-quiet" : "adult-rest")
        }
        var frame = CompanionRules.spriteFrame(elapsedMs: clip ? age : now, fps: fps, frames: 36)
        if !clip && (sleep && stage != "adult" || (glow == 0 || resting) && stage != "adult") { frame = 0 }   // R1: still when unfed, resting or asleep
        let light = min(sleep && !clip ? (store.lightsOut ? 0.15 : 0.55) : 1, away)
        var shine = sleep ? 0 : Double(CompanionRules.meter(nowMs: now, lastMs: r?.lastHeld ?? 0)) / 4
        if clip && (store.event == "held" || store.event == "real") { shine = max(shine, sin(.pi * age / clipMs)) }
        return S(who: who, act: act, frame: frame, light: light, lying: sleep && !clip, saturation: 0.35 + 0.65 * Double(glow) / 4, shine: shine, worn: who == nil || r != nil ? store.worn : [])
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
            Text(name).font(Font.pl(.footnote)).foregroundStyle(PLG.dim(scheme)).lineLimit(1).fixedSize().frame(minWidth: 44, alignment: .leading)   // his 8:07 AM screenshot: "Glow" wrapped at a large text size
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
        .onAppear { store.scheduleNudge() }
    }

    private var birth: some View { CompanionOpening(store: store) }

    private var home: some View {
        let now = CompanionStore.nowMs()
        let r = store.record!
        let today = store.day()
        let todays = r.gratitudes.filter { $0.day == today }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CompanionScene(store: store, tapForLights: true).frame(height: 320).clipShape(RoundedRectangle(cornerRadius: PLG.radius))
                VStack(spacing: 8) {
                    CompanionMeter(name: "Glow", value: CompanionRules.meter(nowMs: now, lastMs: r.lastGratitude), tint: PLG.gold)
                    CompanionMeter(name: "Pull", value: CompanionRules.meter(nowMs: now, lastMs: r.lastHeld), tint: PLG.teal)
                }
                VStack(alignment: .leading, spacing: 8) {
                    TextField("One thing you are grateful for", text: $line, axis: .vertical)
                        .lineLimit(1...4).focused($typing)
                        .padding(12).background(PLG.surface(scheme), in: RoundedRectangle(cornerRadius: 12 * PLStyle.radius))
                        .onChange(of: line) { _, v in if v.count > 240 { line = String(v.prefix(240)) } }
                    HStack {
                        Text("\(line.count)/240").font(Font.pl(.caption)).monospacedDigit().foregroundStyle(PLG.dim(scheme))
                        Spacer()
                        Button("Keep it") {
                            if store.gratitude(line) { line = ""; typing = false; UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
                        }
                        .buttonStyle(.borderedProminent).tint(PLG.gold).frame(minHeight: 44)
                        .disabled(line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !store.error.isEmpty { Text(store.error).font(Font.pl(.footnote)).foregroundStyle(PLG.red) }
                }
                VStack(spacing: 0) {
                    NavigationLink { CompanionDesiresView(store: store) } label: { row("Desires", "\(store.activeDesires) of 12") }
                    Divider().overlay(PLG.line(scheme))
                    NavigationLink { CompanionArchiveView(store: store) } label: { row("Archive", "") }
                }
                .background(PLG.surface(scheme), in: RoundedRectangle(cornerRadius: 12 * PLStyle.radius))
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

    private func row(_ title: String, _ detail: String) -> some View {
        HStack {
            Text(title).foregroundStyle(PLG.ink(scheme))
            Spacer()
            Text(detail).font(Font.pl(.footnote)).monospacedDigit().foregroundStyle(PLG.dim(scheme))
            Image(systemName: "chevron.right").font(Font.pl(.footnote)).foregroundStyle(PLG.dim(scheme))
        }
        .padding(.horizontal, 14).frame(minHeight: 48).contentShape(Rectangle())
    }
}

/// Desires: up to twelve active. Held once a practice day lights Pull; Came true asks first and plays the cheer; Archive keeps it in the record.
struct CompanionDesiresView: View {
    @Bindable var store: CompanionStore
    @State private var draft = ""
    @State private var confirmReal: Int?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let ds = store.record?.desires ?? []
        let active = ds.indices.filter { ds[$0].status == "active" }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CompanionScene(store: store).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: PLG.radius))
                if store.activeDesires < 12 {
                    TextField("Name a desire", text: $draft)
                        .padding(12).background(PLG.surface(scheme), in: RoundedRectangle(cornerRadius: 12 * PLStyle.radius))
                        .onChange(of: draft) { _, v in if v.count > 80 { draft = String(v.prefix(80)) } }
                        .submitLabel(.done).onSubmit(keep)
                    HStack {
                        Text("\(draft.count)/80").font(Font.pl(.caption)).monospacedDigit().foregroundStyle(PLG.dim(scheme))
                        Spacer()
                        Button("Keep desire", action: keep).buttonStyle(.borderedProminent).tint(PLG.gold).frame(minHeight: 44)
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    Text("Twelve desires held.").font(Font.pl(.footnote)).foregroundStyle(PLG.dim(scheme))
                }
                if !store.error.isEmpty { Text(store.error).font(Font.pl(.footnote)).foregroundStyle(PLG.red) }
                ForEach(active, id: \.self) { i in
                    let d = ds[i], level = store.desireLevel(ds[i])
                    VStack(alignment: .leading, spacing: 8) {
                        Text(d.name).plHand(22, relativeTo: .body).foregroundStyle(PLG.ink(scheme)).opacity(level == 2 ? 0.45 : level == 1 ? 0.65 : 1)
                        HStack(spacing: 8) {
                            Button("Held") { if store.held(i) { UIImpactFeedbackGenerator(style: .soft).impactOccurred() } }
                                .buttonStyle(.borderedProminent).tint(PLG.teal)
                            Button("Came true") { confirmReal = i }.buttonStyle(.bordered).tint(PLG.gold)
                            Spacer()
                            Button("Archive") { store.archive(i) }.buttonStyle(.bordered).tint(PLG.dim(scheme))
                        }
                        .frame(minHeight: 44)
                    }
                    .padding(12).background(PLG.surface(scheme), in: RoundedRectangle(cornerRadius: 12 * PLStyle.radius))
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PLG.bg(scheme))
        .navigationTitle("Desires").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(confirmReal.flatMap { ds.indices.contains($0) ? ds[$0].name : nil } ?? "Came true",
                            isPresented: Binding(get: { confirmReal != nil }, set: { if !$0 { confirmReal = nil } }), titleVisibility: .visible) {
            Button("Record it came true") {
                if let i = confirmReal, store.real(i, true) { UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() }
                confirmReal = nil
            }
            Button("Back", role: .cancel) { confirmReal = nil }
        }
    }

    private func keep() { if store.desire(draft) { draft = "" } }
}

/// The record: every desire that came true (with its undo) or was archived, then every gratitude, newest first. Nothing is ever deleted.
struct CompanionArchiveView: View {
    @Bindable var store: CompanionStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ds = store.record?.desires ?? [], gs = store.record?.gratitudes ?? []
        let closed = ds.indices.reversed().filter { ds[$0].status != "active" }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if gs.isEmpty && closed.isEmpty {
                    Text("The record begins with one line.").foregroundStyle(PLG.dim(scheme)).padding(.top, 24)
                }
                ForEach(closed, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ds[i].name).plHand(20, relativeTo: .body).foregroundStyle(PLG.ink(scheme))
                            Text(ds[i].status == "real" ? "Came true" : "Archived").font(Font.pl(.caption)).foregroundStyle(ds[i].status == "real" ? PLG.gold : PLG.dim(scheme))
                        }
                        Spacer()
                        if ds[i].status == "real" { Button("Undo") { store.real(i, false) }.buttonStyle(.bordered).frame(minHeight: 44) }
                    }
                }
                if !store.error.isEmpty { Text(store.error).font(Font.pl(.footnote)).foregroundStyle(PLG.red) }
                ForEach(gs.reversed()) { g in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.day).font(Font.pl(.caption)).monospacedDigit().foregroundStyle(PLG.dim(scheme))
                        Text(g.text).plHand(20, relativeTo: .body).foregroundStyle(PLG.ink(scheme))
                    }
                }
            }
            .padding(16)
        }
        .background(PLG.bg(scheme))
        .navigationTitle("Archive").navigationBarTitleDisplayMode(.inline)
    }
}

/// The R1 opening (PetView "intro" then "choose"): "psyched luxuries" in his hand fades in and out on black (4.4 s; a tap skips it),
/// then "choose a companion": GlyphGuy, GlyphGirl or both, the chosen one clapping above, and confirm.
struct CompanionOpening: View {
    let store: CompanionStore
    @State private var start = Date()
    @State private var choosing = false
    @State private var choice = "him"
    private func label(_ id: String) -> String { id == "him" ? "GlyphGuy" : id == "her" ? "GlyphGirl" : "both" }

    var body: some View {
        if choosing { choose } else { intro }
    }

    private var intro: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            let a = max(0, min(1, min((t - 0.6) / 1.2, (4.2 - t) / 1.0)))
            ZStack {
                Color.black.ignoresSafeArea()
                Text("psyched luxuries").plHand(34, relativeTo: .largeTitle).foregroundStyle(PLG.gold).opacity(a)
            }
            .onChange(of: t > 4.4) { _, done in if done { choosing = true } }
        }
        .contentShape(Rectangle())
        .onTapGesture { choosing = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("psyched luxuries")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Skips the opening")
    }

    private var choose: some View {
        let day = !CompanionRules.asleep(Date(), sleep: 360, wake: 900)
        return ScrollView {
            VStack(spacing: 14) {
                Text("choose a companion").plHand(30, relativeTo: .title).foregroundStyle(PLG.gold).padding(.top, 20)
                CompanionScene(store: store, who: choice).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: PLG.radius))
                ForEach(["him", "her", "both"], id: \.self) { id in
                    Button { choice = id; UISelectionFeedbackGenerator().selectionChanged() } label: {
                        Text(label(id)).plHand(28, relativeTo: .title2).foregroundStyle(choice == id ? PLG.gold : Color(hex: 0xefe6d2))
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(Color(hex: 0x1a1a1a), in: RoundedRectangle(cornerRadius: 24 * PLStyle.radius))
                            .overlay(RoundedRectangle(cornerRadius: 24 * PLStyle.radius).stroke(choice == id ? PLG.gold : .clear, lineWidth: 2))
                            .contentShape(RoundedRectangle(cornerRadius: 24 * PLStyle.radius))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(choice == id ? .isSelected : [])
                }
                Button {
                    if store.born(who: choice, colours: ["bone-blue"]) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                } label: {
                    Text("Confirm").font(Font.pl(.headline)).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent).tint(PLG.gold)
                if !store.error.isEmpty { Text(store.error).font(Font.pl(.footnote)).foregroundStyle(PLG.red) }
            }
            .padding(16)
        }
        .background((day ? Color(hex: 0x0F1D3A) : Color(hex: 0x080810)).ignoresSafeArea())   // the R1 sky: day blue, night near-black
    }
}

private extension View {
    /// A tap only where it belongs: off, the view takes no gesture at all, so a button around or under it gets every touch.
    @ViewBuilder func lightsTap(_ on: Bool, _ action: @escaping () -> Void) -> some View {
        if on { contentShape(Rectangle()).onTapGesture(perform: action) } else { self }
    }
}

/// Settings: the one way to start over (the record is never deleted any other way).
struct CompanionSettingsRows: View {
    @Bindable var store: CompanionStore
    @State private var confirm = false

    private func time(_ get: @escaping (CompanionRecord) -> Int, _ set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(get: {
            let m = store.record.map(get) ?? 0
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in set(CompanionRules.minutes(d, .current)) })
    }

    var body: some View {
        if let r = store.record {
            Picker("Companion", selection: Binding(get: { r.who }, set: { store.setWho($0) })) {
                Text("GlyphGuy").tag("him"); Text("GlyphGirl").tag("her"); Text("Both").tag("both")
            }
            DatePicker("Wakes", selection: time({ $0.wake }, { store.setTimes(wake: $0) }), displayedComponents: .hourAndMinute)
            DatePicker("Rests", selection: time({ $0.sleep }, { store.setTimes(sleep: $0) }), displayedComponents: .hourAndMinute)
            Toggle("One gratitude nudge a day", isOn: Binding(get: { r.nudge }, set: { store.setTimes(nudge: $0) }))
            if r.nudge {
                DatePicker("Nudge at", selection: time({ $0.nudgeTime }, { store.setTimes(nudgeTime: $0) }), displayedComponents: .hourAndMinute)
            }
            ForEach(CompanionRules.wardrobe.filter { store.shownDays >= $0.day }, id: \.id) { item in
                Toggle(item.label, isOn: Binding(get: { !(store.record?.off.contains(item.id) ?? false) }, set: { store.setWorn(item.id, $0) }))
            }
            VStack(alignment: .leading) {
                Text(store.previewDays.map { "Preview at day \($0)" } ?? "Preview growth (test hook, saves nothing)")
                Slider(value: Binding(get: { Double(store.previewDays ?? store.activeDays) }, set: { store.previewDays = Int($0) }), in: 0...70, step: 1)
                if store.previewDays != nil { Button("End the preview") { store.previewDays = nil } }
            }
        }
        Button("Start the companion over", role: .destructive) { confirm = true }
            .disabled(store.record == nil && !store.unreadable)
            .confirmationDialog("Start over? Every gratitude and desire in the Companion is removed from this phone.", isPresented: $confirm, titleVisibility: .visible) {
                Button("Start over", role: .destructive) { store.reset() }
                Button("Keep it", role: .cancel) {}
            }
    }
}
