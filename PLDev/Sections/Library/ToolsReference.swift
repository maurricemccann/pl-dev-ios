import SwiftUI

// The reference text of pl-curves-gallery app/tools/page.tsx + ToolsClient.tsx (the Registry, languages, tools, folder map) and
// app/source/page.tsx (the API reference), copied as the pages have it, em dashes turned to commas (S350·3b7f). Left out: the
// "Machine & Device Map" block (machine paths and the dead D: drive; not in the audit's row). The web pages hold these as written
// text, so this does too; when a page changes, this file changes with it.

enum ToolsReference {
    struct Reg: Identifiable { let key, name, source, ids, request: String; var id: String { key } }
    struct Line: Identifiable { let name, body: String; var example: String? = nil; var id: String { name } }

    static let registry: [Reg] = [
        Reg(key: "living-curves", name: "Living Curves",
            source: "Hand-authored generative code in public/scripts/pieces.js (this repo). The curated WORDSIGNS + canon set runs live on /curves and feeds the /live controller.",
            ids: "V-CRV-<piece id>, e.g. V-CRV-nexus. The piece id is the pieces.js id, unchanged.",
            request: "Hand a session V-CRV-* IDs + direction (\"remix V-CRV-nexus with slower drift\"). New pieces enter through pieces.js and validate via scripts/validate-pieces.mjs."),
        Reg(key: "curve-archive", name: "Curve Archive",
            source: "Hand-authored pieces retired from the live set, same pieces.js, archive partition (window.PL_ARCHIVE).",
            ids: "V-CRV-<piece id>, same law as Living Curves.",
            request: "Same door: cite the V-CRV ID; a session can revive, remix, or re-render from the archived code."),
        Reg(key: "wave-one", name: "Wave One",
            source: "Fleet-authored 2026-06 via the scripts/w1/ workflow, gated S116. Code ships in public/scripts/pieces-w1.js.",
            ids: "V-W1-<id>, the w1- prefix is the namespace, so w1-noise-c03-04 becomes V-W1-noise-c03-04.",
            request: "Point a session at scripts/w1/ with V-W1-* IDs; new waves follow the same fleet workflow and gate."),
        Reg(key: "defiance", name: "Defiance",
            source: "Narrative 3D worlds (Babylon.js) built by hand in app/defiance/*, The Haul, The Weight.",
            ids: "V-LAB-<route id>, route-derived, e.g. V-LAB-the-haul.",
            request: "These are worlds, not batches. Cite the ID and describe the scene change; work lands in app/defiance/<id>/."),
        Reg(key: "labs", name: "Labs",
            source: "Experiments under app/lab/* (one route per lab), plus AR Curves and the Preview board.",
            ids: "V-LAB-<dir name>, e.g. V-LAB-ar, V-LAB-heart-3d.",
            request: "Cite the V-LAB ID; new labs are new app/lab/<id>/page.tsx routes, auto-picked-up by the vault build."),
        Reg(key: "seal-marks", name: "Seal Marks (cy)",
            source: "pl-render seal templates, the cy collection of brand marks, rendered to public/generated/.",
            ids: "V-GEN-cy-<id>, e.g. V-GEN-cy-1280. The numeric id is the render batch id from generated/manifest.json.",
            request: "The founder's handle: give a session V-GEN-cy-* IDs + instructions (\"take V-GEN-cy-1280 and make variations\"). New renders append to generated/manifest.json."),
        Reg(key: "renders", name: "Renders v2 to v4",
            source: "pl-render template batches (centered / edge / later templates), collections v2, v3, v4.",
            ids: "V-GEN-<collection>-<id>, e.g. V-GEN-v2-0105.",
            request: "Same law as Seal Marks: cite V-GEN-v2-* / v3 / v4 IDs against the matching template batch."),
        Reg(key: "touchdesigner", name: "TouchDesigner",
            source: "TouchDesigner exports (td-*.webp), imported into public/generated/ under collection td.",
            ids: "V-TD-<id>, e.g. V-TD-0880.",
            request: "TD stills are source material; cite V-TD-* IDs for crops, recolors, or motion studies built on them."),
        Reg(key: "w1-stills", name: "Wave One Stills",
            source: "Fleet renders of the Wave One curve pieces, stills of running code, collection w1.",
            ids: "V-GEN-w1-<id>, the piece's own w1- prefix is stripped: w1-bezier-c03-01 → V-GEN-w1-bezier-c03-01.",
            request: "Cite the still ID for image work, or its sibling V-W1-* piece ID to regenerate from the living code."),
        Reg(key: "r2-images", name: "Filed by hand, Stills",
            source: "Live pl-vault R2 bucket, images/ and pieces/ prefixes. Appear here the moment they land in R2, no rebuild.",
            ids: "V-R2-<prefix>-<file slug>, e.g. V-R2-images-some-import.",
            request: "Drop files in the bucket to shelve them; cite the V-R2 ID to promote one into a collection."),
        Reg(key: "cinematic", name: "Cinematic, Scored",
            source: "The Remotion / capture pipeline (scripts/capture-piece.mjs, scripts/export-reel.mjs), scored video pieces in public/cinematic/.",
            ids: "V-CIN-<file slug>, e.g. V-CIN-pl-cloth-flow-v1.",
            request: "Cite a V-CIN ID for re-scores or recuts, or a V-CRV piece ID to capture new footage from the living code."),
        Reg(key: "timelapses", name: "Founder Timelapses",
            source: "Procreate and studio recordings by the founder, process footage, tier: source.",
            ids: "V-CIN-<file slug>, same namespace as the scored work.",
            request: "Source material only. Cite the ID for edits; the recordings themselves are founder-made."),
        Reg(key: "r2-video", name: "Filed by hand, Video", source: "pl-vault R2 bucket, video/ prefix.", ids: "V-R2-video-<file slug>.", request: "Same door as all R2 imports."),
        Reg(key: "rigs", name: "Rigs",
            source: "Mixamo FBX rigs (the GlyphBot family) in public/models/fbx/.",
            ids: "V-MOD-<file slug>, e.g. V-MOD-glyphbot-idle.",
            request: "Cite the rig ID plus the animation you need; new rigs come through Mixamo against the real FBX rig."),
        Reg(key: "models", name: "Models", source: "GLB models (Draco-compressed) in public/models/glb/.", ids: "V-MOD-<file slug>.", request: "Cite the V-MOD ID for scene placement or variants."),
        Reg(key: "r2-3d", name: "R2 3D Imports", source: "pl-vault R2 bucket, models/ and animations/ prefixes.", ids: "V-R2-models-<slug> / V-R2-animations-<slug>.", request: "Same door as all R2 imports."),
        Reg(key: "curve-svg", name: "Curve Compositions",
            source: "Hand-drawn SVG curves in public/curves/, the source geometry the generative pieces read.",
            ids: "V-SVG-<file slug>, e.g. V-SVG-curve-007-final.",
            request: "Cite a V-SVG ID as the geometry for a new piece; new curves enter public/curves/ and the vault build picks them up."),
        Reg(key: "audio-files", name: "Audio",
            source: "Scores and captures in public/audio/ plus the R2 audio/ prefix.",
            ids: "V-AUD-<file slug> / V-R2-audio-<slug>.",
            request: "Cite the audio ID when requesting a scored render or an audio-reactive set."),
        Reg(key: "fonts", name: "Brand Fonts",
            source: "Founder-drawn typefaces (PLHand, PLCurved) in public/fonts/.",
            ids: "V-FNT-<file slug>.",
            request: "Cite the font ID for type-driven pieces. The typefaces themselves are founder-made, used, never redrawn."),
        Reg(key: "archive", name: "The Complete Works",
            source: "The seven-year practice, archived in R2 pl-archive, served at /archive.",
            ids: "PL-0001 and on, canonical catalogue numbers, minted at intake, never renamed.",
            request: "Cite a PL number to build on a work (study, derivative, drop candidate). Designation stays with the founder."),
        Reg(key: "registry", name: "Registry",
            source: "This page. Every Vault shelf header links to its entry here.",
            ids: "The ID law in one line: media-type namespace + name-derived slug, deterministic, stable across rebuilds.",
            request: "Copy any ID from the Vault (tap the row) and hand it to a session with instructions."),
    ]

