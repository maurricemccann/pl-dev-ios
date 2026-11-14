import SwiftUI
import SpriteKit

/// The three towns, as the web's TASKS / LIVE / LORE chips.
enum TownMode: String, CaseIterable, Identifiable, Sendable { case tasks = "Tasks", live = "Live", lore = "Lore"; var id: String { rawValue } }

/// The pixel town as a SpriteKit scene (the web page `app/town/page.tsx`, drawn natively). One long street: the gold GlyphGuy is the live
/// session and walks to the building of every tool call, steps in at the door and works at a lit window; townspeople are the Roadmap
/// (open ones stroll, the ones waiting on him stand at HOME and blink "!", blocked ones stand under the watchtower lamp and blink "X",
/// anything a week old stands big and red in the stale lot); orange visitors arrive at the dock on the cart; ghosts replay the routes of
/// earlier sessions; the sky and the lights follow the real sun where the phone is. Units are street pixels, y up.
@MainActor final class TownScene: SKScene {
    private let LH = TownStreet.LH
    // the middle of the sidewalk (painted y 8 to 20), less the ~4 empty units under every sprite's feet (sheet rows end 8-9 px
    // above the cell bottom): was the sidewalk's back edge + 4, so GlyphGuy hovered over it (his note 11-14 "he's floating")
    private var feet: CGFloat { TownStreet.LH - TownStreet.WALK - 6 }
    private let streetNode = SKSpriteNode()
    private let skyNode = SKSpriteNode()
    private let nightWash = SKSpriteNode()
    private let cam = SKCameraNode()
    private let world = SKNode()

    /// One person on the street.
    private final class Npc {
        let key: String
        let node: SKSpriteNode
        var role: String
        var task: TownFeed.Task?
        var tx: CGFloat
        var enter: String?
        var inside: String?
        var outAt: CGFloat?
        var route: [String] = []
        var ri = 0
        var wanderAt: CGFloat = 0
        var mark: SKLabelNode?
        var scale: CGFloat
        var tint: UIColor
        var step: CGFloat = 0          // the stride, in frames (the web's n.step)
        var danceUntil: CGFloat = 0
        var walkSet: [[SKTexture]]?
        init(key: String, node: SKSpriteNode, role: String, task: TownFeed.Task?, tx: CGFloat, scale: CGFloat, tint: UIColor) {
            self.key = key; self.node = node; self.role = role; self.task = task; self.tx = tx; self.scale = scale; self.tint = tint
        }
    }

    private var npcs: [String: Npc] = [:]
    private var me: Npc?
    private var glows: [String: SKSpriteNode] = [:]
    private let bubble = SKNode()
    private let bubbleBox = SKSpriteNode()
    private let bubbleText = SKLabelNode(fontNamed: TownFace.name)
    private var bubbleUntil: CGFloat = 0
    private var lastLiveAt: String?
    private var lastKinds: [String: String] = [:]
    private var greeted = false
    private let board = SKNode()
    private let boardLine = SKLabelNode(fontNamed: TownFace.name)
    private let cart = SKSpriteNode(color: townHex("#ff8a2a"), size: CGSize(width: 30, height: 9))
    private var schedule: [TownFeed.Sched] = []
    private var feed: TownFeed?
    private var painted: (TownLight, Int)?
    private var clock: CGFloat = 0
    private var lastUpdate: TimeInterval = 0
    private var lastCheck: CGFloat = 0
    private var nextChat: CGFloat = 14
    private var dragged = false

    var lightAuto = true
    var light: TownLight = TownSun.mode() { didSet { repaint() } }
    var camFree = false
    var townMode: TownMode = .tasks { didSet { if townMode != oldValue { clearPeople(); if let f = feed { rebuild(f) }; updateMe() } } }

    /// What the SwiftUI side listens to.
    var onTalk: (String) -> Void = { _ in }
    var onCamFree: () -> Void = {}
    var onCelebrate: () -> Void = {}
    var onTap: () -> Void = {}

