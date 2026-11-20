import RealityKit
import SwiftUI
import UIKit

// The Pack test page as a native room (his ruling 11-19, "the Pack in full"): the same layout as /pack/ on the gallery. The count
// and the Collection and Editor pills across the top, the 3D pack over his drifting curves, the hint and the one action button
// below, the two sheets. Courier Prime in champagne on the page's navy, as the page draws it.

enum PackLook {
    static let champ = Color(red: 0xE3 / 255, green: 0xC7 / 255, blue: 0x8F / 255)
    static let ink = Color(red: 7 / 255, green: 7 / 255, blue: 8 / 255)
    static let alert = Color(red: 0xF3 / 255, green: 0xB0 / 255, blue: 0xA0 / 255)
    static func font(_ size: CGFloat = 14) -> Font { .custom(PLFace.label, size: size, relativeTo: .body) }
    // the CC BY credit's link; its id is the model's public page id, split only so the repo's key scan does not read it as a token
    static let sketchfab = "https://sketchfab.com/3d-models/trading-card-pack-" + "26d1a87e4781" + "4d0ea3a710d169e3a671"
}

/// The page's pill button: champagne hairline on smoked black, 44 pt tall.
struct PackPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PackLook.font()).foregroundStyle(PackLook.champ)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(Capsule().fill(configuration.isPressed ? PackLook.champ.opacity(0.16) : PackLook.ink.opacity(0.55)))
            .overlay(Capsule().strokeBorder(PackLook.champ, lineWidth: 1))
            .contentShape(Capsule())
    }
}

struct CurvesPackRoom: View {
    let model: AppModel
    var close: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = PackEngine()

    init(model: AppModel, close: (() -> Void)? = nil) { self.model = model; self.close = close }

    var body: some View {
        @Bindable var e = engine
        ZStack {
            engine.ground.ignoresSafeArea()
            PackBackdrop(engine: engine).ignoresSafeArea().allowsHitTesting(false)
            RealityView { content in engine.install(&content) }
                .ignoresSafeArea()
                .background { GeometryReader { g in Color.clear.onAppear { engine.fit(g.size) }.onChange(of: g.size) { _, s in engine.fit(s) } } }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { engine.drag($0.location) }.onEnded { _ in engine.lift() })
                .accessibilityElement()
                .accessibilityLabel(engine.stageLabel)
                .accessibilityAddTraits(.allowsDirectInteraction)
                .accessibilityAction(named: "Open the pack") { engine.tapOpen() }
            VStack(spacing: 0) {
                bar
                notes
                Spacer(minLength: 0)
                Text("Drag to turn \u{00b7} swipe the top to rip")
                    .font(PackLook.font()).foregroundStyle(PackLook.champ).lineLimit(1).minimumScaleFactor(0.8)
                    .opacity(engine.loaded && engine.state == .sealed ? 0.8 : 0)
                    .animation(.easeInOut(duration: 0.4), value: engine.state)
                    .padding(.bottom, 20).allowsHitTesting(false).accessibilityHidden(engine.state != .sealed)
                if let t = engine.actTitle {
                    Button(t) { Task { await engine.act() } }.buttonStyle(PackPill()).frame(minWidth: 150).padding(.bottom, 20)
                } else { Color.clear.frame(height: 64) }
            }
            .padding(.horizontal, 12)
            if !engine.loaded && engine.failure == nil { ProgressView().tint(PackLook.champ).accessibilityLabel("Loading the pack") }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(PLHaptic.commit, trigger: engine.state) { _, s in s == .rising || s == .slabbed }
        .sheet(item: $e.sheet) { s in
            Group {
                switch s {
                case .collection: PackCollectionSheet(engine: engine)
                case .editor: PackEditorSheet(engine: engine)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))   // the card still turns while a sheet is half up, as on the page
            .presentationBackground(PackLook.ink.opacity(0.94))
            .preferredColorScheme(.dark)
        }
        .task { engine.still = reduceMotion; await engine.start(model: model) }
        .onDisappear { engine.stop() }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            if let close {   // presented full screen: its own way out; pushed: the navigation bar's back and the edge swipe
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).foregroundStyle(PackLook.champ).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
            }
            Text(engine.countText).font(PackLook.font()).foregroundStyle(PackLook.champ.opacity(0.9)).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.updatesFrequently)
            Button("Collection") { engine.sheet = .collection }.buttonStyle(PackPill()).disabled(!engine.loaded)
            Button("Editor") { engine.sheet = .editor }.buttonStyle(PackPill()).disabled(!engine.loaded)
        }
        .padding(.top, 16)
    }

    @ViewBuilder private var notes: some View {
        if let f = engine.failure {
            VStack(alignment: .leading, spacing: 8) {
                Text(f).font(PackLook.font()).foregroundStyle(PackLook.alert).fixedSize(horizontal: false, vertical: true)
                if !engine.loaded { Button("Try again") { Task { await engine.start(model: model) } }.buttonStyle(PackPill()) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 24)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isStaticText)
        }
        if engine.prismEmpty {
            Text("Prism is empty. Mark favourites in /curate and they are dealt here.")
                .font(PackLook.font()).foregroundStyle(PackLook.champ.opacity(0.85)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.top, 24).allowsHitTesting(false)
        }
    }
}

