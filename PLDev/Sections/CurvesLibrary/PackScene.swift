import AVFoundation
import RealityKit
import SwiftUI
import UIKit

// THE PACK, native (his rulings 11-19: "the Pack in full"; the page it ports is pl-curves-gallery public/pack/index.html, S348/S349).
// His pack.glb (same entity names), his tile, heart and money mark, the same cards and favourites, the same SETTINGS. The page was
// written to port: every material is PhysicallyBasedMaterial fields, the rip is two pure functions, one state machine. Not ported:
// three.js iridescence (Prism's shimmer) and acrylic transmission, which PhysicallyBasedMaterial has no field for; the slab is a
// clear, glossy blend instead, and Prism keeps its holographic colour.

enum PackState: String { case sealed, tearing, rising, poised, revealing, revealed, slabbing, slabbed, viewing }
enum PackSheet: String, Identifiable { case collection, editor; var id: String { rawValue } }

@MainActor @Observable final class PackEngine {
    // what the screen shows
    private(set) var state: PackState = .sealed
    private(set) var loaded = false
    var failure: String?
    var said = ""
    private(set) var prismEmpty = false
    private(set) var cards: [PackShowCard] = []
    private(set) var opened: [String] = []
    private(set) var countText = ""
    var settings = PackSettings.load()
    var sheet: PackSheet?
    var pvTier = ""
    var pvMod = ""
    var json = ""
    private(set) var tick = 0   // a state change the haptics follow

    // the scene
    @ObservationIgnored let root = Entity()
    @ObservationIgnored private let camera = Entity()
    @ObservationIgnored private let packGroup = Entity()
    @ObservationIgnored private let stripGroup = Entity()
    @ObservationIgnored private let hero = Entity()
    @ObservationIgnored private let slabGroup = Entity()
    @ObservationIgnored private var card: ModelEntity?
    @ObservationIgnored private var slabFront: ModelEntity?
    @ObservationIgnored private var slabBack: ModelEntity?
    @ObservationIgnored private var label: ModelEntity?
    @ObservationIgnored private var labelBack: ModelEntity?
    @ObservationIgnored private var packE: [ModelEntity] = []
    @ObservationIgnored private var stripE: [ModelEntity] = []
    @ObservationIgnored private var packMesh: PackMesh?
    @ObservationIgnored private var stripMesh: PackMesh?
    @ObservationIgnored private let flare = Entity()
    @ObservationIgnored private var videoPlane: ModelEntity?
    @ObservationIgnored private var player: AVQueuePlayer?
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var subscription: EventSubscription?
    @ObservationIgnored private var art: PackArt?
    @ObservationIgnored private var tex: [String: TextureResource] = [:]
    @ObservationIgnored private var M: [String: PhysicallyBasedMaterial] = [:]
    @ObservationIgnored private var G = PackGeometry()
    @ObservationIgnored private var decks = PackDecks.fresh(0)
    @ObservationIgnored private(set) var current: PackShowCard?
    @ObservationIgnored private var artCache: [String: CGImage] = [:]
    @ObservationIgnored private var model: AppModel?
    @ObservationIgnored private var base = ""

    // the motion
    @ObservationIgnored private var tState = 0.0
    @ObservationIgnored private var front = -1.0
    @ObservationIgnored private var fall = 0.0
    @ObservationIgnored private var autoTear = false
    @ObservationIgnored private var yaw = -0.42
    @ObservationIgnored private var pitch = 0.06
    @ObservationIgnored private var yawHome = false
    @ObservationIgnored private var swayK = 0.0
    @ObservationIgnored private var dragging: (tear: Bool, x: CGFloat, y: CGFloat, t: Date, moved: CGFloat)?
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var resume: (state: PackState, card: PackShowCard?, seed: Int, mod: String?)?
    @ObservationIgnored private var frame = 0
    @ObservationIgnored private var stageQ = simd_quatf(angle: 0, axis: [0, 1, 0])
    @ObservationIgnored private var size = CGSize(width: 390, height: 844)
    @ObservationIgnored private var camZ: Float = 0.4
    @ObservationIgnored var still = false
    @ObservationIgnored private(set) var bgClock = 40.0
    @ObservationIgnored private(set) var bgK = 0.22
    @ObservationIgnored private var redrawTask: Task<Void, Never>?

    var ground: Color { Color(PackMath.ui(settings.colour.ground)) }
    func imageURL(_ c: PackShowCard) -> URL? { PackPaths.url(c.img, base: base) }

    // MARK: start