    override func didMove(to view: SKView) {
        backgroundColor = townHex("#120c06")
        anchorPoint = .zero
        scaleMode = .aspectFit
        addChild(world); addChild(cam); camera = cam
        skyNode.anchorPoint = .zero; skyNode.zPosition = -10; world.addChild(skyNode)
        streetNode.anchorPoint = .zero; streetNode.zPosition = 0; world.addChild(streetNode)
        nightWash.anchorPoint = .zero; nightWash.zPosition = 50; world.addChild(nightWash)
        cam.position = CGPoint(x: size.width / 2, y: LH / 2)
        buildFixtures()
        repaint(force: true)
        Task {
            await TownSprites.bake()
            self.spawnMe()
            if let f = self.feed { self.rebuild(f); self.updateMe() }
        }
    }

    // MARK: painting and light

    func repaint(force: Bool = false) {
        let bucket = Int(Date().timeIntervalSince1970 / 600)
        if !force, let p = painted, p.0 == light, p.1 == bucket { return }
        painted = (light, bucket)
        let t = SKTexture(image: TownPainter.street(mode: light)); t.filteringMode = .nearest
        streetNode.texture = t; streetNode.size = CGSize(width: TownStreet.width, height: LH)
        let st = SKTexture(image: TownPainter.sky(mode: light, width: TownStreet.width)); st.filteringMode = .nearest
        skyNode.texture = st; skyNode.size = CGSize(width: TownStreet.width, height: LH); skyNode.position = .zero
        nightWash.size = CGSize(width: TownStreet.width, height: LH)
        let wash: (UIColor, CGFloat) = { switch light { case .night: return (townHex("#0a1230"), 0.32); case .dusk: return (townHex("#ff7a3a"), 0.10); case .dawn: return (townHex("#ffb070"), 0.08); case .day: return (.clear, 0) } }()
        nightWash.color = wash.0; nightWash.colorBlendFactor = 1; nightWash.alpha = wash.1
    }

    // MARK: fixed things on the street: the watchtower's lamp, the cloud board, the cart, the speech bubble

    private func buildFixtures() {
        if let w = TownStreet.building("watch") {
            let lamp = SKShapeNode(circleOfRadius: 14)
            lamp.fillColor = UIColor(red: 1, green: 0.2, blue: 0.12, alpha: 1); lamp.strokeColor = .clear; lamp.alpha = 0.14
            lamp.position = CGPoint(x: w.doorX + 27, y: LH - (TownStreet.WALK - 46)); lamp.zPosition = 6; lamp.blendMode = .add
            lamp.run(.repeatForever(.sequence([.fadeAlpha(to: 0.24, duration: 1.0), .fadeAlpha(to: 0.10, duration: 1.0)])))
            world.addChild(lamp)
        }
        if let d = TownStreet.building("dock") {
            // the CLOUD board by the dock: the next scheduled cloud run
            board.position = CGPoint(x: d.doorX + 40, y: LH - (TownStreet.WALK - 70) - 22); board.zPosition = 8
            let post = SKSpriteNode(color: townHex("#2a1a10"), size: CGSize(width: 2, height: 22)); post.anchorPoint = .zero; post.position = CGPoint(x: 28, y: -22)
            let frame = SKSpriteNode(color: townHex("#2a1a10"), size: CGSize(width: 60, height: 24)); frame.anchorPoint = .zero; frame.position = CGPoint(x: -1, y: -1)
            let face = SKSpriteNode(color: townHex("#ff8a2a"), size: CGSize(width: 58, height: 22)); face.anchorPoint = .zero
            let next = SKLabelNode(fontNamed: TownFace.name); next.fontSize = 7 * TownFace.scale; next.text = "NEXT"; next.fontColor = townHex("#2a1a10"); next.horizontalAlignmentMode = .left; next.verticalAlignmentMode = .baseline; next.position = CGPoint(x: 13, y: 13)
            boardLine.fontSize = 7 * TownFace.scale; boardLine.text = "NONE"; boardLine.fontColor = townHex("#2a1a10"); boardLine.horizontalAlignmentMode = .left; boardLine.verticalAlignmentMode = .baseline; boardLine.position = CGPoint(x: 2, y: 3)
            [post, frame, face, next, boardLine].forEach { board.addChild($0) }
            world.addChild(board)
            // the orange cart the cloud sessions arrive on
            cart.anchorPoint = CGPoint(x: 0.5, y: 0); cart.position = CGPoint(x: TownStreet.width + 40, y: feet - 2); cart.zPosition = 11
            for dx in [-9, 9] { let wheel = SKSpriteNode(color: townHex("#2a1a10"), size: CGSize(width: 5, height: 5)); wheel.position = CGPoint(x: CGFloat(dx), y: 0); cart.addChild(wheel) }
            world.addChild(cart)
        }
        bubble.zPosition = 40; bubble.alpha = 0
        bubbleBox.color = townHex("#f8f0d8"); bubbleBox.anchorPoint = CGPoint(x: 0.5, y: 0)
        bubbleText.fontSize = 7 * TownFace.scale; bubbleText.fontColor = townHex("#2a1a10"); bubbleText.verticalAlignmentMode = .center; bubbleText.horizontalAlignmentMode = .center
        bubble.addChild(bubbleBox); bubble.addChild(bubbleText)
        world.addChild(bubble)
    }

