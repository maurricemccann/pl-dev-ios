import SwiftUI

// The Glass page, the Wallpaper page and the face pickers (his rulings 11-24, S353·7b1e).

/// One page for all glass: a live preview, then cards and Home tiles set apart.
struct GlassPage: View {
    @AppStorage("pldev.glass.card.style") private var cardStyle = "frosted"
    @AppStorage("pldev.glass.card.tint") private var cardTint = 0.0
    @AppStorage("pldev.glass.card.through") private var cardThrough = 0.5
    @AppStorage("pldev.glass.tile.style") private var tileStyle = "frosted"
    @AppStorage("pldev.glass.tile.tint") private var tileTint = 0.45
    @AppStorage("pldev.glass.tile.through") private var tileThrough = 0.5
    @AppStorage("pldev.styleTile") private var tileShape = "squircle"
    @AppStorage("pldev.styleLook") private var look = "glass"
    @AppStorage("pldev.styleIcons") private var iconSet = "pl"
    @State private var kit = HouseKit.shared

    init() {}

    var body: some View {
        List {
            Section {
                ZStack {
                    ThemeGround(quiet: false)
                    VStack(spacing: PLSpace.margin) {
                        HStack(spacing: 28) {
                            ForEach(["house", "curate", "town"], id: \.self) { id in
                                TileIcon(section: id, symbol: "square", iconSet: iconSet)
                                    .modifier(PLTile(shape: PLTile.shape(tileShape), look: look))
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("A card").plTitle(.headline)
                            Text("Panels, rows and sheets wear this.").plFont(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(PLSpace.margin)
                        .plGlass(in: RoundedRectangle(cornerRadius: PLRadius.card, style: .continuous))
                    }
                    .padding(PLSpace.margin)
                }
                .frame(height: 230)
                .listRowInsets(EdgeInsets())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview of tiles and a card on your wallpaper")
            }
            controls("Cards", style: $cardStyle, tint: $cardTint, through: $cardThrough)
            controls("Home tiles", style: $tileStyle, tint: $tileTint, through: $tileThrough)
            Section {
                Picker("Tile look", selection: $look) {
                    ForEach(["glass", "typewriter", "keycap", "bubble", "dome", "terminal", "neon", "bevel", "flat", "bare"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                Button("Reset to the theme\u{2019}s own") {
                    if let t = PLThemePreset.current { t.resetGlass(); look = t.look } else { reset() }
                }
                .frame(minHeight: PLMetric.touch)
            }
        }
        .plGround()
        .plScreenTitle("Glass")
        .sensoryFeedback(PLHaptic.select, trigger: [cardStyle, tileStyle, look])
    }

    private func reset() {
        cardStyle = "frosted"; cardTint = 0; cardThrough = 0.5; tileStyle = "frosted"; tileTint = 0.45; tileThrough = 0.5; look = "glass"
    }

    private func controls(_ title: String, style: Binding<String>, tint: Binding<Double>, through: Binding<Double>) -> some View {
        Section(title) {
            Picker("Style", selection: style) {
                Text("Frosted").tag("frosted"); Text("Clear").tag("clear"); Text("Solid").tag("solid"); Text("Outlined").tag("outline")
            }
            .pickerStyle(.segmented)
            slider("Tint", tint, "drop.fill")
            slider("See-through", through, "circle.dotted")
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: PLSpace.tight) {
            SettingsLabel("\(title): \(Int(value.wrappedValue * 100))%", symbol, kit.palette.keyColor)
            Slider(value: value, in: 0...1) { Text(title) }
                .accessibilityValue("\(Int(value.wrappedValue * 100)) percent")
        }
    }
}

/// The wallpaper for the theme he is wearing, remembered per theme.
struct WallpaperPage: View {
    @AppStorage("pldev.styleWall") private var wall = ""
    @AppStorage("pldev.tileStrength") private var strength = 0.5

    private static let art = "https://pub-4420dc4349624d6bbed7eb9555f42661.r2.dev/"
    private static let picks: [(String, String)] = [
        ("Studio night", "mask|" + art + "abstract-pattern_organic-curves_monochrome_digital_970.png"),
        ("Drop day", "color|" + art + "abstract-pattern_organic-interlocking_red-warm_digital_2437.png"),
        ("Copper", "color|" + art + "abstract-pattern_organic-flowing_warm-pink_digital_4693.png"),
        ("The ledger", "invert|" + art + "abstract-pattern_organic-interlocking_monochrome_digital-ink_5373.png"),
        ("Hyperspace", "invert|" + art + "abstract-pattern_organic-flowing_monochrome_digital_5457.png"),
        ("From the archive", "invert|" + art + "glyph-abstract_organic-labyrinthine_monochrome_ink_017.jpg"),
        ("Ember", "mask|" + art + "abstract-pattern_organic-interlocking_black-white_ink-marker_1239.jpg")]
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    init() {}

    var body: some View {
        let theme = PLThemePreset.current
        ScrollView {
            VStack(alignment: .leading, spacing: PLSpace.margin) {
                Text(theme.map { "For \($0.title). Each theme remembers its own." } ?? "Pick a theme to have the choice remembered with it.")
                    .plFont(.footnote).foregroundStyle(.secondary)
                Button {
                    if let theme { UserDefaults.standard.removeObject(forKey: "pldev.wall." + theme.id); wall = theme.wall } else { wall = "" }
                } label: {
                    Label("Reset to the theme\u{2019}s own", systemImage: "arrow.uturn.backward").plFont(.callout, emphasized: true).frame(minHeight: PLMetric.touch)
                }
                .buttonStyle(.bordered)
                VStack(alignment: .leading, spacing: PLSpace.tight) {
                    Text("Strength").plFont(.callout)
                    Slider(value: $strength, in: 0...1) { Text("Wallpaper strength") }
                }
                group("Your seven", Self.picks)
                group("Your patterns", [("Curves", "curves"), ("PL tile", "kit|patterns/pl_tile.png"), ("Curve tile", "kit|patterns/ar-curve-tile.png")])
                group("Drawn grounds", CodeGround.names.map { ($0.1, "code|" + $0.0) })
                NavigationLink { ArchiveWallPage(choose: choose) } label: {
                    Label("Choose from the archive", systemImage: "square.grid.3x3").plFont(.callout, emphasized: true).frame(minHeight: PLMetric.touch)
                }
                .buttonStyle(.bordered)
            }
            .padding(PLSpace.margin)
        }
        .plGround()
        .plScreenTitle("Wallpaper")
        .sensoryFeedback(PLHaptic.select, trigger: wall)
    }

    private func choose(_ spec: String) {
        if let t = PLThemePreset.current { UserDefaults.standard.set(spec, forKey: "pldev.wall." + t.id) }
        wall = spec
    }

    private func group(_ title: String, _ list: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: PLSpace.gap) {
            Text(title).plFont(.headline)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(list, id: \.1) { name, spec in
                    Button { choose(spec) } label: {
                        VStack(spacing: 4) {
                            ThemeGround(spec: spec, quiet: false)
                                .frame(height: 130)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(wall == spec ? PLTone.accent : .secondary.opacity(0.3), lineWidth: wall == spec ? 3 : 1) }
                            Text(name).plFont(.caption2).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                    .accessibilityAddTraits(wall == spec ? .isSelected : [])
                }
            }
        }
    }
}

/// His shareable pieces from the archive's own manifest, for a wallpaper he picks himself.
struct ArchiveWallPage: View {
    let choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pieces: [Piece] = []
    @State private var problem: String?

    struct Piece: Decodable, Identifiable {
        let cr: String, url: String, thumb: String?, title: String?, shareable: Bool?
        var id: String { cr }
    }
    private struct Manifest: Decodable { let pieces: [Piece] }

    /// The twin of pl-headless `lib/archive-manifest.ts` THIRD_PARTY_CR: never offered, whatever the manifest says.
    private static let hidden: Set<String> = ["PL-0099", "PL-0174", "PL-0122", "PL-0501", "PL-1533", "PL-0332", "PL-0421", "PL-0431", "PL-0172", "PL-0173", "PL-0330",
        "PL-0036", "PL-0090", "PL-0211", "PL-0213", "PL-0354", "PL-0358", "PL-0458", "PL-0461", "PL-0045", "PL-0063", "PL-0134", "PL-0285", "PL-0286", "PL-0287",
        "PL-0429", "PL-0209", "PL-0345", "PL-0080", "PL-0086", "PL-0123"]

    var body: some View {
        ScrollView {
            if let problem {
                EmptyNote(symbol: "wifi.slash", title: "The archive did not load", detail: problem, actionTitle: "Try again") { Task { await load() } }
            } else if pieces.isEmpty {
                ProgressView("Reading the archive").padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                    ForEach(pieces) { p in
                        Button { choose("color|" + p.url); dismiss() } label: {
                            Color.secondary.opacity(0.12).aspectRatio(1, contentMode: .fit)
                                .overlay { AsyncImage(url: URL(string: p.thumb ?? p.url)) { $0.resizable().scaledToFill() } placeholder: { Color.clear } }
                                .clipped()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(p.title ?? p.cr)
                    }
                }
                .padding(6)
            }
        }
        .plGround()
        .plScreenTitle("The archive")
        .task { if pieces.isEmpty { await load() } }
    }

    private func load() async {
        problem = nil
        guard let url = URL(string: "https://assets.psychedluxuries.com/manifest.json") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { problem = "The archive refused the list."; return }
            pieces = try JSONDecoder().decode(Manifest.self, from: data).pieces.filter { $0.shareable != false && !Self.hidden.contains($0.cr) }
            if pieces.isEmpty { problem = "The list came back empty." }
        } catch { problem = plainSentence(error) }
    }
}

/// The notices the open icon sets ask for.
struct AcknowledgementsPage: View {
    init() {}

    var body: some View {
        List {
            ForEach(Licences.all, id: \.name) { l in
                Section(l.name) {
                    Text(l.source).font(.footnote).foregroundStyle(.secondary)
                    Text(l.text).font(.footnote).textSelection(.enabled)
                }
            }
        }
        .plGround()
        .plScreenTitle("Acknowledgements")
    }
}

/// Title face or text face, from every face the house has. A house face is fetched once, then kept.
struct FacePage: View {
    let isTitle: Bool
    @AppStorage("pldev.font") private var textFace = "system"
    @State private var kit = HouseKit.shared
    @State private var busy: String?
    @State private var problem: String?

    init(isTitle: Bool) { self.isTitle = isTitle }

    var body: some View {
        List {
            if let problem { Text(problem).font(.footnote).foregroundStyle(.secondary) }
            group("Your hands", KitFaces.his.filter { isTitle || !["v1", "ransom", "ledger"].contains($0.1) })
            group("House faces", KitFaces.house)
            if !isTitle { group("Built in", KitFaces.bundled) }
        }
        .plGround()
        .plScreenTitle(isTitle ? "Title face" : "Text face")
    }

    @ViewBuilder private func group(_ title: String, _ list: [(String, String)]) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list, id: \.1) { name, token in
                    let on = (isTitle ? kit.titleFace : textFace) == token
                    Button {
                        busy = token
                        Task {
                            if await HouseFonts.ensure(token) {
                                problem = nil
                                if isTitle { kit.titleFace = token } else { textFace = token }
                                PLCarry.epoch.n += 1
                            } else { problem = "\(name) needs a connection once." }
                            busy = nil
                        }
                    } label: {
                        HStack {
                            Text(name).font(HouseFonts.name(token).map { Font.custom($0, size: 19) } ?? .body)
                            Spacer()
                            if busy == token { ProgressView() } else if on { Image(systemName: "checkmark").foregroundStyle(kit.palette.keyColor) }
                        }
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    .disabled(busy != nil)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}
