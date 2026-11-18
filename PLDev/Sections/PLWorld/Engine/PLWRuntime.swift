import SwiftUI
import RealityKit
import Combine
import UIKit
import simd

/// The integrator: the one place that drives a room. It owns the engine view's frame, the character controller (gravity, double jump, the orb),
/// the camera rig, the triggers, the glyph keys, the save and the palette. A room never touches any of these; it answers `step` and `receive`
/// with commands, and this validates and applies each one (idempotently). One room is loaded at a time here; the ring (lane B) places several.
@MainActor @Observable final class PLWRuntime {
    // what the screen watches
    private(set) var ready = false
    private(set) var loadFailed = false
    private(set) var caption: String?
    private(set) var fps = 0
    private(set) var frameMS: Float = 0
    private(set) var worstMS: Float = 0
    private(set) var readout = ""

    let engine = WorldEngine(fov: 62, far: 1400)
    let input = PLWInput()
    let store: PLWSaveStore
    let tuning = PLWTuning.shared
    private let camera = PLWCameraRig()
    private let figure = PLWHeroFigure()
    private let player = Entity()           // the capsule's centre
    private let visual = Entity()           // feet at the capsule's base; turns to face where he goes
    private let ball = ModelEntity()
    private let dreamOrb = ModelEntity()
    @ObservationIgnored private var room: (any PLWRoom)?
    @ObservationIgnored private var markers: [PLWKey: Entity] = [:]
    @ObservationIgnored private var subs: [Cancellable] = []
    @ObservationIgnored private var active: Set<String> = []    // triggers the player stands in
    @ObservationIgnored private var tunnels = 0

    @ObservationIgnored private var vel = SIMD3<Float>.zero
    @ObservationIgnored private var jumpsUsed = 0
    @ObservationIgnored private var coyote: Float = 0
    @ObservationIgnored private var jumpBuffer: Float = 0
    @ObservationIgnored private var airLock: Float = 0
    @ObservationIgnored private var wasGrounded = true
    @ObservationIgnored private var facing: Float = 0
    @ObservationIgnored private var clock: Float = 0
    @ObservationIgnored private var jumpTimes: [Float] = []
    @ObservationIgnored private var asBall = false
    @ObservationIgnored private var dreamRise: Float = 0
    @ObservationIgnored private var captionUntil: Float = 0
    @ObservationIgnored private var statTime: Float = 0
    @ObservationIgnored private var statFrames = 0
    @ObservationIgnored private var statWorst: Float = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var pendingLift: Float = 0                      // updraft acceleration a room asked for, used on the next frame
    @ObservationIgnored private var railPoints: [SIMD3<Float>] = []             // room-local zip path; empty = not on a rail
    @ObservationIgnored private var railIndex = 0
    @ObservationIgnored private var railSpeed: Float = 0
    private let softKick = UIImpactFeedbackGenerator(style: .soft)
    private let lightKick = UIImpactFeedbackGenerator(style: .light)
    /// glTF models face +Z. If a hero is seen walking backwards on device, this one value (set to .pi) fixes it.
    private let facingOffset: Float = 0

    init(store: PLWSaveStore) { self.store = store }

    // MARK: start, enter, stop