    private func say(_ text: String) {
        bubbleText.text = text
        let w = CGFloat(text.count) * 5.2 + 8
        bubbleBox.size = CGSize(width: w, height: 12)
        bubbleBox.position = .zero; bubbleText.position = CGPoint(x: 0, y: 6)
        bubbleUntil = clock + 4
        bubble.alpha = 1
    }

    // MARK: sprites

    private func sprite(_ tint: UIColor?, scale: CGFloat = 1, her: Bool = false) -> SKSpriteNode {
        let n = SKSpriteNode(texture: TownSprites.walk(her: her, tint: tint ?? .white)[0][8], size: CGSize(width: 40 * scale, height: 56 * scale))
        n.anchorPoint = CGPoint(x: 0.5, y: 0)
        return n
    }

    private func palette(_ s: String) -> UIColor {
        ["#2f4f9a", "#8a2222", "#2f6a2a", "#5e2f8a", "#a03a6a", "#1f6a6a", "#6a4a30", "#5a5a64"].map(townHex)[townHash(s) % 8]
    }

    private func door(_ id: String) -> CGFloat { TownStreet.building(id)?.doorX ?? 100 }

    private func spawnMe() {
        guard me == nil, TownSprites.frames["down"] != nil else { return }
        let g = sprite(townHex("#d9a02e"), scale: 1.05)
        g.zPosition = 20; g.position = CGPoint(x: door("home"), y: feet)
        world.addChild(g)
        let n = Npc(key: "__me", node: g, role: "me", task: nil, tx: door("home"), scale: 1.05, tint: townHex("#d9a02e"))
        me = n
    }

    // MARK: the feed

    func apply(_ f: TownFeed) {
        let before = feed
        feed = f
        schedule = f.schedule ?? []
        updateBoard()
        celebrate(before, f)
        rebuild(f)
        liveEvents(f)
        updateMe()
        if !greeted, f.ok == true {
            greeted = true
            let open = (f.tasks ?? []).filter { $0.state != "done" }.count, done = (f.tasks ?? []).count - open
            onTalk("GLYPHGUY: \(open) task\(open == 1 ? "" : "s") in town, \(done) done this session. Drag to walk the street, tap anyone to talk.")
        }
    }

    private func updateBoard() {
        let on = schedule.filter { $0.enabled == true && $0.next != nil }.compactMap { s -> Date? in ISO8601DateFormatter().date(from: s.next ?? "") }.sorted().first
        if let on {
            let f = DateFormatter(); f.dateFormat = "EEE h a"; f.timeZone = TimeZone(identifier: "America/Los_Angeles"); f.locale = Locale(identifier: "en_US")
            boardLine.text = String(f.string(from: on).uppercased().replacingOccurrences(of: ",", with: "").prefix(7))
        } else { boardLine.text = "NONE" }
    }

