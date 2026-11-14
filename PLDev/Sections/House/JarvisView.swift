import AVFoundation
import SwiftUI

/// pl-os `/jarvis`: the local board, wearing the Claude Code terminal. Port of `components/JarvisRoom.tsx` + `lib/jarvis-api.ts`.
/// The board is reached at the config's "board" origin (Tailscale, with its key from the config, exactly as pl-os's own proxy
/// does), so the room has two honest states: present and asleep. Conductor (the whole fleet in one chat) is the default brain;
/// the others stream plain text. Voice in is Apple's on-device speech; voice out is the board's own `/api/tts` (never his voice).
/// Left out, with its reason in LANES-house.md: the OpenCode runner (it needs the board's action token, which the phone does not hold).
@MainActor @Observable final class JarvisModel {
    struct Msg: Identifiable { let id = UUID(); let you: Bool; var text: String }
    struct Flow: Decodable, Identifiable {
        let id: String; let label: String; let schedule: String?; let brain: String?
        let runs: Int?; let last_rel: String?; let last_saved: String?
    }
    struct FlowsReply: Decodable { let flows: [Flow]? }
    struct Turn: Decodable { let at: String?; let brain: String?; let you: String?; let jarvis: String? }
    struct ConvReply: Decodable { let turns: [Turn]? }
    struct ConfigReply: Decodable { let name: String?; let tagline: String?; let brains: [String: String]? }

    var online: Bool?
    var brains: [(key: String, label: String)] = []
    var brain = "conductor"
    var tagline = "Here. What do you need?"
    var messages: [Msg] = []
    var busy = false
    var started = Date()
    var speak = false
    var recording = false
    var heard = ""
    var recent: [Turn] = []
    var flows: [Flow] = []
    var note: String?
    var report: (title: String, text: String)?

    private let dictation = CaptureDictation()
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?
    let model: AppModel
    init(model: AppModel) { self.model = model }

    private func get<T: Decodable>(_ path: String, _ t: T.Type, timeout: TimeInterval = 8) async -> T? {
        guard let http = model.http, let d = try? await http.send(RequestPlan(origin: "board", path: path), timeout: timeout, cache: false) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    func boot() async {
        guard model.http != nil else { online = false; return }
        guard let cfg = await get("api/config", ConfigReply.self, timeout: 4) else { online = false; return }
        online = true
        let order = ["npu", "fast", "ollama", "vjcoder", "drafter", "council", "oracle"]
        let all = cfg.brains ?? [:]
        let keys = order.filter { all[$0] != nil } + all.keys.filter { !order.contains($0) }.sorted()
        brains = [("conductor", "\u{25C6} Conductor")] + keys.map { ($0, all[$0] ?? $0) }
        if let t = cfg.tagline { tagline = t }
        await refresh()
    }

    func refresh() async {
        async let c = get("api/conversation", ConvReply.self)
        async let f = get("api/flows", FlowsReply.self)
        recent = Array((await c)?.turns?.reversed().prefix(5) ?? [])
        flows = (await f)?.flows ?? []
    }

    func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        let history = messages.map { ["role": $0.you ? "user" : "assistant", "content": $0.text] }
        messages.append(Msg(you: true, text: q)); messages.append(Msg(you: false, text: ""))
        busy = true; started = Date()
        task = Task {
            defer { busy = false }
            do {
                if brain == "conductor" {
                    let d = try await model.http!.send(RequestPlan(origin: "board", method: "POST", path: "api/conductor", headers: ["content-type": "application/json"],
                                                                   body: try JSONSerialization.data(withJSONObject: ["message": q])), idempotent: false, timeout: 120, cache: false)
                    let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
                    let r = o["result"] as? [String: Any]
                    let reply = "\u{2192} \((o["label"] as? String) ?? "V.A.U.L.T.") \u{00B7} \((o["why"] as? String) ?? "")\n\n\((r?["text"] as? String) ?? "")"
                    messages[messages.count - 1].text = reply
                    await say((r?["text"] as? String) ?? "")
                } else {
                    var acc = ""
                    for try await ch in try await stream(q, history) { acc.append(ch); messages[messages.count - 1].text = acc }
                    await say(acc)
                }
                await refresh()
            } catch is CancellationError {
                if messages.last?.text.isEmpty == true { messages.removeLast() }
            } catch {
                online = false
                messages[messages.count - 1].text = "The desk is asleep: your machine is off, or this phone is off Tailscale."
            }
        }
    }

