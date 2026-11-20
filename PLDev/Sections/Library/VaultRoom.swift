import SwiftUI

// The Vault, ported from pl-curves-gallery app/library/vault/page.tsx, components/VaultHub.tsx and components/VaultExplorer.tsx
// (S350·3b7f): the count cards, then the tree by media type, then provenance, every row carrying its Vault ID. Tap a row to copy
// the ID (his generation handle). Same data the web reads: vault-manifest.json, generated and cinematic manifests, the live R2
// listing, the affirmations feed and the pieces the native runtime lists. No web view.

/// The Vault ID law, lib/vault-id.ts line for line.
enum VaultID {
    static func slug(_ s: String) -> String {
        let base = s.split(separator: "/").last.map(String.init) ?? s
        let noExt = base.replacingOccurrences(of: #"\.[A-Za-z0-9]{2,5}$"#, with: "", options: .regularExpression)
        return noExt.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
    static func curve(_ id: String) -> String { id.hasPrefix("w1-") ? "V-W1-" + id.dropFirst(3) : "V-CRV-" + id }
    static func gen(_ c: String, _ id: String) -> String {
        if c == "td" { return "V-TD-\(id)" }
        return "V-GEN-\(c)-" + (c == "w1" && id.hasPrefix("w1-") ? String(id.dropFirst(3)) : id)
    }
    static func cin(_ f: String) -> String { "V-CIN-" + slug(f) }
    static func model(_ f: String) -> String { "V-MOD-" + slug(f) }
    static func svg(_ f: String) -> String { "V-SVG-" + slug(f) }
    static func audio(_ f: String) -> String { "V-AUD-" + slug(f) }
    static func font(_ f: String) -> String { "V-FNT-" + slug(f) }
    static func lab(_ id: String) -> String { "V-LAB-" + slug(id) }
    static func r2(_ prefix: String, _ name: String) -> String { "V-R2-\(slug(prefix))-\(slug(name))" }
    static func r1(_ s: String) -> String { "V-R1-" + slug(s) }

    /// The web's own fixtures (vault-id.ts selfCheck); a drift here would hand him an ID the web does not know.
    static func selfCheck() {
        assert(curve("nexus") == "V-CRV-nexus")
        assert(curve("w1-noise-c03-04") == "V-W1-noise-c03-04")
        assert(gen("cy", "1280") == "V-GEN-cy-1280")
        assert(gen("td", "0880") == "V-TD-0880")
        assert(gen("w1", "w1-bezier-c03-01") == "V-GEN-w1-bezier-c03-01")
        assert(cin("pl-cloth-flow-v1.mp4") == "V-CIN-pl-cloth-flow-v1")
        assert(model("GlyphBot Idle.fbx") == "V-MOD-glyphbot-idle")
        assert(svg("curve_007 FINAL.svg") == "V-SVG-curve-007-final")
        assert(r2("images", "Some Import (2).png") == "V-R2-images-some-import-2")
        assert(r1("oracle-pocket") == "V-R1-oracle-pocket")
    }
}

struct VaultRow: Identifiable, Hashable {
    let vid: String
    let name: String
    var meta: String? = nil
    var img: URL? = nil
    var room: GalleryRoom? = nil   // a lead row opens its room instead of copying
    var r2Key: String? = nil       // a file filed by hand opens in the native previewer from its menu
    var url: URL? = nil            // the file on the gallery, for Share
    var id: String { vid + "|" + name }
}

struct VaultSub: Identifiable {
    let key: String
    let label: String
    let provenance: String
    var lead: VaultRow? = nil
    let rows: [VaultRow]
    var id: String { key }
    var count: Int { rows.count + (lead == nil ? 0 : 1) }
}

struct VaultCat: Identifiable {
    let key: String
    let label: String
    let subs: [VaultSub]
    var id: String { key }
    var count: Int { subs.reduce(0) { $0 + $1.count } }
}

/// Everything the tree is built from. Only vault-manifest.json is required; every other source that fails is named on the screen.
struct VaultSources {
    struct Manifest: Decodable {
        struct Route: Decodable { let id: String; let name: String; let route: String; let bucket: String? }
        struct Count: Decodable { let count: Int }
        struct File: Decodable { let name: String; let path: String; let kind: String? }
        struct Figure: Decodable { let name: String; let path: String; let figure: String; let clips: [String] }
        let defiance: [Route]
        let labs: [Route]
        let archive: Count
        let generated: Count?
        let cinematic: Count?
        let models: [File]
        let figures: [Figure]?
        let curves: [File]
        let audio: [File]
        let fonts: [File]
        let guides: [Route]
    }
    struct Media: Decodable { let id: String; let file: String; let collection: String; let w: Int?; let h: Int?; let duration: Double? }
    struct R2: Decodable { let name: String; let key: String }
    struct Aff: Decodable { let id: Int; let text: String; let audio: String? }

    var m: Manifest
    var gen: [Media] = []
    var cin: [Media] = []
    var r2: [String: [R2]] = [:]
    var aff: [Aff] = []
    var pieces: [PieceInfo] = []
    var problems: [String] = []

    static let affirmations = "https://pl-manifestation-practice.psychedluxuries.workers.dev"
    static let r1Base = "https://pl-r1.psychedluxuries.workers.dev"
    // VaultExplorer.tsx R1_CREATIONS, its install page's card order
    static let r1: [(String, String)] = [("plos", "the plos board"), ("jarvis", "the jarvis board"), ("library", "the curve library"), ("archive", "the archive"),
                                         ("fleet", "the fleet"), ("practice", "the practice"), ("curves", "the curves"), ("oracle-pocket", "oracle pocket"),
                                         ("codex", "codex draw"), ("seeds", "seed phrase draw"), ("academy", "academy companion"), ("games", "pl tarot")]

    @MainActor static func load(model: AppModel) async throws -> VaultSources {
        guard let http = model.http else { throw Console.Problem.notSetUp }
        struct Items<T: Decodable>: Decodable { let items: [T]? }
        struct Groups: Decodable { let groups: [String: [R2]]? }

        var s = VaultSources(m: try JSONDecoder().decode(Manifest.self, from: try await http.send(RequestPlan(origin: "gallery", path: "vault-manifest.json"), timeout: 60)))
        async let g = http.send(RequestPlan(origin: "gallery", path: "generated/manifest.json"), timeout: 60)
        async let c = http.send(RequestPlan(origin: "gallery", path: "cinematic/manifest.json"), timeout: 60)
        async let l = http.send(RequestPlan(origin: "gallery", path: "api/vault-list"), timeout: 60)
        async let a = URLSession.shared.data(from: URL(string: affirmations + "/api/affirmations")!)
        let lib = LibraryData.shared
        if lib.items.isEmpty { try? await lib.load(model: model) }
        await CodeArtBoot.shared.ensure(model: model)

        // his ruling S282: a cut piece is hidden everywhere. The index name of a still or clip is its file name.
        let cut = Set(lib.items.filter { lib.marks[$0.vault_id]?.v == "cut" }.compactMap(\.name))
        do { s.gen = (try JSONDecoder().decode(Items<Media>.self, from: try await g).items ?? []).filter { !cut.contains($0.file) } }
        catch { s.problems.append("Stills not loaded. \(plainSentence(error))") }
        do { s.cin = (try JSONDecoder().decode(Items<Media>.self, from: try await c).items ?? []).filter { !cut.contains($0.file) } }
        catch { s.problems.append("Video not loaded. \(plainSentence(error))") }
        do { s.r2 = try JSONDecoder().decode(Groups.self, from: try await l).groups ?? [:] }
        catch { s.problems.append("Files filed by hand not loaded. \(plainSentence(error))") }
        do { s.aff = try JSONDecoder().decode(Items<Aff>.self, from: (try await a).0).items ?? [] }
        catch { s.problems.append("Affirmations not loaded. \(plainSentence(error))") }
        if case .failed(let why) = CodeArtBoot.shared.state { s.problems.append("Pieces not loaded. \(why)") }
        s.pieces = PieceRuntime.shared.pieces.filter { $0.set != "forge" }
        if !lib.marksLoaded { s.problems.append("Your marks did not load, so cut stills and clips still show.") }
        return s
    }

    /// VaultExplorer.tsx `cats`, the same shelves in the same order; empty shelves hidden.
    func tree(base: String) -> [VaultCat] {
        func u(_ p: String) -> URL? { URL(string: p.hasPrefix("http") ? p : base + (p.hasPrefix("/") ? p : "/" + p)) }
        func pieceRows(_ keep: (PieceInfo) -> Bool) -> [VaultRow] { pieces.filter(keep).map { VaultRow(vid: VaultID.curve($0.id), name: $0.name) } }
        func genRows(_ c: String) -> [VaultRow] {
            gen.filter { $0.collection == c }.map { g in
                VaultRow(vid: VaultID.gen(g.collection, g.id), name: (g.file as NSString).deletingPathExtension,
                         meta: g.w.flatMap { w in g.h.map { "\(w)×\($0)" } }, url: u("/generated/" + g.file))
            }
        }
        func cinRows(_ c: String) -> [VaultRow] {
            cin.filter { $0.collection == c }.map { v in
                VaultRow(vid: VaultID.cin(v.file), name: (v.file as NSString).deletingPathExtension, meta: v.duration.map { "\(Int($0.rounded()))s" }, url: u("/media/cinematic/" + v.file))
            }
        }
        func r2Rows(_ p: String) -> [VaultRow] { (r2[p] ?? []).map { VaultRow(vid: VaultID.r2(p, $0.name), name: $0.name, meta: "imported", r2Key: $0.key) } }
        func files(_ list: [Manifest.File], _ id: (String) -> String) -> [VaultRow] { list.map { VaultRow(vid: id($0.name), name: $0.name, meta: $0.kind, url: u($0.path)) } }
        func labs(_ bucket: String) -> [VaultRow] { m.labs.filter { ($0.bucket ?? "experiences") == bucket }.map { VaultRow(vid: VaultID.lab($0.id), name: $0.name) } }
        let voiced = aff.filter { $0.audio != nil }
        let n = m.archive.count

        var out: [VaultCat] = [
            VaultCat(key: "code", label: "Living Code", subs: [
                VaultSub(key: "living-curves", label: "Living Curves", provenance: "curated live set · pieces.js · feeds the controller",
                         lead: VaultRow(vid: "V-CRV-*", name: "Open the grid, live previews", meta: "\(pieces.filter(\.live).count) pieces", room: .curves),
                         rows: pieceRows { $0.live }),
                VaultSub(key: "curve-archive", label: "Curve Archive", provenance: "hand-authored generative code · pieces.js archive", rows: pieceRows { $0.set == "curve-archive" }),
                VaultSub(key: "jarvis-crafted", label: "Jarvis-Crafted", provenance: "chat-crafted via VJ Coder · pieces-ai.js · vjcoder-auto branch, Accept-gated deploy",
                         rows: pieceRows { $0.set == "jarvis-crafted" }),
                VaultSub(key: "wave-two", label: "The Hand, Wave Two", provenance: "S162 hand-study batch · pieces-h2.js · spec: THE HAND, MACHINE SPEC",
                         rows: pieceRows { $0.set == "wave-two" && !$0.live }),
                VaultSub(key: "wave-one", label: "Wave One", provenance: "fleet-authored 2026-06 · gated S116", rows: pieceRows { $0.set == "wave-one" }),
                VaultSub(key: "defiance", label: "Defiance", provenance: "narrative 3D worlds · Babylon.js", rows: m.defiance.map { VaultRow(vid: VaultID.lab($0.id), name: $0.name) }),
                VaultSub(key: "labs-experiences", label: "Labs, Experiences", provenance: "polished pieces · app/lab routes", rows: labs("experiences")),
                VaultSub(key: "labs-tools", label: "Labs, Tools", provenance: "dev diagnostics and proofs-of-concept · app/lab routes", rows: labs("tools")),
                VaultSub(key: "labs-private", label: "Labs, Private", provenance: "founder-only mocks and experiments · app/lab routes",
                         rows: [VaultRow(vid: VaultID.lab("manifestation-preview"), name: "The Preview, his private board", meta: "private · S116")] + labs("private")),
            ]),
            VaultCat(key: "stills", label: "Stills", subs: [
                VaultSub(key: "the-hand", label: "The Hand", provenance: "S162 hand-study batch · pl-hand-* pieces rendered to stills", rows: genRows("hand")),
                VaultSub(key: "seal-marks", label: "Seal Marks", provenance: "pl-render seal templates · cy collection",
                         lead: VaultRow(vid: "V-GEN-cy-*", name: "Open the gallery", meta: "\(gen.isEmpty ? (m.generated?.count ?? 0) : gen.count) stills", room: .generated),
                         rows: genRows("cy")),
                VaultSub(key: "renders", label: "Renders v2 to v4", provenance: "pl-render template batches", rows: genRows("v2") + genRows("v3") + genRows("v4")),
                VaultSub(key: "touchdesigner", label: "TouchDesigner", provenance: "TouchDesigner exports · td-*", rows: genRows("td")),
                VaultSub(key: "w1-stills", label: "Wave One Stills", provenance: "fleet renders of Wave One pieces", rows: genRows("w1")),
                VaultSub(key: "r2-images", label: "Filed by hand", provenance: "pl-vault bucket · images/ + pieces/", rows: r2Rows("images") + r2Rows("pieces")),
            ]),
            VaultCat(key: "video", label: "Video", subs: [
                VaultSub(key: "cinematic", label: "Cinematic, Scored", provenance: "Remotion / capture pipeline · scored pieces",
                         lead: VaultRow(vid: "V-CIN-*", name: "Open the reel", meta: "\(cin.isEmpty ? (m.cinematic?.count ?? 0) : cin.count) videos", room: .cinematic),
                         rows: cinRows("cinematic")),
                VaultSub(key: "timelapses", label: "Founder Timelapses", provenance: "Procreate / studio recordings", rows: cinRows("timelapse")),
                VaultSub(key: "r2-video", label: "Filed by hand", provenance: "pl-vault bucket · video/", rows: r2Rows("video")),
            ]),
            VaultCat(key: "3d", label: "3D and Motion", subs: [
                VaultSub(key: "figures", label: "Figures", provenance: "GlyphGuy v4 · him + her · animations baked into glyphguy-clips.glb",
                         rows: (m.figures ?? []).flatMap { f in
                             [VaultRow(vid: VaultID.model(f.name + ".glb"), name: f.name, meta: "\(f.clips.count) animations", url: u(f.path))]
                                 + f.clips.map { VaultRow(vid: VaultID.model("\(f.figure)-\($0)"), name: "\(f.name) · \($0)", meta: "baked clip") }
                         }),
                VaultSub(key: "models", label: "Models", provenance: "GLB · Draco-compressed (+ his FBX props)", rows: files(m.models, VaultID.model)),
                VaultSub(key: "r2-3d", label: "Filed by hand", provenance: "pl-vault bucket · models/ + animations/", rows: r2Rows("models") + r2Rows("animations")),
            ]),
            VaultCat(key: "vector", label: "Vector", subs: [
                VaultSub(key: "curve-svg", label: "Curve Compositions", provenance: "hand-drawn SVG curves · the source geometry", rows: files(m.curves, VaultID.svg) + r2Rows("curves")),
            ]),
            VaultCat(key: "audio", label: "Audio", subs: [
                VaultSub(key: "audio-files", label: "Audio", provenance: "scores + captures · public/audio + R2", rows: files(m.audio, VaultID.audio) + r2Rows("audio")),
                VaultSub(key: "affirmations", label: "Affirmations, Founder Voice", provenance: "house-AI-drafted, founder-voice audio · pl-manifestation-practice R2",
                         lead: aff.isEmpty ? nil : VaultRow(vid: "V-AUD-AFF-*", name: "The Affirmation Library", meta: "\(aff.count) lines · \(voiced.count) voiced"),
                         rows: voiced.map { VaultRow(vid: "V-AUD-AFF-" + String(format: "%03ld", $0.id), name: $0.text, meta: "wav", url: URL(string: Self.affirmations + ($0.audio ?? ""))) }),
            ]),
            VaultCat(key: "type", label: "Type", subs: [
                VaultSub(key: "fonts", label: "Brand Fonts", provenance: "founder-drawn typefaces · PLHand + Curved", rows: files(m.fonts, VaultID.font) + r2Rows("fonts")),
            ]),
            VaultCat(key: "works", label: "The Complete Works", subs: [
                VaultSub(key: "archive", label: "The Archive", provenance: "the seven-year practice · R2 pl-archive",
                         rows: [VaultRow(vid: "PL-0001…", name: "The Archive", meta: "\(n.formatted()) works · PL-0001…PL-" + String(format: "%04ld", n), room: .archive)]),
            ]),
            VaultCat(key: "ui", label: "UI Components", subs: [
                VaultSub(key: "components", label: "House Components", provenance: "reusable UI pieces from the repos · live demos at /components", rows: [
                    VaultRow(vid: VaultID.lab("cmp-electric-border"), name: "ElectricBorder, fractal-noise border", meta: "Canvas2D · S138"),
                    VaultRow(vid: VaultID.lab("cmp-liquid-glass"), name: "Liquid Glass, The Prism shader", meta: "GLSL · S138"),
                    VaultRow(vid: VaultID.lab("cmp-glass-card"), name: "Glass Card, the house glass surface", meta: "CSS"),
                    VaultRow(vid: VaultID.lab("cmp-plhand"), name: "PLHand, founder handwriting", meta: "font · founder-drawn"),
                    VaultRow(vid: VaultID.lab("cmp-curved"), name: "Curvedabc, curved letterforms", meta: "font · founder-drawn"),
                ]),
            ]),
            VaultCat(key: "tools", label: "Provenance and Tools", subs: [
                VaultSub(key: "registry", label: "Registry", provenance: "where every piece comes from · how IDs are formed",
                         rows: [VaultRow(vid: "V-REG", name: "Provenance Registry", meta: "one entry per shelf", room: .tools)]
                             + m.guides.map { VaultRow(vid: VaultID.lab($0.id), name: $0.name, room: .tools) }),
            ]),
            VaultCat(key: "r1", label: "Rabbit R1", subs: [
                VaultSub(key: "r1-creations", label: "R1 Creations", provenance: "Rabbit R1 creations SDK · install via QR, scan with the device camera",
                         rows: Self.r1.map { VaultRow(vid: VaultID.r1($0.0), name: $0.1, img: URL(string: "\(Self.r1Base)/qr/\($0.0).png"), url: URL(string: "\(Self.r1Base)/\($0.0)/")) }),
            ]),
        ]
        // any R2 prefix not mapped above gets its own shelf: nothing hides
        let known: Set = ["images", "pieces", "video", "models", "animations", "curves", "audio", "fonts"]
        let stray = r2.keys.filter { !known.contains($0) && !(r2[$0] ?? []).isEmpty }.sorted()
        if !stray.isEmpty {
            out.append(VaultCat(key: "r2-other", label: "R2, Other Imports", subs: stray.map {
                VaultSub(key: "r2-\($0)", label: $0.replacingOccurrences(of: "[-_]", with: " ", options: .regularExpression).capitalized, provenance: "pl-vault bucket · \($0)/", rows: r2Rows($0))
            }))
        }
        return out.map { VaultCat(key: $0.key, label: $0.label, subs: $0.subs.filter { $0.count > 0 }) }.filter { !$0.subs.isEmpty }
    }
}

// MARK: - The room

struct VaultRoom: View {
    let model: AppModel
    @State private var data = LibraryData.shared
    @State private var search = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Loaded(load: {
            #if DEBUG
            VaultID.selfCheck()
            #endif
            let s = try await VaultSources.load(model: model)
            return (s.tree(base: LibraryData.shared.base(model)), s.problems, s.m.archive.count)
        }) { loaded, _ in
            let cats = loaded.0
            let problems = loaded.1
            let works = loaded.2
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GalleryHeading(eyebrow: "The Gallery", title: "The Vault")
                    Text("Everything in one place. Open a folder, open a file. What gets made comes home here; what's here feeds the controller.")
                        .font(.system(size: 13.5, weight: .light)).foregroundStyle(PLG.dim(scheme)).plReading()
                    ForEach(problems, id: \.self) { ResultLine(text: $0) }
                    if search.isEmpty {
                        NavigationLink { LabsRoom(model: model) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Labs").gEyebrow(10).foregroundStyle(PLG.goldDim(scheme))
                                Text("Instruments and experiments").gTitle(20, relativeTo: .title3).foregroundStyle(PLG.ink(scheme))
                                Text("The VJ, the ribbon lab, the curve toys.").font(.system(size: 13, weight: .light)).foregroundStyle(PLG.dim(scheme))
                            }
                            .gCard(padding: 16, radius: 10)
                        }
                        .buttonStyle(.plain)
                        hub
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                            ForEach(cats) { c in
                                NavigationLink { VaultCategoryView(model: model, cat: c) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(c.label).gEyebrow(11.5).foregroundStyle(PLG.ink(scheme)).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                        Text((c.key == "works" ? works : c.count).formatted()).font(.system(size: 18, design: .monospaced)).foregroundStyle(PLG.goldDim(scheme))
                                    }
                                    .frame(minHeight: 60, alignment: .topLeading)
                                    .gCard(padding: 14, radius: 14)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(c.label), \(c.count)")
                            }
                        }
                        holds
                        footer(works)
                    } else {
                        let hits = VaultCategoryView.filter(cats, search)
                        if hits.isEmpty {
                            ContentUnavailableView("Nothing holds that name.", systemImage: "scribble", description: Text("Try a shorter word, or an ID."))
                        }
                        ForEach(hits) { VaultShelves(model: model, cat: $0) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .gScreen()
        .navigationTitle("The Vault").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Name or ID (V-GEN-cy-1280)")
    }

    /// VaultHub.tsx: six cards, counts by kind from the index (a count not read shows a dash, never a made-up zero).
    private var hub: some View {
        let byClass = Dictionary(grouping: data.items, by: \.class).mapValues(\.count)
        func n(_ k: String) -> String { data.items.isEmpty ? "—" : (byClass[k] ?? 0).formatted() }
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                tile("Generated", n("still"), "stills · seven collections", .generated, word: false)
                tile("Cinematic", n("cinematic"), "scored and timelapse", .cinematic, word: false)
                tile("Archive", n("archive-work"), "the complete works", .archive, word: false)
                tile("Curves", "LIVE", "the living set", .curves, word: true)
                tile("Forge", "OPEN", "shader studio", .forge, word: true)
                tile("Tools", "REG", "provenance registry", .tools, word: true)
            }
            Text("Tiles count by kind: Generated is rendered stills, Cinematic is video, Archive is the drawn work. The folders below count files where they sit, so the two will not match.")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(PLG.dim(scheme))
        }
    }