    func start(model: AppModel) async {
        guard !loaded else { return }
        self.model = model
        failure = nil
        guard let http = model.http, let b = model.config?.origin("gallery")?.base else { failure = "The pack could not load: no gallery address in the config."; return }
        base = b.hasSuffix("/") ? String(b.dropLast()) : b
        func image(_ d: Data, _ p: String) throws -> CGImage {
            guard let i = UIImage(data: d)?.cgImage else { throw PackGLB.Failure(description: "could not load \(p)") }
            return i
        }
        do {
            async let tileD = http.send(RequestPlan(origin: "gallery", path: "pack/pl_tile.png"), timeout: 30)
            async let heartD = http.send(RequestPlan(origin: "gallery", path: "pack/heart.png"), timeout: 30)
            async let moneyD = http.send(RequestPlan(origin: "gallery", path: "pack/money.png"), timeout: 30)
            async let baseD = http.send(RequestPlan(origin: "gallery", path: "pack/pack_base.png"), timeout: 30)
            async let mrD = http.send(RequestPlan(origin: "gallery", path: "pack/pack_mr.png"), timeout: 30)
            async let glbD = http.send(RequestPlan(origin: "gallery", path: "pack/pack.glb"), timeout: 90)
            async let cardsD = http.send(RequestPlan(origin: "gallery", path: "pack/cards.json"), timeout: 30)
            struct Deck: Decodable { let cards: [PackShowCard] }
            var all = try JSONDecoder().decode(Deck.self, from: try await cardsD).cards
            guard !all.isEmpty else { throw PackGLB.Failure(description: "no cards") }
            // Prism = the archive pieces he starred in Curate, nothing else; cards.json's own Prism cards only lend their small image.
            var local: [String: PackShowCard] = [:]
            for c in all where c.tier == "exclusive" { local[c.id] = local[c.id] ?? c }
            var favs: [PackShowCard] = [], favFailed = false
            do {
                struct Favs: Decodable { struct Item: Decodable { let id: String; let name: String?; let src: String? }; let items: [Item]? }
                let d = try await http.send(RequestPlan(origin: "gallery", path: "api/taste", query: ["favs": "1"]), timeout: 30, cache: false)
                let items: [Favs.Item] = try JSONDecoder().decode(Favs.self, from: d).items ?? []
                for f in items {
                    if let l = local[f.id] { favs.append(l); continue }
                    guard let src = f.src else { continue }
                    let name: String = String((f.name ?? "").uppercased().prefix(22))
                    favs.append(PackShowCard(id: f.id, tier: "exclusive", piece: f.id + " \u{00b7} " + name, img: src))
                }
            } catch { favFailed = true; failure = "Prism could not read your favourites: \(Self.plain(error))" }   // one note at a time: the failure, not also "empty"
            all = all.filter { $0.tier != "exclusive" } + favs
            prismEmpty = favs.isEmpty && !favFailed
            cards = all
            if let gd = try? await http.send(RequestPlan(origin: "gallery", path: "pack/pack.json"), timeout: 30), let g = try? JSONDecoder().decode(PackGeometry.self, from: gd) { G = g }   // the defaults are the same numbers
            decks = PackDecks.load() ?? .fresh(Int(Date().timeIntervalSince1970 * 1000) % 100_000)
            let sig = all.filter { $0.tier == "exclusive" }.map { $0.id }.joined(separator: ",")
            if decks.prismSig != sig { decks.piles["exclusive"] = nil; decks.prismSig = sig }   // the Prism pile holds indices: rebuild it when the favourites change
            if decks.cur.map({ $0 >= all.count }) == true { decks.cur = nil }
            opened = decks.opened

            let glb = try PackGLB.parse(try await glbD)
            let need = ["pack", "strip", "card", "slabFront", "slabBack", "label"]
            if let miss = need.first(where: { glb.nodes[$0] == nil }) { throw PackGLB.Failure(description: "pack.glb is missing a part (\(miss))") }
            art = PackArt(tile: try image(try await tileD, "pl_tile.png"), heart: try image(try await heartD, "heart.png"), money: try image(try await moneyD, "money.png"))
            art?.set = settings
            try await build(glb, packBase: try image(try await baseD, "pack_base.png"), packMR: try image(try await mrD, "pack_mr.png"))
            loaded = true
            json = settings.json
            await sealedPack()
        } catch {
            failure = "The pack could not load: \(Self.plain(error))"
        }
    }

    private static func plain(_ e: Error) -> String {
        if let f = e as? PackGLB.Failure { return f.description }
        if let u = e as? URLError { return u.localizedDescription }
        return String(describing: e)
    }