    func start() async {
        guard !started else { return }
        started = true
        let t = tuning
        player.name = "plw.player"
        player.components.set(CharacterControllerComponent(radius: t.capsuleRadius, height: t.capsuleHeight,
                                                           slopeLimit: t.slopeLimitDegrees * .pi / 180, stepLimit: t.stepLimit))
        visual.position.y = -t.capsuleHeight / 2
        player.addChild(visual)
        await figure.load(store.save.hero, height: t.capsuleHeight)
        if figure.missing {
            AppModel.shared.debug.note("plworld", "hero model missing; stand-in shown")
            let skin = SimpleMaterial(color: .systemYellow, roughness: 0.6, isMetallic: false)
            let body = ModelEntity(mesh: .generateCylinder(height: 1.3, radius: 0.28), materials: [skin]); body.position.y = 0.65
            let head = ModelEntity(mesh: .generateSphere(radius: 0.22), materials: [skin]); head.position.y = 1.5
            figure.root.addChild(body); figure.root.addChild(head)
        }
        visual.addChild(figure.root)
        ball.model = ModelComponent(mesh: .generateSphere(radius: 0.55), materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.93, blue: 0.7, alpha: 1))])
        ball.position.y = 0.55; ball.isEnabled = false
        visual.addChild(ball)
        dreamOrb.model = ModelComponent(mesh: .generateSphere(radius: 0.22), materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.9, blue: 0.62, alpha: 1))])
        dreamOrb.isEnabled = false
        player.addChild(dreamOrb)
        engine.add(player)
        if let scene = engine.view?.scene { listen(scene) }
        await enter(store.save.checkpointArea, port: store.save.checkpointPort)
        engine.onFrame = { [weak self] dt in self?.frame(dt) }
    }

    func stop() {
        engine.onFrame = { _ in }
        subs.forEach { $0.cancel() }; subs = []
        room?.unload(); room = nil
        store.flush()
    }

    /// Loads `area`, stands the hero on its `port` and applies the look. The previous room is unloaded first.
    func enter(_ area: PLWArea, port: String) async {
        ready = false
        railPoints = []; pendingLift = 0
        room?.unload(); markers = [:]; active = []; tunnels = 0; camera.lean = nil; camera.firstPerson = false
        let r = PLWRoomRegistry.make(area)
        do { try await r.load() } catch {
            AppModel.shared.debug.note("plworld", "room \(area.rawValue) did not load: \(error.localizedDescription)")
            loadFailed = true; return
        }
        r.restore(store.save)
        engine.add(r.root)
        solidify(r.root)
        for t in r.triggers { r.root.addChild(triggerEntity(t)) }
        for g in r.glyphs where !store.save.glyphs.contains(g.key) { markers[g.key] = marker(g, in: r.root) }
        room = r
        store.commit { $0.reached.insert(area) }
        applyLook()
        place(at: port)
        updateDreamOrb()
        ready = true
    }

    private func place(at port: String) {
        guard let r = room else { return }
        let tr = r.ports[port] ?? r.ports["start"] ?? Transform()
        let p = r.root.convert(position: tr.translation, to: nil)
        player.position = p + SIMD3(0, tuning.capsuleHeight / 2 + 0.05, 0)
        let fwd = tr.rotation.act(SIMD3<Float>(0, 0, -1))
        camera.yaw = atan2(-fwd.x, -fwd.z); camera.snap()
        facing = camera.yaw; vel = .zero; airLock = 0.2
    }

    // MARK: building blocks

    /// The contract gives every solid piece a static collision shape; the character controller wants a static body as well, so add one.
    private func solidify(_ e: Entity) {
        if let c = e.components[CollisionComponent.self], c.mode != .trigger, !e.components.has(PhysicsBodyComponent.self) {
            e.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .static))
        }
        for k in e.children { solidify(k) }
    }

    private func triggerEntity(_ t: PLWTrigger) -> Entity {
        let e = Entity()
        e.name = "plw.trigger.\(t.id)"
        e.position = t.center
        e.orientation = simd_quatf(angle: t.yaw, axis: [0, 1, 0])
        e.components.set(CollisionComponent(shapes: [.generateBox(size: t.halfExtents * 2)], mode: .trigger))
        return e
    }

    private func marker(_ g: PLWGlyphPlacement, in root: Entity) -> Entity {
        let gold = SimpleMaterial(color: UIColor(red: 1, green: 0.82, blue: 0.35, alpha: 1), roughness: 0.25, isMetallic: true)
        let e = ModelEntity(mesh: .generateSphere(radius: 0.17), materials: [gold])
        e.name = "plw.glyph"
        e.position = g.position
        root.addChild(e)
        return e
    }

    private func listen(_ scene: RealityKit.Scene) {
        subs.append(scene.subscribe(to: CollisionEvents.Began.self) { [weak self] e in
            MainActor.assumeIsolated { self?.contact(e.entityA, e.entityB, began: true) }
        })
        subs.append(scene.subscribe(to: CollisionEvents.Ended.self) { [weak self] e in
            MainActor.assumeIsolated { self?.contact(e.entityA, e.entityB, began: false) }
        })
    }

    private func contact(_ a: Entity, _ b: Entity, began: Bool) {
        guard let room else { return }
        let pair = [a, b]
        guard pair.contains(where: { $0.name == "plw.player" }), let t = pair.first(where: { $0.name.hasPrefix("plw.trigger.") }) else { return }
        let id = String(t.name.dropFirst("plw.trigger.".count))
        if began { guard active.insert(id).inserted else { return } } else { guard active.remove(id) != nil else { return } }
        if id.hasPrefix("tunnel") {   // a tunnel trigger puts the camera in first person for as long as he is inside
            tunnels = max(0, tunnels + (began ? 1 : -1)); camera.firstPerson = tunnels > 0
            figure.setVisible(!camera.firstPerson && !asBall)
        }
        apply(room.receive(PLWTriggerEvent(id: id, phase: began ? .entered : .exited)), from: room)
    }

    // MARK: the frame

    private func frame(_ rawDt: Float) {
        guard ready, let room else { return }
        let dt = min(rawDt, 0.05)                                  // a hitch never throws him through a floor
        clock += dt
        tick(rawDt)
        var s = input.sample()
        camera.yaw += s.lookYaw; camera.pitch += s.lookPitch
        let onRail = !railPoints.isEmpty
        if onRail { s.move = .zero; s.jumpPressed = false; s.actPressed = false }   // input is locked until the rail ends

        // the orb: JUMP twice, then ACT within 1.3 s, and he rolls as the dream orb at three times the speed; the same again and he is himself
        if s.jumpPressed { jumpTimes.append(clock); if jumpTimes.count > 3 { jumpTimes.removeFirst() } }
        if s.actPressed, jumpTimes.count >= 2, clock - jumpTimes[jumpTimes.count - 2] < 1.3 {
            jumpTimes = []; asBall.toggle(); s.actPressed = false
            ball.isEnabled = asBall; figure.setVisible(!asBall && !camera.firstPerson)
        }

        let t = tuning
        let state = player.components[CharacterControllerStateComponent.self]
        airLock = max(0, airLock - dt)
        let grounded = (state?.isOnGround ?? false) && airLock == 0
        if grounded { coyote = 0.1; jumpsUsed = 0 } else { coyote = max(0, coyote - dt) }
        if !grounded && coyote == 0 && jumpsUsed == 0 { jumpsUsed = 1 }       // walked off a ledge: the next press is the double jump
        jumpBuffer = s.jumpPressed ? 0.14 : max(0, jumpBuffer - dt)

        // horizontal: the stick relative to the camera, easing toward the wanted speed
        let raw = simd_length(s.move)
        let mag: Float = raw < 0.08 ? 0 : min(1, (raw - 0.08) / 0.7)           // a small dead zone, full walk at 78% of the stick
        let runShare = max(0, min(1, (raw - 0.85) / 0.15))
        var top = (t.walk * mag) * (1 - runShare) + t.run * runShare
        if asBall { top *= t.orbSpeedFactor }
        let fwd = SIMD3<Float>(-sin(camera.yaw), 0, -cos(camera.yaw)), right = SIMD3<Float>(cos(camera.yaw), 0, -sin(camera.yaw))
        var wish = fwd * s.move.y + right * s.move.x
        if simd_length_squared(wish) > 1e-6 { wish = simd_normalize(wish) }
        let target = wish * top * (grounded ? 1 : t.airControl)
        var h = SIMD3<Float>(vel.x, 0, vel.z)
        let dv = target - h, step = (grounded ? t.groundAccel : t.airAccel) * dt
        h += simd_length(dv) <= step ? dv : simd_normalize(dv) * step
        vel.x = h.x; vel.z = h.z

        // vertical: gravity, jump, double jump
        if grounded && vel.y <= 0 { vel.y = -1 } else { vel.y -= t.gravity * dt }
        if jumpBuffer > 0 {
            if (grounded || coyote > 0) && jumpsUsed == 0 {
                vel.y = (2 * t.gravity * t.jumpPeak).squareRoot(); jumpsUsed = 1; jumpBuffer = 0; coyote = 0; airLock = 0.12; kick(.light)
            } else if !grounded && jumpsUsed < 2 {
                vel.y = (2 * t.gravity * t.doubleJumpPeak).squareRoot(); jumpsUsed = 2; jumpBuffer = 0; airLock = 0.1; kick(.light)
            }
        }
        vel.y += pendingLift * dt; pendingLift = 0
        if onRail { vel = railVelocity(room, dt) }
        if vel.y > 0, !onRail, airLock == 0, let sv = state?.velocity.y, sv < vel.y * 0.2 { vel.y = 0 }   // his head met a ceiling

        player.moveCharacter(by: vel * dt, deltaTime: dt, relativeTo: nil)
        if grounded, !wasGrounded { kick(.soft) }
        wasGrounded = grounded
        let feet = player.position - SIMD3(0, t.capsuleHeight / 2, 0)
        if feet.y < -80 { Task { await respawn() }; return }                    // fell out of the world: back to the last checkpoint

        // the hero: turns toward where he goes, plays idle, walking or jump
        let speed = simd_length(SIMD2(vel.x, vel.z))
        if mag > 0.05 { var d = atan2(wish.x, wish.z) + facingOffset - facing; d = atan2(sin(d), cos(d)); facing += d * min(1, dt * 10) }
        visual.orientation = simd_quatf(angle: facing, axis: [0, 1, 0])
        figure.play(!grounded ? .jump : (speed > 0.4 ? .walking : .idle))
        dreamOrb.position = SIMD3(0.55, t.capsuleHeight / 2 + 0.35 + dreamRise * 1.1 + sin(clock * 1.8) * 0.06, 0)

        // the room
        let local = room.root.convert(position: feet, from: nil)
        let pf = PLWFrame(dt: dt, position: local, velocity: room.root.convert(direction: vel, from: nil),
                             lookDirection: simd_normalize(room.root.convert(direction: camera.forward(), from: nil)), grounded: grounded,
                             jumpPressed: s.jumpPressed, jumpHeld: s.jumpHeld, actPressed: s.actPressed, actHeld: s.actHeld, save: store.save)
        var cmds = room.step(pf)
        for id in active { cmds += room.receive(PLWTriggerEvent(id: id, phase: .stayed)) }
        apply(cmds, from: room)
        if s.actPressed { collectNearest(room, around: local + SIMD3(0, 0.9, 0)) }
        for (_, m) in markers { m.orientation = simd_quatf(angle: clock * 1.2, axis: [0, 1, 0]) }

        camera.update(dt: dt, hero: player.position, camera: engine.camera, scene: engine.view?.scene)
        if caption != nil, clock > captionUntil { caption = nil }
        if t.debug { readout = String(format: "x %.1f  y %.1f  z %.1f  %@  %.1f m/s", local.x, local.y, local.z, grounded ? "ground" : "air", speed) }
    }

    /// The velocity that carries his feet along the rail's room-local points at its speed; clears the rail at the last point.
    private func railVelocity(_ room: any PLWRoom, _ dt: Float) -> SIMD3<Float> {
        let feet = player.position - SIMD3(0, tuning.capsuleHeight / 2, 0)
        let d = room.root.convert(position: railPoints[railIndex], to: nil) - feet
        let dist = simd_length(d), stride = railSpeed * dt
        if dist <= stride {
            railIndex += 1
            if railIndex >= railPoints.count { railPoints = []; jumpsUsed = 0 }
            return d / max(dt, 0.001)
        }
        return d / dist * railSpeed
    }

    private func respawn() async {
        let s = store.save
        if room?.id == s.checkpointArea { place(at: s.checkpointPort) } else { await enter(s.checkpointArea, port: s.checkpointPort) }
    }

    private func tick(_ dt: Float) {
        statTime += dt; statFrames += 1; statWorst = max(statWorst, dt)
        if statTime >= 0.5 {
            fps = Int((Float(statFrames) / statTime).rounded()); frameMS = statTime / Float(statFrames) * 1000; worstMS = statWorst * 1000
            statTime = 0; statFrames = 0; statWorst = 0
        }
    }

    // MARK: commands

    /// A gate is open when its rule says so; with `PLWGating.enforced` off (his ruling 11-17) every gate is open.
    func isOpen(_ g: PLWGate) -> Bool { g.isOpen(store.save) }

    private func apply(_ cmds: [PLWCommand], from room: any PLWRoom) {
        for c in cmds {
            switch c {
            case .completeMoment(let a):
                guard a == room.id, !store.save.completed.contains(a) else { continue }
                store.commit {
                    $0.completed.insert(a)
                    if let p = a.page { $0.unlocks.insert("page\(p)"); $0.reached.insert(PLWArea(rawValue: p + 1) ?? .hub) }
                }
                applyLook(); PLHaptics.keep()
            case .collect(let k):
                guard room.glyphs.contains(where: { $0.key == k }), !store.save.glyphs.contains(k) else { continue }
                store.commit { $0.glyphs.insert(k) }
                markers.removeValue(forKey: k)?.removeFromParent(); PLHaptics.keep()
            case .mark(let m):
                guard (1...64).contains(m.count), !store.save.marks.contains(m) else { continue }
                store.commit { $0.marks.insert(m) }
            case .roomFlag(let a, let f):
                guard a == room.id, (1...64).contains(f.count), !(store.save.roomFlags[a.rawValue]?.contains(f) ?? false) else { continue }
                store.commit { $0.roomFlags[a.rawValue, default: []].insert(f) }
            case .dream(let d):
                guard store.save.dream != d else { continue }
                store.commit { $0.dream = d }
                updateDreamOrb(); applyLook()
            case .checkpoint(let a, let port):
                guard a == room.id, room.ports[port] != nil, !(store.save.checkpointArea == a && store.save.checkpointPort == port) else { continue }
                store.commit { $0.checkpointArea = a; $0.checkpointPort = port }
            case .camera(let p, let t, let w):
                guard w.isFinite, p.x.isFinite, t.x.isFinite else { continue }
                camera.lean = w > 0 ? PLWCameraRig.Lean(position: room.root.convert(position: p, to: nil), target: room.root.convert(position: t, to: nil), weight: min(1, w)) : nil
            case .lift(let a):
                if a.isFinite { pendingLift = max(0, min(30, a)) }
            case .rail(let pts, let speed):
                guard railPoints.isEmpty, (2...64).contains(pts.count), speed.isFinite, (0.5...40).contains(speed), pts.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { continue }
                railPoints = pts; railIndex = 0; railSpeed = speed; vel = .zero
            case .raiseDream(let f):
                dreamRise = f.isFinite ? max(0, min(1, f)) : 0
            case .caption(let s):
                let line = s.replacingOccurrences(of: "\u{2014}", with: ",")      // house copy: no em dashes, never the word "manifest"
                guard !line.isEmpty, line.count <= 140, !line.lowercased().contains("manifest") else { continue }
                caption = line; captionUntil = clock + 4.5
            }
        }
    }

    private func collectNearest(_ room: any PLWRoom, around p: SIMD3<Float>) {
        let near = room.glyphs.filter { markers[$0.key] != nil }.min { simd_distance($0.position, p) < simd_distance($1.position, p) }
        if let g = near, simd_distance(g.position, p) < 1.8 { apply([.collect(g.key)], from: room) }
    }

    private func updateDreamOrb() {
        let d = store.save.dream
        dreamOrb.isEnabled = d == .carried || d == .recovered
        if d == .absent || d == .buried { dreamRise = 0 }
    }

    /// The palette: the page colour at its vividness. Fog and the sky are the page hue, never black.
    private func applyLook() {
        guard let room else { return }
        let look = PLWPalette.look(room.id, store.save)
        room.apply(look)
        let c = PLWPalette.saturate(look.fogRGB, look.saturation)
        engine.view?.environment.background = .color(UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1))
    }

    private func kick(_ s: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard PLHaptics.on else { return }
        (s == .soft ? softKick : lightKick).impactOccurred()
    }
}
