import SwiftUI
import UIKit

/// The drawing surface. `host` fills the screen and owns the zoom, twist and pan gestures; `stage` is the canvas at one point per pixel,
/// moved by an affine transform, so a touch located in the stage is already a document pixel. The Pencil draws (a finger only when
/// "Finger paints"); in the select, transform, pick and fill modes one finger is the tool.
@MainActor final class CanvasStage: UIView {
    let model: NativeCanvasModel
    private let stageView = StageView()
    private let overlay = ToolOverlay()
    private var xf = CGAffineTransform.identity
    private let wetLayer = CALayer()
    private let floatLayer = CALayer()
    private let selLayer = CALayer()
    private let cpuLayer = CALayer()
    private var layerViews: [CALayer] = []
    private var glowViews: [Int: CALayer] = [:]
    private var clipMasks: [(base: Int, mask: CALayer)] = []
    private var probe: (CGPoint, String)?
    private var probeTask: Task<Void, Never>?
    private var holdTimer: Timer?
    private var lastBuilt = -1

    var zoom: Double { (Double(xf.a) * Double(xf.a) + Double(xf.b) * Double(xf.b)).squareRoot() }

    init(model: NativeCanvasModel) {
        self.model = model
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.1, alpha: 1)
        clipsToBounds = true
        stageView.model = model
        addSubview(stageView)
        addSubview(overlay)
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        overlay.painter = { [weak self] ctx, rect in self?.paintOverlay(ctx, rect) }
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        let rot = UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.minimumNumberOfTouches = 2; pan.maximumNumberOfTouches = 2
        for g in [pinch, rot, pan] as [UIGestureRecognizer] { g.delegate = self; g.cancelsTouchesInView = false; addGestureRecognizer(g) }
        for n in 2...4 {   // a tap of two, three or four fingers runs what it is bound to (Gesture controls)
            let t = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
            t.numberOfTouchesRequired = n; t.cancelsTouchesInView = false; t.delegate = self
            addGestureRecognizer(t)
        }
        for n in 2...3 {   // hold two or three fingers: the bound action runs, and Undo and Redo keep stepping
            let h = UILongPressGestureRecognizer(target: self, action: #selector(hold(_:)))
            h.numberOfTouchesRequired = n; h.minimumPressDuration = 0.65; h.allowableMovement = 20; h.cancelsTouchesInView = false; h.delegate = self
            addGestureRecognizer(h)
        }
        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)
        wetLayer.isHidden = true; floatLayer.isHidden = true; selLayer.isHidden = true; cpuLayer.isHidden = true
        model.stage = self
        if model.doc != nil { rebuild() }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        stageView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        overlay.frame = bounds
        // the phone turned (handbook ch. 10: "the app fits itself to the screen"): fit again; a still phone keeps his own zoom
        let turned = laidOutSize != .zero && (laidOutSize.width > laidOutSize.height) != (bounds.width > bounds.height)
        laidOutSize = bounds.size
        if xf == .identity || turned { fit() }
    }
    private var laidOutSize: CGSize = .zero

    // MARK: layers on screen

    /// Rebuilds the layer tree from the open work: groups as containers, one CALayer per layer, masks and clips, the stroke buffer above the active one.
    func rebuild() {
        stageView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        layerViews = []; clipMasks = []; glowViews = [:]
        guard let d = model.doc else { stageView.bounds = .zero; overlay.setNeedsDisplay(); return }
        stageView.bounds = CGRect(x: 0, y: 0, width: d.w, height: d.h)
        stageView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        stageView.transform = xf
        stageView.backgroundColor = model.lightsOff ? UIColor(red: 0.027, green: 0.024, blue: 0.039, alpha: 1) : d.bgVis ? (Hex.color(d.bg).map { UIColor(cgColor: $0) } ?? .white) : .clear
        let frame = CGRect(x: 0, y: 0, width: d.w, height: d.h)
        if d.usesCustomBlend {
            // a PSD-only blend is on: the whole picture is composed per pixel, once, and shown as one layer
            cpuLayer.frame = frame; cpuLayer.contentsScale = 1; cpuLayer.contentsGravity = .resize
            cpuLayer.contents = d.compositeBuffer(includeBackground: false)?.ctx.makeImage()
            cpuLayer.isHidden = false
            stageView.layer.addSublayer(cpuLayer)
            for (i, l) in d.layers.enumerated() {   // keep the indices aligned: hidden stand-ins
                let c = CALayer(); c.frame = frame; c.contentsScale = 1; c.contentsGravity = .resize; c.contents = l.pixels.image(); c.isHidden = true
                layerViews.append(c)
                if i == d.active { attachLive(frame) }
            }
        } else {
            cpuLayer.isHidden = true
            var container: CALayer?, containerGroup = 0
            for (i, l) in d.layers.enumerated() {
                let gid = l.meta["grp"] as? Int ?? 0
                let c = layerContent(i, l, d, frame)
                layerViews.append(c)
                var node: CALayer = c
                if let b = d.clipBase(of: i), d.layers.indices.contains(b) {   // clipped to the layer below: that layer's picture is this one's mask
                    let wrap = CALayer(); wrap.frame = frame
                    let mk = CALayer(); mk.frame = frame; mk.contentsGravity = .resize; mk.contents = d.layers[b].pixels.image()
                    wrap.mask = mk; clipMasks.append((b, mk))
                    // blend, opacity and the eye belong to the clipped whole, so they act on what is beneath it
                    wrap.isHidden = c.isHidden; wrap.opacity = c.opacity; wrap.compositingFilter = c.compositingFilter
                    c.isHidden = false; c.opacity = 1; c.compositingFilter = nil
                    wrap.addSublayer(c)
                    node = wrap
                }
                if gid != 0, let g = d.group(gid) {
                    if container == nil || containerGroup != gid {
                        let gc = CALayer(); gc.frame = frame
                        gc.isHidden = !(g["vis"] as? Bool ?? true)
                        gc.opacity = Float((g["op"] as? Double) ?? Double(g["op"] as? Int ?? 1))
                        if let f = NativeBlend.mode(g["blend"] as? String).filter { gc.compositingFilter = f }
                        stageView.layer.addSublayer(gc)
                        container = gc; containerGroup = gid
                    }
                    container?.addSublayer(node)
                    if i == d.active { attachLive(frame, in: container) }
                } else {
                    container = nil; containerGroup = 0
                    stageView.layer.addSublayer(node)
                    if i == d.active { attachLive(frame) }
                }
                if let glow = glowLayer(for: i, d, frame) { (container ?? stageView.layer).addSublayer(glow); glowViews[i] = glow }
            }
        }
        selLayer.frame = frame; selLayer.contentsGravity = .resize
        stageView.layer.addSublayer(selLayer)
        refreshSelection()
        if let t = model.transform { setFloat(t) }
        overlay.setNeedsDisplay()
    }

    private func attachLive(_ frame: CGRect, in container: CALayer? = nil) {
        wetLayer.removeFromSuperlayer(); floatLayer.removeFromSuperlayer()
        wetLayer.frame = frame; wetLayer.contentsScale = 1; wetLayer.isHidden = true
        let host = container ?? stageView.layer
        host.addSublayer(wetLayer); host.addSublayer(floatLayer)
    }

    private func layerContent(_ i: Int, _ l: NativeLayer, _ d: NativeDoc, _ frame: CGRect) -> CALayer {
        let c = CALayer()
        c.frame = frame; c.contentsScale = 1; c.contentsGravity = .resize
        c.contents = l.pixels.image()
        c.isHidden = !l.visible
        let glowing = ((l.meta["glow"] as? Double) ?? Double(l.meta["glow"] as? Int ?? 0)) > 0
        c.opacity = Float(l.opacity * (model.lightsOff && !glowing ? 0.1 : 1))   // Lights off: only glowing layers carry the piece
        if let f = NativeBlend.mode(l.meta["blend"] as? String).filter { c.compositingFilter = f }
        if let m = l.maskPx?.image() {
            let mk = CALayer(); mk.frame = frame; mk.contentsGravity = .resize; mk.contents = m; c.mask = mk
        }
        return c
    }

    private func glowLayer(for i: Int, _ d: NativeDoc, _ frame: CGRect) -> CALayer? {
        let l = d.layers[i]
        let g = (l.meta["glow"] as? Double) ?? Double(l.meta["glow"] as? Int ?? 0)
        guard g > 0, l.visible, let img = l.pixels.image() else { return nil }
        let r = max(8, (Double(max(d.w, d.h)) / 70).rounded())
        let gl = CALayer(); gl.frame = frame; gl.contentsGravity = .resize
        gl.contents = NativeEffects.blur(img, radius: r)
        gl.compositingFilter = "plusL"
        gl.opacity = Float(min(1, g * (model.lightsOff ? 1.2 : 0.8)))
        return gl
    }

    /// New images over the changed buffers: no pixel copy, only a new CGImage over the same memory.
    func refresh(active: Int, wetOpacity: Double) {
        guard let d = model.doc, d.layers.indices.contains(active), layerViews.indices.contains(active) else { return }
        layerViews[active].contents = d.layers[active].pixels.image()
        for m in clipMasks where m.base == active { m.mask.contents = d.layers[active].pixels.image() }
        if let mk = layerViews[active].mask, let mp = d.layers[active].maskPx { mk.contents = mp.image() }
        if wetOpacity > 0, let w = model.wetBuffer {
            wetLayer.contents = w.image(); wetLayer.opacity = Float(wetOpacity); wetLayer.isHidden = false
        } else { wetLayer.isHidden = true }
        if d.usesCustomBlend && wetOpacity == 0 { cpuLayer.contents = d.compositeBuffer(includeBackground: false)?.ctx.makeImage() }
        if wetOpacity == 0 { refreshGlow(active) }
    }

    private func refreshGlow(_ i: Int) {
        guard let d = model.doc, d.layers.indices.contains(i) else { return }
        let g = (d.layers[i].meta["glow"] as? Double) ?? Double(d.layers[i].meta["glow"] as? Int ?? 0)
        guard g > 0, let gl = glowViews[i], let img = d.layers[i].pixels.image() else { return }
        gl.contents = NativeEffects.blur(img, radius: max(8, (Double(max(d.w, d.h)) / 70).rounded()))
    }

    func refreshAll() {
        guard let d = model.doc, layerViews.count == d.layers.count else { rebuild(); return }
        for (i, l) in d.layers.enumerated() {
            layerViews[i].contents = l.pixels.image()
            if let mk = layerViews[i].mask, let mp = l.maskPx { mk.contents = mp.image() }
            refreshGlow(i)
        }
        for m in clipMasks where d.layers.indices.contains(m.base) { m.mask.contents = d.layers[m.base].pixels.image() }
        if d.usesCustomBlend { cpuLayer.contents = d.compositeBuffer(includeBackground: false)?.ctx.makeImage() }
        wetLayer.isHidden = true
        refreshSelection()
        overlay.setNeedsDisplay()
    }

    func refreshSelection() {
        guard let sel = model.selection, sel.has else { selLayer.isHidden = true; return }
        selLayer.contents = sel.overlayImage()
        selLayer.isHidden = false
    }

    // MARK: the floating picture of a transform

    func setFloat(_ t: NativeTransform?) {
        guard let t, let d = model.doc else { floatLayer.isHidden = true; floatLayer.contents = nil; overlay.setNeedsDisplay(); return }
        floatLayer.isHidden = false
        _ = d
        refreshFloat()
    }

    func refreshFloat() {
        guard let t = model.transform, let d = model.doc else { return }
        if t.isPlain {
            floatLayer.contents = t.src
            floatLayer.bounds = CGRect(x: 0, y: 0, width: t.w0, height: t.h0)
            floatLayer.position = CGPoint(x: t.cx, y: t.cy)
            floatLayer.setAffineTransform(t.floatTransform)
            floatLayer.contentsGravity = .resize
            floatLayer.magnificationFilter = t.smooth ? .linear : .nearest
        } else {
            let k = min(1.0, 1200.0 / Double(max(d.w, d.h)))
            let pw = max(1, Int(Double(d.w) * k)), ph = max(1, Int(Double(d.h) * k))
            if let c = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                c.translateBy(x: 0, y: Double(ph)); c.scaleBy(x: 1, y: -1)
                c.scaleBy(x: k, y: k)
                t.paint(into: c, fine: false)
                floatLayer.contents = c.makeImage()
            }
            floatLayer.setAffineTransform(.identity)
            floatLayer.bounds = CGRect(x: 0, y: 0, width: d.w, height: d.h)
            floatLayer.position = CGPoint(x: Double(d.w) / 2, y: Double(d.h) / 2)
            floatLayer.contentsGravity = .resize
        }
        floatLayer.isHidden = false
        overlay.setNeedsDisplay()
    }

    func updateOverlay() { overlay.setNeedsDisplay() }
    func updateOverlay(probe p: CGPoint, hex: String) {
        probe = (p, hex)
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.probe = nil; self?.overlay.setNeedsDisplay()
        }
        overlay.setNeedsDisplay()
    }

    // MARK: view transform

    func fit() {
        guard let d = model.doc, bounds.width > 0 else { return }
        // fit between the floating chrome: the side sliders (left, about 72 pt), the top bar and the tool bars at the foot,
        // so a new or fitted picture is never under them (sim shot 006, 11-14: the sidebar covered the left edge)
        let room = bounds.inset(by: UIEdgeInsets(top: 112, left: 76, bottom: 200, right: 12))
        let area = room.width > 100 && room.height > 100 ? room : bounds
        let k = min(area.width / CGFloat(d.w), area.height / CGFloat(d.h)) * 0.96
        xf = CGAffineTransform(scaleX: k, y: k)
        stageView.center = CGPoint(x: area.midX, y: area.midY)
        stageView.transform = xf
        overlay.setNeedsDisplay()
    }

    /// Fits the picture into the area between the bars (they are floating, so the picture is not hidden by them).
    func zoomToFill() {
        guard let d = model.doc, bounds.width > 0 else { return }
        let k = max(bounds.width / CGFloat(d.w), bounds.height / CGFloat(d.h))
        xf = CGAffineTransform(scaleX: k, y: k); stageView.center = CGPoint(x: bounds.midX, y: bounds.midY); stageView.transform = xf
        overlay.setNeedsDisplay()
    }
    func actualSize() {
        guard model.doc != nil else { return }
        let k = 1 / UIScreen.main.scale
        xf = CGAffineTransform(scaleX: k, y: k); stageView.center = CGPoint(x: bounds.midX, y: bounds.midY); stageView.transform = xf
        overlay.setNeedsDisplay()
    }
    func turnUpright() {
        let k = CGFloat(zoom)
        xf = CGAffineTransform(scaleX: k, y: k); stageView.transform = xf; overlay.setNeedsDisplay()
    }

    func toScreen(_ p: CGPoint) -> CGPoint { stageView.convert(p, to: self) }

    /// Scale and rotate about a point in this view, then move; the stage turns about its own centre, so the point is taken from there.
    private func apply(pivot p: CGPoint, scale: CGFloat, rotation: CGFloat, move: CGPoint) {
        let a = CGPoint(x: p.x - stageView.center.x, y: p.y - stageView.center.y)
        let now = (xf.a * xf.a + xf.b * xf.b).squareRoot()
        let k = (now * scale < 0.05 || now * scale > 40) ? 1 : scale   // stop at a twentieth and at forty times
        let step = CGAffineTransform(translationX: -a.x, y: -a.y)
            .concatenating(CGAffineTransform(scaleX: k, y: k))
            .concatenating(CGAffineTransform(rotationAngle: rotation))
            .concatenating(CGAffineTransform(translationX: a.x + move.x, y: a.y + move.y))
        xf = xf.concatenating(step)
        // a small twist near upright snaps back to level
        let ang = atan2(xf.b, xf.a)
        if abs(ang) < 0.06, abs(ang) > 0 { let back = CGAffineTransform(rotationAngle: -ang); xf = xf.concatenating(back) }
        stageView.transform = xf
        overlay.setNeedsDisplay()
    }
    @objc private func pinch(_ g: UIPinchGestureRecognizer) { apply(pivot: g.location(in: self), scale: g.scale, rotation: 0, move: .zero); g.scale = 1 }
    @objc private func rotate(_ g: UIRotationGestureRecognizer) { apply(pivot: g.location(in: self), scale: 1, rotation: g.rotation, move: .zero); g.rotation = 0 }
    @objc private func pan(_ g: UIPanGestureRecognizer) { let t = g.translation(in: self); apply(pivot: .zero, scale: 1, rotation: 0, move: t); g.setTranslation(.zero, in: self) }
    @objc private func tap(_ g: UITapGestureRecognizer) {
        if model.shapeHeld { model.perfectShape(); return }
        model.run(action: model.gestures["tap\(g.numberOfTouches)"] ?? "None")
    }
    @objc private func hold(_ g: UILongPressGestureRecognizer) {
        let name = model.gestures["hold\(g.numberOfTouches)"] ?? "None"
        switch g.state {
        case .began:
            model.run(action: name)
            holdTimer?.invalidate()
            if name == "Undo" || name == "Redo" {
                holdTimer = Timer.scheduledTimer(withTimeInterval: 0.13, repeats: true) { [weak self] _ in Task { @MainActor in self?.model.run(action: name) } }
            }
        case .ended, .cancelled, .failed: holdTimer?.invalidate(); holdTimer = nil
        default: break
        }
    }

    // MARK: the overlay in screen space

    private func paintOverlay(_ c: CGContext, _ rect: CGRect) {
        guard let d = model.doc else { return }
        let gold = UIColor(red: 0.9, green: 0.78, blue: 0.4, alpha: 1)
        drawTilePreview(c, d)
        drawSeam(c, d)
        // guides
        if model.guide != .off { drawGuide(c, d) }
        if model.sym != .off { drawSymmetry(c, d) }
        if model.tile != .off { drawTileEdges(c, d) }
        drawTileGuides(c, d)
        drawNodes(c)
        // a selection being dragged
        if let dr = model.selDrag {
            c.saveGState()
            c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(1.6); c.setLineDash(phase: 0, lengths: [8, 5])
            switch dr.shape {
            case .rect:
                let a = toScreen(dr.p0), b = toScreen(CGPoint(x: dr.p1.x, y: dr.p0.y)), e = toScreen(dr.p1), f = toScreen(CGPoint(x: dr.p0.x, y: dr.p1.y))
                c.addLines(between: [a, b, e, f]); c.closePath(); c.strokePath()
            case .ellipse:
                c.beginPath()
                for i in 0...48 {
                    let t = Double(i) / 48 * .pi * 2
                    let p = toScreen(CGPoint(x: (dr.p0.x + dr.p1.x) / 2 + cos(t) * (dr.p1.x - dr.p0.x) / 2, y: (dr.p0.y + dr.p1.y) / 2 + sin(t) * (dr.p1.y - dr.p0.y) / 2))
                    if i == 0 { c.move(to: p) } else { c.addLine(to: p) }
                }
                c.strokePath()
            case .free:
                if dr.pts.count > 1 { c.addLines(between: dr.pts.map(toScreen)); c.strokePath() }
            case .auto: break
            }
            c.restoreGState()
        }
        // the transform handles
        if let t = model.transform { drawHandles(c, t, gold) }
        // the picked colour
        if let (p, hex) = probe, let rgb = Hex.rgb(hex) {
            let s = toScreen(p)
            c.setFillColor(CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)); c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(3)
            let r = CGRect(x: s.x - 22, y: s.y - 70, width: 44, height: 44)
            c.fillEllipse(in: r); c.strokeEllipse(in: r)
            c.move(to: CGPoint(x: s.x, y: s.y - 26)); c.addLine(to: s); c.strokePath()
        }
    }

    private func drawGuide(_ c: CGContext, _ d: NativeDoc) {
        c.saveGState()
        c.setStrokeColor(CGColor(red: 0.47, green: 0.67, blue: 1, alpha: 0.4)); c.setLineWidth(1)
        let W = Double(d.w), H = Double(d.h), g = max(8, model.guideSize)
        func line(_ a: CGPoint, _ b: CGPoint) { c.move(to: toScreen(a)); c.addLine(to: toScreen(b)) }
        switch model.guide {
        case .grid:
            var x = 0.0; while x <= W { line(CGPoint(x: x, y: 0), CGPoint(x: x, y: H)); x += g }
            var y = 0.0; while y <= H { line(CGPoint(x: 0, y: y), CGPoint(x: W, y: y)); y += g }
            c.strokePath()
        case .iso:
            var x = 0.0; while x <= W { line(CGPoint(x: x, y: 0), CGPoint(x: x, y: H)); x += g }
            let t = tan(Double.pi / 6), span = H / t
            let n = Int(ceil(H / g / t)) + 2
            for k in -n...(Int(ceil(W / g)) + 2) {
                let x0 = Double(k) * g * 1.1547
                line(CGPoint(x: x0, y: 0), CGPoint(x: x0 + span, y: H)); line(CGPoint(x: x0, y: 0), CGPoint(x: x0 - span, y: H))
            }
            c.strokePath()
        case .persp, .persp2, .persp3:
            let V = model.guideVPs()
            let cols: [CGColor] = [CGColor(red: 0.35, green: 0.63, blue: 1, alpha: 0.38), CGColor(red: 1, green: 0.47, blue: 0.43, alpha: 0.38), CGColor(red: 0.43, green: 0.86, blue: 0.55, alpha: 0.38)]
            let reach = 9000.0, step = V.count == 1 ? 10.0 : 6.0
            for (k, v) in V.enumerated() {
                c.setStrokeColor(cols[k])
                var dg = 0.0
                while dg < 360 { let r = dg * .pi / 180; line(v, CGPoint(x: Double(v.x) + cos(r) * reach, y: Double(v.y) + sin(r) * reach)); dg += step }
                c.strokePath()
            }
            c.setStrokeColor(CGColor(gray: 1, alpha: 0.55))
            if V.count >= 2 {
                let dx = Double(V[1].x - V[0].x), dy = Double(V[1].y - V[0].y), l = max(1e-9, hypot(dx, dy))
                line(CGPoint(x: Double(V[0].x) - dx / l * reach, y: Double(V[0].y) - dy / l * reach), CGPoint(x: Double(V[0].x) + dx / l * reach, y: Double(V[0].y) + dy / l * reach))
            } else if let v = V.first { line(CGPoint(x: -reach, y: Double(v.y)), CGPoint(x: reach, y: Double(v.y))) }
            c.strokePath()
            if model.vpEdit {
                for (k, v) in V.enumerated() {
                    let s = toScreen(v)
                    c.setFillColor(cols[k].copy(alpha: 1) ?? cols[k]); c.setStrokeColor(CGColor(gray: 1, alpha: 1)); c.setLineWidth(2.5)
                    let r = CGRect(x: s.x - 11, y: s.y - 11, width: 22, height: 22)
                    c.fillEllipse(in: r); c.strokeEllipse(in: r)
                }
            }
        default: break
        }
        c.restoreGState()
    }

    private func drawSymmetry(_ c: CGContext, _ d: NativeDoc) {
        let W = Double(d.w), H = Double(d.h)
        c.saveGState(); c.setStrokeColor(CGColor(red: 0.9, green: 0.78, blue: 0.4, alpha: 0.7)); c.setLineWidth(1.2); c.setLineDash(phase: 0, lengths: [6, 6])
        func line(_ a: CGPoint, _ b: CGPoint) { c.move(to: toScreen(a)); c.addLine(to: toScreen(b)) }
        if model.sym == .v || model.sym == .quad || model.sym == .radial { line(CGPoint(x: W / 2, y: 0), CGPoint(x: W / 2, y: H)) }
        if model.sym == .h || model.sym == .quad || model.sym == .radial { line(CGPoint(x: 0, y: H / 2), CGPoint(x: W, y: H / 2)) }
        if model.sym == .radial { line(CGPoint(x: 0, y: 0), CGPoint(x: W, y: H)); line(CGPoint(x: W, y: 0), CGPoint(x: 0, y: H)) }
        c.strokePath(); c.restoreGState()
    }
    private func drawTileEdges(_ c: CGContext, _ d: NativeDoc) {
        c.saveGState(); c.setStrokeColor(CGColor(red: 0.5, green: 0.9, blue: 0.7, alpha: 0.8)); c.setLineWidth(1.4)
        let r = [CGPoint(x: 0, y: 0), CGPoint(x: d.w, y: 0), CGPoint(x: d.w, y: d.h), CGPoint(x: 0, y: d.h)].map(toScreen)
        c.addLines(between: r + [r[0]]); c.strokePath(); c.restoreGState()
    }

    private func drawHandles(_ c: CGContext, _ t: NativeTransform, _ gold: UIColor) {
        let z = max(0.001, zoom)
        func node(_ p: CGPoint, _ col: UIColor) {
            let s = toScreen(p)
            c.setFillColor(col.cgColor); c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(2)
            let r = CGRect(x: s.x - 9, y: s.y - 9, width: 18, height: 18)
            c.fillEllipse(in: r); c.strokeEllipse(in: r)
        }
        c.saveGState()
        c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(1.8); c.setLineDash(phase: 0, lengths: [8, 6])
        let blue = UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1)
        if t.mode == .distort {
            let q = t.q.map(toScreen)
            c.addLines(between: q); c.closePath(); c.strokePath(); c.setLineDash(phase: 0, lengths: [])
            for p in t.q { node(p, blue) }
        } else if t.mode == .warp {
            let m = t.warpMap()
            c.setLineDash(phase: 0, lengths: []); c.setAlpha(0.85)
            for k in 0..<4 {
                c.beginPath()
                for s in 0...24 { let p = toScreen(m(Double(k) / 3, Double(s) / 24)); if s == 0 { c.move(to: p) } else { c.addLine(to: p) } }
                c.strokePath()
                c.beginPath()
                for s in 0...24 { let p = toScreen(m(Double(s) / 24, Double(k) / 3)); if s == 0 { c.move(to: p) } else { c.addLine(to: p) } }
                c.strokePath()
            }
            c.setAlpha(1)
            for p in t.warpNodes() { node(p, blue) }
        } else {
            let k = (0..<4).map { t.corner($0) }
            let ks = k.map(toScreen)
            c.addLines(between: ks); c.closePath(); c.strokePath(); c.setLineDash(phase: 0, lengths: [])
            let rn = t.rotNode(z), top = CGPoint(x: (k[0].x + k[1].x) / 2, y: (k[0].y + k[1].y) / 2)
            c.setStrokeColor(UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1).cgColor)
            c.move(to: toScreen(top)); c.addLine(to: toScreen(rn)); c.strokePath()
            if t.mode == .free {
                for p in t.edgeNodes() {
                    let s = toScreen(p)
                    c.setFillColor(UIColor(red: 0.58, green: 0.77, blue: 0.99, alpha: 1).cgColor); c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(2)
                    let r = CGRect(x: s.x - 7, y: s.y - 7, width: 14, height: 14)
                    c.fill(r); c.stroke(r)
                }
            }
            for p in k { node(p, blue) }
            node(rn, UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1))
            let yn = t.pivotNode(z), bot = CGPoint(x: (k[2].x + k[3].x) / 2, y: (k[2].y + k[3].y) / 2)
            c.setStrokeColor(gold.cgColor); c.move(to: toScreen(bot)); c.addLine(to: toScreen(yn)); c.strokePath()
            let ys = toScreen(yn)
            c.setFillColor(gold.cgColor); c.setStrokeColor(UIColor.white.cgColor)
            let r = CGRect(x: ys.x - 8, y: ys.y - 8, width: 16, height: 16)
            c.fill(r); c.stroke(r)
            if let pv = t.pivot {
                let s = toScreen(pv)
                c.setStrokeColor(gold.cgColor); c.setLineWidth(2.4)
                c.strokeEllipse(in: CGRect(x: s.x - 12, y: s.y - 12, width: 24, height: 24))
                c.move(to: CGPoint(x: s.x - 18, y: s.y)); c.addLine(to: CGPoint(x: s.x + 18, y: s.y))
                c.move(to: CGPoint(x: s.x, y: s.y - 18)); c.addLine(to: CGPoint(x: s.x, y: s.y + 18)); c.strokePath()
            }
        }
        c.restoreGState()
    }
}

