import SwiftUI
import RealityKit

/// The Oracle room's stage, as `GlyphRoom.tsx` draws it: his GlyphGuy v4 seated on the left (`sitting.glb` converted to
/// `glyphbot-sitting.usdz` with Blender, never redrawn), breathing, with a warm gold aura that brightens while the room speaks,
/// and the latest answer in a speech bubble beside him (its tail on the left, sources as small mono chips).
/// GlyphGuy has no face: the aura and the typewriter are the whole of his reaction.
@MainActor private final class GlyphSeat {
    let root = Entity()
    var base: SIMD3<Float> = .zero
    var amp: Float = 0.01
    var loaded = false

    func load() async -> Bool {
        guard let url = Bundle.main.url(forResource: "glyphbot-sitting", withExtension: "usdz"),
              let model = try? await Entity(contentsOf: url) else { return false }
        // the recline lives in the (single-frame) clip, not the bind pose: play it before measuring, as the web does
        if let anim = model.availableAnimations.first { model.playAnimation(anim.repeat(), transitionDuration: 0, startsPaused: false) }
        let holder = Entity(); holder.addChild(model)
        var b = model.visualBounds(relativeTo: holder)
        let r = max(b.boundingRadius, 0.001)
        model.scale = SIMD3<Float>(repeating: 0.9 / r)           // fits a unit-ish sphere so any pose frames the same
        b = model.visualBounds(relativeTo: holder)
        model.position -= b.center
        root.addChild(holder)
        base = root.position; amp = 0.012
        loaded = true
        return true
    }

    func breathe(_ t: Float) {
        let breath = sin(t * 1.1)
        root.position.y = base.y + breath * amp
        root.orientation = simd_quatf(angle: breath * 0.012, axis: [0, 0, 1])
    }
}

struct GlyphStageFigure: View {
    var speaking: Bool
    @State private var seat = GlyphSeat()
    @State private var missing = false
    @State private var ready = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlyphARStage(seat: seat, onLoaded: { ok in if ok { ready = true } else { missing = true } })
            .task {
                let start = Date()
                while !Task.isCancelled {
                    if seat.loaded && !reduceMotion { seat.breathe(Float(Date().timeIntervalSince(start))) }
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }
            .overlay {
                if missing { Image(systemName: "figure.seated.side").font(.system(size: 44)).foregroundStyle(PLOS.gold.opacity(0.4)) }
                else if !ready { ProgressView().tint(PLOS.gold.opacity(0.5)) }
            }
            .shadow(color: PLOS.gold.opacity(speaking ? 0.5 : 0.22), radius: speaking ? 22 : 16)
            .animation(.easeInOut(duration: 0.5), value: speaking)
            .accessibilityLabel("GlyphGuy")
    }
}

/// A non-AR RealityKit view with a clear background (the web's transparent three.js canvas).
private struct GlyphARStage: UIViewRepresentable {
    let seat: GlyphSeat
    let onLoaded: (Bool) -> Void

    func makeUIView(context: Context) -> ARView {
        let v = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        v.environment.background = .color(.clear)
        v.isOpaque = false; v.backgroundColor = .clear
        let anchor = AnchorEntity(world: .zero)
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 33
        cam.position = [0, 0, 2.6]
        anchor.addChild(cam)
        anchor.addChild(Self.light(1800, [2.5, 4, 5], UIColor(red: 1, green: 0.9, blue: 0.68, alpha: 1)))     // warm key
        anchor.addChild(Self.light(900, [-4, 1, 3], UIColor(red: 0.74, green: 0.83, blue: 1, alpha: 1)))      // cool fill
        anchor.addChild(Self.light(800, [-2, 4, -5], .white))                                                  // rim
        anchor.addChild(seat.root)
        v.scene.addAnchor(anchor)
        Task { @MainActor in onLoaded(await seat.load()) }
        return v
    }

    func updateUIView(_ v: ARView, context: Context) {}

    private static func light(_ intensity: Float, _ p: SIMD3<Float>, _ tint: UIColor) -> Entity {
        let e = Entity()
        var l = DirectionalLightComponent(); l.intensity = intensity; l.color = tint
        e.components.set(l); e.look(at: .zero, from: p, relativeTo: nil)
        return e
    }
}

/// The speech bubble: the latest answer typed out, the sources as chips, three pulsing dots while the Oracle thinks.
struct GlyphStageBubble: View {
    let text: String
    let sources: [GlyphBot.Passage]
    let loading: Bool
    let typing: Bool
    var onDone: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loading {
                HStack(spacing: 4) { ForEach(0..<3, id: \.self) { i in
                    Circle().fill(PLOS.gold.opacity(pulse ? 0.8 : 0.3)).frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: pulse)
                } }.padding(.vertical, 6)
            } else {
                TypewriterText(text: text, animate: typing, onDone: onDone)
                    .font(.system(size: 15)).foregroundStyle(PLOS.text(scheme))
                if !typing, !sources.isEmpty {
                    FlowChips(items: sources.prefix(4).map { "\($0.source) \u{00B7} \(String(format: "%.2f", $0.score))" })
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous).fill(PLOS.surface2(scheme)) }
        .overlay { UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous).strokeBorder(PLOS.line(scheme), lineWidth: 0.8) }
        .onAppear { pulse = true }
        .accessibilityElement(children: .combine)
    }
}

private struct FlowChips: View {
    let items: [String]
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // the web wraps its chips; at phone width four short mono chips wrap in two lines
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { ForEach(items, id: \.self) { chip($0) } }
            VStack(alignment: .leading, spacing: 6) { ForEach(items, id: \.self) { chip($0) } }
        }
    }
    private func chip(_ s: String) -> some View {
        Text(s).osEyebrow(8).foregroundStyle(PLOS.dim(scheme).opacity(0.75)).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .overlay { Rectangle().strokeBorder(PLOS.line(scheme), lineWidth: 0.6) }
    }
}