    /// Fireworks over the street when a task flips to done.
    private func celebrate(_ old: TownFeed?, _ new: TownFeed) {
        guard let old else { return }
        let was = Dictionary(uniqueKeysWithValues: (old.tasks ?? []).map { ($0.id, $0.state ?? "") })
        let fresh = (new.tasks ?? []).filter { $0.state == "done" && (was[$0.id] ?? "") != "done" && was[$0.id] != nil }
        guard !fresh.isEmpty else { return }
        onCelebrate()
        me?.danceUntil = clock + 3.2   // his own dance clip, front-on, while the fireworks go
        let x = me?.node.position.x ?? door("home")
        let cols = [townHex("#ffe07a"), .white, townHex("#ff8a2a"), townHex("#9fe8ff")]
        for i in 0..<22 {
            let p = SKSpriteNode(color: cols[i % cols.count], size: CGSize(width: 2, height: 2))
            p.position = CGPoint(x: x, y: feet + 70); p.zPosition = 30; world.addChild(p)
            let a = CGFloat.random(in: 0...(2 * .pi)), v = CGFloat.random(in: 26...70)
            p.run(.sequence([.group([.moveBy(x: cos(a) * v, y: sin(a) * v - 20, duration: 1.5), .fadeOut(withDuration: 1.5)]), .removeFromParent()]))
        }
    }

