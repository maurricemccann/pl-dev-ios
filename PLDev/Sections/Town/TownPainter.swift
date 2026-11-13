import UIKit
import SpriteKit
import SceneKit

/// Paints the street once per light mode: sidewalk, a hazy back row, every facade (brick or panels, cornice, windows lit by the hour,
/// door, roof, neon sign), lamps and the clock face. The web paints the same street on a canvas; this draws it into one image.
enum TownPainter {
    static func street(mode: TownLight, now: Date = Date()) -> UIImage {
        let LW = TownStreet.width, LH = TownStreet.LH, WALK = TownStreet.WALK, G = WALK - 4
        let lit = mode != .day, night = mode == .night
        var seed: UInt64 = 7
        func rnd() -> CGFloat { seed = (seed &* 16807) % 2147483647; return CGFloat(seed) / 2147483647 }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 2; fmt.opaque = false
        let r = UIGraphicsImageRenderer(size: CGSize(width: LW, height: LH), format: fmt)
        return r.image { rc in
            let g = rc.cgContext
            g.interpolationQuality = .none
            func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: UIColor) { g.setFillColor(c.cgColor); g.fill(CGRect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())) }
            func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ c: UIColor) {
                (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: size, weight: .heavy), .foregroundColor: c])
            }
            // the back row: hazier buildings behind the street
            let haze = townHex("#7f8fb0")
            let BR = ["#6a4a5a", "#4a5a78", "#6a6a52", "#7a5048", "#4a6a6a", "#5a4a78"].map(townHex)
            var bx: CGFloat = -8
            while bx < LW {
                let bw = 34 + (rnd() * 34).rounded(.down), bh = 100 + (rnd() * 96).rounded(.down), top = G - bh
                let col = townMix(BR[Int(rnd() * CGFloat(BR.count)) % BR.count], haze, 0.4)
                px(bx, top, bw, bh, col); px(bx, top, bw, 2, townTint(col, 1.25)); px(bx + bw - 2, top, 2, bh, townTint(col, 0.7))
                var wy = top + 8
                while wy < G - 52 {
                    var wx = bx + 5
                    while wx < bx + bw - 9 {
                        let on = lit && rnd() < (night ? 0.42 : 0.22)
                        let cc = [townHex("#ffd27a"), townHex("#bfe9ff"), townHex("#ff9ad8")][Int(rnd() * 3) % 3]
                        px(wx - 1, wy - 1, 8, 10, townTint(col, 0.6))
                        px(wx, wy, 6, 8, on ? cc : (night ? townHex("#1c2840") : townMix(townHex("#6a98c0"), haze, 0.3)))
                        wx += 11
                    }
                    wy += 14
                }
                bx += bw + (rnd() * 6).rounded(.down)
            }
            // behind the street: a back wall
            px(0, G - 40, LW, 40, townHex("#6a3e30"))
            var yy = G - 39
            while yy < G { var x: CGFloat = Int(yy / 4) % 2 == 0 ? 4 : 0; while x < LW { px(x, yy, 7, 3, townHex(rnd() < 0.15 ? "#7a4636" : "#74443a")); x += 8 }; yy += 4 }
            // the sidewalk and curb
            px(0, G, LW, 12, townHex("#bdb5a5"))
            var sx: CGFloat = 0; while sx < LW { px(sx, G, 1, 12, townHex("#9a9282")); sx += 24 }
            px(0, G, LW, 1, townHex("#d4ccbc")); px(0, G + 12, LW, 3, townHex("#8a847a")); px(0, G + 15, LW, LH - G - 15, townHex("#4a4642"))

            for b in TownStreet.buildings {
                let x = b.x, w = b.w, h = b.h, top = G - h
                if b.lot {   // the stale lot: dirt, weeds, a broken fence, a sign
                    px(x, G - 3, w, 3, townHex("#6a5a40"))
                    var k: CGFloat = 0; while k < w { px(x + k, G - 4 - rnd() * 3, 1, 3, townHex("#5a7a30")); k += 3 }
                    k = 0; while k < w { px(x + k, G - 18 + (rnd() < 0.3 ? 5 : 0), 3, 18, townHex("#7a6040")); k += 8 }
                    px(x, G - 14, w, 2, townHex("#6a5034")); px(x, G - 8, w, 2, townHex("#6a5034"))
                    px(x + w / 2 - 22, G - 44, 44, 13, townHex("#2a1a10")); px(x + w / 2 - 21, G - 43, 42, 11, townHex("#8a5a28"))
                    text(b.label, x + w / 2 - 17, G - 42, 7, townHex("#f8ecd0")); px(x + w / 2 - 1, G - 31, 3, 28, townHex("#3a2410"))
                    continue
                }
                let wall = townHex(b.wall), trim = townHex(b.trim), neon = townHex(b.neon)
                let stone = ["bank", "curate", "library"].contains(b.id)
                px(x, top, w, h, townMix(wall, townHex("#d8ccb8"), 0.45))
                if b.modern {
                    var y = top; while y < G { var k: CGFloat = 0; while k < w { px(x + k, y, min(23, w - k), min(19, G - y), townTint(wall, 0.94 + rnd() * 0.12)); k += 24 }; y += 20 }
                    var k: CGFloat = 24; while k < w { px(x + k - 1, top, 1, h, townTint(wall, 0.7)); k += 24 }
                    px(x + 3, top + 4, 3, h - TownStreet.doorH - 22, townTint(neon, night ? 0.45 : 0.7))
                } else if stone {
                    var y = top; var row = 0
                    while y < G { var k: CGFloat = row % 2 == 1 ? -10 : 0; while k < w { let v = 0.94 + rnd() * 0.1; let x1 = max(0, k); px(x + x1, y, min(19, w - x1), 7, townTint(wall, v)); k += 20 }; y += 8; row += 1 }
                } else {
                    var y = top; var row = 0
                    while y < G { var k: CGFloat = row % 2 == 1 ? -3 : 0; while k < w { let x1 = max(0, k); let bw2 = min(6, w - x1); if bw2 > 0 { px(x + x1, y, bw2, 3, townTint(wall, 0.88 + rnd() * 0.22)) }; k += 7 }; y += 4; row += 1 }
                }
                px(x, top, 2, h, townTint(wall, 1.14)); px(x + w - 3, top, 3, h, townTint(wall, 0.78))   // lit edge, shaded side
                // a stepped cornice with dentils and its shadow
                px(x - 3, top - 5, w + 6, 5, trim); px(x - 3, top - 5, w + 6, 1, townTint(trim, 1.4))
                var dx: CGFloat = 0; while dx < w { px(x + dx, top, 3, 2, townTint(trim, 0.8)); dx += 6 }
                px(x, top + 2, w, 2, townTint(wall, 0.6))
                // the roof
                let roofC = townHex(b.roofC)
                switch b.roof {
                case .flat: px(x - 1, top - 9, w + 2, 4, roofC)
                case .gable:
                    g.setFillColor(roofC.cgColor); g.move(to: CGPoint(x: x - 4, y: top - 5)); g.addLine(to: CGPoint(x: x + w / 2, y: top - 30)); g.addLine(to: CGPoint(x: x + w + 4, y: top - 5)); g.closePath(); g.fillPath()
                case .tiles:
                    var ty = top - 14; while ty < top - 4 { px(x - 2, ty, w + 4, 3, townTint(roofC, 0.9 + rnd() * 0.2)); ty += 3 }
                case .tower:
                    g.setFillColor(roofC.cgColor); g.move(to: CGPoint(x: x - 3, y: top - 5)); g.addLine(to: CGPoint(x: x + w / 2, y: top - 36)); g.addLine(to: CGPoint(x: x + w + 3, y: top - 5)); g.closePath(); g.fillPath()
                    px(x + w / 2 - 1, top - 48, 2, 14, townHex("#2a2a30"))
                case .dome:
                    g.setFillColor(roofC.cgColor); g.addEllipse(in: CGRect(x: x + 6, y: top - 30, width: w - 12, height: 50)); g.fillPath(); px(x - 1, top - 5, w + 2, 5, trim)
                }
                if b.penthouse { px(x + 22, top - 22, w - 44, 17, townTint(wall, 0.85)); px(x + 20, top - 24, w - 40, 3, trim) }
                // windows in rows, lit by the hour
                var wy = top + 14
                while wy < G - TownStreet.doorH - 8 {
                    var wx = x + 10
                    while wx < x + w - 20 {
                        if abs(wx + 7 - (x + w / 2)) < 1000 {
                            let on = lit && rnd() < (night ? 0.55 : 0.35)
                            let glow = [townHex("#ffd27a"), townHex("#ffe9a8"), townHex("#bfe9ff")][Int(rnd() * 3) % 3]
                            px(wx - 2, wy - 3, 16, 3, trim); px(wx - 1, wy - 1, 14, 17, trim)
                            px(wx, wy, 12, 15, on ? glow : (night ? townHex("#18223a") : townHex("#6a98c0")))
                            px(wx + 6, wy, 1, 15, trim); px(wx, wy + 7, 12, 1, trim)
                            if !on && !night { px(wx + 1, wy + 1, 4, 4, townHex("#a8d0f0")) }
                            px(wx - 2, wy + 15, 16, 2, townTint(trim, 1.3))
                            if rnd() < 0.18 { px(wx - 1, wy + 17, 14, 3, townHex("#5a8a3a")); px(wx + 1, wy + 16, 3, 2, townHex("#ff7a9a")) }
                        }
                        wx += 22
                    }
                    wy += 26
                }
                // a door sized to the people, with a lit sign above it
                let dxo = x + w / 2 - TownStreet.doorW / 2, dy = G - TownStreet.doorH
                px(dxo - 2, dy - 2, TownStreet.doorW + 4, TownStreet.doorH + 2, trim)
                px(dxo, dy, TownStreet.doorW, TownStreet.doorH, lit ? townHex("#3a2a14") : townHex("#1a1410"))
                if lit { px(dxo + 3, dy + 3, TownStreet.doorW - 6, 24, townTint(townHex("#ffd27a"), night ? 0.9 : 0.6)) }
                px(dxo + TownStreet.doorW / 2, dy, 1, TownStreet.doorH, trim)
                let sw = CGFloat(b.label.count) * 6 + 10, sy = dy - 20
                px(x + w / 2 - sw / 2 - 1, sy - 1, sw + 2, 13, townHex("#120c06"))
                px(x + w / 2 - sw / 2, sy, sw, 11, townTint(neon, lit ? 0.35 : 0.55))
                text(b.label, x + w / 2 - sw / 2 + 5, sy + 1, 7, lit ? neon : townTint(neon, 0.9))
                if lit {   // the neon glow around the sign
                    g.saveGState(); g.setBlendMode(.plusLighter); g.setFillColor(neon.withAlphaComponent(night ? 0.18 : 0.1).cgColor)
                    g.fill(CGRect(x: x + w / 2 - sw / 2 - 5, y: sy - 5, width: sw + 10, height: 21)); g.restoreGState()
                }
                if b.id == "clock" {   // the clock face shows the real time
                    let cx = x + w / 2, cy = top + 36
                    g.setFillColor(townHex("#f4ecd8").cgColor); g.fillEllipse(in: CGRect(x: cx - 15, y: cy - 15, width: 30, height: 30))
                    g.setStrokeColor(townHex("#3a2a20").cgColor); g.setLineWidth(2); g.strokeEllipse(in: CGRect(x: cx - 15, y: cy - 15, width: 30, height: 30))
                    let cal = Calendar.current.dateComponents([.hour, .minute], from: now)
                    let m = Double(cal.minute ?? 0), hr = Double((cal.hour ?? 0) % 12) + m / 60
                    func hand(_ a: Double, _ len: CGFloat, _ wd: CGFloat) { g.setLineWidth(wd); g.move(to: CGPoint(x: cx, y: cy)); g.addLine(to: CGPoint(x: cx + sin(a) * len, y: cy - cos(a) * len)); g.strokePath() }
                    hand(hr / 12 * 2 * .pi, 8, 2); hand(m / 60 * 2 * .pi, 12, 1.4)
                }
                if b.id == "signal" { px(x + w / 2 - 2, top - 52, 4, 4, lit ? townHex("#ff3a2a") : townHex("#5a1a1a")) }
            }
            // lamps between buildings
            for b in TownStreet.buildings {
                let lx = b.x + b.w + 8
                px(lx, G - 34, 2, 34, townHex("#2a2a2e")); px(lx - 3, G - 38, 8, 4, townHex("#2a2a2e"))
                if lit { g.saveGState(); g.setBlendMode(.plusLighter); g.setFillColor(townHex("#ffe9a8").withAlphaComponent(night ? 0.35 : 0.2).cgColor); g.fillEllipse(in: CGRect(x: lx - 10, y: G - 46, width: 22, height: 22)); g.restoreGState(); px(lx - 2, G - 37, 6, 3, townHex("#ffe9a8")) }
            }
        }
    }

    /// The sky: a vertical gradient per light, with stars after dark.
    static func sky(mode: TownLight, width: CGFloat) -> UIImage {
        let H = TownStreet.LH
        let stops: [UIColor]
        switch mode {
        case .day: stops = [townHex("#5a9ee0"), townHex("#a8d4f4")]
        case .dusk: stops = [townHex("#3a2a5a"), townHex("#ff9a5a")]
        case .night: stops = [townHex("#050814"), townHex("#1a2040")]
        case .dawn: stops = [townHex("#4a4a8a"), townHex("#ffc08a")]
        }
        let r = UIGraphicsImageRenderer(size: CGSize(width: width, height: H))
        return r.image { rc in
            let g = rc.cgContext
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: stops.map(\.cgColor) as CFArray, locations: [0, 1]) {
                g.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: H), options: [])
            }
            if mode == .night || mode == .dusk {
                var s: UInt64 = 99
                for _ in 0..<Int(width / 9) {
                    s = (s &* 16807) % 2147483647; let x = CGFloat(s % 100000) / 100000 * width
                    s = (s &* 16807) % 2147483647; let y = CGFloat(s % 100000) / 100000 * (H * 0.55)
                    g.setFillColor(UIColor.white.withAlphaComponent(mode == .night ? 0.85 : 0.35).cgColor); g.fill(CGRect(x: x, y: y, width: 1.5, height: 1.5))
                }
            }
        }
    }
}