    private func tile(_ kind: String, _ big: String, _ line: String, _ room: GalleryRoom, word: Bool) -> some View {
        NavigationLink { room.view(model) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(kind).font(.system(size: 11, design: .monospaced)).textCase(.uppercase).tracking(1.4).foregroundStyle(PLG.dim(scheme))
                Text(big).font(.system(size: word ? 21 : 24, design: .serif)).tracking(word ? 2 : 0).monospacedDigit()
                    .foregroundStyle(word ? PLG.gold : PLG.ink(scheme))
                Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(PLG.dim(scheme)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(minHeight: 44)
            .gCard(padding: 12, radius: 14)
            .overlay(alignment: .top) { Rectangle().fill(word ? PLG.gold : PLG.gold.opacity(0.18)).frame(height: 2).padding(.horizontal, 10) }
        }
        .buttonStyle(.plain)
    }

    /// What the index holds, by class (the app's own count, kept from the earlier vault room).
    @ViewBuilder private var holds: some View {
        let byClass = Dictionary(grouping: data.items, by: \.class).mapValues(\.count)
        if !byClass.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                GalleryHeader(text: "What the gallery holds")
                ForEach(byClass.keys.sorted(), id: \.self) { k in
                    HStack { Text(k).font(.system(size: 13)); Spacer(); Text((byClass[k] ?? 0).formatted()).font(.system(size: 12, design: .monospaced)) }
                        .foregroundStyle(PLG.dim(scheme)).frame(minHeight: 28)
                }
            }
            .gCard(padding: 14, radius: 14)
        }
    }

    /// The page's footer links: Archive, Tools, Source.
    private func footer(_ works: Int) -> some View {
        VStack(spacing: 10) {
            foot("Archive", "\(works.formatted()) pieces, the complete works", .archive)
            foot("Tools", "Languages, services, folder map", .tools)
            foot("Source", "Piece implementations for model use", .tools)
        }
        .padding(.top, 14)
    }

    private func foot(_ label: String, _ sub: String, _ room: GalleryRoom) -> some View {
        NavigationLink { room.view(model) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).gEyebrow(10).foregroundStyle(PLG.goldDim(scheme))
                Text(sub).font(.system(size: 13, weight: .light)).foregroundStyle(PLG.dim(scheme))
            }
            .gCard(padding: 14, radius: 10)
        }
        .buttonStyle(.plain)
    }
}