extension CanvasStage: UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
        !(a is UITapGestureRecognizer) && !(b is UITapGestureRecognizer) && !(a is UILongPressGestureRecognizer) && !(b is UILongPressGestureRecognizer)
    }
    /// A resting palm is not a gesture: while the Pencil is drawing (or the stroke is held as a shape) the view does not move.
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if model.drawing && model.palmGuard { return false }
        if model.palmGuard, ProcessInfo.processInfo.systemUptime - model.pencilDownAt < 0.35 { return false }
        return true
    }
    /// The Pencil's double tap runs the side button's action ("Pen side button"); the squeeze of a Pencil Pro runs the second button's ("Pen second
    /// button"). Settings > Swap the Pencil's two buttons trades them. Either way it runs on the press and never draws.
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        model.run(action: model.gestures[model.swapPencil ? "penbtn2" : "penbtn"] ?? "Eyedropper")
    }
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended else { return }
        model.run(action: model.gestures[model.swapPencil ? "penbtn" : "penbtn2"] ?? "Eraser (toggle)")
    }
}

/// The canvas itself. Touch points here are document pixels because this view's own transform is the zoom.
@MainActor final class StageView: UIView {
    weak var model: NativeCanvasModel?
    private var tracked: UITouch?

    override init(frame: CGRect) { super.init(frame: frame); isMultipleTouchEnabled = true; layer.masksToBounds = true }
    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let m = model else { return }
        let count = event?.touches(for: self)?.count ?? 1
        if let live = tracked, count > 1, live.type != .pencil {
            if m.shapeHeld { m.perfectShape(); return }
            m.touchCancelled(); tracked = nil; return   // a second finger means zoom or tap gesture, not a mark
        }
        if tracked != nil, m.shapeHeld, touches.contains(where: { $0.type != .pencil }) { m.perfectShape(); return }   // a finger on a held shape makes it exact
        guard tracked == nil, let t = touches.first(where: { m.accepts(pencil: $0.type == .pencil) }) else { return }
        if t.type != .pencil, count > 1 { return }   // two fingers landing together are a gesture
        tracked = t
        m.touchBegan(t.preciseLocation(in: self), pressure: Self.pressure(t), time: t.timestamp, tilt: Self.tilt(t), pencil: t.type == .pencil)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let m = model, let t = tracked, touches.contains(t) else { return }
        if t.type != .pencil, (event?.touches(for: self)?.count ?? 0) > 1 { m.touchCancelled(); tracked = nil; return }
        let all = event?.coalescedTouches(for: t) ?? [t]   // every sample the pen produced, not one per frame
        for c in all { m.touchMoved(c.preciseLocation(in: self),   // preciseLocation: sub-point positions (ProCraft's CanvasView does the same, 11-14)
                                 pressure: Self.pressure(c), time: c.timestamp, tilt: Self.tilt(c)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let m = model, let t = tracked, touches.contains(t) else { return }
        tracked = nil; m.touchEnded(t.preciseLocation(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let m = model, let t = tracked, touches.contains(t) else { return }
        tracked = nil; m.touchCancelled()
    }

    /// Pencil force over its maximum; a finger has no pressure, so it paints at the middle (the laptop's 0.5 for a pointer).
    static func pressure(_ t: UITouch) -> Double {
        guard t.type == .pencil, t.maximumPossibleForce > 0 else { return 0.5 }
        return Double(t.force / t.maximumPossibleForce)
    }
    /// Altitude and azimuth as the tiltX and tiltY the laptop logs, in degrees.
    static func tilt(_ t: UITouch) -> (Double, Double)? {
        guard t.type == .pencil else { return nil }
        let a = Double(t.altitudeAngle), z = Double(t.azimuthAngle(in: t.view))
        let x = cos(z) * cos(a), y = sin(z) * cos(a), up = sin(a)
        return (atan2(x, up) * 180 / .pi, atan2(y, up) * 180 / .pi)
    }
}

/// Draws what belongs to the screen, not to the picture: guide lines, handles, the pick marker. It never takes a touch.
final class ToolOverlay: UIView {
    var painter: ((CGContext, CGRect) -> Void)?
    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        painter?(c, rect)
    }
}

struct CanvasRepresentable: UIViewRepresentable {
    let model: NativeCanvasModel
    func makeUIView(context: Context) -> CanvasStage {
        let v = CanvasStage(model: model)
        v.isAccessibilityElement = true; v.accessibilityLabel = "Canvas"; v.accessibilityIdentifier = "canvas.surface"
        v.accessibilityHint = "Draw with the Apple Pencil. Two fingers tap to undo, three to redo."
        return v
    }
    func updateUIView(_ v: CanvasStage, context: Context) {}
}
