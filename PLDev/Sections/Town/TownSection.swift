import SwiftUI
import SpriteKit
import TipKit
import UserNotifications

/// Task Town, native (the web page `/town` on the gallery, drawn as the page draws it): the pixel street in SpriteKit with his baked
/// GlyphGuy, the page's header chips (TASKS, LIVE, LORE, the sky, the camera, the sound), the HUD and mini-map, the typed dialog, the
/// done-this-session row, and a list of the same town for VoiceOver and for reading.
@MainActor enum TownSection: PLSection {
    static let manifest = SectionManifest(id: "town", title: "Town", symbol: "building.2", needsKeys: ["vault"], needsOrigins: ["gallery"])
    static let state = TownModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(TownView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, let first = path.first, let room = TownRoom(id: first) { state.go(room) }
        return true
    }
    private static var indexed = false
    static func refresh(model: AppModel) async -> SectionRefresh {
        if !indexed { indexed = true; await TownSpotlight.index() }   // the rooms into Spotlight, once per launch
        await state.load(model: model)
        return SectionRefresh(badge: nil, notify: [])
    }
}

@MainActor @Observable final class TownModel {
    var feed: TownFeed?
    var error: String?
    var mode: TownMode = TownModel.savedMode()
    var sky: TownLight?          // nil = the sun decides (the chip reads SUN·DAY)
    var camFree = false
    var sound = false
    var dialog: String?
    var dialogTick = 0
    var showList = false
    var celebrate = 0

    @ObservationIgnored var scene: TownScene?
    @ObservationIgnored private var pending: TownRoom?
    @ObservationIgnored private let sounder = TownSound()

    private static func savedMode() -> TownMode { TownMode(rawValue: UserDefaults.standard.string(forKey: "town.mode") ?? "") ?? .tasks }

    var open: Int { (feed?.tasks ?? []).filter { $0.state != "done" }.count }
    var done: [TownFeed.Task] { (feed?.tasks ?? []).filter { $0.state == "done" } }
    var stale: Int? { if let a = feed?.age_min, a > 30 { return a } else { return nil } }
    var skyNow: TownLight { sky ?? TownSun.mode() }

    // MARK: the feed

    func load(model: AppModel) async {
        guard let http = model.http else { return }
        do {
            let f = try JSONDecoder().decode(TownFeed.self, from: try await http.send(RequestPlan(origin: "gallery", path: "api/town")))
            guard f.ok == true else { error = "The town sent nothing usable. Pull to try again."; return }
            feed = f; error = nil
            scene?.apply(f)
            TownGlanceWriter.publish(f)
        } catch {
            if let fail = error as? HTTPClient.Failure, fail == .unauthorized { self.error = "This town shows your tasks, and the gallery refused the key. Load your config again." }
            else { self.error = feed == nil ? "Could not reach the town. Pull to try again." : "Could not reach the town. Showing the last one." }
        }
    }

    // MARK: the screen's moves

    func talk(_ text: String) { dialog = text; dialogTick += 1 }

    func setMode(_ m: TownMode) {
        mode = m
        UserDefaults.standard.set(m.rawValue, forKey: "town.mode")
        scene?.townMode = m
        if sound { restartSound() }
    }

    func cycleSky() {
        let order: [TownLight?] = [nil, .day, .dusk, .night, .dawn]
        let i = order.firstIndex { $0 == sky } ?? 0
        sky = order[(i + 1) % order.count]
        scene?.lightAuto = sky == nil
        scene?.light = skyNow
        if sound { restartSound() }
    }

    func toggleCam() {
        camFree.toggle()
        scene?.camFree = camFree
        if !camFree { scene?.followSession() }
    }

    func toggleSound() {
        sound.toggle()
        if sound { sounder.start(dark: skyNow != .day) } else { sounder.stop() }
    }

    private func restartSound() { sounder.stop(); sounder.start(dark: skyNow != .day) }
    func stopSound() { if sound { sounder.stop(); sound = false } }

    /// A link, Spotlight or Siri asked for a room: a mode switches the town, a building walks the camera to its door.
    func go(_ room: TownRoom) {
        switch room {
        case .mode(let m): setMode(m)
        case .building(let id):
            if let scene { scene.focus(building: id); camFree = true } else { pending = room }
        }
    }