    static let languagesActive: [Line] = [
        Line(name: "TypeScript", body: "All Next.js pages, components, API routes. Primary language. Strict mode."),
        Line(name: "TSX / JSX", body: "React components throughout. Client and server components."),
        Line(name: "GLSL (Fragment + Vertex Shaders)", body: "Three.js labs: RibbonCurves, WorldGalleryLab, fluid, WebGPU probe. Inline as template literals or .glsl strings. Used for holographic finish, displacement, post-processing."),
        Line(name: "Canvas 2D API", body: "All 251 pieces across five bundles (123 live). inkStroke, fadeToBg, paintBg, flow fields, phyllotaxis, guilloché, kinematic beziers, cloth engine, weave, poster frames."),
        Line(name: "CSS 3D Transforms", body: "/lab/study, door entry, frosted panels. perspective + rotateY for the door swing. No Three.js, pure CSS."),
        Line(name: "SQL (D1 / SQLite)", body: "pl-cron and pl-transmission D1 database. Not used inside pl-curves-gallery directly, but available via CF binding if wired."),
        Line(name: "JavaScript (CJS)", body: "Playwright shot scripts (*.cjs at root). cosmos.cjs, shot.cjs, export.cjs, screenshot and export tooling."),
    ]

    static let languagesAvailable: [Line] = [
        Line(name: "p5.js", body: "Add to package.json: npm i p5 @types/p5. Import inside a useEffect (p5 is browser-only). Use p5.Vector, noise(), beginShape/endShape for sketch-style generative work. Best for rapid iteration on new pieces.",
             example: "new p5((s) => { s.setup = () => {}; s.draw = () => {}; }, canvasRef.current)"),
        Line(name: "WebGPU", body: "Already probed in /lab/webgpu-probe. navigator.gpu is available on Chrome 113+. Use for compute shaders (particle systems, fluid sim at GPU scale). Wire via canvas.getContext(\"webgpu\"). Types already installed: @webgpu/types.",
             example: "const adapter = await navigator.gpu.requestAdapter(); const device = await adapter.requestDevice();"),
        Line(name: "Web Audio API", body: "No install needed, browser native. AudioContext + AnalyserNode → FFT data → drive any generative parameter. Planned for audio-reactive version of Living Curves.",
             example: "const analyser = ctx.createAnalyser(); analyser.getByteFrequencyData(dataArray);"),
        Line(name: "Hydra (Video Synth)", body: "Load via CDN: <Script src=\"https://unpkg.com/hydra-synth\" />. Hydra patches live on a canvas, good for VJ-style feedback loops and texture synthesis. Does not require a build step.",
             example: "osc(4, 0.1, 0.8).rotate(0.3).out()"),
        Line(name: "WebAssembly (WASM)", body: "Compile Rust or C++ to .wasm via wasm-pack or Emscripten. Load with WebAssembly.instantiateStreaming(fetch(\"/module.wasm\")). Put the .wasm file in /public. Use for heavy math (noise fields, SDF raymarching) at near-native speed.",
             example: "const { instance } = await WebAssembly.instantiateStreaming(fetch(\"/noise.wasm\")); instance.exports.perlin(x, y);"),
        Line(name: "Three.js (extended, instancing, compute)", body: "Already installed (three@0.184). Currently used for RibbonCurves and WorldGalleryLab. Unused: InstancedMesh for multiples-engine, WebGPURenderer (Three r165+), TSL (Three Shading Language, TypeScript shader nodes).",
             example: "const mesh = new THREE.InstancedMesh(geo, mat, count); mesh.setMatrixAt(i, matrix);"),
        Line(name: "SVG + Maker.js", body: "npm i makerjs. Converts parametric line-drawing (curves, guilloché) to SVG paths exportable for CNC/laser. The 12 comp SVGs in /public/curves/ are the seed; Maker.js generates new ones programmatically.",
             example: "const model = makerjs.model.mirror(ringModel, true, false); makerjs.exporter.toSVG(model);"),
    ]