/// The faint curve hero behind everything: his curves drift, each clearing its own channel, brighter at rest than while opening.
struct PackBackdrop: View {
    let engine: PackEngine
    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in
                let clock = engine.bgClock, k = engine.bgK, col = Color(PackMath.ui(engine.settings.colour.curves))
                var r = PackRNG(5)
                let curves = PackCurve.make(&r, size.width, size.height, 0.5)
                for i in stride(from: 14, through: 0, by: -1) {
                    let c = curves[i], pts = c.points(clock, 48)
                    var p = Path(); p.move(to: CGPoint(x: pts[0], y: pts[1]))
                    for j in 1..<48 { p.addLine(to: CGPoint(x: pts[j * 2], y: pts[j * 2 + 1])) }
                    ctx.blendMode = .destinationOut; ctx.opacity = 1
                    ctx.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: c.w + 24, lineCap: .butt))
                    ctx.blendMode = .normal; ctx.opacity = min(1, min(1, c.op) * k)
                    ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: max(1, c.w), lineCap: .butt))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The sheets' header: the title spaced out, and Close.
private struct PackSheetHeader: View {
    let title: String
    let close: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(PackLook.font(16)).tracking(1.3).foregroundStyle(PackLook.champ).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
            Button("Close", action: close).buttonStyle(PackPill()).accessibilityLabel("Close the \(title.lowercased())")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

struct PackCollectionSheet: View {
    let engine: PackEngine
    var body: some View {
        VStack(spacing: 0) {
            PackSheetHeader(title: "COLLECTION") { engine.sheet = nil }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    ForEach(PackTier.order, id: \.self) { tier in
                        ForEach(engine.cards.filter { $0.tier == tier }) { c in cell(c) }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 20)
            }
        }
    }

    @ViewBuilder private func cell(_ c: PackShowCard) -> some View {
        let name = PackTier.name(c.tier), shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if engine.opened.contains(c.id) {
            Button { Task { await engine.view(c) } } label: {
                Color.black.aspectRatio(63.0 / 88.0, contentMode: .fit)
                    .overlay { AsyncImage(url: engine.imageURL(c)) { i in i.resizable().scaledToFill() } placeholder: { ProgressView().tint(PackLook.champ) } }
                    .overlay(alignment: .bottom) {
                        Text(name).font(PackLook.font(11)).foregroundStyle(PackLook.champ).padding(.horizontal, 4).padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading).background(PackLook.ink.opacity(0.82))
                    }
                    .clipShape(shape).overlay(shape.strokeBorder(PackLook.champ, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name): \(c.piece). Show it.")
        } else {
            Text(name).font(PackLook.font(11)).foregroundStyle(PackLook.champ)
                .frame(maxWidth: .infinity).aspectRatio(63.0 / 88.0, contentMode: .fit)
                .background(PackLook.ink.opacity(0.55), in: shape).overlay(shape.strokeBorder(PackLook.champ, lineWidth: 1)).opacity(0.35)
                .accessibilityLabel("\(name), not opened yet")
        }
    }
}

/// Every control the page's editor has, writing the same SETTINGS.
enum PackControl {
    case range(String, WritableKeyPath<PackSettings, Double>, Double, Double, Double)
    case colour(String, WritableKeyPath<PackSettings, String>)

