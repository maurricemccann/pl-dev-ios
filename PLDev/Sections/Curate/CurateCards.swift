import AVFoundation
import AVKit
import SwiftUI

/// The sound choice for clips, remembered across cards and visits (web `pl-curate-sound`, S310): off until he taps the speaker.
enum CurateSound {
    static var on: Bool {
        get { UserDefaults.standard.bool(forKey: "pl-curate-sound") }
        set { UserDefaults.standard.set(newValue, forKey: "pl-curate-sound") }
    }
}

/// A muted clip that loops, through the system player. (The Library's card uses this one.)
struct LoopingClip: View {
    let url: URL
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let p = AVQueuePlayer(); p.isMuted = true
                looper = AVPlayerLooper(player: p, templateItem: AVPlayerItem(url: url))
                player = p; p.play()
            }
            .onDisappear { player?.pause(); player = nil; looper = nil }
    }
}

/// A looping player with no controls: the card is the picture, the swipe is the gesture.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> LayerHost { let v = LayerHost(); v.playerLayer.player = player; v.playerLayer.videoGravity = .resizeAspect; return v }
    func updateUIView(_ v: LayerHost, context: Context) { v.playerLayer.player = player }
    final class LayerHost: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// A deck clip: its poster paints first, the clip loops over it, and one tap on the speaker brings its sound (web SoundVideo).
/// The recorded pieces carry their scored sound and his Voicebox lines, which an iPhone only plays when he asks.
struct CurateClip: View {
    let url: URL
    var poster: URL?
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var sound = CurateSound.on
    @State private var ready = false
    @State private var token = UUID()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let poster { AsyncImage(url: poster) { $0.resizable().scaledToFit() } placeholder: { Color.clear } }
            if let player { PlayerLayerView(player: player).opacity(ready ? 1 : 0).animation(.easeOut(duration: 0.2), value: ready) }
            Button { toggle() } label: {
                Image(systemName: sound ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain).padding(8)
            .accessibilityLabel(sound ? "Sound off" : "Sound on")
        }
        .onAppear { start() }
        .onDisappear { player?.pause(); player = nil; looper = nil; ready = false }
    }

    private func start() {
        let p = AVQueuePlayer()
        p.isMuted = !CurateSound.on
        if CurateSound.on { try? AVAudioSession.sharedInstance().setCategory(.playback); try? AVAudioSession.sharedInstance().setActive(true) }
        looper = AVPlayerLooper(player: p, templateItem: AVPlayerItem(url: url))
        player = p; sound = CurateSound.on
        p.play()
        Task { @MainActor in   // the first decoded frame lifts the poster away
            for _ in 0..<80 { if p.currentTime().seconds > 0.05 { ready = true; return }; try? await Task.sleep(for: .milliseconds(100)) }
            ready = true
        }
    }

    private func toggle() {
        sound.toggle(); CurateSound.on = sound
        if sound { try? AVAudioSession.sharedInstance().setCategory(.playback); try? AVAudioSession.sharedInstance().setActive(true) }
        player?.isMuted = !sound
        if sound { player?.play() }
    }
}