    static let toolsActive: [Line] = [
        Line(name: "Cloudflare Workers", body: "Runtime, pl-curves-gallery deploys here via OpenNext"),
        Line(name: "OpenNext (@opennextjs/cloudflare)", body: "Adapter, builds Next.js for the CF Workers runtime. opennextjs-cloudflare build → .open-next/worker.js"),
        Line(name: "Next.js 16", body: "Framework, App Router, server + client components, API routes"),
        Line(name: "Three.js r0.184", body: "WebGL/3D, used in lab/ribbon, lab/room, lab/home"),
        Line(name: "Tailwind CSS v4", body: "Styling utility, PostCSS plugin, no config file needed"),
        Line(name: "Framer Motion", body: "Animation, available, used sparingly (entrance transitions)"),
        Line(name: "Playwright", body: "Screenshot tooling, shot.cjs and variants at repo root for visual iteration; also drives piece capture for video (chrome-hidden solo captures, measured page-load offsets)"),
        Line(name: "Wrangler", body: "CF CLI, wrangler deploy ships the built .open-next output"),
        Line(name: "Remotion", body: "Custom composition (ClothFlow.tsx) drives a curve piece's per-frame zoom from a precomputed audio-energy array. ffmpeg's crop/scale can't animate w/h per frame, only Remotion's useCurrentFrame() can. Rendered via OpenMontage's VideoCompose atelier mode, not raw `npx remotion`."),
        Line(name: "OpenMontage", body: "Agentic video pipeline (C:\\dev\\OpenMontage), stage-director orchestration + tool registry. Its atelier composition_mode is the sanctioned path for a hand-authored Remotion piece; its post-render self-review catches real issues (audio clipping, missing art_direction) automatically. First real output: pl-cloth-flow-v1.mp4."),
        Line(name: "ffmpeg", body: "Frame extraction, spectrogram generation (showspectrumpic, used to verify Piper voice quality objectively rather than by ear), audio trimming, video muxing throughout the cinematic pipeline."),
        Line(name: "Piper TTS", body: "Local, offline text-to-speech (en_US-lessac-high.onnx). Every other voice tier tested showed an audible noise floor via spectrogram regardless of its \"high\"/\"medium\" label. Verify before trusting the tier name."),
        Line(name: "Ollama", body: "Local LLM serving (:11434), used to test wiring ViMax's planning stage to a local model instead of its default paid API."),
    ]