    /// The scene for a screen this wide: kept while the shape stays about the same (the web reloads when it changes by more than 40 px).
    func sceneFor(width: CGFloat) -> TownScene {
        if let s = scene, abs(s.size.width - width) < 40 { return s }
        let s = TownScene(size: CGSize(width: width, height: TownStreet.LH))
        s.townMode = mode; s.lightAuto = sky == nil; s.light = skyNow; s.camFree = camFree
        s.onTalk = { [weak self] in self?.talk($0) }
        s.onCamFree = { [weak self] in self?.camFree = true }
        s.onCelebrate = { [weak self] in self?.celebrate += 1 }
        if let f = feed { s.apply(f) }
        scene = s
        if let p = pending, case .building(let id) = p { s.focus(building: id); camFree = true; pending = nil }
        return s
    }
}

struct TownView: View {
    let model: AppModel
    @Bindable var state: TownModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase

    var body: some View {
        VStack(spacing: 8) {
            header
            chips
            if let a = state.stale {
                Text("FEED IS \(a) MIN OLD. THE PC BEAT MAY HAVE STOPPED. DON'T TRUST THIS TOWN.")
                    .font(TownInk.px(9)).foregroundStyle(TownInk.text).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(TownInk.warn)
            }
            if let e = state.error, state.feed != nil {
                Text(e).font(TownInk.px(9)).foregroundStyle(TownInk.gold).frame(maxWidth: .infinity, alignment: .leading)
            }
            street
            if !state.done.isEmpty { doneRow }
            TipView(TownDragTip()).tipBackground(TownInk.panel)
        }
        .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)
        .townScreen()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())   // the left-edge swipe home still works with the bar hidden
        .sensoryFeedback(PLHaptic.select, trigger: state.mode)
        .sensoryFeedback(PLHaptic.select, trigger: state.dialogTick)
        .sensoryFeedback(PLHaptic.success, trigger: state.celebrate)
        .sheet(isPresented: $state.showList) { TownListSheet(model: model, state: state) }
        .task {
            while !Task.isCancelled {   // the web polls every 10 s; so does this, only while it is on screen
                await state.load(model: model)
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; state.scene?.isPaused = false }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; state.scene?.isPaused = true; state.stopSound() }
        .onChange(of: phase) { _, p in state.scene?.isPaused = p != .active }
    }

    // MARK: header: the way home, the name, the call count

    private var header: some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    Image("PLIcons/pl-mark").resizable().scaledToFit().frame(width: 28, height: 28)
                }
                .foregroundStyle(TownInk.gold).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Back to Home")
            Rectangle().fill(TownInk.gold).frame(width: 8, height: 8).shadow(color: TownInk.goldDeep, radius: 0, x: 2, y: 2)
            Text("TASK TOWN").font(TownInk.px(11, relativeTo: .headline)).foregroundStyle(TownInk.gold)
            if let c = state.feed?.live?.calls, c > 0 { Text("·\(c)").font(TownInk.px(8)).foregroundStyle(TownInk.cyan).contentTransition(.numericText()) }
            Spacer(minLength: 0)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TownMode.allCases) { m in
                    Button(m.rawValue.uppercased()) { state.setMode(m) }.buttonStyle(TownChipStyle(on: state.mode == m))
                        .accessibilityAddTraits(state.mode == m ? .isSelected : [])
                }
                Button(state.sky == nil ? "SUN·\(state.skyNow.rawValue.uppercased())" : state.skyNow.rawValue.uppercased()) { state.cycleSky() }
                    .buttonStyle(TownChipStyle(on: state.sky != nil)).accessibilityLabel("Sky: \(state.sky == nil ? "follows the sun, now " : "")\(state.skyNow.rawValue)")
                Button(state.camFree ? "CAM·FREE" : "CAM·AUTO") { state.toggleCam() }.buttonStyle(TownChipStyle(on: state.camFree))
                    .accessibilityLabel(state.camFree ? "Camera free. Tap to follow the session" : "Camera follows the session")
                Button(state.sound ? "SND" : "MUTE") { state.toggleSound() }.buttonStyle(TownChipStyle(on: state.sound))
                    .accessibilityLabel(state.sound ? "Sound on" : "Sound off")
                Button("LIST") { state.showList = true }.buttonStyle(TownChipStyle()).accessibilityLabel("The town as a list")
            }
            .padding(.trailing, 4).padding(.bottom, 3)
        }
        .scrollClipDisabled()
    }

    // MARK: the street: the scene, the HUD, the mini-map, the dialog

    private var street: some View {
        GeometryReader { geo in
            let w = max(150, min(TownStreet.width, TownStreet.LH * geo.size.width / max(1, geo.size.height)))
            let scene = state.sceneFor(width: w)
            ZStack(alignment: .top) {
                SpriteView(scene: scene, preferredFramesPerSecond: 30, options: [.ignoresSiblingOrder])
                    .accessibilityLabel("Task Town. \(state.open) tasks open, \(state.done.count) done. Use the List button to read the town.")
                VStack(spacing: 0) {
                    TownHUD(state: state)
                    TownMiniMap(scene: scene)
                    if state.mode == .live, let line = liveLine { Text(line).font(TownInk.px(8)).foregroundStyle(state.liveOn ? TownInk.cyan : TownInk.dim).lineLimit(1).padding(.horizontal, 4).padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading).background(TownInk.hud) }
                    if let d = state.dialog { TownDialog(text: d, reduceMotion: reduceMotion) { state.dialog = nil }.padding(4).transition(.opacity) }
                    Spacer(minLength: 0)
                }
                if state.feed == nil {
                    ZStack {
                        TownInk.ground
                        Text(state.error ?? "LOADING...").font(TownInk.px(10)).foregroundStyle(TownInk.gold).multilineTextAlignment(.center).padding(16)
                    }
                }
            }
            .overlay(Rectangle().strokeBorder(TownInk.panel, lineWidth: 3))
            .overlay(Rectangle().strokeBorder(TownInk.gold, lineWidth: 1).padding(-3))
            .animation(.snappy, value: state.dialog)
        }
        .padding(3)
    }

    private var liveLine: String? {
        guard let h = state.feed?.live?.hist, !h.isEmpty else { return nil }
        let words = h.prefix(8).map { TownStreet.kindLabel[$0.k ?? ""] ?? ($0.k ?? "").uppercased() }.joined(separator: " > ")
        return (state.liveOn ? "" : "IDLE ") + words
    }

    private var doneRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(state.done) { t in
                    Button { state.talk(TownScene.talkText(t)) } label: { Text("★ " + String((t.title ?? "").prefix(22)).uppercased()) }
                        .buttonStyle(TownChipStyle(on: false))
                }
            }
        }
    }
}

