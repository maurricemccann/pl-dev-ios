import AVFoundation
import SwiftUI

// The preview: the piece played on the phone, shot by shot, with the transitions the spec will ask for (dissolve, black, wipe, slide, cut).
// It is the board's intent made visible, not the renderer: a library asset shows its thumbnail, a clip from Photos plays (in and out kept),
// and the bed is not mixed. Scrub, step shot to shot, play.

struct ComposerPreviewSheet: View {
    let piece: ComposerPiece
    @State private var lib = ComposerLibrary.shared
    @State private var extras = ComposerExtras.shared
    @State private var t = 0.0
    @State private var playing = false
    @Environment(\.dismiss) private var dismiss
    private let ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    private var total: Double { max(0.1, piece.duration) }
    private var ratio: CGFloat {
        let p = piece.resolution.split(separator: "x").compactMap { Double($0) }
        return p.count == 2 && p[1] > 0 ? CGFloat(p[0] / p[1]) : 9.0 / 16.0
    }

    /// Where the timeline is: the shot, the seconds into it, and the transition that brought it in.
    private struct Where { var index: Int; var local: Double; var word: String; var secs: Double }
    private func locate(_ at: Double) -> Where {
        var start = 0.0
        for (i, s) in piece.shots.enumerated() {
            let end = start + s.duration
            if at < end || i == piece.shots.count - 1 {
                let (w, secs) = i == 0 ? ("cut", 0) : entering(s)
                return Where(index: i, local: min(max(0, at - start), s.duration), word: w, secs: secs)
            }
            start = end
        }
        return Where(index: 0, local: 0, word: "cut", secs: 0)
    }
    private func entering(_ s: ComposerShot) -> (String, Double) {
        let raw = s.transition ?? piece.transition ?? "cut"
        let parts = raw.split(separator: " ")
        let word = parts.first.map(String.init) ?? "cut"
        return (word, word == "cut" ? 0 : (parts.dropFirst().first.flatMap { Double($0) } ?? composerTransitionSeconds))
    }
    private func startOf(_ index: Int) -> Double { piece.shots.prefix(index).reduce(0) { $0 + $1.duration } }