    static let toolsAvailable: [Line] = [
        Line(name: "Cloudflare D1", body: "SQLite at edge, wire by adding a binding in wrangler.jsonc. Use for: piece like counts persisted server-side, usage analytics."),
        Line(name: "Cloudflare KV", body: "Key-value store, fast reads, good for caching generated source docs or piece thumbnails."),
        Line(name: "Cloudflare R2", body: "Object storage, use to serve heavy assets (PNG exports, .wasm modules, video) via assets.psychedluxuries.com CDN."),
        Line(name: "Cloudflare AI Gateway", body: "Already wired in pl-cron. Could proxy CF AI calls from the lab if we add AI-reactive features."),
        Line(name: "canvas-sketch", body: "Generative art framework, loop helpers, MP4/GIF export, print-resolution render. npm i canvas-sketch. Described in RESEARCH.md as the clean path to social video from pieces."),
        Line(name: "Pts.js / Paper.js / Two.js", body: "2D geometry libs, higher-level than raw Canvas 2D. Good for bezier manipulation, path intersection, vector math on curve compositions."),
        Line(name: "regl / OGL", body: "Lightweight WebGL wrappers, less boilerplate than raw WebGL, less overhead than Three.js. Good for shader-heavy pieces that don't need Three's scene graph."),
        Line(name: "Theatre.js", body: "Sequence editor + animation engine, wire for choreographed piece transitions or timed brand reveals."),
    ]