extension TownModel {
    /// The session made a call in the last 90 s (the web's `liveOn`).
    var liveOn: Bool { (feed?.live?.age_s ?? 999) < 90 }
}

/// The page's top strip: tasks open (a heart), tasks done (a star), the call count, and the light of the hour.
private struct TownHUD: View {
    let state: TownModel
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) { Image(systemName: "heart.fill").foregroundStyle(TownInk.red); Text("x\(state.open)").foregroundStyle(TownInk.text) }
            HStack(spacing: 4) { Image(systemName: "star.fill").foregroundStyle(TownInk.gold); Text("x\(state.done.count)").foregroundStyle(TownInk.text) }
            if let c = state.feed?.live?.calls { Text("CALLS \(c)").foregroundStyle(TownInk.cyan).contentTransition(.numericText()) }
            Spacer(minLength: 0)
            Text(state.skyNow.rawValue.uppercased()).foregroundStyle(state.skyNow == .night ? Color(hex: 0x9cc4ff) : state.skyNow == .day ? TownInk.gold : Color(hex: 0xffb080))
        }
        .font(TownInk.px(9)).padding(.horizontal, 5).frame(height: 22).background(TownInk.hud)
        .accessibilityElement(children: .combine)
    }
}

/// The page's mini-map: the whole street, every person a dot, and the window the screen shows. A tap or a drag on it walks the camera there.
private struct TownMiniMap: View {
    let scene: TownScene
    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                Canvas { ctx, size in
                    let sc = size.width / TownStreet.width
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 20 / 255, green: 12 / 255, blue: 4 / 255).opacity(0.7)))
                    for b in TownStreet.buildings {
                        let c = b.lot ? Color(hex: 0x5a4630) : Color(uiColor: townHex(b.neon))
                        ctx.fill(Path(CGRect(x: b.x * sc, y: 2, width: max(1, b.w * sc), height: 2)), with: .color(c))
                    }
                    for d in scene.dots() { ctx.fill(Path(CGRect(x: d.x * sc, y: 5, width: 2, height: 4)), with: .color(Color(uiColor: d.color))) }
                    ctx.stroke(Path(CGRect(x: (scene.camX - scene.viewW / 2) * sc + 0.5, y: 0.5, width: scene.viewW * sc, height: size.height - 1)), with: .color(TownInk.text), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in scene.jump(toX: v.location.x / max(1, geo.size.width) * TownStreet.width) })
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