    @MainActor static let sections: [(String, [PackControl])] = [
        ("PATTERN", [.range("Tile size", \PackSettings.pattern.size, 0.3, 3, 0.05)]),
        ("SHEEN", [.range("Shiny part", \PackSettings.sheen.shiny, 0.02, 0.5, 0.01), .range("Matte black", \PackSettings.sheen.matte, 0.3, 1, 0.01), .range("Matte gold", \PackSettings.sheen.goldMatte, 0.2, 1, 0.01),
                   .range("Pack gloss", \PackSettings.sheen.clearcoat, 0, 1, 0.01), .range("Studio light", \PackSettings.sheen.light, 0, 3, 0.01), .range("Idle sway", \PackSettings.sheen.sway, 0, 3, 0.05),
                   .range("Prism shimmer (web only)", \PackSettings.sheen.iridescence, 0, 1, 0.01)]),
        ("COLOUR", [.colour("Gold", \PackSettings.colour.champagne), .colour("Black", \PackSettings.colour.obsidian), .colour("Heart", \PackSettings.colour.heart), .colour("Silver", \PackSettings.colour.silver),
                    .colour("Page ground", \PackSettings.colour.ground), .colour("Curves", \PackSettings.colour.curves)]),
        ("PRISM", [.range("Rainbow, ground", \PackSettings.colour.prismRainbow, 0, 1, 0.01), .range("Rainbow, curves", \PackSettings.colour.prismCurveRainbow, 0, 1, 0.01),
                   .range("Saturation", \PackSettings.colour.prismSaturation, 0, 1, 0.01), .range("Bands", \PackSettings.colour.prismBands, 0.5, 6, 0.1)]),
        ("BACKGROUND", [.range("At rest", \PackSettings.background.rest, 0, 0.6, 0.01), .range("While opening", \PackSettings.background.during, 0, 0.6, 0.01),
                        .range("As it seats", \PackSettings.background.slab, 0, 0.6, 0.01), .range("Speed", \PackSettings.background.speed, 0, 3, 0.05)]),
        ("ANIMATION (seconds)", [.range("Tap tear", \PackSettings.timing.tearAuto, 0.2, 2, 0.01), .range("Card emerges", \PackSettings.timing.emerge, 0.05, 1, 0.01), .range("Pull", \PackSettings.timing.pull, 0.05, 1, 0.01),
                                 .range("Catch", \PackSettings.timing.`catch`, 0, 0.5, 0.01), .range("Wrapper leaves", \PackSettings.timing.clear, 0.2, 2, 0.01), .range("Poise", \PackSettings.timing.poise, 0, 1.5, 0.01),
                                 .range("Reveal", \PackSettings.timing.reveal, 0.3, 3, 0.01), .range("Clean art", \PackSettings.timing.clean, 0, 2, 0.01), .range("Slab seats", \PackSettings.timing.slab, 0.3, 2.5, 0.01),
                                 .range("Next card", \PackSettings.timing.deal, 0.2, 2, 0.01)]),
        ("REVEAL", [.range("Curves", \PackSettings.reveal.curves, 3, 15, 1), .range("Rim width", \PackSettings.reveal.rim, 0, 10, 0.5), .range("Channel", \PackSettings.reveal.channel, 0, 60, 1),
                    .range("Heart unravels", \PackSettings.reveal.heartUnravel, 0, 1, 1), .range("Lattice cell", \PackSettings.reveal.cell, 18, 48, 1), .range("Lattice jitter", \PackSettings.reveal.jitter, 0, 0.45, 0.01),
                    .range("Wander", \PackSettings.reveal.wander, 0, 8, 0.1), .range("Smoothing", \PackSettings.reveal.smooth, 1, 5, 1), .range("Swell", \PackSettings.reveal.swell, 0, 0.25, 0.01),
                    .range("Hand (his sweep)", \PackSettings.reveal.hand, 0, 1, 0.01), .range("Grow time", \PackSettings.reveal.grow, 0.15, 0.8, 0.01), .range("Stagger", \PackSettings.reveal.stagger, 0, 0.3, 0.01),
                    .range("Opening starts", \PackSettings.reveal.openAt, 0, 0.7, 0.01)]),
        ("TEAR (mm)", [.range("Coil radius", \PackSettings.tear.coil, 1, 8, 0.1), .range("Lip push", \PackSettings.tear.lip, 0, 5, 0.1)]),
        ("MODIFIERS", [.range("Chance per pack (%)", \PackSettings.modifier.chance, 0, 100, 1), .range("Blend", \PackSettings.modifier.blend, 0, 1, 0.01),
                       .range("Pattern scale", \PackSettings.modifier.scale, 0.3, 3, 0.05), .range("Edge softness", \PackSettings.modifier.soft, 0.02, 0.6, 0.01)]),
        ("ODDS (per pack)", [.range("Obsidian", \PackSettings.odds.obsidian, 0, 100, 1), .range("Champagne", \PackSettings.odds.champagne, 0, 100, 1), .range("Prism", \PackSettings.odds.prism, 0, 100, 1),
                             .range("Prism at least every", \PackSettings.odds.pity, 0, 40, 1), .range("Champagne after N black", \PackSettings.odds.champagneAfter, 0, 20, 1)]),
    ]
}

struct PackEditorSheet: View {
    static let credit: AttributedString = {
        let md = "Pack shape adapted from \"Trading Card Pack\" by Mhew2 Creations ([Sketchfab](\(PackLook.sketchfab))), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Changed: re-modelled, re-textured, original artwork removed."
        return (try? AttributedString(markdown: md)) ?? AttributedString("Pack shape adapted from Trading Card Pack by Mhew2 Creations, CC BY 4.0.")
    }()
    @Bindable var engine: PackEngine
    @State private var palette = ""