    static let folders = """
    pl-curves-gallery/   two pillars: LIBRARY (the vault) + LIVE (the controller)
    ├── app/
    │   ├── layout.tsx           # Root, fonts, globals, LabNav + BottomTabBar
    │   ├── globals.css          # Brand tokens, Tailwind, @font-face
    │   ├── page.tsx             # Home / lab index
    │   ├── library/page.tsx     # THE VAULT, Obsidian-style file tree of every asset
    │   ├── live/page.tsx        # LIVE, VJ controller (VJEngine)
    │   ├── curves/page.tsx      # Living Curves gallery (36 live, ?solo=<id> for one)
    │   ├── archive/             # the works gallery (+ /archive/space 3D walk)
    │   ├── defiance/the-haul/   # The Haul, Defiance distribution piece (Three.js)
    │   ├── lab/                 # 22 experiments, ground truth is vault-manifest.json,
    │   │                        #   grouped Experiences/Tools/Private in /library's labs section
    │   ├── tools/page.tsx       # This page, tools, languages, folder map
    │   ├── source/page.tsx      # Source library index (+ brand tokens, voice)
    │   └── api/
    │       ├── source/[id]/route.ts   # GET /api/source/:id, piece/lab source JSON
    │       ├── tools/route.ts         # GET /api/tools, this page as JSON
    │       ├── vault-list/route.ts    # GET, live pl-vault R2 listing (grouped by kind)
    │       └── vault/[...key]/route.ts# GET, stream an R2 object (imported assets)
    ├── components/
    │   ├── LabNav.tsx           # Top nav, two pillars: LIBRARY · LIVE
    │   ├── BottomTabBar.tsx     # Mobile nav (hidden on /live)
    │   ├── VaultExplorer.tsx    # The vault file tree (reads vault-manifest + /api/vault-list)
    │   ├── VJEngine.tsx         # LIVE controller, pieces + audio + the WebGL stage
    │   ├── VJDeck.tsx · VJBrowser.tsx  # DJ-deck control surface + piece browser
    │   ├── vj/VJEffects.ts      # WebGL compositor + effect shaders (2-layer + blend)
    │   └── ui.tsx               # Shared design kit (GlassPanel, GoldText, Tag…)
    ├── scripts/
    │   └── build-vault-manifest.mjs  # scans actual files → public/vault-manifest.json,
    │                                  #   labs' single source of truth (home grid + /library)
    ├── public/
    │   ├── fonts/ · curves/curve-comp-01..12.svg
    │   ├── models/fbx/*.fbx · models/glb/heart1.glb   # 3D + Mixamo animations
    │   ├── audio/{fractal.mp4,helium.mp3}
    │   ├── scripts/pieces.js    # + 4 more bundles, 251 pieces, 123 live (window.PL_PIECES)
    │   ├── archive/manifest.json# the works
    │   └── vault-manifest.json  # generated ground-truth index for the vault
    ├── wrangler.jsonc           # CF Worker, ASSETS + VAULT (pl-vault R2) bindings
    └── next.config.ts · package.json · tsconfig.json

    R2 BUCKETS: pl-vault (creative library + imports) · pl-archive (the fine-art works) · pl-assets
    """

    // app/source/page.tsx
    static let sourceIntro = "Every piece and lab experiment has a machine-readable implementation. Use the API to read any of them: id, name, technique tags, full source code. A model can pull a feature from here and transplant it to any part of the site."
    static let usage = """
    # Get the cloth piece implementation
    curl https://pl-curve-library.psychedluxuries.workers.dev/api/source/cloth

    # Get the study lab implementation
    curl https://pl-curve-library.psychedluxuries.workers.dev/api/source/study

    # Get the full tools list
    curl https://pl-curve-library.psychedluxuries.workers.dev/api/tools
    """
    static let forModels = [
        "Fetch /api/tools: understand what's available.",
        "Fetch /api/source/:id: read the full implementation.",
        "Adapt for the target location in pl-headless: match the surrounding code style (TypeScript, App Router, Tailwind v4, brand tokens).",
        "The brand tokens are --obsidian: #0e0c08, --gold: #c9a84c, --ground: #f0ece4.",
        "Voice: declarative, earned certainty. Never the house's banned words (CLAUDE.md, Voice Rules).",
    ]
}