/// An essay card: its whole text scrolling inside the card, title in italics, paragraphs in the serif, `*word*` set in italic
/// (web EssayCard). A scroll here is never a swipe: the keys below decide.
struct EssayCard: View {
    let url: URL
    @State private var text: String?
    var body: some View {
        ScrollView {
            if let text {
                let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                VStack(alignment: .leading, spacing: 14) {
                    Text(parts.first ?? "").font(.system(size: 26, design: .serif).italic()).foregroundStyle(PLC.ink)
                    ForEach(Array((parts.count > 1 ? parts[1] : "").trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, para in
                        Text((try? AttributedString(markdown: para, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(para))
                            .font(.system(size: 17, design: .serif)).foregroundStyle(PLC.ink).lineSpacing(5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 40)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            }
        }
        .task(id: url) {
            if let (d, _) = try? await URLSession.shared.data(from: url) { text = String(decoding: d, as: UTF8.self) } else { text = "This essay did not load." }
        }
    }
}

/// A seed phrase as the web deck draws it: his hand, upper-cased, sized to fit (30 / 23 / 17 / 14 by length), on the house ground.
struct SeedCard: View {
    let phrase: String
    @State private var kit = HouseKit.shared
    var body: some View {
        let n = phrase.count
        ZStack {
            kit.palette.groundColor
            Text(phrase.uppercased())
                .plHand(n < 70 ? 34 : n < 160 ? 26 : n < 300 ? 20 : 16, relativeTo: .title)
                .foregroundStyle(kit.palette.textColor)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)
                .padding(28)
        }
        .accessibilityLabel(phrase)
    }
}

/// One card's picture, by class (web CardMedia): code runs live, shorts play, archive works paint their thumbnail then fade the
/// original in, stills and fonts show whole, a work with only a palette shows its four colours.
struct CurateCardMedia: View {
    let model: AppModel
    let state: CurateModel
    let item: LibraryItem

    var body: some View {
        let m = state.media(item, model: model)
        Group {
            switch item.class {
            case "seed": SeedCard(phrase: item.name ?? "")
            case "essay":
                if let src = item.src, let url = URL(string: LibraryData.shared.base(model) + src) { EssayCard(url: url) } else { label }
            case "code-piece": LivePieceCard(model: model, pieceID: item.item_id, thumb: m.still)
            case "cinematic":
                if let v = m.video { CurateClip(url: v, poster: m.still) } else { still(m.still) }
            case "archive-work": archive(m.still)
            default: still(m.still)
            }
        }
        .id(item.vault_id)   // a fresh card each time, so the last picture never shows under the next name
    }

    /// `thumb/` inserted before the file name: ~40 KB, paints at once while the 10-22 MB original arrives.
    private func archive(_ url: URL?) -> some View {
        let s = url?.absoluteString ?? ""
        let thumb = (s.contains(".r2.dev/") && !s.contains("/thumb/"))
            ? URL(string: s.replacingOccurrences(of: #"/([^/]+)\.(png|jpe?g)$"#, with: "/thumb/$1.jpg", options: [.regularExpression, .caseInsensitive])) : nil
        return ZStack {
            if let thumb { AsyncImage(url: thumb) { $0.resizable().scaledToFit() } placeholder: { Color.clear } }
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let i): i.resizable().scaledToFit()
                case .failure: if thumb == nil { palette }
                default: if thumb == nil { ProgressView() }
                }
            }
        }
    }

    private func still(_ url: URL?) -> some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let i): i.resizable().scaledToFit()
                    case .failure: palette
                    default: ProgressView()
                    }
                }
            } else { palette }
        }
    }

    /// A work with no picture shows its four palette colours side by side, else its class in the instrument face.
    @ViewBuilder private var palette: some View {
        let colors = state.palette(item)
        if colors.isEmpty { label } else { HStack(spacing: 0) { ForEach(colors.indices, id: \.self) { colors[$0] } } }
    }

    private var label: some View {
        Text(item.class).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.06))
    }
}

/// One of his keycap pictures (gallery /remote/cap-<name>-up|down-t3.png): up at rest, down while pressed, and pinned down when
/// the card is already a favourite. Five caps edge to edge in the black tray, as the macropad is built (S332, S336).
struct KeyCap: View {
    let model: AppModel
    let name: String
    let label: String
    var down = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(CapStyle(base: LibraryData.shared.base(model), name: name, pinned: down))
            .accessibilityLabel(label)
            .accessibilityAddTraits(down ? .isSelected : [])
    }
    struct CapStyle: ButtonStyle {
        let base: String
        let name: String
        let pinned: Bool
        func makeBody(configuration: Configuration) -> some View {
            let pressed = configuration.isPressed || pinned
            AsyncImage(url: URL(string: "\(base)/remote/cap-\(name)-\(pressed ? "down" : "up")-t3.png")) { $0.resizable().scaledToFit() }
                placeholder: { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PLG.surface(.dark)) }
                .aspectRatio(152.0 / 134.0, contentMode: .fit)
                .frame(maxWidth: 80)
                .contentShape(Rectangle())
        }
    }
}
