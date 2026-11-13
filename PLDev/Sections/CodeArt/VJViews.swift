import SwiftUI
import UIKit

// The VJ instrument's screens (the twin of /live): the full-bleed output, a rack under it (deck, mix, effects, modulation,
// sequencer, sets), the piece browser, SNAP and REC. Segmented control, grouped form, no second tab bar (DESIGN.md).

struct NativeVJRoom: View {
    let model: AppModel
    var body: some View { CodeArtGate(model: model) { VJInstrument(model: model) } }
}

private enum RackTab: String, CaseIterable, Identifiable {
    case deck = "Deck", mix = "Mix", fx = "FX", mod = "Mod", seq = "Seq", sets = "Sets"
    var id: String { rawValue }
}

struct VJInstrument: View {
    let model: AppModel
    @State private var vj = VJModel()
    @State private var tab = RackTab.deck
    @State private var open = false
    @State private var browsing: VJTarget?
    @State private var audio = AudioController.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VJMetalView(vj: vj)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { audio.toggle() }
                .gesture(DragGesture(minimumDistance: 44).onEnded { g in
                    if abs(g.translation.width) > abs(g.translation.height) { vj.step(g.translation.width < 0 ? 1 : -1) }
                })
            HUD(vj: vj)
        }
        .background(Color.black)
        .navigationTitle(vj.nameA.isEmpty ? "Live" : vj.nameA)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { browsing = .deckA } label: { Image(systemName: "square.grid.2x2") }.accessibilityLabel("Pieces")
                Button { vj.snap(model: model) } label: { Image(systemName: "camera") }.accessibilityLabel("Snap")
                Button { vj.toggleRecording() } label: { Image(systemName: vj.recording ? "stop.circle.fill" : "record.circle").foregroundStyle(vj.recording ? .red : .primary) }
                    .accessibilityLabel(vj.recording ? "Stop recording" : "Record")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { rack }
        .sheet(item: $browsing) { t in VJBrowser(vj: vj, target: t) { vj.choose($0, for: t); browsing = nil } }
        .sheet(item: $vj.share) { ShareSheet(items: $0.items) }
        .task { vj.start() }
        .sensoryFeedback(PLHaptic.select, trigger: vj.p.pieceA)
        .sensoryFeedback(.impact(weight: .light), trigger: vj.beat)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // the rack: a handle, then the tab picker, then the tab's form
    private var rack: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                Capsule().fill(.secondary.opacity(0.6)).frame(width: 38, height: 5).padding(.vertical, 8).frame(maxWidth: .infinity)
            }.buttonStyle(.plain).accessibilityLabel(open ? "Close the rack" : "Open the rack")
            Picker("Rack", selection: $tab) { ForEach(RackTab.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding(.horizontal)
                .onChange(of: tab) { _, _ in if !open { withAnimation(.snappy) { open = true } } }
            if open {
                Form {
                    switch tab {
                    case .deck: deck
                    case .mix: mix
                    case .fx: fx
                    case .mod: mod
                    case .seq: seq
                    case .sets: sets
                    }
                    if let l = vj.line { Section { ResultLine(text: l) } }
                }
                .frame(height: 330)
                .scrollContentBackground(.hidden)
            }
        }
        .background(.bar)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ fmt: String = "%.2f") -> some View {
        HStack {
            Text(title).frame(width: 78, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: fmt, value.wrappedValue)).monospacedDigit().font(.caption).frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: Deck

    @ViewBuilder private var deck: some View {
        Section("Now") {
            Button { browsing = .deckA } label: { LabeledContent("Piece", value: vj.name(vj.p.pieceA)) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    let id = vj.p.slots[i]
                    Text(id.isEmpty ? "Pad \(i + 1)" : vj.name(id)).font(.caption2).lineLimit(1).frame(maxWidth: .infinity, minHeight: 34)
                        .background(id == vj.p.pieceA ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onTapGesture { if id.isEmpty { browsing = .slot(i) } else { vj.p.pieceA = id } }
                        .contextMenu {
                            Button("Put the current piece here", systemImage: "square.and.arrow.down") { vj.p.slots[i] = vj.p.pieceA }
                            Button("Choose a piece", systemImage: "square.grid.2x2") { browsing = .slot(i) }
                            if !id.isEmpty { Button("Clear", systemImage: "xmark", role: .destructive) { vj.p.slots[i] = "" } }
                        }
                }
            }
            Button("Random piece", systemImage: "dice") { vj.randomPiece() }
        }
        Section("Movement") {
            slider("Speed", $vj.p.speed, 0...3)
            slider("Zoom", $vj.p.zoom, 0.3...3.5)
            slider("Tilt", $vj.p.tilt, -180...180, "%.0f°")
            slider("Warm", $vj.p.warm, 0...1)
            slider("Strength", $vj.p.blend, 0.1...1)
        }
        Section("Reacts to the sound") {
            slider("Bass", $vj.p.react[0], 0...2)
            slider("Mid", $vj.p.react[1], 0...2)
            slider("High", $vj.p.react[2], 0...2)
        }
        Section("Tempo") {
            HStack {
                Button("Tap tempo", systemImage: "hand.tap") { vj.tapTempo() }
                Spacer()
                Text(vj.p.bpm > 0 ? "\(Int(vj.p.bpm)) bpm" : "Following the bass").foregroundStyle(.secondary).monospacedDigit()
                if vj.p.bpm > 0 { Button("Auto") { vj.autoTempo() } }
            }
            Toggle("Change piece on the beat", isOn: $vj.p.auto)
            if vj.p.auto { Picker("Every", selection: $vj.p.autoEvery) { ForEach([4, 8, 16, 32], id: \.self) { Text("\($0) beats").tag($0) } } }
        }
        Section("Sound") {
            AudioSourceMenu(model: model)
            if let l = audio.line { ResultLine(text: l) }
            Toggle("Include the archive (\(max(0, PieceRuntime.shared.pieces.count - PieceRuntime.shared.pieces.filter(\.live).count)) more)", isOn: $vj.p.includeArchive)
                .onChange(of: vj.p.includeArchive) { _, _ in vj.refreshPieces() }
        }
    }

    // MARK: Mix

    @ViewBuilder private var mix: some View {
        Section("Layers") {
            LabeledContent("A (under)", value: vj.name(vj.p.pieceA))
            Toggle("Layer B (over)", isOn: $vj.p.layerBOn)
            if vj.p.layerBOn {
                Button { browsing = .deckB } label: { LabeledContent("Piece on B", value: vj.p.pieceB.isEmpty ? "Choose" : vj.name(vj.p.pieceB)) }
                Picker("Blend", selection: $vj.p.layerBlend) { ForEach(0..<4, id: \.self) { Text(VJParams.blendNames[$0]).tag($0) } }
                slider("Opacity B", $vj.p.opacityB, 0...1)
            }
        }
    }

    // MARK: FX

    @ViewBuilder private var fx: some View {
        Section("Effects") {
            ForEach(0..<8, id: \.self) { i in slider(VJParams.fxIDs[i].capitalized, $vj.p.fx[i], 0...1) }
            Button("All off", systemImage: "xmark.circle", role: .destructive) { vj.p.fx = Array(repeating: 0, count: 8) }
        }
    }

    // MARK: Mod

    @ViewBuilder private var mod: some View {
        Section {
            Text("Send the bass, mid, high, beat or a tempo-synced wave into any knob. It adds to where the knob sits.").font(.footnote).foregroundStyle(.secondary)
        }
        ForEach(0..<5, id: \.self) { k in
            Section(VJParams.modParams[k].capitalized) {
                ForEach(0..<5, id: \.self) { s in slider(VJParams.modSources[s].capitalized, $vj.p.mod[k][s], -1...1) }
            }
        }
        Section { Button("Clear every route", systemImage: "xmark.circle", role: .destructive) { vj.p.mod = [[Double]](repeating: [Double](repeating: 0, count: 5), count: 5) } }
    }

    // MARK: Seq

    @ViewBuilder private var seq: some View {
        Section {
            Toggle("Step sequencer (moves on the beat)", isOn: $vj.p.seqOn)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(0..<8, id: \.self) { i in
                    let id = vj.p.seq[i]
                    Text(id.isEmpty ? "\(i + 1)" : vj.name(id)).font(.caption2).lineLimit(2).frame(maxWidth: .infinity, minHeight: 44)
                        .background(vj.p.seqOn && vj.seqStep == i ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onTapGesture { browsing = .step(i) }
                        .contextMenu { if !id.isEmpty { Button("Clear step", systemImage: "xmark", role: .destructive) { vj.p.seq[i] = "" } } }
                }
            }
        } footer: { Text("Tap a step to choose its piece. Touch and hold to clear it.") }
    }

    // MARK: Sets

    @ViewBuilder private var sets: some View {
        Section {
            ForEach(0..<8, id: \.self) { i in
                HStack {
                    if let s = vj.presets[i] {
                        Button { vj.recall(i) } label: { VStack(alignment: .leading) { Text("Set \(i + 1)").font(.footnote).foregroundStyle(.secondary); Text(vj.name(s.pieceA)) } }
                        Spacer()
                        Button("Replace") { vj.savePreset(i) }.buttonStyle(.bordered)
                    } else {
                        Text("Set \(i + 1)").foregroundStyle(.secondary)
                        Spacer()
                        Button("Save here") { vj.savePreset(i) }.buttonStyle(.bordered)
                    }
                }
                .swipeActions(edge: .trailing) { if vj.presets[i] != nil { Button("Clear", role: .destructive) { vj.clearPreset(i) } } }
            }
        } footer: { Text("A set keeps the piece, the knobs, the layers, the effects and the routes.") }
    }
}

