import AVFoundation
import SwiftUI

/// The art each doctrine page carries on the site, kept when the page is read natively: the Three Truths' gold curves over
/// its breathing flow field (`P5Sketch field` at 12 %, `GoldCurves`), the Forge's corridor footage scrubbed by the scroll
/// (`TheBasement`: grayscale at 60 %, washed gold), the Brand's gold line under each section heading (`GoldLine`).
enum SiteReaderArt: Equatable { case none, curves, corridor, goldLine }

struct SiteReaderCurvesHero: View {
    var body: some View { GoldCurvesLayer().frame(height: 260).clipped().padding(.bottom, -120) }
}

/// The flow field behind the whole page, faint, held still under Reduce Motion (the site hides it then).
struct SiteFieldBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        if !reduce { FieldSketch().opacity(0.12).ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true) }
    }
}

/// The corridor: the site's `/videos/forge-corridor.mp4`, muted, its time driven by how far the page has scrolled.
struct SiteCorridor: View {
    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack {
            Color(hex: 0x0e0c08)
            if let player { CorridorLayer(player: player).grayscale(1).opacity(0.6) }
            Bone.gold.opacity(0.35).blendMode(.color)
        }
        .frame(height: 360).clipped()
        .padding(.bottom, -80)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { y in
            guard let player, duration > 0, !reduce else { return }
            let t = min(duration, max(0, Double(-y) / 360 * duration))
            player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
        }
        .task {
            guard let u = Site.page("videos/forge-corridor.mp4") else { return }
            let item = AVPlayerItem(url: u)
            let p = AVPlayer(playerItem: item); p.isMuted = true
            player = p
            if let d = try? await item.asset.load(.duration) { duration = d.seconds.isFinite ? d.seconds : 0 }
        }
        .accessibilityHidden(true)
    }

    private struct CorridorLayer: UIViewRepresentable {
        let player: AVPlayer
        func makeUIView(context: Context) -> PlayerView { let v = PlayerView(); v.playerLayer.player = player; v.playerLayer.videoGravity = .resizeAspectFill; return v }
        func updateUIView(_ v: PlayerView, context: Context) {}
        final class PlayerView: UIView {
            override static var layerClass: AnyClass { AVPlayerLayer.self }
            var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        }
    }
}
