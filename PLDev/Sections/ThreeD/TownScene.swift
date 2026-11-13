import SwiftUI
import SpriteKit
import AVFoundation

/// The pixel town as a SpriteKit scene. One long street; the gold GlyphGuy walks to the building of each tool call; townspeople are
/// the Roadmap; orange visitors are cloud sessions on the dock; light follows the sun over the town.
enum TownMode: String, CaseIterable, Identifiable { case tasks = "Tasks", live = "Live", lore = "Lore"; var id: String { rawValue } }

@MainActor final class TownScene: SKScene {
    private let LH = TownStreet.LH
    private let streetNode = SKSpriteNode()
    private let skyNode = SKSpriteNode()
    private let nightWash = SKSpriteNode()
    private let cam = SKCameraNode()
    private let world = SKNode()
    private var gold: SKSpriteNode?
    private var people: [String: SKSpriteNode] = [:]
    private var ghostNodes: [SKSpriteNode] = []
    private var visitorNodes: [SKSpriteNode] = []
    private var target: CGFloat = 0
    private var facing = "down"
    private var clock: CGFloat = 0
    private var painted: (TownLight, Int)?
    private var lastUpdate: TimeInterval = 0
    private var lastCheck: CGFloat = 0
    private var dragged = false
    var lightAuto = true

    var light: TownLight = TownSun.mode()
    var camFree = false
    var townMode: TownMode = .tasks { didSet { applyMode() } }
    var onBuilding: (TownBuilding) -> Void = { _ in }
    var onPerson: (TownFeed.Task) -> Void = { _ in }
    var onLoreTap: () -> Void = {}
    private var feed: TownFeed?
    private var taskByNode: [String: TownFeed.Task] = [:]
    private var ghostRoutes: [[String]] = []

    override func didMove(to view: SKView) {
        backgroundColor = townHex("#120c06")
        anchorPoint = .zero
        addChild(world); addChild(cam); camera = cam
        skyNode.anchorPoint = .zero; skyNode.zPosition = -10; world.addChild(skyNode)
        streetNode.anchorPoint = .zero; streetNode.zPosition = 0
        world.addChild(streetNode)
        nightWash.anchorPoint = .zero; nightWash.zPosition = 50
        world.addChild(nightWash)
        cam.position = CGPoint(x: size.width / 2, y: LH / 2)
        repaint(force: true)
        Task { await TownSprites.bake(); self.spawnGold() }
    }

    // MARK: painting and light

    func repaint(force: Bool = false) {
        let bucket = Int(Date().timeIntervalSince1970 / 600)
        if !force, let p = painted, p.0 == light, p.1 == bucket { return }
        painted = (light, bucket)
        let img = TownPainter.street(mode: light)
        let t = SKTexture(image: img); t.filteringMode = .nearest
        streetNode.texture = t; streetNode.size = CGSize(width: TownStreet.width, height: LH)
        let st = SKTexture(image: TownPainter.sky(mode: light, width: TownStreet.width)); st.filteringMode = .nearest
        skyNode.texture = st; skyNode.size = CGSize(width: TownStreet.width, height: LH)
        skyNode.position = .zero
        nightWash.size = CGSize(width: TownStreet.width, height: LH)
        let wash: (UIColor, CGFloat) = { switch light { case .night: return (townHex("#0a1230"), 0.32); case .dusk: return (townHex("#ff7a3a"), 0.10); case .dawn: return (townHex("#ffb070"), 0.08); case .day: return (.clear, 0) } }()
        nightWash.color = wash.0; nightWash.colorBlendFactor = 1; nightWash.alpha = wash.1
    }

    // MARK: sprites

    private func sprite(_ tint: UIColor?, scale: CGFloat = 1) -> SKSpriteNode {
        let n = SKSpriteNode(texture: TownSprites.frames["down"], size: CGSize(width: 40 * scale, height: 56 * scale))
        n.anchorPoint = CGPoint(x: 0.5, y: 0)
        if let tint { n.color = tint; n.colorBlendFactor = 0.82 }
        return n
    }

    private func spawnGold() {
        guard gold == nil, TownSprites.frames["down"] != nil else { return }
        let g = sprite(townHex("#d9a02e"), scale: 1.1)
        g.zPosition = 20
        g.position = CGPoint(x: TownStreet.building("home")?.doorX ?? 60, y: LH - TownStreet.WALK + 6)
        target = g.position.x
        world.addChild(g); gold = g
        let tag = SKLabelNode(fontNamed: "Menlo-Bold"); tag.fontSize = 7; tag.fontColor = townHex("#ffe07a"); tag.position = CGPoint(x: 0, y: 66); tag.name = "tag"; g.addChild(tag)
        if let f = feed { apply(f) }
    }