/// The reference blocks: Registry, languages, tools, the folder map, the Source API. One view so the Vault's shelf links scroll to their entry.
struct ToolsReferenceBlocks: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            block("Provenance Registry", "Where every piece comes from, how its ID is formed, and how to request generation against it. Each Vault shelf links here.") {
                ForEach(ToolsReference.registry) { e in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(e.name).font(.system(size: 17, design: .serif).italic()).foregroundStyle(PLG.ink(scheme))
                            Spacer()
                            Text("#reg-\(e.key)").font(.system(size: 11, design: .monospaced)).foregroundStyle(PLG.goldDim(scheme))
                        }
                        labelled("Source.", e.source); labelled("IDs.", e.ids); labelled("Request.", e.request)
                    }
                    .padding(.vertical, 12)
                    .id("reg-" + e.key)
                    Divider().overlay(PLG.line(scheme))
                }
            }
            .id("registry")
            block("Languages, in use", "In use right now") { lines(ToolsReference.languagesActive) }
            block("Languages, available", "Capable, not yet wired. Add any of these on demand.") { lines(ToolsReference.languagesAvailable) }
            block("Tools, in use", nil) { lines(ToolsReference.toolsActive) }
            block("Tools, available", "Configured or installable, not yet wired.") { lines(ToolsReference.toolsAvailable) }
            block("Folder structure", nil) { code(ToolsReference.folders) }

            GalleryHeading(eyebrow: "PL Creative Lab · Source Library", title: "Source").padding(.top, 10).id("source")
            Text(ToolsReference.sourceIntro).font(.system(size: 14, weight: .light)).foregroundStyle(PLG.dim(scheme)).plReading()
            block("Endpoint", nil) {
                Text("GET /api/source/:id").font(.system(size: 13, design: .monospaced)).foregroundStyle(PLG.dim(scheme)).textSelection(.enabled)
                Group {
                    Text("Returns: ") + Text("{ id, name, sub, tags, type, code }").font(.system(size: 12, design: .monospaced)).foregroundColor(PLG.ink(scheme))
                    Text("type").font(.system(size: 12, design: .monospaced)).foregroundColor(PLG.goldDim(scheme)) + Text(" is \"piece\" (Canvas 2D) or \"lab\" (Next.js component).")
                    Text("code").font(.system(size: 12, design: .monospaced)).foregroundColor(PLG.goldDim(scheme)) + Text(" is the full implementation: pieces.js entry for pieces, TSX file for labs.")
                }
                .font(.system(size: 12, weight: .light)).foregroundStyle(PLG.dim(scheme))
            }
            block("Usage", nil) { code(ToolsReference.usage) }
            block("For models", "To implement a feature from this lab on the main site (psychedluxuries.com / pl-headless):") {
                ForEach(Array(ToolsReference.forModels.enumerated()), id: \.offset) { i, t in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1).").font(.system(size: 13, design: .monospaced)).foregroundStyle(PLG.goldDim(scheme))
                        Text(t).font(.system(size: 13, weight: .light)).foregroundStyle(PLG.dim(scheme)).textSelection(.enabled)
                    }
                }
            }
            block("Machine-readable", nil) {
                Text("All of this is also available as JSON at GET /api/tools, for model consumption without rendering the page.")
                    .font(.system(size: 13, weight: .light)).foregroundStyle(PLG.dim(scheme))
            }
        }
    }

    private func block<C: View>(_ title: String, _ sub: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).gEyebrow(11).foregroundStyle(PLG.goldDim(scheme))
            if let sub { Text(sub).font(.system(size: 13)).foregroundStyle(PLG.dim(scheme)) }
            content()
        }
        .gCard(padding: 18, radius: 8)
    }

    private func labelled(_ k: String, _ v: String) -> some View {
        (Text(k + " ").font(.system(size: 13, weight: .medium)).foregroundColor(PLG.ink(scheme)) + Text(v).font(.system(size: 13)).foregroundColor(PLG.dim(scheme)))
            .textSelection(.enabled)
    }

    @ViewBuilder private func lines(_ l: [ToolsReference.Line]) -> some View {
        ForEach(l) { r in
            VStack(alignment: .leading, spacing: 5) {
                Text(r.name).font(.system(size: 15)).foregroundStyle(PLG.ink(scheme))
                Text(r.body).font(.system(size: 13)).foregroundStyle(PLG.dim(scheme)).textSelection(.enabled)
                if let ex = r.example {
                    Text(ex).font(.system(size: 11, design: .monospaced)).foregroundStyle(PLG.dim(scheme)).textSelection(.enabled)
                        .padding(.vertical, 8).padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) { Rectangle().fill(PLG.line(scheme)).frame(width: 2) }
                }
            }
            .padding(.vertical, 10)
            Divider().overlay(PLG.line(scheme))
        }
    }

    /// A code block keeps its lines (a tree wrapped loses its shape): it scrolls sideways inside its card; the page never does.
    private func code(_ s: String) -> some View {
        ScrollView(.horizontal) {
            Text(s).font(.system(size: 11, design: .monospaced)).lineSpacing(5).foregroundStyle(PLG.dim(scheme)).textSelection(.enabled).fixedSize()
        }
    }
}
