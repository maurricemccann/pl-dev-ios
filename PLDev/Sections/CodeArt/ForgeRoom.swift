import CryptoKit
import SwiftUI

// The Forge, native (the twin of /forge): describe a piece, the generator writes it, it runs at once in the same runtime as every
// other piece, edit the code, run it again, copy it. The generator is the gallery's own route; the phone never holds a model key.

struct NativeForgeRoom: View {
    let model: AppModel
    var body: some View { CodeArtGate(model: model) { ForgeBench(model: model) } }
}

private enum ForgeText {
    /// Pins the generator to the piece contract (the same text /forge sends): its base prompt is generic, and without this it writes standalone canvas code that cannot run here.
    static let contract = [
        "Output ONLY one piece({...}) registration and nothing else — no explanation, no markdown, no document.createElement, no your-own canvas.",
        "The harness already supplies the canvas + ctx and calls your make/draw.",
        "Contract: piece({ id:\"unique-id\", name:\"Name\", sub:\"subtitle\", pal: P(g,ink,body,hi), warm: 20, make(w,h){ return {/*state*/}; }, draw(ctx, st, w, h, t){ /* t = frame counter */ } })",
        "st.pal has exactly these 4 fields — g (ground/background), ink, body, hi. Access as st.pal.g / st.pal.ink / st.pal.body / st.pal.hi — never st.pal[0..3] and never st.pal.ground/.background.",
        "Available globals (do not import/define these): inkStroke(ctx, drawFn, {ink, body, hi, w, shadow}), paintBg(ctx,w,h,g), fadeToBg(ctx,w,h,g,alpha), rand(a,b), TWO (=2*PI), P(g,ink,body,hi).",
        "For audio reactivity read window.__VJ_AUDIO = {bass,mid,high,beat} (0..1) inside draw.",
        "Palette: warm gold-on-obsidian house style, e.g. P(\"#0e0c08\",\"#e8dfce\",\"#c9a84c\",\"#7a5c1e\").",
        "For a pure fragment shader instead, use shaderPiece({ id, name, sub, frag }) with uniforms u_time,u_res,u_bass,u_mid,u_high,u_beat,u_gold,u_ink,u_bg.",
    ].joined(separator: " ")

    static let starter = """
    // A curve piece. Edit freely, then Run.
    piece({
      id: 'forge-sketch', name: 'Forge Sketch', sub: 'a place to begin',
      pal: P('#0e0c08', '#e8dfce', '#c9a84c', '#7a5c1e'), warm: 20,
      make(w, h) { return { t: 0 }; },
      draw(ctx, st, w, h, t) {
        fadeToBg(ctx, w, h, st.pal.g, 0.08);
        const cx = w / 2, cy = h / 2, R = Math.min(w, h) * 0.32;
        inkStroke(ctx, () => {
          ctx.beginPath();
          for (let a = 0; a <= TWO; a += 0.02) {
            const r = R * (1 + 0.3 * Math.sin(a * 5 + t * 0.03));
            const x = cx + Math.cos(a) * r, y = cy + Math.sin(a) * r;
            a === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
          }
          ctx.closePath(); ctx.stroke();
        }, { ink: st.pal.ink, body: st.pal.body, hi: st.pal.hi, w: 2 });
      },
    });
    """
}

struct ForgeBench: View {
    let model: AppModel
    @State private var prompt = ""
    @State private var code = ForgeText.starter
    @State private var previewID: String?
    @State private var runs = 0
    @State private var busy = false
    @State private var status: String?
    @State private var problem: String?
    @State private var tick = 0
    @FocusState private var editing: Bool

    var body: some View {
        List {
            Section {
                ZStack {
                    Color.black
                    if let previewID { LivePieceView(pieceID: previewID).id("\(previewID)-\(runs)") }
                    else { ContentUnavailableView("Nothing running", systemImage: "scribble.variable", description: Text("Run the code to see it here.")) }
                }
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if let problem { Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red) }
            }
            Section("Describe it") {
                TextField("A slow gold spiral that pulses on the beat", text: $prompt, axis: .vertical).lineLimit(1...4).focused($editing)
                Button { Task { await generate() } } label: {
                    HStack { Text(busy ? "Writing it" : "Generate"); if busy { Spacer(); PLLoader() } }
                }.disabled(busy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("The code") {
                TextEditor(text: $code)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 240)
                    .scrollContentBackground(.hidden)
                    .focused($editing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                HStack {
                    Button("Run", systemImage: "play.fill") { Task { await run() } }.buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = code; status = "Copied."; tick += 1 }
                    Button("Start over", systemImage: "arrow.counterclockwise", role: .destructive) { code = ForgeText.starter; status = nil }
                }
                .buttonStyle(.bordered)
                if let status { ResultLine(text: status) }
            }
            Section {
                CodeArtSoundMenu(model: model)
            } footer: { Text("With no sound source the preview moves to a gentle signal of its own.") }
        }
        .navigationTitle("Forge")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar { ToolbarItem(placement: .keyboard) { Button("Done") { editing = false } } }
        .plGround()
        .onAppear { if VJAudio.shared.source == .off { VJAudio.shared.setSynthetic(true) } }
        .onDisappear { VJAudio.shared.setSynthetic(false) }
        .task { await run() }
        .sensoryFeedback(PLHaptic.select, trigger: tick)
        .sensoryFeedback(PLHaptic.select, trigger: runs)
    }

    private func run() async {
        editing = false
        let r = await PieceRuntime.shared.run(source: code)
        if let id = r.id { previewID = id; runs += 1; problem = nil; status = "Running." }
        else { problem = r.error ?? "It would not run."; status = nil }
    }

    private func generate() async {
        guard let http = model.http else { status = "Not written. The gallery is not set up."; return }
        busy = true; defer { busy = false }
        struct Out: Decodable { let ok: Bool?; let code: String?; let error: String? }
        var headers = ["content-type": "application/json", "Origin": LibraryData.shared.base(model)]
        var extra: [String: String] = [:]
        if let key = model.config?.key("vault") {
            let token = SHA256.hash(data: Data("pl-lib-unlock:\(key)".utf8)).map { String(format: "%02x", $0) }.joined()
            extra["Cookie"] = "pl_lib=\(token)"
        }
        headers["accept"] = "application/json"
        do {
            let body = try JSONSerialization.data(withJSONObject: ["task": prompt, "context": ForgeText.contract, "code": code])
            let d = try await http.send(RequestPlan(origin: "gallery", method: "POST", path: "api/vj-coder", headers: headers, body: body), idempotent: false, extraHeaders: extra, timeout: 120)
            let o = try JSONDecoder().decode(Out.self, from: d)
            if o.ok == true, let c = o.code { code = c; status = "Written. Running it."; await run() }
            else { status = "Not written. \(o.error ?? "The generator did not answer.")" }
        } catch let e as HTTPClient.Failure where e == .unauthorized {
            status = "Not written. The gallery did not accept this phone for the generator."
        } catch { status = "Not written. The generator did not answer." }
    }
}