    private func palette(_ s: String) -> UIColor {
        let pals = ["#2f4f9a", "#8a2222", "#2f6a2a", "#5e2f8a", "#a03a6a", "#1f6a6a", "#6a4a30", "#5a5a64"].map(townHex)
        return pals[townHash(s) % pals.count]
    }

    // MARK: the feed

    func apply(_ f: TownFeed) {
        feed = f
        if let live = f.live {
            let b = TownStreet.target(area: live.area, kind: live.kind)
            if let b, f.working == true || (live.age_s ?? 999) < 120 { target = b.doorX }
        }
        syncPeople(f)
        syncVisitors(f)
        ghostRoutes = (f.ghosts ?? []).prefix(3).compactMap { $0.p }
        applyMode()
    }

    private func syncPeople(_ f: TownFeed) {
        guard TownSprites.frames["down"] != nil else { return }
        let tasks = Array((f.tasks ?? []).prefix(24))
        let keep = Set(tasks.map { $0.id })
        for (k, n) in people where !keep.contains(k) { n.removeFromParent(); people[k] = nil; taskByNode[k] = nil }
        for t in tasks where people[t.id] == nil {
            let stale = (t.age_days ?? 0) >= 7
            let done = t.state == "done"
            let b = stale ? TownStreet.building("stale") : TownStreet.buildings.filter { !$0.lot }[townHash(t.title ?? t.id) % (TownStreet.buildings.count - 1)]
            let n = sprite(stale ? townHex("#9a1a12") : palette(t.title ?? t.id), scale: stale ? 1.25 : 0.9)
            n.name = "person:\(t.id)"; n.zPosition = 10
            n.position = CGPoint(x: (b?.doorX ?? 100) + CGFloat(townHash(t.id) % 40) - 20, y: LH - TownStreet.WALK + 4)
            let l = SKLabelNode(fontNamed: "Menlo-Bold"); l.fontSize = 6; l.fontColor = done ? townHex("#ffe07a") : .white
            l.text = (done ? "* " : "") + String((t.title ?? "").prefix(14)); l.position = CGPoint(x: 0, y: 56); l.name = "label"; n.addChild(l)
            world.addChild(n); people[t.id] = n; taskByNode[t.id] = t
            // a slow stroll near the building
            let home = n.position.x
            n.run(.repeatForever(.sequence([.moveTo(x: home + 22, duration: Double(4 + townHash(t.id) % 4)), .moveTo(x: home - 22, duration: Double(5 + townHash(t.id) % 4))])), withKey: "stroll")
        }
    }

    private func syncVisitors(_ f: TownFeed) {
        for n in visitorNodes { n.removeFromParent() }
        visitorNodes = []
        guard TownSprites.frames["down"] != nil else { return }
        let dock = TownStreet.building("dock")
        for (i, v) in (f.visitors ?? []).prefix(4).enumerated() {
            let n = sprite(townHex("#ff8a2a"), scale: 0.95)
            n.position = CGPoint(x: (dock?.x ?? 0) + 20 + CGFloat(i) * 22, y: LH - TownStreet.WALK + 4); n.zPosition = 12
            let l = SKLabelNode(fontNamed: "Menlo-Bold"); l.fontSize = 6; l.fontColor = townHex("#ffd0a0"); l.text = String((v.name ?? "cloud").prefix(12)); l.position = CGPoint(x: 0, y: 54); n.addChild(l)
            world.addChild(n); visitorNodes.append(n)
        }
    }

    private func applyMode() {
        for (_, n) in people { n.isHidden = townMode == .live }
        for n in ghostNodes { n.removeFromParent() }
        ghostNodes = []
        if townMode == .lore, TownSprites.frames["down"] != nil {
            for (i, route) in ghostRoutes.enumerated() {
                let n = sprite(townHex("#a8c8f0"), scale: 0.9); n.alpha = 0.6; n.zPosition = 9
                let stops = route.compactMap { TownStreet.target(area: $0, kind: nil)?.doorX }
                guard let first = stops.first else { continue }
                n.position = CGPoint(x: first, y: LH - TownStreet.WALK + 4)
                n.run(.repeatForever(.sequence(stops.map { SKAction.moveTo(x: $0, duration: 3.5 + Double(i)) })))
                world.addChild(n); ghostNodes.append(n)
            }
        }
    }

    // MARK: frame