    /// The scene into a RealityView: the camera, the stage, and one update per frame.
    func install(_ content: inout RealityViewCameraContent) {
        content.camera = .virtual
        camera.components.set(PerspectiveCameraComponent(near: 0.01, far: 5, fieldOfViewInDegrees: 30))
        content.add(camera)
        content.add(root)
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] e in
            let dt = e.deltaTime
            MainActor.assumeIsolated { self?.update(min(0.05, dt)) }
        }
        fit(size)
    }

    func stop() { player?.pause(); subscription?.cancel(); subscription = nil }

    /// The camera backs off until the pack and its slab fit the screen in either direction (the page's fit()).
    func fit(_ s: CGSize) {
        guard s.width > 0, s.height > 0 else { return }
        size = s
        let t = Float(tan(15 * Double.pi / 180)), aspect = Float(s.width / s.height)
        camZ = max(0.19 / (2 * t), 0.11 / (2 * t * aspect))
        camera.look(at: [0, 0.008, 0], from: [0, 0.008, camZ], relativeTo: nil)
    }

    // MARK: building the scene from his files

    private func texture(_ img: CGImage, _ s: TextureResource.Semantic) async throws -> TextureResource {
        try await TextureResource(image: img, options: .init(semantic: s))
    }
    /// A material map (red = foil, green = roughness, blue = metallic) as its two grey maps, so either channel RealityKit reads is right.
    private static func split(_ img: CGImage) -> (rough: CGImage?, metal: CGImage?) {
        let w = img.width, h = img.height
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: PackCanvas.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let r = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: PackCanvas.space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let m = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: PackCanvas.space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let src = c.data?.assumingMemoryBound(to: UInt8.self), let rd = r.data?.assumingMemoryBound(to: UInt8.self), let md = m.data?.assumingMemoryBound(to: UInt8.self) else { return (nil, nil) }
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in 0..<(w * h) {
            let o = i * 4, a = Int(src[o + 3])
            let g = a > 0 ? UInt8(min(255, Int(src[o + 1]) * 255 / a)) : 0, b = a > 0 ? UInt8(min(255, Int(src[o + 2]) * 255 / a)) : 0
            rd[o] = g; rd[o + 1] = g; rd[o + 2] = g; rd[o + 3] = 255
            md[o] = b; md[o + 1] = b; md[o + 2] = b; md[o + 3] = 255
        }
        return (r.makeImage(), m.makeImage())
    }

    private func build(_ glb: PackGLB, packBase: CGImage, packMR: CGImage) async throws {
        guard let art, let blank = art.back.image, let blankHD = art.front.image, let lab = art.label.image, let rimI = art.rim.image else { return }
        let pm = Self.split(packMR)
        guard let pr = pm.rough, let pmet = pm.metal else { throw PackGLB.Failure(description: "pack_mr.png could not be read") }
        tex["packBase"] = try await texture(packBase, .color)
        tex["packRough"] = try await texture(pr, .scalar); tex["packMetal"] = try await texture(pmet, .scalar)
        let maps: [(String, CGImage, TextureResource.Semantic)] = [("front", blankHD, .color), ("frontRough", blankHD, .scalar), ("frontMetal", blankHD, .scalar),
                          ("reveal", blank, .color), ("backRough", blank, .scalar), ("backMetal", blank, .scalar), ("label", lab, .color), ("rim", rimI, .color)]
        for (k, i, s) in maps {
            tex[k] = try await texture(i, s)
        }
        let env = try await EnvironmentResource(equirectangular: Self.studio())
        root.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: Self.exposure(settings.sheen.light)))

        func t(_ k: String) -> MaterialParameters.Texture? { tex[k].map { .init($0) } }
        var pack = PhysicallyBasedMaterial()
        pack.baseColor = .init(tint: .white, texture: t("packBase"))
        pack.roughness = .init(scale: 1, texture: t("packRough")); pack.metallic = .init(scale: 1, texture: t("packMetal"))
        pack.clearcoat = .init(floatLiteral: Float(settings.sheen.clearcoat)); pack.clearcoatRoughness = .init(floatLiteral: 0.2)
        var inner = PhysicallyBasedMaterial()   // a dark cavity inside: champagne foil gone to shadow
        inner.baseColor = .init(tint: PackMath.mix(settings.colour.champagne, "#000000", 0.88)); inner.metallic = 1.0; inner.roughness = 0.6; inner.faceCulling = .front
        var cardFront = PhysicallyBasedMaterial()
        cardFront.baseColor = .init(tint: .white, texture: t("front"))
        cardFront.roughness = .init(scale: 1, texture: t("frontRough")); cardFront.metallic = .init(scale: 1, texture: t("frontMetal"))
        var cardBack = PhysicallyBasedMaterial()
        cardBack.baseColor = .init(tint: .white, texture: t("reveal"))
        cardBack.emissiveColor = .init(color: .white, texture: t("rim")); cardBack.emissiveIntensity = 1
        var edge = PhysicallyBasedMaterial(); edge.baseColor = .init(tint: PackMath.ui("#070708")); edge.metallic = 0.0; edge.roughness = 0.55
        var acrylic = PhysicallyBasedMaterial()   // shortcut: no transmission in PhysicallyBasedMaterial; a clear glossy blend stands in until a ShaderGraph acrylic is made
        acrylic.baseColor = .init(tint: .white); acrylic.metallic = 0.0; acrylic.roughness = 0.03; acrylic.clearcoat = 1.0; acrylic.clearcoatRoughness = 0.02
        acrylic.blending = .transparent(opacity: .init(floatLiteral: 0.14))
        var labelM = PhysicallyBasedMaterial(); labelM.baseColor = .init(tint: .white, texture: t("label")); labelM.metallic = 0.0; labelM.roughness = 0.42
        M = ["pack": pack, "packInner": inner, "cardFront": cardFront, "cardBack": cardBack, "cardEdge": edge, "acrylic": acrylic, "label": labelM]

        func entity(_ name: String, _ mesh: PackMesh, override: String? = nil) -> ModelEntity {
            let e = ModelEntity(mesh: mesh.resource, materials: mesh.materials.map { M[override ?? $0] ?? M["cardEdge"] ?? PhysicallyBasedMaterial() })
            e.name = name
            e.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
            return e
        }
        guard let pp = glb.nodes["pack"], let sp = glb.nodes["strip"], let cp = glb.nodes["card"], let sf = glb.nodes["slabFront"], let sb = glb.nodes["slabBack"], let lp = glb.nodes["label"] else { return }
        let pmesh = try await PackMesh(pp), smesh = try await PackMesh(sp)
        packMesh = pmesh; stripMesh = smesh
        packE = [entity("pack", pmesh, override: "pack"), entity("packInner", pmesh, override: "packInner")]
        stripE = [entity("strip", smesh, override: "pack"), entity("stripInner", smesh, override: "packInner")]
        packE.forEach { packGroup.addChild($0) }; stripE.forEach { stripGroup.addChild($0) }
        let c = entity("card", try await PackMesh(cp)); card = c
        slabFront = entity("slabFront", try await PackMesh(sf), override: "acrylic"); slabBack = entity("slabBack", try await PackMesh(sb), override: "acrylic")
        let l = entity("label", try await PackMesh(lp), override: "label"); label = l
        let lb = l.clone(recursive: true); lb.name = "labelBack"; lb.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0]); labelBack = lb   // the grading reads from the back too
        // the corner gussets read as crude (11-16): the acrylic holds the card, so they are not added
        c.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])   // the heart side faces the viewer; the reveal plays on it
        hero.addChild(c)
        [slabFront, slabBack, label, labelBack].compactMap { $0 }.forEach { slabGroup.addChild($0) }
        hero.addChild(slabGroup)
        root.addChild(packGroup); root.addChild(stripGroup); root.addChild(hero)
        flare.components.set(PointLightComponent(color: PackMath.ui("#E3C78F"), intensity: 0, attenuationRadius: 0.12))
        root.addChild(flare)
        let lights: [(SIMD3<Float>, UIColor, Float)] = [([0.3, 0.5, 0.8], .white, 1600), ([-0.6, 0.3, -0.5], PackMath.ui("#ffe0b0"), 1000)]
        for (from, col, lux) in lights {
            let d = Entity(); d.components.set(DirectionalLightComponent(color: col, intensity: lux)); d.look(at: .zero, from: from, relativeTo: nil); root.addChild(d)
        }
    }

    private static func exposure(_ light: Double) -> Float { Float(0.6 + log2(max(0.05, light))) }

    /// The studio the foil reflects (his note 11-16: "doesn't have much hdri"): a dark room of softboxes, the page's panels painted
    /// at their own directions into an equirectangular map. 8-bit, so brightness above white is folded into the light's exposure.
    static func studio() -> CGImage {
        let W = 1024.0, H = 512.0, c = PackCanvas(1024, 512)
        c.fill(PackMath.ui("#0b0c10"))
        let panels: [(w: Double, h: Double, x: Double, y: Double, z: Double, k: Double, tint: String)] = [
            (5.0, 1.6, 0, 4.6, 1.5, 16, "#ffffff"), (0.7, 6.0, -4.4, 0.6, 2.6, 22, "#eaf0ff"), (0.5, 6.0, 4.6, 0.2, 2.0, 18, "#ffe2b0"),
            (1.6, 1.6, 2.4, 1.8, 4.6, 9, "#ffffff"), (6.0, 1.0, 0, -3.6, 3.6, 4, "#ffe9c8"), (0.4, 4.0, -2.6, 1.0, -4.6, 26, "#ffffff"), (0.4, 4.0, 2.9, 0.4, -4.6, 20, "#ffe2b0")]
        for p in panels {
            let dist = (p.x * p.x + p.y * p.y + p.z * p.z).squareRoot(), flat = (p.x * p.x + p.z * p.z).squareRoot()
            let lon = atan2(p.x, p.z), lat = atan2(p.y, flat)
            let aw = 2 * atan(p.w / 2 / dist), ah = 2 * atan(p.h / 2 / dist)
            let u = (0.5 + lon / (2 * .pi)) * W, v = (0.5 - lat / .pi) * H
            let col = PackMath.ui(p.tint).withAlphaComponent(min(1, p.k / 16))
            c.fill(col, CGRect(x: u - aw / (2 * .pi) * W / 2, y: v - ah / .pi * H / 2, width: aw / (2 * .pi) * W, height: ah / .pi * H))
        }
        return c.image ?? PackCanvas(4, 4).image!
    }

    // MARK: the rip: pure functions of rest geometry and the tear front (vault pl-pack-open-v3.py)

    private func tearY(_ x: Double) -> Double { G.TEAR + 0.0009 * sin(x * 140 + 0.7) + 0.00025 * sin(x * 2300 + 1.3) + 0.00015 * sin(x * 6100 + 0.4) }

    private func deformStrip(_ fall: Double) {
        guard let m = stripMesh, stripGroup.isEnabled else { return }
        let R0 = settings.tear.coil / 1000, r = m.rest, f = front
        var out = r
        for i in stride(from: 0, to: r.count - 2, by: 3) {
            let rx = Double(r[i]), ry = Double(r[i + 1]), rz = Double(r[i + 2]), s = max(0, f - rx)
            var x = rx, z = rz
            if s > 0 { let a = s / R0, rr = R0 + 0.00006 * a; x = f - rr * sin(a); z = rz + rr * (1 - cos(a)) }   // a tight roll riding the front
            out[i] = Float(x + 0.05 * fall); out[i + 1] = Float(ry - 0.9 * fall * fall - 0.02 * fall); out[i + 2] = Float(z - 0.10 * fall)   // once free it falls back and down
        }
        m.write(out)
    }

    private func deformPack() {
        guard let m = packMesh else { return }
        let LIP = 0.004, PUSH = settings.tear.lip / 1000, r = m.rest, f = front
        var out = r
        for i in stride(from: 0, to: r.count - 2, by: 3) {
            let rx = Double(r[i]), ry = Double(r[i + 1]), rz = Double(r[i + 2]), d = tearY(rx) - ry
            let k = (d >= 0 && rx < f) ? max(0, 1 - d / LIP) : 0
            guard k > 0 else { continue }
            out[i + 1] = Float(ry - k * PUSH * 0.5); out[i + 2] = Float(rz + (rz >= 0 ? 1 : -1) * k * PUSH)
        }
        m.write(out)
    }

    // MARK: dressing the card

    private func artFor(_ c: PackShowCard) async -> CGImage? {
        if let i = artCache[c.id] { return i }
        guard let http = model?.http else { return nil }
        let d: Data?
        if c.img.hasPrefix("http"), let u = URL(string: c.img) { d = try? await URLSession.shared.data(from: u).0 }
        else { d = try? await http.send(RequestPlan(origin: "gallery", path: PackPaths.path(c.img)), timeout: 30) }
        guard let d, let i = UIImage(data: d)?.cgImage else { failure = "Could not load the art for \(c.piece)."; return nil }
        artCache[c.id] = i
        return i
    }

    private func upload(_ key: String, _ img: CGImage?, _ s: TextureResource.Semantic = .color) {
        guard let img, let t = tex[key] else { return }
        do { try t.replace(withImage: img, options: .init(semantic: s)) } catch { model?.debug.note("pack", "texture \(key) not replaced: \(error)") }
    }
    private func uploadMR(_ prefix: String, _ c: PackCanvas) {
        guard let i = c.image else { return }
        let s = Self.split(i)
        upload(prefix + "Rough", s.rough, .scalar); upload(prefix + "Metal", s.metal, .scalar)
    }
    private func uploadFaces() {
        guard let art else { return }
        upload("front", art.front.image); uploadMR("front", art.frontMR); uploadMR("back", art.backMR); upload("label", art.label.image)
    }

    private func setCard(_ c: PackShowCard, seed: Int, mod: String?) async {
        guard let art else { return }
        art.set = settings
        art.mod = mod.map { (name: $0, seed: (seed & 0xFFFF_FFFF) % 100_000) }
        current = c
        let img = await artFor(c)
        art.composeFront(tier: c.tier, piece: c.piece, art: img); art.composeBack(tier: c.tier); art.composeLabel(tier: c.tier, piece: c.piece)
        art.newReveal(seed: seed, tier: c.tier)
        uploadFaces()
        let e: (String, Float, Float) = c.tier == "common" ? (settings.colour.obsidian, 0, 0.55) : c.tier == "legendary" ? (settings.colour.champagne, 1, 0.2) : ("#F2D48A", 1, 0.12)
        M["cardEdge"]?.baseColor = .init(tint: PackMath.ui(e.0)); M["cardEdge"]?.metallic = .init(floatLiteral: e.1); M["cardEdge"]?.roughness = .init(floatLiteral: e.2)
        applyCard()
        setVideo(c, art: img)
    }

    /// A video card plays in its window, on its front (a plane over the art window, cropped to cover as the page's coverInto does).
    private func setVideo(_ c: PackShowCard, art img: CGImage?) {
        player?.pause(); looper = nil; player = nil
        videoPlane?.removeFromParent(); videoPlane = nil
        guard let v = c.video, let url = PackPaths.url(v, base: base), let card else { return }
        let item = AVPlayerItem(url: url), q = AVQueuePlayer()
        looper = AVPlayerLooper(player: q, templateItem: item); q.isMuted = true; player = q
        let W = PackArt.window, RW = Double(PackArt.RW), RH = Double(PackArt.RH)
        let x0 = Float(-0.0315 + 0.063 * W.minX / RW), x1 = Float(-0.0315 + 0.063 * W.maxX / RW)
        let yT = Float(0.044 - 0.088 * W.minY / RH), yB = Float(0.044 - 0.088 * W.maxY / RH), z: Float = 0.00035
        // shortcut: the crop uses the still's shape, which is the clip's own first frame (cards.json pairs them); a clip of another shape would need its track size
        let va = img.map { Double($0.width) / Double(max(1, $0.height)) } ?? Double(W.width / W.height), wa = Double(W.width / W.height)
        var u0: Float = 0, u1: Float = 1, v0: Float = 0, v1: Float = 1
        if va > wa { let f = Float(wa / va); u0 = (1 - f) / 2; u1 = (1 + f) / 2 } else { let f = Float(va / wa); v0 = (1 - f) / 2; v1 = (1 + f) / 2 }
        var d = MeshDescriptor(name: "video")
        d.positions = MeshBuffers.Positions([[x0, yB, z], [x1, yB, z], [x1, yT, z], [x0, yT, z]])
        d.textureCoordinates = MeshBuffers.TextureCoordinates([[u0, v0], [u1, v0], [u1, v1], [u0, v1]])
        d.primitives = .triangles([0, 1, 2, 0, 2, 3])
        guard let mesh = try? MeshResource.generate(from: [d]) else { model?.debug.note("pack", "video plane not made"); return }
        let p = ModelEntity(mesh: mesh, materials: [VideoMaterial(avPlayer: q)])
        p.isEnabled = false
        card.addChild(p); videoPlane = p
    }

    private func applyCard() {
        guard let card else { return }
        card.model?.materials = ["cardFront", "cardBack", "cardEdge"].compactMap { M[$0] }
    }

    /// The back is foil until it opens; the face under it is printed art.
    private func backAsFoil(_ on: Bool) {
        guard var b = M["cardBack"] else { return }
        if on { b.roughness = .init(scale: 1, texture: tex["backRough"].map { .init($0) }); b.metallic = .init(scale: 1, texture: tex["backMetal"].map { .init($0) }) }
        else { b.roughness = .init(floatLiteral: 0.55); b.metallic = .init(floatLiteral: 0) }
        M["cardBack"] = b; applyCard()
    }

    private func showBack() {
        art?.drawReveal(0); upload("reveal", art?.reveal.image); upload("rim", art?.rim.image); backAsFoil(true)
    }
    private func heartSideUp() { card?.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0]); showBack() }
    private func faceSideUp() { card?.orientation = simd_quatf(angle: 0, axis: [0, 1, 0]); showBack() }
    private var faceUp: Bool { (card?.orientation.angle ?? .pi) < 0.01 }

    private func applySheen() {
        M["pack"]?.clearcoat = .init(floatLiteral: Float(settings.sheen.clearcoat))
        M["packInner"]?.baseColor = .init(tint: PackMath.mix(settings.colour.champagne, "#000000", 0.88))
        for e in packE + stripE { e.model?.materials = [e.name.hasSuffix("Inner") ? M["packInner"] : M["pack"]].compactMap { $0 } }
        if var ibl = root.components[ImageBasedLightComponent.self] { ibl.intensityExponent = Self.exposure(settings.sheen.light); root.components.set(ibl) }
    }

    // MARK: state

    private var cardYHidden: Float { Float(G.TEAR - 0.002 - 0.044) }
    private var cardY8: Float { Float(G.TEAR + 0.008 - 0.044) }
    private var cardY14: Float { cardY8 + 0.006 }

    private func setState(_ s: PackState) {
        state = s; tState = 0; tick += 1
        countText = "Pack \(decks.n + 1) \u{00b7} \(decks.opened.count)/\(cards.count)"
    }

    var stageLabel: String {
        switch state {
        case .sealed: return "A sealed pack. Drag to turn it. Swipe across the top to rip it open."
        case .slabbed: return "Your card, in its slab. Drag to turn it."
        case .viewing: return "A card from your collection. Drag to turn it."
        default: return "The pack is opening."
        }
    }
    var actTitle: String? { state == .slabbed ? "Next pack" : state == .viewing ? "Back to the pack" : nil }

    private func sealedPack() async {
        guard !cards.isEmpty else { return }
        busy = true
        let c: PackShowCard
        if let i = decks.cur, cards.indices.contains(i) { c = cards[i] }
        else if let p = decks.pull(cards, odds: settings.odds) {
            var mr = PackRNG(decks.seed + decks.n * 977 + 11)   // the second, rarer roll, on its own stream
            decks.mod = art?.rollModifier(&mr); c = p
        } else { busy = false; return }
        decks.save()
        await setCard(c, seed: decks.packSeed, mod: decks.mod)
        heartSideUp()
        front = G.X0 - 0.001; fall = 0; autoTear = false; yawHome = false; yaw = -0.42; pitch = 0.06
        packGroup.isEnabled = true; stripGroup.isEnabled = true
        deformStrip(0); deformPack()
        packGroup.position = .zero; packGroup.orientation = simd_quatf(angle: 0, axis: [1, 0, 0])
        hero.position = [0, cardYHidden, 0]; card?.isEnabled = false; slabGroup.isEnabled = false
        flare.components[PointLightComponent.self]?.intensity = 0
        busy = false
        setState(.sealed)
    }

    private func markOpened() {
        guard let id = current?.id, !decks.opened.contains(id) else { return }
        decks.opened.append(id); decks.save(); opened = decks.opened
    }

    private var playing: Bool { [.revealed, .slabbing, .slabbed, .viewing].contains(state) }

    private func update(_ dt: Double) {
        guard loaded else { return }
        frame += 1
        tState += dt
        let TM = settings.timing
        if state == .sealed && autoTear { setState(.tearing) }
        switch state {
        case .tearing:
            if autoTear { front = G.X0 + (G.X1 - G.X0 + 0.004) * PackMath.ease(tState / TM.tearAuto) }
            deformStrip(0); deformPack()
            let fx = min(front, G.X1)
            flare.position = [Float(fx), Float(tearY(fx)), 0.004]; setFlare(0.02)
            if front >= G.X1 + 0.003 { card?.isEnabled = true; setState(.rising) }   // the last bridge breaks
        case .rising:
            fall += dt
            if stripGroup.isEnabled { deformStrip(fall) }
            stripGroup.isEnabled = fall < 0.8
            let t = tState, t1 = TM.emerge, t2 = t1 + TM.pull, t3 = t2 + TM.catch, t4 = t3 + TM.clear
            let y: Float = t < t1 ? Float(PackMath.lerp(Double(cardYHidden), Double(cardY8), PackMath.ease(t / t1)))
                : t < t2 ? Float(PackMath.lerp(Double(cardY8), Double(cardY14), 1 - pow(1 - (t - t1) / TM.pull, 2))) : cardY14   // 8 mm, +6 mm, the catch
            hero.position.y = y
            let w = PackMath.clamp((t - t3) / (TM.clear + 0.12), 0, 1)   // the wrapper leaves
            packGroup.position = [0, Float(-0.26 * w * w), Float(-0.01 * w)]; packGroup.orientation = simd_quatf(angle: Float(0.25 * w), axis: [1, 0, 0])
            packGroup.isEnabled = w < 1
            flare.position = [0, Float(G.TEAR - 0.004), 0]; setFlare(0.02 * (1 - PackMath.ease((t - t3) / 0.4))); yawHome = true
            if t >= t4 + 0.12 { setState(.poised) }
        case .poised:
            if tState >= TM.poise { backAsFoil(false); setState(.revealing) }
        case .revealing:
            let u = min(1, tState / TM.reveal)
            art?.drawReveal(u)
            if frame % 2 == 0 || u >= 1 { upload("reveal", art?.reveal.image); upload("rim", art?.rim.image) }   // shortcut: a blocking replace every other frame; DrawableQueue if it stutters on the phone
            if u >= 1 { faceSideUp(); markOpened(); setState(.revealed) }
        case .revealed:
            if tState >= TM.clean { slabGroup.isEnabled = true; setState(.slabbing) }
        case .slabbing:
            let k = TM.slab / 0.95, b = PackMath.ease(tState / (0.45 * k)), c = PackMath.ease((tState - 0.25 * k) / (0.55 * k)), drop = Float(0.18 * pow(1 - c, 2))
            slabBack?.position = [0, 0, Float(-0.10 * (1 - b))]
            slabFront?.position = [0, drop, 0]; label?.position = [0, drop, 0]; labelBack?.position = [0, drop, 0]
            if tState >= TM.slab { setState(.slabbed) }
        default: break
        }
        let show = playing && faceUp && player != nil
        videoPlane?.isEnabled = show
        if show { if player?.rate == 0 { player?.play() } } else if player?.rate != 0 { player?.pause() }
        if yawHome && dragging == nil {
            let k = min(1, dt * 5); yaw += (0 - yaw) * k; pitch += (0 - pitch) * k
            if abs(yaw) < 0.002 { yawHome = false }
        }
        let rest = dragging == nil && !still && [.sealed, .slabbed, .viewing].contains(state), now = Date().timeIntervalSince1970
        swayK += ((rest ? 1 : 0) - swayK) * min(1, dt * 3)
        let sw = settings.sheen.sway
        stageQ = simd_quatf(angle: Float(pitch + sin(now * 0.53) * 0.035 * swayK * sw), axis: [1, 0, 0]) * simd_quatf(angle: Float(yaw + sin(now * 0.8) * 0.16 * swayK * sw), axis: [0, 1, 0])
        root.orientation = stageQ
        let target = [.sealed, .slabbed, .viewing].contains(state) ? settings.background.rest : state == .slabbing ? settings.background.slab : settings.background.during
        bgK += (target - bgK) * min(1, dt * 3)
        bgClock += dt * 60 * settings.background.speed * ((state == .slabbed || state == .viewing) ? 1.0 / 3 : 1)
    }

    private func setFlare(_ v: Double) { flare.components[PointLightComponent.self]?.intensity = Float(v * 4 * .pi * 1000) }   // the page's candela as RealityKit lumens, scaled to its exposure

    // MARK: input: drag = turn; a swipe that starts on the top seal = the tear follows the finger; a tap = open

    private func project(_ p: SIMD3<Float>) -> CGPoint {
        let w = stageQ.act(p), t = Float(tan(15 * Double.pi / 180)), aspect = Float(size.width / size.height)
        let vx = w.x, vy = w.y - 0.008, vz = w.z - camZ
        let nx = (vx / -vz) / (t * aspect), ny = (vy / -vz) / t
        return CGPoint(x: CGFloat((nx + 1) / 2) * size.width, y: CGFloat((1 - ny) / 2) * size.height)
    }
    private func sealRect() -> (x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat) {
        let a = project([Float(G.X0), Float(G.TOP), 0.002]), b = project([Float(G.X1), Float(G.TOP), 0.002])
        let c = project([Float(G.X0), Float(G.TEAR - 0.006), 0.002]), d = project([Float(G.X1), Float(G.TEAR - 0.006), 0.002])
        return (min(a.x, c.x), max(b.x, d.x), min(a.y, b.y) - 28, max(c.y, d.y) + 28)
    }

    func drag(_ p: CGPoint) {
        guard loaded else { return }
        if dragging == nil {
            guard !busy else { return }
            let r = sealRect()
            let onSeal = (state == .sealed || (state == .tearing && !autoTear)) && p.x > r.x0 - 30 && p.x < r.x1 + 30 && p.y > r.y0 && p.y < r.y1
            dragging = (tear: onSeal, x: p.x, y: p.y, t: Date(), moved: 0)
            return
        }
        guard var d = dragging else { return }
        let dx = p.x - d.x, dy = p.y - d.y
        d.x = p.x; d.y = p.y; d.moved += abs(dx) + abs(dy); dragging = d
        if d.tear {
            let r = sealRect(), frac = (p.x - r.x0) / max(1, r.x1 - r.x0)
            if d.moved > 6 {
                if state == .sealed { setState(.tearing) }
                front = max(front, G.X0 + (G.X1 - G.X0 + 0.004) * min(1.02, max(0, Double(frac))))
            }
        } else {
            yaw += Double(dx) * 0.008; pitch = max(-0.6, min(0.6, pitch + Double(dy) * 0.005)); yawHome = false
        }
    }
    func lift() {
        if let d = dragging, d.moved < 6, Date().timeIntervalSince(d.t) < 0.3, state == .sealed { autoTear = true }
        dragging = nil
    }
    func tapOpen() { if state == .sealed && !busy { autoTear = true } }

    // MARK: the act button, the collection, the editor

    func act() async {
        guard !busy else { return }
        if state == .viewing {
            let r = resume; resume = nil; pvTier = ""
            if let r, r.state == .slabbed, let c = r.card {
                busy = true
                await setCard(c, seed: r.seed, mod: r.mod); faceSideUp()
                hero.position.y = cardY14; packGroup.isEnabled = false; stripGroup.isEnabled = false; card?.isEnabled = true; slabGroup.isEnabled = true; yaw = 0
                busy = false; setState(.slabbed)
            } else { await sealedPack() }
            return
        }
        guard state == .slabbed else { return }
        decks.n += 1; decks.cur = nil
        await sealedPack()   // the next pack: a new pull, a new tear
    }

    /// One card on its own, to turn in the hand.
    func view(_ c: PackShowCard, keepSheet: Bool = false) async {
        guard !busy, [.sealed, .slabbed, .viewing].contains(state) else { return }
        busy = true
        if !keepSheet { sheet = nil }
        if state == .slabbed { resume = (state: .slabbed, card: current, seed: decks.packSeed, mod: art?.mod?.name) }
        else if state != .viewing { resume = (state: .sealed, card: nil, seed: 0, mod: nil) }
        await setCard(c, seed: decks.seed + (cards.firstIndex(of: c) ?? 0), mod: pvMod.isEmpty ? nil : pvMod)
        faceSideUp()
        packGroup.isEnabled = false; stripGroup.isEnabled = false; card?.isEnabled = true; slabGroup.isEnabled = true
        for e in [slabBack, slabFront, label, labelBack] { e?.position = .zero }
        hero.position = [0, cardY14, 0]; yaw = 0.25; pitch = 0.04; yawHome = false
        busy = false; setState(.viewing)
    }

    private func need() -> Bool {
        if state == .viewing { return true }
        said = "Pick a tier under \"Show a card\" first."; return false
    }

    func previewTier(_ t: String) async {
        pvTier = t
        if t.isEmpty { if state == .viewing { await act() }; return }
        if let c = cards.first(where: { $0.tier == t }) { await view(c, keepSheet: true) }
    }
    func previewMod(_ m: String) async {
        pvMod = m
        let t = pvTier
        if let c = current.flatMap({ t.isEmpty || $0.tier == t ? $0 : nil }) ?? cards.first(where: { $0.tier == t }) { await view(c, keepSheet: true) }
    }
    func showFront() { if need() { faceSideUp(); slabGroup.isEnabled = true; yaw = 0.25 } }
    func showRealBack() { if need() { faceSideUp(); slabGroup.isEnabled = true; yaw = .pi + 0.25 } }   // the card's real back, turned toward him
    func playReveal() {
        guard need() else { return }
        slabGroup.isEnabled = false; heartSideUp(); sheet = nil; yaw = 0; pitch = 0; setState(.poised)
    }
    func copySettings() { json = settings.json; UIPasteboard.general.string = json; said = "Copied. Paste it to Claude." }
    func applyPasted() {
        do {
            guard let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { throw PackGLB.Failure(description: "not an object") }
            settings = try PackSettings.merged(o); redraw(); said = "Applied."
        } catch { said = "That text is not settings: \(Self.plain(error))" }
    }
    func defaults() { settings = PackSettings(); redraw(); said = "Back to the defaults." }
    func newDecks() async {
        guard !busy else { return }
        decks = .fresh(Int.random(in: 0..<100_000)); decks.save(); opened = []
        sheet = nil; resume = nil; pvTier = ""
        await sealedPack()
    }
    func palette(_ name: String) {
        guard let p = PackTier.house.first(where: { $0.name == name }) else { return }
        settings.colour.ground = p.ground; settings.colour.curves = p.key; redraw()
    }

    /// Every control writes SETTINGS and the card redraws at once (60 ms after the last change, as the page does).
    func redraw() {
        redrawTask?.cancel()
        redrawTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, !Task.isCancelled else { return }
            settings.save(); applySheen(); json = settings.json
            guard let c = current, !busy, let art else { return }
            art.set = settings
            art.composeFront(tier: c.tier, piece: c.piece, art: artCache[c.id]); art.composeBack(tier: c.tier); art.composeLabel(tier: c.tier, piece: c.piece)
            art.newReveal(seed: decks.packSeed, tier: c.tier)
            uploadFaces()
            if state != .revealing { showBack() }
        }
    }
}