    private func picture(_ s: ComposerShot) -> UIImage? {
        for id in s.sourceIds {
            guard let a = lib.byId[id], a.kind != "audio" else { continue }
            if let img = extras.preview(id) ?? lib.image(id) { return img }
        }
        return nil
    }
    private func clip(_ s: ComposerShot) -> (url: URL, start: Double)? {
        for id in s.sourceIds {
            guard let a = lib.byId[id], a.kind != "audio" else { continue }
            if let u = extras.clipURL(id) { return (u, extras.extra(id)?.trimIn ?? 0) }
            return nil   // the base is not a Photos clip: the thumbnail stands in
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if piece.shots.isEmpty {
                    ContentUnavailableView("No shots to play", systemImage: "play.slash", description: Text("Add a shot and attach something to it, then preview the piece here."))
                } else {
                    let w = locate(t)
                    stage(w).aspectRatio(ratio, contentMode: .fit).frame(maxHeight: 520).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CMP.line, lineWidth: 0.8) }
                        .accessibilityIdentifier("composer.preview.stage")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Shot \(String(format: "%02d", w.index + 1)) of \(piece.shots.count): \(piece.shots[w.index].title)").font(.system(size: 14, design: .serif)).foregroundStyle(CMP.text).lineLimit(1)
                            .accessibilityIdentifier("composer.preview.shot")
                        Text(w.index == 0 ? "opens the piece" : "enters with " + (w.word == "cut" ? "a cut" : "\(w.word) \(GVal.js(w.secs))s")).cmpNum(11).foregroundStyle(CMP.dim)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 12) {
                        Button { jump(w.index - 1, w) } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Previous shot")
                        Button { toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 20)).frame(width: 52, height: 44) }
                            .buttonStyle(CMPPill(primary: true)).accessibilityLabel(playing ? "Pause" : "Play").accessibilityIdentifier("composer.preview.play")
                        Button { jump(w.index + 1, w) } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Next shot")
                        Slider(value: Binding(get: { t }, set: { t = $0; playing = false }), in: 0...total).tint(CMP.gold)
                            .accessibilityLabel("Position").accessibilityIdentifier("composer.preview.scrub")
                    }
                    .foregroundStyle(CMP.text)
                    HStack {
                        Text(String(format: "%.1f s", t)).cmpNum(12).foregroundStyle(CMP.text).accessibilityIdentifier("composer.preview.time")
                        Spacer()
                        Text(String(format: "%.1f s", total) + " · \(piece.resolution) · \(piece.fps) fps").cmpNum(11).foregroundStyle(CMP.muted)
                    }
                    Text("A library asset shows its thumbnail; a clip from Photos plays. The bed is not mixed here: the renderer does that.").font(.system(size: 11)).foregroundStyle(CMP.muted).frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(PLSpace.margin)
            .cmpScreen().navigationTitle("Preview").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onReceive(ticker) { _ in
                guard playing else { return }
                t = min(total, t + 1.0 / 30.0)
                if t >= total { playing = false }
            }
        }
        .presentationDetents([.large])
    }

    private func toggle() {
        if !playing, t >= total - 0.05 { t = 0 }
        playing.toggle()
    }
    private func jump(_ to: Int, _ w: Where) {
        playing = false
        let i = min(max(0, to), piece.shots.count - 1)
        t = to < w.index && w.local > 0.5 ? startOf(w.index) : startOf(i)
    }

    @ViewBuilder private func still(_ s: ComposerShot) -> some View {
        ZStack {
            Color.black
            if let img = picture(s) { Image(uiImage: img).resizable().scaledToFill() }
            else { Text(s.sourceIds.isEmpty ? "no sources: this shot renders black" : "no picture for this shot").font(.system(size: 11)).foregroundStyle(CMP.muted) }
        }
        .clipped()
    }

    @ViewBuilder private func stage(_ w: Where) -> some View {
        GeometryReader { geo in
            let cur = piece.shots[w.index]
            let inTransition = w.index > 0 && w.word != "cut" && w.local < w.secs
            let p = inTransition ? w.local / max(0.05, w.secs) : 1.0
            ZStack {
                Color.black
                if inTransition {
                    let prev = piece.shots[w.index - 1]
                    switch w.word {
                    case "black":
                        if p < 0.5 { still(prev).opacity(1 - p * 2) } else { still(cur).opacity(p * 2 - 1) }
                    case "wipe":
                        still(prev)
                        still(cur).offset(y: geo.size.height * (1 - p)).clipped()
                    case "slide":
                        still(prev).offset(y: -geo.size.height * p)
                        still(cur).offset(y: geo.size.height * (1 - p))
                    default:   // dissolve
                        still(prev)
                        still(cur).opacity(p)
                    }
                } else {
                    still(cur)
                    if let c = clip(cur) { ClipLayer(url: c.url, start: c.start + w.local, playing: playing) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height).clipped()
        }
    }
}

/// A clip from Photos, drawn by AVPlayer. It follows the timeline: scrubbing seeks it, play and pause drive it.
private struct ClipLayer: UIViewRepresentable {
    let url: URL
    let start: Double
    let playing: Bool

    final class Host: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var layer_: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer?
        var url: URL?
    }

    func makeUIView(context: Context) -> Host {
        let v = Host(); v.backgroundColor = .black; v.layer_.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ v: Host, context: Context) {
        if v.url != url {
            let p = AVPlayer(playerItem: AVPlayerItem(url: url))
            p.isMuted = true; v.player = p; v.layer_.player = p; v.url = url
            p.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        guard let p = v.player else { return }
        let drift = abs(p.currentTime().seconds - start)
        if !playing || drift > 0.4 { p.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
        if playing { p.play() } else { p.pause() }
    }

    static func dismantleUIView(_ v: Host, coordinator: ()) { v.player?.pause(); v.player = nil }
}