    override func update(_ t: TimeInterval) {
        let dt = lastUpdate == 0 ? 0.016 : min(0.1, t - lastUpdate); lastUpdate = t
        clock += CGFloat(dt)
        if let g = gold {
            let dx = target - g.position.x
            let moving = abs(dx) > 1.5
            if moving { g.position.x += (dx > 0 ? 1 : -1) * min(abs(dx), 42 * CGFloat(dt)) }
            let face = moving ? (dx > 0 ? "right" : "left") : "down"
            if face != facing { facing = face; g.texture = TownSprites.frames[face] }
            g.position.y = LH - TownStreet.WALK + 6 + (moving ? abs(sin(clock * 9)) * 2.2 : 0)
            if let tag = g.childNode(withName: "tag") as? SKLabelNode, let f = feed {
                tag.text = f.working == true ? (TownStreet.kindLabel[f.live?.kind ?? ""] ?? "WORK") : ""
            }
        }
        if !camFree {
            let focus = townMode == .live ? (gold?.position.x ?? size.width / 2) : (gold?.position.x ?? size.width / 2)
            let want = clampCam(focus)
            cam.position.x += (want - cam.position.x) * 0.06
        } else { cam.position.x = clampCam(cam.position.x) }
        cam.position.y = LH / 2
        if clock - lastCheck > 30 { lastCheck = clock; light = lightAuto ? TownSun.mode() : light; repaint() }   // the sun moves, the clock hands move
    }

    private func clampCam(_ x: CGFloat) -> CGFloat { max(size.width / 2, min(TownStreet.width - size.width / 2, x)) }

    // MARK: touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { dragged = false }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let dx = t.location(in: self).x - t.previousLocation(in: self).x
        if abs(dx) > 0.5 { dragged = true; camFree = true }
        cam.position.x = clampCam(cam.position.x - dx)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, !dragged else { return }
        let p = t.location(in: world)
        for n in world.nodes(at: p) {
            if let name = n.name, name.hasPrefix("person:"), let task = taskByNode[String(name.dropFirst(7))] { onPerson(task); return }
            if let par = n.parent, let name = par.name, name.hasPrefix("person:"), let task = taskByNode[String(name.dropFirst(7))] { onPerson(task); return }
        }
        if townMode == .lore { onLoreTap(); return }
        if let b = TownStreet.buildings.first(where: { p.x >= $0.x && p.x <= $0.x + $0.w }) { onBuilding(b) }
    }
}

private final class WindState: @unchecked Sendable { var last: Float = 0; var phase: Float = 0 }

/// Wind always, crickets after dark: made live, no files (as the web's SND button).
@MainActor final class TownSound {
    private let engine = AVAudioEngine()
    private var running = false
    private var dark = false
    private var timer: Timer?

    func start(dark: Bool) {
        guard !running else { return }
        self.dark = dark
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let fmt = engine.outputNode.inputFormat(forBus: 0)
        let sr = fmt.sampleRate
        let st = WindState()
        let wind = AVAudioSourceNode { _, _, frames, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            for i in 0..<Int(frames) {
                st.last = (st.last + 0.02 * (Float.random(in: -1...1))) / 1.02
                st.phase += 0.07 / Float(sr)
                let v = st.last * 3.5 * 0.18 * (0.55 + 0.45 * sin(st.phase * 2 * .pi))
                for b in list { b.mData?.assumingMemoryBound(to: Float.self)[i] = v }
            }
            return noErr
        }
        engine.attach(wind)
        engine.connect(wind, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1))
        do { try engine.start() } catch { return }
        running = true
        if dark { timer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: true) { [weak self] _ in Task { @MainActor in self?.chirp(sr) } } }
    }

    private func chirp(_ sr: Double) {
        guard running else { return }
        let n = Int(sr * 0.22)
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1), let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { return }
        buf.frameLength = AVAudioFrameCount(n)
        let f = Float(4300 + Double.random(in: 0...200))
        for i in 0..<n {
            let t = Float(i) / Float(sr)
            let burst = Float(Int(t / 0.07) < 3 ? 1 : 0) * max(0, 1 - Float((t.truncatingRemainder(dividingBy: 0.07)) / 0.05))
            buf.floatChannelData?[0][i] = sin(2 * .pi * f * t) * 0.025 * burst
        }
        let p = AVAudioPlayerNode(); engine.attach(p); engine.connect(p, to: engine.mainMixerNode, format: fmt)
        p.scheduleBuffer(buf, completionHandler: nil); p.play()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if running { engine.stop() }
        running = false
    }
}