    /// A deploy or a send sends a pigeon from the POST; a question for him pulses HOME's lantern; every new call shows in a bubble.
    private func liveEvents(_ f: TownFeed) {
        guard let live = f.live, (live.age_s ?? 999) < 90 else { return }
        guard live.at != lastLiveAt else { return }
        lastLiveAt = live.at
        let label = TownStreet.kindLabel[live.kind ?? ""] ?? String((live.tool ?? "").replacingOccurrences(of: "mcp__", with: "").components(separatedBy: "__")[0].replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").uppercased().prefix(12))
        if !label.isEmpty { say(label) }
        if live.kind == "deploy" || live.kind == "send" { pigeon() }
        if live.kind == "ask" { askPulse() }
    }

    private func pigeon() {
        guard let post = TownStreet.building("post") else { return }
        let p = SKNode(); p.position = CGPoint(x: post.doorX, y: LH - (TownStreet.WALK - 120)); p.zPosition = 35
        let body = SKSpriteNode(color: townHex("#f0f0f4"), size: CGSize(width: 4, height: 3))
        let w1 = SKSpriteNode(color: townHex("#c0c0cc"), size: CGSize(width: 3, height: 1)); w1.position = CGPoint(x: -3.5, y: 0)
        let w2 = SKSpriteNode(color: townHex("#c0c0cc"), size: CGSize(width: 3, height: 1)); w2.position = CGPoint(x: 4, y: 0)
        [body, w1, w2].forEach { p.addChild($0) }
        let flap = SKAction.repeatForever(.sequence([.moveBy(x: 0, y: 2, duration: 0.055), .moveBy(x: 0, y: -2, duration: 0.055)]))
        w1.run(flap); w2.run(flap)
        world.addChild(p)
        p.run(.sequence([.group([.moveBy(x: 120, y: 90, duration: 3), .sequence([.wait(forDuration: 2.4), .fadeOut(withDuration: 0.6)])]), .removeFromParent()]))
    }

    private func askPulse() {
        let g = SKShapeNode(circleOfRadius: 16)
        g.fillColor = townHex("#ffc86e"); g.strokeColor = .clear; g.alpha = 0
        g.position = CGPoint(x: door("home") - 10, y: LH - (TownStreet.WALK - 50)); g.zPosition = 7; g.blendMode = .add
        world.addChild(g)
        g.run(.sequence([.repeat(.sequence([.fadeAlpha(to: 0.7, duration: 0.3), .fadeAlpha(to: 0.15, duration: 0.3)]), count: 6), .removeFromParent()]))
    }

    // MARK: people

    private func clearPeople() {
        for (_, n) in npcs { n.node.removeFromParent() }
        npcs = [:]
        for (_, g) in glows { g.alpha = 0 }
    }

    private func person(_ key: String, role: String, task: TownFeed.Task?, tint: UIColor, x: CGFloat, tx: CGFloat? = nil, scale: CGFloat = 1) -> Npc {
        if let n = npcs[key] {
            if n.role == role { n.task = task; if let tx { n.tx = tx }; return n }
            n.node.removeFromParent(); npcs[key] = nil   // his state changed: a new body with the right mark
        }
        let node = sprite(tint, scale: scale, her: role == "visitor")
        node.zPosition = 10 + scale; node.position = CGPoint(x: x, y: feet)
        node.name = "npc:" + key
        world.addChild(node)
        let n = Npc(key: key, node: node, role: role, task: task, tx: tx ?? x, scale: scale, tint: tint)
        if role == "his" || role == "blocked" {
            let m = SKLabelNode(fontNamed: TownFace.name); m.fontSize = 9 * TownFace.scale; m.text = role == "his" ? "!" : "X"
            m.fontColor = role == "blocked" ? townHex("#ff4a3a") : townHex("#fff8e0")
            m.position = CGPoint(x: 0, y: 60 * scale); m.zPosition = 5
            m.run(.repeatForever(.sequence([.fadeAlpha(to: 0, duration: 0.25), .wait(forDuration: 0.25), .fadeAlpha(to: 1, duration: 0.01), .wait(forDuration: 0.5)])))
            node.addChild(m); n.mark = m
        }
        npcs[key] = n
        return n
    }

    private func rebuild(_ f: TownFeed) {
        guard TownSprites.frames["down"] != nil else { return }
        var want: Set<String> = []
        let stale = TownStreet.building("stale"), curate = door("curate"), clockX = door("clock")
        if townMode == .lore {
            for (i, (word, story)) in TownStreet.lore.enumerated() {
                let key = "lore\(i)"; want.insert(key)
                let x = i < 9 ? door("library") - 70 + CGFloat(i) * 17 : door("records") - 40 + CGFloat(i - 9) * 16
                _ = person(key, role: "lore", task: TownFeed.Task(key: key, title: word, state: "lore", proof: story, session: "", age_days: 0), tint: townHex("#7a7a84"), x: x)
            }
        } else if townMode == .tasks {
            let live = (f.tasks ?? []).filter { $0.state != "done" }
            var by: [String: [TownFeed.Task]] = ["now": [], "open": [], "his": [], "blocked": [], "boss": []]
            for t in live { by[(t.age_days ?? 0) >= 7 ? "boss" : (by[t.state ?? ""] != nil ? (t.state ?? "open") : "open"), default: []].append(t) }
            for (i, t) in (by["now"] ?? []).enumerated() { want.insert(t.id); _ = person(t.id, role: "now", task: t, tint: palette(t.id), x: door("studio") - 50 + CGFloat(i) * 26, tx: door("studio") - 50 + CGFloat(i % 4) * 26 + (i > 3 ? 13 : 0)) }
            for (i, t) in (by["his"] ?? []).enumerated() { want.insert(t.id); _ = person(t.id, role: "his", task: t, tint: palette(t.id), x: door("home") + 20 + CGFloat(i) * 18, tx: door("home") + 22 + CGFloat(i) * 18) }
            for (i, t) in (by["blocked"] ?? []).enumerated() { want.insert(t.id); _ = person(t.id, role: "blocked", task: t, tint: palette(t.id), x: door("watch") + 26 + CGFloat(i) * 16, tx: door("watch") + 20 + CGFloat(i) * 16) }
            for (i, t) in (by["boss"] ?? []).enumerated() { want.insert(t.id); let x = (stale?.doorX ?? 100) - 14 + CGFloat(i) * 30; _ = person(t.id, role: "boss", task: t, tint: townHex("#9a1a12"), x: x, tx: x, scale: 1.4) }
            for t in by["open"] ?? [] { want.insert(t.id); _ = person(t.id, role: "open", task: t, tint: palette(t.id), x: curate + CGFloat(townHash(t.id) % max(1, Int(clockX - curate)))) }
        }
        do {
            let vis = (f.visitors ?? []).filter { ($0.age_s ?? 999) < 180 }.prefix(3)
            cart.removeAllActions()
            cart.run(.moveTo(x: vis.isEmpty ? TownStreet.width + 40 : door("dock") + 30, duration: 2.5))
            for (i, v) in vis.enumerated() {
                let key = "vis:" + (v.name ?? "cloud"); want.insert(key)
                _ = person(key, role: "visitor", task: TownFeed.Task(key: key, title: v.name ?? "cloud", state: "visitor", proof: "", session: "", age_days: 0), tint: townHex("#ff8a2a"), x: door("dock") - 30 + CGFloat(i) * 20, tx: door("dock") - 34 + CGFloat(i) * 20)
            }
        }
        if townMode != .live {
            for (i, gh) in (f.ghosts ?? []).prefix(6).enumerated() {
                let key = "ghost:\(gh.s ?? "")\(i)"; want.insert(key)
                let route = (gh.p ?? []).filter { TownStreet.building($0) != nil && TownStreet.building($0)?.lot == false }
                let first = route.first ?? "library"
                let t = TownFeed.Task(key: key, title: gh.s ?? "a past session", state: "ghost", proof: (gh.p ?? []).map { TownStreet.building($0)?.label ?? $0 }.joined(separator: " > "), session: gh.s, age_days: 0)
                let n = person(key, role: "ghost", task: t, tint: townHex("#a8c8f0"), x: door(first) + CGFloat(i % 3) * 8)
                if n.route.isEmpty && !route.isEmpty {
                    n.route = route; n.ri = (i * 5) % route.count; n.tx = door(route[n.ri]); n.enter = route[n.ri]
                }
            }
        }
        for (k, n) in npcs where !want.contains(k) { n.node.removeFromParent(); npcs[k] = nil }
    }

    /// Where the session is and what he is doing, as the web's `apply`: a live call within 90 s sends him to its building and in at the door.
    private func updateMe() {
        guard let me, let f = feed else { return }
        let lv = (f.live?.age_s ?? 999) < 90 ? f.live : nil
        let bid: String
        if let lv { bid = TownStreet.target(area: lv.area, kind: lv.kind)?.id ?? "clock" }
        else { bid = (f.working == true && (f.tasks ?? []).contains { $0.state == "now" }) ? "studio" : "home" }
        me.tx = door(bid)
        me.enter = (lv != nil && TownStreet.building(bid)?.lot == false) ? bid : nil
        if let inside = me.inside, inside != me.enter { me.inside = nil; me.node.alpha = 1 }
    }

    // MARK: frame

    override func update(_ t: TimeInterval) {
        let dt = lastUpdate == 0 ? CGFloat(0.016) : CGFloat(min(0.1, t - lastUpdate)); lastUpdate = t
        clock += dt
        for n in [me].compactMap({ $0 }) + Array(npcs.values) { step(n, dt) }
        // two open townspeople meet and talk now and then
        if townMode == .tasks, clock > nextChat {
            nextChat = clock + 14
            let opens = npcs.values.filter { $0.role == "open" && $0.inside == nil }.shuffled()
            if opens.count >= 2 {
                let cx = door("curate") + CGFloat.random(in: 0...max(1, door("clock") - door("curate") - 30))
                opens[0].tx = cx; opens[1].tx = cx + 18
                opens[0].wanderAt = clock + 9; opens[1].wanderAt = clock + 9
            }
        }
        // windows glow warm while someone is in the building
        var lit: Set<String> = []
        for n in [me].compactMap({ $0 }) + Array(npcs.values) { if let b = n.inside { lit.insert(b) } }
        for id in Set(glows.keys).union(lit) {
            guard let b = TownStreet.building(id) else { continue }
            let g: SKSpriteNode
            if let e = glows[id] { g = e } else {
                g = SKSpriteNode(color: townHex("#ffe9a0"), size: CGSize(width: b.w * 0.34, height: 30))
                g.zPosition = 5; g.blendMode = .add; g.alpha = 0
                g.position = CGPoint(x: b.x + b.w * 0.3, y: feet + 28)
                world.addChild(g); glows[id] = g
            }
            let want: CGFloat = lit.contains(id) ? 0.32 + 0.05 * sin(clock * 2) : 0
            g.alpha += (want - g.alpha) * min(1, dt * 6)
        }
        // the speech bubble follows the session and fades after four seconds
        if let me {
            bubble.position = CGPoint(x: me.node.position.x, y: me.inside == nil ? me.node.position.y + 60 : feet + TownStreet.doorH + 36)
            if clock > bubbleUntil { bubble.alpha = max(0, bubble.alpha - dt * 3) }
        }
        // the camera follows the session unless he has taken it
        if !camFree, let me {
            let want = clampCam(me.node.position.x)
            cam.position.x += (want - cam.position.x) * 0.06
        } else { cam.position.x = clampCam(cam.position.x) }
        cam.position.y = LH / 2
        if clock - lastCheck > 30 { lastCheck = clock; if lightAuto { let m = TownSun.mode(); if m != light { light = m } }; repaint() }
    }

    private func step(_ n: Npc, _ dt: CGFloat) {
        let node = n.node
        if let b = n.inside {
            if let out = n.outAt, clock > out {
                n.inside = nil; n.outAt = nil; n.enter = nil; node.alpha = 1
                node.run(.sequence([.moveBy(x: 0, y: 5, duration: 0.1), .moveBy(x: 0, y: -5, duration: 0.1)]))
                if n.role == "ghost", !n.route.isEmpty { n.ri = (n.ri + 1) % n.route.count; n.enter = n.route[n.ri]; n.tx = door(n.enter ?? b) }
            } else { return }
        }
        // the open ones wander a little between chats
        if n.role == "open", clock > n.wanderAt {
            n.wanderAt = clock + CGFloat.random(in: 5...12)
            n.tx = door("curate") + CGFloat.random(in: 0...max(1, door("clock") - door("curate") - 30))
        } else if n.role == "now" || n.role == "his", clock > n.wanderAt {
            n.wanderAt = clock + CGFloat.random(in: 6...12)
            n.tx += CGFloat.random(in: -10...10)
        }
        let dx = n.tx - node.position.x
        let speed: CGFloat = n.role == "me" ? 60 : n.role == "ghost" ? 26 : 34
        let moving = abs(dx) > 1.5
        if moving { node.position.x += (dx > 0 ? 1 : -1) * min(abs(dx), speed * dt) }
        else if let e = n.enter, abs(door(e) - node.position.x) < 16 {
            n.inside = e
            n.outAt = n.role == "me" ? nil : clock + (n.role == "ghost" ? CGFloat.random(in: 3...5) : CGFloat.random(in: 6...12))
            node.alpha = 0
            return
        }
        // his real frames, as the web plays them: 8 stride frames while moving, a 4-frame breath standing, the dance clip on a celebration
        let rm = UIAccessibility.isReduceMotionEnabled, her = n.role == "visitor"
        let tex: SKTexture
        if !moving, !rm, clock < n.danceUntil {
            let d = TownSprites.dance(her: her, tint: n.tint)
            tex = d[Int(clock * 10) % max(1, d.count)]
        } else {
            if n.walkSet == nil { n.walkSet = TownSprites.walk(her: her, tint: n.tint) }
            let rows = n.walkSet ?? [], row = moving ? (dx > 0 ? 2 : 1) : 0
            if moving && !rm { n.step += dt * 11 } else { n.step = 0 }
            let i = moving && !rm ? Int(n.step) % 8 : (rm ? 8 : 8 + (Int(clock * 1.5) + townHash(n.key)) % 4)
            tex = rows.indices.contains(row) && rows[row].indices.contains(i) ? rows[row][i] : (node.texture ?? SKTexture())
        }
        if node.texture !== tex { node.texture = tex }
        node.position.y = feet
        if n.role == "ghost" { node.alpha = 0.5 + 0.12 * sin(clock * 2 + CGFloat(townHash(n.key) % 5)) }
    }

    private func clampCam(_ x: CGFloat) -> CGFloat { max(size.width / 2, min(max(size.width / 2, TownStreet.width - size.width / 2), x)) }

    // MARK: what a tap on someone says (the web's `talkText`)

    static func talkText(_ t: TownFeed.Task) -> String {
        let title = t.title ?? "", state = t.state ?? ""
        switch state {
        case "ghost": return "GHOST OF \(title): replaying its session. " + (t.proof ?? "").components(separatedBy: " > ").prefix(10).joined(separator: " > ")
        case "visitor": return "GLYPHGIRL: \(title), a cloud session or API run, is working right now."
        case "lore": return "\"\(title.uppercased())\": \(t.proof ?? "")"
        case "done": return "DONE! \(title). \(t.proof ?? "")"
        default: break
        }
        if (t.age_days ?? 0) >= 7 { return "STALE BOSS (\(t.age_days ?? 0) DAYS): \(title). Finish it or strike it." }
        switch state {
        case "his": return "Waiting on you: \(title)."
        case "blocked": return "Blocked: \(title)."
        case "now": return "Working on it: \(title)."
        default: let d = t.age_days ?? 0; return "\(title). On the Roadmap \(d) day\(d == 1 ? "" : "s")."
        }
    }


    // MARK: what the mini-map reads (the whole street, every person a dot, the window the screen shows)

    var camX: CGFloat { cam.position.x }
    var viewW: CGFloat { size.width }
    struct Dot { let x: CGFloat; let color: UIColor }
    func dots() -> [Dot] {
        var out: [Dot] = [Dot(x: me?.node.position.x ?? door("home"), color: townHex("#ffe07a"))]
        for n in npcs.values { out.append(Dot(x: n.node.position.x, color: n.role == "boss" ? townHex("#ff3a2a") : n.role == "visitor" ? townHex("#ff8a2a") : .white)) }
        return out
    }

    // MARK: public moves for the SwiftUI side

    func jump(toX x: CGFloat) { camFree = true; cam.position.x = clampCam(x); onCamFree() }

    func focus(building id: String) { if let b = TownStreet.building(id) { jump(toX: b.doorX); onTalk("\(b.label): \(b.note)") } }

    func followSession() { camFree = false }

    /// The R1's press: talk to whoever is nearest the centre of the screen, or read the building there.
    func talkNearest() {
        let mid = cam.position.x
        let near = npcs.values.filter { $0.inside == nil }.min { abs($0.node.position.x - mid) < abs($1.node.position.x - mid) }
        if let near, abs(near.node.position.x - mid) < size.width / 2, let t = near.task { onTalk(Self.talkText(t)); return }
        if let b = TownStreet.buildings.first(where: { mid >= $0.x && mid <= $0.x + $0.w }) { onTalk("\(b.label): \(b.note)") }
    }

    private func meText() -> String {
        guard let f = feed, let lv = f.live, (lv.age_s ?? 999) < 90 else { return "GLYPHGUY: that is me, the session." }
        let b = TownStreet.target(area: lv.area, kind: lv.kind)
        return "GLYPHGUY: that is me, the session. Right now: \(TownStreet.kindLabel[lv.kind ?? ""] ?? (lv.kind ?? "working")) at the \(b?.label ?? "street")."
    }

    // MARK: touch: drag to walk the street, tap to talk (people first, then the cloud board, then the building behind)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { dragged = false }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let dx = t.location(in: self).x - t.previousLocation(in: self).x
        if abs(dx) > 0.5 { if !dragged { onCamFree() }; dragged = true; camFree = true }
        cam.position.x = clampCam(cam.position.x - dx)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, !dragged else { return }
        let p = t.location(in: world)
        onTap()
        let all = ([me].compactMap { $0 } + Array(npcs.values)).filter { $0.inside == nil }.sorted { $0.node.position.y < $1.node.position.y }
        if let hit = all.first(where: { abs(p.x - $0.node.position.x) < 12 * $0.scale && p.y > $0.node.position.y - 2 && p.y < $0.node.position.y + 56 * $0.scale }) {
            hit.node.run(.sequence([.moveBy(x: 0, y: 6, duration: 0.08), .moveBy(x: 0, y: -6, duration: 0.08)]))
            if let task = hit.task { onTalk(Self.talkText(task)) } else { onTalk(meText()) }
            return
        }
        let dock = door("dock")
        if p.x > dock + 40, p.x < dock + 86, p.y > LH - (TownStreet.WALK - 40), p.y < LH - (TownStreet.WALK - 72) {
            let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; f.timeZone = TimeZone(identifier: "America/Los_Angeles"); f.locale = Locale(identifier: "en_US")
            let line = schedule.isEmpty ? "no routines on file." : schedule.map { s -> String in
                guard s.enabled == true, let d = ISO8601DateFormatter().date(from: s.next ?? "") else { return "\(s.name ?? "routine") paused" }
                return "\(s.name ?? "routine") \(f.string(from: d))"
            }.joined(separator: " · ")
            onTalk("CLOUD SCHEDULE: " + line); return
        }
        if p.y > LH - TownStreet.WALK, let b = TownStreet.buildings.first(where: { p.x >= $0.x && p.x <= $0.x + $0.w }) { onTalk("\(b.label): \(b.note)") }
    }
}