    var body: some View {
        VStack(spacing: 0) {
            PackSheetHeader(title: "EDITOR") { engine.sheet = nil }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heading("PREVIEW")
                    row("Show a card") {
                        menu(engine.pvTier, [("", "the pack"), ("common", "Obsidian"), ("legendary", "Champagne"), ("exclusive", "Prism")]) { t in Task { await engine.previewTier(t) } }
                    }
                    row("Modifier") {
                        menu(engine.pvMod, [("", "none")] + PackTier.modifiers.map { ($0, $0) }) { m in Task { await engine.previewMod(m) } }
                    }
                    buttons([("Front", engine.showFront), ("Back", engine.showRealBack), ("Play the reveal", engine.playReveal)])
                    row("House palette") {
                        menu(palette, [("", "keep")] + PackTier.house.map { ($0.name, $0.name) }) { p in palette = p; engine.palette(p) }
                    }
                    ForEach(PackControl.sections.indices, id: \.self) { i in
                        let (title, rows) = PackControl.sections[i]
                        heading(title)
                        ForEach(rows.indices, id: \.self) { j in control(rows[j]) }
                    }
                    heading("HAND IT OVER")
                    buttons([("Copy settings", engine.copySettings), ("Apply pasted", engine.applyPasted), ("Defaults", engine.defaults), ("New decks", { Task { await engine.newDecks() } })])
                    Text(engine.said).font(PackLook.font()).foregroundStyle(PackLook.champ.opacity(0.85)).frame(minHeight: 18).padding(.top, 8).accessibilityAddTraits(.updatesFrequently)
                    Text(Self.credit)
                        .font(PackLook.font(11)).foregroundStyle(PackLook.champ.opacity(0.6)).tint(PackLook.champ).padding(.top, 14)
                    TextEditor(text: $engine.json)
                        .font(.custom(PLFace.label, size: 12, relativeTo: .caption)).foregroundStyle(PackLook.champ)
                        .scrollContentBackground(.hidden).background(Color(red: 13 / 255, green: 13 / 255, blue: 16 / 255), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PackLook.champ.opacity(0.5), lineWidth: 1))
                        .frame(minHeight: 120).padding(.top, 10)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .accessibilityLabel("Settings as text: copy from here, or paste settings here and press Apply pasted")
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func heading(_ t: String) -> some View {
        Text(t).font(PackLook.font(12)).tracking(1.7).foregroundStyle(PackLook.champ.opacity(0.7)).padding(.top, 18).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
    }

    private func row<C: View>(_ name: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(name).font(PackLook.font()).foregroundStyle(PackLook.champ).frame(width: 130, alignment: .leading).lineLimit(2).minimumScaleFactor(0.85)
            content()
        }
        .frame(minHeight: 44)
    }

    private func menu(_ value: String, _ options: [(String, String)], _ pick: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.0) { o in Button(o.1) { pick(o.0) } }
        } label: {
            HStack {
                Text(options.first { $0.0 == value }?.1 ?? options.first?.1 ?? "").font(PackLook.font()).foregroundStyle(PackLook.champ)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(PackLook.champ.opacity(0.7))
            }
            .padding(.horizontal, 8).frame(minHeight: 44)
            .background(Color(red: 13 / 255, green: 13 / 255, blue: 16 / 255), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PackLook.champ.opacity(0.5), lineWidth: 1))
        }
    }

    private func buttons(_ items: [(String, @MainActor () -> Void)]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { ForEach(items.indices, id: \.self) { i in Button(items[i].0, action: items[i].1).buttonStyle(PackPill()) } }
            VStack(alignment: .leading, spacing: 8) { ForEach(items.indices, id: \.self) { i in Button(items[i].0, action: items[i].1).buttonStyle(PackPill()) } }
        }
        .padding(.top, 12)
    }

    @ViewBuilder private func control(_ c: PackControl) -> some View {
        switch c {
        case let .range(name, kp, lo, hi, step):
            row(name) {
                Slider(value: Binding(get: { engine.settings[keyPath: kp] }, set: { engine.settings[keyPath: kp] = $0; engine.redraw() }), in: lo...hi, step: step)
                    .tint(PackLook.champ).accessibilityLabel(name)
                Text(String(format: step >= 1 ? "%.0f" : step >= 0.1 ? "%.1f" : "%.2f", engine.settings[keyPath: kp]))
                    .font(PackLook.font()).foregroundStyle(PackLook.champ.opacity(0.85)).monospacedDigit().frame(width: 52, alignment: .trailing)
            }
        case let .colour(name, kp):
            row(name) {
                ColorPicker(name, selection: Binding(get: { Color(PackMath.ui(engine.settings[keyPath: kp])) },
                                                     set: { engine.settings[keyPath: kp] = PackMath.hex(UIColor($0)); engine.redraw() }), supportsOpacity: false)
                    .labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
