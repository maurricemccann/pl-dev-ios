import SwiftUI
import RealityKit

/// His GlyphGuy v4 (the model in `glyphguy-v4.usdz`, converted from his GLB), with the lab's clips and looks.
/// The clip pack's motion is tried first (`Clips/clip-<name>.usdz` played on the model); when a clip carries no skeleton motion the
/// figure moves by a plain body motion for that clip instead (a bob, a spin, an arc), so a button always does something.
enum GlyphClip: String, CaseIterable, Identifiable {
    case idle, walking, samba, gangnam, backflip, jump
    case dancing = "dancing", hiphop = "hip-hop-dancing", house = "house-dancing", silly = "silly-dancing", robot = "robot-hip-hop-dance"
    case thriller = "thriller-part-2", capoeira, spin = "northern-soul-spin", salute, wave = "waving-gesture"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .idle: return "Idle"; case .walking: return "Walk"; case .samba: return "Samba"; case .gangnam: return "Gangnam"
        case .backflip: return "Flip"; case .jump: return "Jump"; case .dancing: return "Dance"; case .hiphop: return "Hip-hop"
        case .house: return "House"; case .silly: return "Silly"; case .robot: return "Robot"; case .thriller: return "Thriller"
        case .capoeira: return "Capoeira"; case .spin: return "Spin"; case .salute: return "Salute"; case .wave: return "Wave"
        }
    }
    /// The six the GlyphBot lab shows; the dance lab shows all.
    static let lab: [GlyphClip] = [.walking, .idle, .samba, .gangnam, .backflip, .jump]
}

enum GlyphLook: String, CaseIterable, Identifiable {
    case gold, marble, obsidian
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    @MainActor var material: SimpleMaterial {
        switch self {
        case .gold: return ThreeDModels.goldMaterial()
        case .marble: return SimpleMaterial(color: UIColor(white: 0.93, alpha: 1), roughness: 0.25, isMetallic: false)
        case .obsidian: return SimpleMaterial(color: UIColor(white: 0.04, alpha: 1), roughness: 0.12, isMetallic: true)
        }
    }
}

/// One GlyphGuy in a scene: loads, takes a look, plays a clip.
@MainActor final class GlyphFigure {
    let root = Entity()          // move this one
    private(set) var model: Entity?
    private var clipSupportsMotion = false
    private(set) var clip: GlyphClip = .idle
    private var clock: Float = 0
    private var motionBase = SIMD3<Float>.zero

    func load(height: Float = 1.8, look: GlyphLook = .gold, world: Bool = true) async -> Bool {
        guard let e = await ThreeDModels.load(world ? "glyphguy-v4-world" : "glyphguy-v4") else { return false }
        let fit = ThreeDModels.fitted(e, longest: height)
        model = e
        root.addChild(fit)
        setLook(look)
        return true
    }

    func setLook(_ l: GlyphLook) { if let m = model { ThreeDModels.paint(m, l.material) } }

    func play(_ c: GlyphClip) async {
        clip = c; clock = 0
        guard let model else { return }
        model.stopAllAnimations()
        clipSupportsMotion = false
        if let url = ThreeDModels.url("clip-\(c.rawValue)") ?? Bundle.main.url(forResource: "clip-\(c.rawValue)", withExtension: "usdz", subdirectory: "Models/Clips"),
           let ce = try? await Entity(contentsOf: url), let anim = ce.availableAnimations.first {
            model.playAnimation(anim.repeat(), transitionDuration: 0.3, startsPaused: false)
            clipSupportsMotion = true
        }
    }

    /// Called every frame by the room. Plain body motion only when the clip pack's own motion is not playing.
    func tick(_ dt: Float) {
        clock += dt
        guard !clipSupportsMotion else { return }
        let t = clock
        var y: Float = 0, roll: Float = 0, yaw: Float = 0, pitch: Float = 0
        switch clip {
        case .idle: y = sin(t * 1.6) * 0.01
        case .walking, .salute, .wave: y = abs(sin(t * 5)) * 0.03; roll = sin(t * 5) * 0.05
        case .jump: y = max(0, sin(t * 4)) * 0.45
        case .backflip: let p = (t * 1.1).truncatingRemainder(dividingBy: 1); pitch = -p * .pi * 2; y = sin(p * .pi) * 0.7
        case .spin: yaw = t * 6
        default: y = abs(sin(t * 6)) * 0.07; roll = sin(t * 3) * 0.14; yaw = sin(t * 1.5) * 0.5
        }
        root.position.y = y
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: roll, axis: [0, 0, 1]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }
}

struct GlyphGuyRoom: View {
    enum Kind { case glyphbot, dance }
    let kind: Kind
    @State private var figure = GlyphFigure()
    @State private var clip: GlyphClip = .walking
    @State private var look: GlyphLook = .gold
    @State private var ready = false
    @State private var missing = false

    private var clips: [GlyphClip] { kind == .glyphbot ? GlyphClip.lab : GlyphClip.allCases }

    var body: some View {
        // the stage and the bar are stacked, not overlaid (his note 11-14: "Glyph's feet are clipping"): the bar was laid over the bottom of
        // the stage and covered his feet, most of all in landscape. The stage now is exactly the space above the bar.
        VStack(spacing: 0) {
            OrbitStage(distance: 4.6, height: 0.95, autoSpin: false) { pivot in
                let floor = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 1.8), materials: [SimpleMaterial(color: ThreeDHouse.ground, roughness: 0.9, isMetallic: false)])
                floor.position.y = -0.01
                pivot.addChild(floor)
                if await figure.load(look: look) { pivot.addChild(figure.root); await figure.play(clip); ready = true } else { missing = true }
            }
            .overlay { if missing { ContentUnavailableView("Model not found", systemImage: "cube.transparent", description: Text("GlyphGuy is not in this build.")) } }
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(clips) { c in
                            Button(c.label) { clip = c; Task { await figure.play(c) } }
                                .buttonStyle(.bordered).tint(clip == c ? PLTone.accent : .secondary)
                                .sensoryFeedback(PLHaptic.select, trigger: clip)
                        }
                    }.padding(.horizontal)
                }
                if kind == .dance {
                    Picker("Look", selection: $look) { ForEach(GlyphLook.allCases) { Text($0.label).tag($0) } }
                        .pickerStyle(.segmented).padding(.horizontal)
                        .onChange(of: look) { _, l in figure.setLook(l) }
                }
            }
            .padding(.top, 8).padding(.bottom, 10)
            .background(.bar)
        }
        .task {
            var last = Date()
            while !Task.isCancelled {
                let now = Date(); figure.tick(Float(now.timeIntervalSince(last))); last = now
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .navigationTitle(kind == .glyphbot ? "GlyphGuy" : "Dance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
