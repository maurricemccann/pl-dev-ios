import SwiftUI
import UIKit

/// The drawing surface. `host` fills the screen and owns the zoom, twist and pan gestures; `stage` is the canvas at one point per pixel,
/// moved by an affine transform, so a touch located in the stage is already a document pixel. Pencil draws (fingers only when "Finger paints").
@MainActor final class CanvasStage: UIView {
    let model: NativeCanvasModel
    private let stageView = StageView()
    private var xf = CGAffineTransform.identity
    private var wetLayer = CALayer()
    private var layerViews: [CALayer] = []

    init(model: NativeCanvasModel) {
        self.model = model
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.1, alpha: 1)
        clipsToBounds = true
        stageView.model = model
        addSubview(stageView)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        let rot = UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.minimumNumberOfTouches = 2; pan.maximumNumberOfTouches = 2
        for g in [pinch, rot, pan] as [UIGestureRecognizer] { g.delegate = self; g.cancelsTouchesInView = false; addGestureRecognizer(g) }
        for n in 2...4 {   // two-finger tap undoes, three redoes, four fits
            let t = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
            t.numberOfTouchesRequired = n; t.cancelsTouchesInView = false; t.delegate = self
            addGestureRecognizer(t)
        }
        wetLayer.isHidden = true
        model.stage = self
        if model.doc != nil { rebuild() }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        stageView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if xf == .identity { fit() }
    }

    // MARK: layers on screen

    /// Rebuilds the layer tree from the open work: one CALayer per layer, the stroke buffer above the active one.
    func rebuild() {
        stageView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        layerViews = []
        guard let d = model.doc else { stageView.bounds = .zero; return }
        stageView.bounds = CGRect(x: 0, y: 0, width: d.w, height: d.h)
        stageView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        stageView.transform = xf
        stageView.backgroundColor = d.bgVis ? (Hex.color(d.bg).map { UIColor(cgColor: $0) } ?? .white) : .clear
        let frame = CGRect(x: 0, y: 0, width: d.w, height: d.h)
        for (i, l) in d.layers.enumerated() {
            let c = CALayer()
            c.frame = frame; c.contentsScale = 1; c.contentsGravity = .resize
            c.contents = l.pixels.image()
            c.isHidden = !l.visible; c.opacity = Float(l.opacity)
            if let m = l.mask, let img = NativeDoc.image(fromDataURL: m) {   // a mask he made on the laptop: shown, not editable yet
                let mk = CALayer(); mk.frame = frame; mk.contents = img; c.mask = mk
            }
            stageView.layer.addSublayer(c); layerViews.append(c)
            if i == d.active { wetLayer.removeFromSuperlayer(); wetLayer.frame = frame; wetLayer.contentsScale = 1; wetLayer.isHidden = true; stageView.layer.addSublayer(wetLayer) }
        }
    }

    /// New images over the changed buffers: no pixel copy, only a new CGImage over the same memory.
    func refresh(active: Int, wetOpacity: Double) {
        guard let d = model.doc, d.layers.indices.contains(active), layerViews.indices.contains(active) else { return }
        layerViews[active].contents = d.layers[active].pixels.image()
        if wetOpacity > 0, let w = model.wetBuffer {
            wetLayer.contents = w.image(); wetLayer.opacity = Float(wetOpacity); wetLayer.isHidden = false
        } else { wetLayer.isHidden = true }
    }

    // MARK: view transform

    func fit() {
        guard let d = model.doc, bounds.width > 0 else { return }
        let k = min(bounds.width / CGFloat(d.w), bounds.height / CGFloat(d.h)) * 0.94
        xf = CGAffineTransform(scaleX: k, y: k)
        stageView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        stageView.transform = xf
    }

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
        stageView.transform = xf
    }
    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        apply(pivot: g.location(in: self), scale: g.scale, rotation: 0, move: .zero); g.scale = 1
    }
    @objc private func rotate(_ g: UIRotationGestureRecognizer) {
        apply(pivot: g.location(in: self), scale: 1, rotation: g.rotation, move: .zero); g.rotation = 0
    }
    @objc private func pan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        apply(pivot: .zero, scale: 1, rotation: 0, move: t); g.setTranslation(.zero, in: self)
    }
    @objc private func tap(_ g: UITapGestureRecognizer) {
        switch g.numberOfTouches {
        case 2: model.undoStroke()
        case 3: model.redoStroke()
        default: fit()
        }
    }
}

extension CanvasStage: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { true }
}

/// The canvas itself. Touch points here are document pixels because this view's own transform is the zoom.
@MainActor final class StageView: UIView {
    weak var model: NativeCanvasModel?
    private var tracked: UITouch?

    override init(frame: CGRect) { super.init(frame: frame); isMultipleTouchEnabled = true; layer.masksToBounds = true }
    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let m = model else { return }
        if let live = tracked, (event?.touches(for: self)?.count ?? 0) > 1, live.type != .pencil { m.cancel(); tracked = nil; return }   // a second finger means zoom or tap gesture, not a mark
        guard tracked == nil, let t = touches.first(where: { m.canPaint($0) }) else { return }
        if t.type != .pencil, (event?.touches(for: self)?.count ?? 0) > 1 { return }   // two fingers landing together are a gesture
        tracked = t
        m.begin(at: t.location(in: self), pressure: Self.pressure(t), time: t.timestamp, tilt: Self.tilt(t))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let m = model, let t = tracked, touches.contains(t) else { return }
        if t.type != .pencil, (event?.touches(for: self)?.count ?? 0) > 1 { m.cancel(); tracked = nil; return }
        let all = event?.coalescedTouches(for: t) ?? [t]   // every sample the pen produced, not one per frame
        for c in all { m.extend(to: c.location(in: self), pressure: Self.pressure(c), time: c.timestamp, tilt: Self.tilt(c)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let m = model, let t = tracked, touches.contains(t) else { return }
        tracked = nil; m.end()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let m = model, let t = tracked, touches.contains(t) else { return }
        tracked = nil; m.cancel()
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

struct CanvasRepresentable: UIViewRepresentable {
    let model: NativeCanvasModel
    func makeUIView(context: Context) -> CanvasStage { CanvasStage(model: model) }
    func updateUIView(_ v: CanvasStage, context: Context) {}
}