// MARK: - the output

/// The levels and the beat, over the picture.
private struct HUD: View {
    let vj: VJModel
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            bar(vj.bass); bar(vj.mid); bar(vj.high)
            Circle().fill(.white).frame(width: 8, height: 8).opacity(vj.beat ? 1 : 0.15).padding(.leading, 3)
        }
        .padding(10)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.top, 8).padding(.trailing, 10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    private func bar(_ v: Double) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 5, height: max(3, 28 * v))
    }
}

final class VJMetalUIView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metal: CAMetalLayer { layer as! CAMetalLayer }
    weak var engine: VJEngine?
    private var link: CADisplayLink?
    private var sized = CGSize.zero

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(window?.screen.scale ?? 2, 2)
        let px = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        if px.width > 1, px != sized {
            sized = px
            metal.drawableSize = px
            engine?.setSize(pxW: Int(px.width), pxH: Int(px.height), dpr: Double(scale))
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let l = CADisplayLink(target: VJLinkProxy(self), selector: #selector(VJLinkProxy.tick))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
        setNeedsLayout()
    }

    fileprivate func tick() { engine?.kick() }
}

private final class VJLinkProxy: NSObject {
    weak var target: VJMetalUIView?
    init(_ t: VJMetalUIView) { target = t }
    @objc func tick() { target?.tick() }
}