    func stop() { task?.cancel() }

    private func stream(_ q: String, _ history: [[String: String]]) async throws -> AsyncCharacterSequence<URLSession.AsyncBytes> {
        guard let cfg = model.config else { throw Console.Problem.notSetUp }
        let body = try JSONSerialization.data(withJSONObject: ["prompt": q, "brain": brain, "history": history, "stream": true] as [String: Any])
        let planned = try RequestPlan(origin: "board", method: "POST", path: "api/ask", headers: ["content-type": "application/json"], body: body).urlRequests(config: cfg)
        guard let p = planned.first else { throw Console.Problem.notSetUp }
        var req = URLRequest(url: p.url, timeoutInterval: 120)
        req.httpMethod = p.method; req.httpBody = p.body
        for (k, v) in p.headers { req.setValue(v, forHTTPHeaderField: k) }
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return bytes.characters
    }

    // MARK: voice

    func toggleMic() async {
        if recording { dictation.stop(); recording = false; return }
        heard = ""
        let why = await dictation.start(onText: { [weak self] t in Task { @MainActor in self?.heard = t } },
                                        onEnd: { [weak self] in Task { @MainActor in
                                            guard let self, self.recording else { return }
                                            self.recording = false
                                            let t = self.heard; self.heard = ""
                                            self.send(t)
                                        } })
        if let why { note = why } else { recording = true }
    }

    private func say(_ text: String) async {
        guard speak, !text.isEmpty, let http = model.http else { return }
        guard let d = try? await http.send(RequestPlan(origin: "board", method: "POST", path: "api/tts", headers: ["content-type": "application/json"],
                                                       body: try JSONSerialization.data(withJSONObject: ["text": String(text.prefix(1500))])), idempotent: false, timeout: 30, cache: false) else { return }
        try? PLAudio.speaking()
        player = try? AVAudioPlayer(data: d)
        player?.play()
    }

    func open(report f: String, title: String) async {
        guard let http = model.http,
              let d = try? await http.send(RequestPlan(origin: "board", path: "api/note", query: ["f": f]), timeout: 15, cache: false),
              let t = String(data: d, encoding: .utf8) else { note = "That report would not open."; return }
        report = (title, t)
    }
}

struct JarvisView: View {
    let model: AppModel
    @State private var j: JarvisModel
    @State private var input = ""
    @State private var stripOpen = false
    @State private var flowsOpen = false
    @FocusState private var focused: Bool

    private let accent = Color(hex: 0xd97757), amber = Color(hex: 0xc8923f), dim = Color(hex: 0x8a8167), ink = Color(hex: 0xe8e2d4)
    private let star = ["\u{273B}", "\u{2722}", "\u{2733}", "\u{2217}", "\u{2738}", "\u{273A}"]
    private let verbs = ["Thinking", "Pondering", "Routing", "Divining", "Channeling", "Conjuring", "Reckoning", "Listening"]