/// His GlyphGuy as pixel sprites: the world model (`glyphguy-v4-world.usdz`, converted from his GLB) rendered once at the sprite size,
/// in three turns (front, left, right), lit like the web's bake. Tinted per person in the scene. Never redrawn.
@MainActor enum TownSprites {
    static var frames: [String: SKTexture] = [:]

    static func bake() async {
        guard frames.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "town-glyphguy", withExtension: "usdz") ?? Bundle.main.url(forResource: "glyphguy-v4-world", withExtension: "usdz"),
              let scene = try? SCNScene(url: url, options: nil), let device = MTLCreateSystemDefaultDevice() else { fallback(); return }
        let model = scene.rootNode
        let white = SCNMaterial(); white.diffuse.contents = UIColor.white; white.lightingModel = .phong; white.shininess = 36
        model.enumerateHierarchy { n, _ in n.geometry?.materials = [white] }
        let (mn, mx) = model.boundingBox
        let hgt = max(0.001, mx.y - mn.y)
        let k = Float(1.8) / hgt
        let holder = SCNNode(); scene.rootNode.addChildNode(holder)
        for c in scene.rootNode.childNodes where c !== holder { holder.addChildNode(c) }
        holder.scale = SCNVector3(k, k, k)
        holder.position = SCNVector3(0, -((mn.y + mx.y) / 2) * k, 0)
        scene.background.contents = UIColor.clear
        let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera?.usesOrthographicProjection = true; cam.camera?.orthographicScale = 1.05
        cam.position = SCNVector3(0, 0.02, 4); scene.rootNode.addChildNode(cam)
        let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient; amb.light?.intensity = 320; scene.rootNode.addChildNode(amb)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional; sun.light?.intensity = 2300; sun.eulerAngles = SCNVector3(-0.7, -0.55, 0); scene.rootNode.addChildNode(sun)
        let rim = SCNNode(); rim.light = SCNLight(); rim.light?.type = .directional; rim.light?.intensity = 900; rim.eulerAngles = SCNVector3(-0.4, 2.5, 0); scene.rootNode.addChildNode(rim)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene; renderer.pointOfView = cam
        for (name, yaw) in [("down", Float(0)), ("left", Float(0.61)), ("right", Float(-0.61))] {
            holder.eulerAngles = SCNVector3(0, yaw, 0)
            let img = renderer.snapshot(atTime: 0, with: CGSize(width: 160, height: 224), antialiasingMode: .none)
            let t = SKTexture(image: img); t.filteringMode = .nearest
            frames[name] = t
        }
    }

    /// Only if his model cannot be read on this device: a plain white pixel figure (tinted per person like the real sprite), so the town still works.
    static func fallback() {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 56))
        for (name, lean) in [("down", CGFloat(0)), ("left", CGFloat(-3)), ("right", CGFloat(3))] {
            let img = r.image { rc in
                let g = rc.cgContext; g.setFillColor(UIColor.white.cgColor)
                g.fill(CGRect(x: 14 + lean, y: 4, width: 12, height: 12)); g.fill(CGRect(x: 11 + lean, y: 18, width: 18, height: 20))
                g.fill(CGRect(x: 12, y: 40, width: 6, height: 14)); g.fill(CGRect(x: 22, y: 40, width: 6, height: 14))
            }
            let t = SKTexture(image: img); t.filteringMode = .nearest
            frames[name] = t
        }
    }
}