/// One category, every shelf open: VaultExplorer's entered section.
struct VaultCategoryView: View {
    let model: AppModel
    let cat: VaultCat
    @State private var search = ""

    var body: some View {
        ScrollView {
            let shown = Self.filter([cat], search)
            VStack(alignment: .leading, spacing: 12) {
                if shown.isEmpty { ContentUnavailableView("Nothing holds that name.", systemImage: "scribble", description: Text("Try a shorter word, or an ID.")) }
                ForEach(shown) { VaultShelves(model: model, cat: $0) }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .gScreen()
        .navigationTitle(cat.label).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Name or ID")
    }

    /// The web's search: name, meta or ID, case-insensitive; a lead row stays only when it matches.
    static func filter(_ cats: [VaultCat], _ q: String) -> [VaultCat] {
        let n = q.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return cats }
        func hit(_ r: VaultRow) -> Bool { r.name.localizedCaseInsensitiveContains(n) || r.vid.localizedCaseInsensitiveContains(n) || (r.meta ?? "").localizedCaseInsensitiveContains(n) }
        return cats.map { c in
            VaultCat(key: c.key, label: c.label, subs: c.subs.map { s in
                VaultSub(key: s.key, label: s.label, provenance: s.provenance, lead: s.lead.flatMap { hit($0) ? $0 : nil }, rows: s.rows.filter(hit))
            }.filter { $0.count > 0 })
        }.filter { !$0.subs.isEmpty }
    }
}

/// A category card with its shelves: the label and count, the provenance line (opens its Registry entry), the rows.
struct VaultShelves: View {
    let model: AppModel
    let cat: VaultCat
    @State private var all: Set<String> = []
    @State private var copied: String?
    @State private var openFile: VaultRow?
    @Environment(\.colorScheme) private var scheme
    private let page = 80   // the web's PAGE: rows shown per shelf before "Show all"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(cat.label).gEyebrow(12).foregroundStyle(PLG.ink(scheme))
                Spacer()
                Text(cat.count.formatted()).font(.system(size: 11, design: .monospaced)).foregroundStyle(PLG.dim(scheme))
            }
            .frame(minHeight: 48)
            ForEach(cat.subs) { sub in
                Divider().overlay(PLG.line(scheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(sub.label) · \(sub.count)").font(.system(size: 11, design: .monospaced)).textCase(.uppercase).tracking(1.6).foregroundStyle(PLG.goldDim(scheme))
                    NavigationLink { ToolsRoom(model: model, focus: "reg-" + sub.key) } label: {
                        Text(sub.provenance + " →").font(.system(size: 11)).foregroundStyle(PLG.dim(scheme)).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens its Registry entry")
                }
                .padding(.top, 8)
                if let lead = sub.lead { row(lead) }
                let rows = all.contains(sub.key) ? sub.rows : Array(sub.rows.prefix(page))
                LazyVStack(spacing: 0) { ForEach(rows) { row($0) } }
                if rows.count < sub.rows.count {
                    Button("Show all \(sub.rows.count)") { all.insert(sub.key) }
                        .font(.system(size: 11)).textCase(.uppercase).tracking(2).foregroundStyle(PLG.goldDim(scheme))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .gCard(padding: 14, radius: 14)
        .sensoryFeedback(PLHaptic.success, trigger: copied) { _, new in new != nil }
        .navigationDestination(item: $openFile) { f in VaultFileView(model: model, key: f.r2Key ?? "", name: f.name) }
    }

    @ViewBuilder private func row(_ r: VaultRow) -> some View {
        if let room = r.room {
            NavigationLink { room.view(model) } label: { rowBody(r, chip: false) }.buttonStyle(.plain)
        } else {
            Button { copy(r.vid) } label: { rowBody(r, chip: true) }
                .buttonStyle(.plain)
                .accessibilityLabel("\(r.name), \(r.vid)")
                .accessibilityHint("Copies the Vault ID")
                .contextMenu {
                    Button("Copy the ID", systemImage: "doc.on.doc") { copy(r.vid) }
                    if r.r2Key != nil { Button("Open the file", systemImage: "doc.viewfinder") { openFile = r } }
                    if let u = r.url { ShareLink(item: u) { Label("Share the file link", systemImage: "square.and.arrow.up") } }
                }
        }
    }

    private func rowBody(_ r: VaultRow, chip: Bool) -> some View {
        HStack(spacing: 10) {
            if let img = r.img {
                AsyncImage(url: img) { $0.resizable().scaledToFit() } placeholder: { Color.white }
                    .frame(width: 36, height: 36).padding(2).background(.white).clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text(r.name).font(.system(size: 16, design: .serif).italic()).foregroundStyle(PLG.ink(scheme)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if let m = r.meta { Text(m).font(.system(size: 11)).tracking(1).foregroundStyle(PLG.dim(scheme)).lineLimit(1) }
            if chip {
                let on = copied == r.vid
                Text(on ? "copied" : r.vid).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(on ? PLG.teal : PLG.goldDim(scheme))
                    .padding(.horizontal, 8).frame(minHeight: 28)
                    .background { RoundedRectangle(cornerRadius: 5).fill((on ? PLG.teal : PLG.goldDim(scheme)).opacity(0.08)) }
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder((on ? PLG.teal : PLG.goldDim(scheme)).opacity(0.35), lineWidth: 1) }
                    .frame(maxWidth: 150, alignment: .trailing)
            } else {
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(PLG.goldDim(scheme))
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func copy(_ vid: String) {
        UIPasteboard.general.string = vid
        copied = vid
        Task { try? await Task.sleep(for: .milliseconds(1300)); if copied == vid { copied = nil } }
    }
}