    init(model: AppModel) { self.model = model; _j = State(initialValue: JarvisModel(model: model)) }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            if j.online == false { asleep }
            else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            welcome
                            if j.online == true { brainsBlock; flowsBlock }
                            ForEach(Array(j.messages.enumerated()), id: \.element.id) { i, m in turn(m, last: i == j.messages.count - 1).id(m.id) }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(.horizontal, 14).padding(.top, 8)
                    }
                    .onChange(of: j.messages.last?.text) { proxy.scrollTo("end") }
                    .onChange(of: j.messages.count) { withAnimation { proxy.scrollTo("end") } }
                }
                promptBox
            }
        }
        .font(.system(size: 13, design: .monospaced))
        .foregroundStyle(ink)
        .background(Color(hex: 0x0d0b08).ignoresSafeArea())
        .navigationTitle("Jarvis").navigationBarTitleDisplayMode(.inline).toolbarColorScheme(.dark, for: .navigationBar)
        .task { await j.boot() }
        .sheet(isPresented: Binding(get: { j.report != nil }, set: { if !$0 { j.report = nil } })) { reportSheet }
        .sensoryFeedback(PLHaptic.success, trigger: j.messages.count)
    }

    // MARK: chrome

    private var titleBar: some View {
        HStack {
            Text("\u{273B}").font(.system(size: 14, design: .monospaced)).foregroundStyle(accent)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(j.online == true ? amber : dim).frame(width: 6, height: 6)
                Text(j.online == nil ? "waking" : j.online == true ? "present" : "asleep").font(.system(size: 10, design: .monospaced)).textCase(.uppercase).tracking(1.5)
            }
            .foregroundStyle(j.online == true ? amber : dim).frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12)
    }

    private var asleep: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Jarvis is at your desk.").font(.system(size: 15, design: .monospaced))
            Text("Your machine is off, or this phone is not on Tailscale. Turn Tailscale on, then pull to try again.")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(dim).multilineTextAlignment(.center).padding(.horizontal, 30)
            Button("Try again") { Task { await j.boot() } }.font(.system(size: 12, design: .monospaced)).foregroundStyle(accent).frame(minHeight: 44)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) { Text("\u{273B}").foregroundStyle(accent); Text("Jarvis \u{2014} local fleet terminal") }
            Text(j.tagline).font(.system(size: 12, design: .monospaced)).foregroundStyle(dim)
            (Text("brain: ").foregroundStyle(dim) + Text(j.brains.first { $0.key == j.brain }?.label ?? "\u{25C6} Conductor").foregroundStyle(amber)).font(.system(size: 11, design: .monospaced))
        }
        .padding(12)
        .background(accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(accent.opacity(0.33), lineWidth: 1) }
    }

    private func fold(_ title: String, _ open: Binding<Bool>, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { open.wrappedValue.toggle() } } label: {
                Text("\(open.wrappedValue ? "\u{25BE}" : "\u{25B8}") \(title)").font(.system(size: 10, design: .monospaced)).textCase(.uppercase).tracking(1.5).foregroundStyle(dim).frame(minHeight: 36)
            }
            if open.wrappedValue {
                VStack(alignment: .leading, spacing: 8) { content() }
                    .padding(.leading, 8).overlay(alignment: .leading) { Rectangle().fill(accent.opacity(0.2)).frame(width: 1) }
            }
        }
    }

    private var brainsBlock: some View {
        fold("brains \u{00B7} context", $stripOpen) {
            WrapPills(items: j.brains.map { ($0.key, $0.label) }, selected: j.brain, accent: accent, dim: dim) { j.brain = $0; focused = true }
            ForEach(Array(j.recent.prefix(3).enumerated()), id: \.offset) { _, t in
                Text("~ \(t.you ?? "\u{2014}")").font(.system(size: 11, design: .monospaced)).foregroundStyle(dim).lineLimit(1)
            }
        }
    }

    private var flowsBlock: some View {
        Group {
            if !j.flows.isEmpty {
                fold("flows \u{00B7} reports", $flowsOpen) {
                    ForEach(j.flows) { f in
                        HStack {
                            Text(f.label).foregroundStyle(ink)
                            Spacer(minLength: 8)
                            Text("\(f.runs ?? 0) \u{00B7} \(f.last_rel ?? "")").foregroundStyle(dim)
                            if let saved = f.last_saved {
                                Button("report \u{2197}") { Task { await j.open(report: saved, title: f.label) } }.foregroundStyle(amber).frame(minHeight: 36)
                            }
                        }
                        .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
    }

    // MARK: turns

    @ViewBuilder private func turn(_ m: JarvisModel.Msg, last: Bool) -> some View {
        if m.you {
            HStack(alignment: .firstTextBaseline, spacing: 6) { Text(">").foregroundStyle(accent); Text(m.text).textSelection(.enabled) }
        } else if j.busy && last && m.text.isEmpty {
            TimelineView(.periodic(from: .now, by: 0.12)) { ctx in
                let n = Int(ctx.date.timeIntervalSince(j.started) * 8.3)
                HStack(spacing: 0) {
                    Text(star[n % star.count]).foregroundStyle(accent)
                    Text(" \(verbs[Int(j.started.timeIntervalSince1970) % verbs.count])\u{2026} ")
                    Text("(\(max(0, Int(ctx.date.timeIntervalSince(j.started))))s \u{00B7} tap stop to interrupt)").foregroundStyle(dim)
                }
            }
        } else { jarvisTurn(m.text, live: j.busy && last) }
    }

    /// A reply the Claude Code way: a bullet; a routed reply lifts its "label \u{00B7} why" line into a tool-call header with a branch.
    private func jarvisTurn(_ text: String, live: Bool) -> some View {
        let routed = text.hasPrefix("\u{2192} ")
        var head: String?
        var body = text
        if routed {
            let nl = text.firstIndex(of: "\n")
            head = String(text[..<(nl ?? text.endIndex)].dropFirst(2)).trimmingCharacters(in: .whitespaces)
            body = nl.map { String(text[$0...]).trimmingCharacters(in: .newlines) } ?? ""
        }
        let parts = head?.components(separatedBy: " \u{00B7} ")
        return VStack(alignment: .leading, spacing: 4) {
            if let parts, let first = parts.first {
                HStack(alignment: .firstTextBaseline, spacing: 0) { Text("\u{25CF} ").foregroundStyle(accent); Text(first) }
                if parts.count > 1 { Text("\u{23BF} " + parts.dropFirst().joined(separator: " \u{00B7} ")).foregroundStyle(dim).padding(.leading, 12) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if head == nil { Text("\u{25CF} ").foregroundStyle(accent) }
                Text(body.isEmpty && !live ? " " : body).textSelection(.enabled).padding(.leading, head == nil ? 0 : 12)
                if live { Text("\u{258B}").foregroundStyle(accent) }
            }
            if !live, let code = Self.pieceCode(body) {
                ScrollView(.horizontal) { Text(code).font(.system(size: 11, design: .monospaced)).foregroundStyle(ink).padding(10) }
                    .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .topTrailing) { Button { UIPasteboard.general.string = code; j.note = "Piece code copied." } label: { Image(systemName: "doc.on.doc").padding(8) }.foregroundStyle(dim) }
            }
        }
        .lineSpacing(3)
    }

    /// The code fence a VJ Coder reply carries, when it has one.
    static func pieceCode(_ s: String) -> String? {
        guard let a = s.range(of: "```") else { return nil }
        let rest = s[a.upperBound...]
        guard let b = rest.range(of: "```") else { return nil }
        var code = String(rest[..<b.lowerBound])
        if let nl = code.firstIndex(of: "\n"), code[..<nl].allSatisfy({ $0.isLetter }) { code = String(code[code.index(after: nl)...]) }
        let t = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 40 ? t : nil
    }

    // MARK: prompt

    private var promptBox: some View {
        VStack(spacing: 4) {
            if let n = j.note { Text(n).font(.system(size: 11, design: .monospaced)).foregroundStyle(dim).onTapGesture { j.note = nil } }
            HStack(spacing: 8) {
                Text(">").foregroundStyle(accent)
                TextField(j.recording ? (j.heard.isEmpty ? "Listening\u{2026}" : j.heard) : "Talk to the fleet\u{2026}", text: $input).focused($focused).disabled(j.busy).submitLabel(.send)
                    .onSubmit { let t = input; input = ""; j.send(t) }.tint(accent)
                Button { Task { await j.toggleMic() } } label: { Image(systemName: j.recording ? "record.circle.fill" : "mic").frame(width: 36, height: 44) }
                    .foregroundStyle(j.recording ? accent : dim).accessibilityLabel("Voice input")
                Button { j.speak.toggle() } label: { Image(systemName: j.speak ? "speaker.wave.2.fill" : "speaker.slash").frame(width: 32, height: 44) }
                    .foregroundStyle(j.speak ? amber : dim).opacity(j.speak ? 1 : 0.6).accessibilityLabel("Speak replies aloud")
                if j.busy {
                    Button { j.stop() } label: { Image(systemName: "stop.circle").frame(width: 36, height: 44) }.foregroundStyle(accent).accessibilityLabel("Stop")
                } else {
                    Button { let t = input; input = ""; j.send(t) } label: { Image(systemName: "return").frame(width: 36, height: 44) }
                        .foregroundStyle(accent).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityLabel("Send")
                }
            }
            .padding(.horizontal, 10)
            .background(.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(j.busy ? accent.opacity(0.4) : .white.opacity(0.14), lineWidth: 1) }
            HStack {
                Text("\u{23CE} send \u{00B7} mic voice \u{00B7} speaker speak aloud").foregroundStyle(dim.opacity(0.67))
                Spacer()
                Text(j.busy ? "working\u{2026}" : j.online == nil ? "waking" : "ready").foregroundStyle(dim.opacity(0.67))
            }.font(.system(size: 10, design: .monospaced)).padding(.horizontal, 4)
        }
        .padding(.horizontal, 12).padding(.bottom, 6).padding(.top, 6)
    }

    private var reportSheet: some View {
        NavigationStack {
            ScrollView {
                let (title, text) = j.report ?? ("", "")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(Self.reportLines(text).enumerated()), id: \.offset) { _, l in
                        if let s = try? AttributedString(markdown: l.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                            Text(s).font(l.head ? .headline : .body).foregroundStyle(l.head ? PLOS.gold : .primary).plReading().textSelection(.enabled)
                        } else { Text(l.text) }
                    }
                }
                .padding(18)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { j.report = nil } } }
        }
    }

    /// A flow report's markdown without its front matter, one block per paragraph.
    static func reportLines(_ text: String) -> [(text: String, head: Bool)] {
        var t = text.replacingOccurrences(of: "\r\n", with: "\n")
        if t.hasPrefix("---"), let e = t.range(of: "\n---", range: t.index(t.startIndex, offsetBy: 3)..<t.endIndex) { t = String(t[e.upperBound...]) }
        return t.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map { p in
            p.hasPrefix("#") ? (p.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces), true) : (p, false)
        }
    }
}

/// The brain pills (the page's wrapped row of bordered buttons).
private struct WrapPills: View {
    let items: [(String, String)]
    let selected: String
    let accent: Color
    let dim: Color
    let pick: (String) -> Void
    var body: some View {
        JarvisFlowRows {
            ForEach(items, id: \.0) { k, label in
                Button { pick(k) } label: {
                    Text(label).font(.system(size: 11, design: .monospaced)).foregroundStyle(selected == k ? accent : dim)
                        .padding(.horizontal, 8).padding(.vertical, 7)
                        .background(selected == k ? accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(selected == k ? accent : .white.opacity(0.12), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct JarvisFlowRows: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, h: CGFloat = 0
        for s in subviews { let z = s.sizeThatFits(.unspecified); if x + z.width > w, x > 0 { x = 0; y += h + 6; h = 0 }; x += z.width + 6; h = max(h, z.height) }
        return CGSize(width: w, height: y + h)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, h: CGFloat = 0
        for s in subviews { let z = s.sizeThatFits(.unspecified); if x + z.width > b.maxX, x > b.minX { x = b.minX; y += h + 6; h = 0 }; s.place(at: CGPoint(x: x, y: y), proposal: .unspecified); x += z.width + 6; h = max(h, z.height) }
    }
}