struct VJMetalView: UIViewRepresentable {
    let vj: VJModel
    func makeUIView(context: Context) -> VJMetalUIView {
        let v = VJMetalUIView()
        v.backgroundColor = .black
        v.engine = vj.engine
        vj.engine.attach(layer: v.metal)
        return v
    }
    func updateUIView(_ v: VJMetalUIView, context: Context) {}
    static func dismantleUIView(_ v: VJMetalUIView, coordinator: ()) { v.engine = nil }
}

// MARK: - the browser

struct VJBrowser: View {
    let vj: VJModel
    let target: VJTarget
    let pick: (String) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var list: [PieceInfo] {
        vj.pieces.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.sub.localizedCaseInsensitiveContains(search) || $0.tags.contains { $0.localizedCaseInsensitiveContains(search) } }
    }

    var body: some View {
        NavigationStack {
            List(list) { p in
                Button { pick(p.id) } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: p.ground) ?? .gray)
                            .overlay(Circle().fill(Color(hex: p.body) ?? .orange).frame(width: 10, height: 10))
                            .frame(width: 34, height: 34)
                        VStack(alignment: .leading) { Text(p.name); if !p.sub.isEmpty { Text(p.sub).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay { if list.isEmpty { ContentUnavailableView.search(text: search) } }
            .searchable(text: $search, prompt: "Piece, word or tag")
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - share

struct ShareItem: Identifiable { let id = UUID(); let items: [Any] }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}