/// The page's dialog: a cream box with a dark rim, typed out at about 50 characters a second; a tap finishes it, a second tap closes it.
private struct TownDialog: View {
    let text: String
    let reduceMotion: Bool
    let close: () -> Void
    @State private var shown = 0

    var body: some View {
        Text(String(text.prefix(shown)))
            .font(TownInk.px(11, relativeTo: .callout)).foregroundStyle(TownInk.panel)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .padding(10)
            .background(TownInk.paper)
            .overlay(Rectangle().strokeBorder(TownInk.panel, lineWidth: 3))
            .overlay(alignment: .bottomTrailing) {
                if shown >= text.count { Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundStyle(TownInk.panel).padding(6).symbolEffect(.pulse) }
            }
            .contentShape(Rectangle())
            .onTapGesture { if shown < text.count { shown = text.count } else { close() } }
            .task(id: text) {
                shown = reduceMotion ? text.count : 0
                while shown < text.count { try? await Task.sleep(for: .milliseconds(20)); if Task.isCancelled { return }; shown += 1 }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityHint("Tap to close")
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - The town as a list: for VoiceOver, and for reading the whole of it

private struct TownListSheet: View {
    let model: AppModel
    let state: TownModel
    @Environment(\.dismiss) private var dismiss

    private func building(_ area: String?) -> String { TownStreet.target(area: area, kind: nil)?.label ?? (area ?? "?").uppercased() }

    private func panel<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(TownInk.px(9)).foregroundStyle(TownInk.gold)
            content()
        }
        .townPanel()
    }

    private func line(_ k: String, _ v: String, tint: Color = TownInk.text) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k.uppercased()).font(TownInk.px(8)).foregroundStyle(TownInk.dim)
            Spacer()
            Text(v).font(TownInk.px(11)).foregroundStyle(tint).multilineTextAlignment(.trailing)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let live = state.feed?.live {
                        panel("Now") {
                            line("Session", state.feed?.working == true ? "Working" : "Quiet", tint: state.feed?.working == true ? TownInk.gold : TownInk.text)
                            line("At", building(live.area))
                            if let t = live.tool { line("Tool", t) }
                            if let s = live.age_s { line("Last step", s < 90 ? "\(s) s ago" : "\(s / 60) min ago") }
                            if let c = live.calls { line("Calls", "\(c)") }
                        }
                        if let hist = live.hist, !hist.isEmpty {
                            panel("Recent path") {
                                ForEach(Array(hist.prefix(8).enumerated()), id: \.offset) { _, s in
                                    Text("\(building(s.a)) · \(TownStreet.kindLabel[s.k ?? ""] ?? (s.k ?? "").uppercased())").font(TownInk.px(11)).foregroundStyle(TownInk.text)
                                }
                            }
                        }
                    }
                    panel("Townspeople (the Roadmap)") {
                        let tasks = state.feed?.tasks ?? []
                        if tasks.isEmpty { Text("No one in town. The Roadmap is empty.").font(TownInk.px(10)).foregroundStyle(TownInk.dim) }
                        ForEach(tasks) { t in
                            Button { dismiss(); state.talk(TownScene.talkText(t)) } label: { line(t.title ?? "", (t.age_days ?? 0) >= 7 ? "STALE \(t.age_days ?? 0) D" : (t.state ?? ""), tint: t.state == "blocked" ? TownInk.red : TownInk.text) }
                                .buttonStyle(.plain)
                        }
                    }
                    if let v = state.feed?.visitors, !v.isEmpty {
                        panel("Visitors (cloud sessions)") { ForEach(v) { Text($0.name ?? "visitor").font(TownInk.px(11)).foregroundStyle(TownInk.text) } }
                    }
                    if let s = state.feed?.schedule, !s.isEmpty {
                        panel("Cloud schedule") {
                            ForEach(s, id: \.self) { r in
                                line(r.name ?? "routine", r.enabled == true ? (ISO8601DateFormatter().date(from: r.next ?? "").map { $0.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "America/Los_Angeles")!).weekday(.abbreviated).hour().minute()) } ?? "") : "paused")
                            }
                        }
                    }
                    panel("The street") {
                        ForEach(TownStreet.buildings.filter { !$0.lot }) { b in
                            Button { dismiss(); state.go(.building(b.id)) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.label).font(TownInk.px(10)).foregroundStyle(Color(uiColor: townHex(b.neon)))
                                    Text(b.note).font(.system(size: 12)).foregroundStyle(TownInk.text.opacity(0.8)).multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
            }
            .townScreen()
            .navigationTitle("The town").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
