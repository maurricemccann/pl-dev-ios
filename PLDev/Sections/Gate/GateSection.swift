import AppIntents
import SwiftUI
import UserNotifications

/// The Gate (his ask 11-26: "I want all"; the Energy Conversion Box lives here, outside Capture, which "is for other things").
/// Ten tools drawn from the Gateway Guidance Manual and the house's research, in our own words: one breath, the box, patterning,
/// missions, the five questions, the answer inbox, a fair viewing game, the body map, his own count, and the ladder with its record.
/// Everything stays on the phone in one protected file.
@MainActor enum GateSection: PLSection {
    static let manifest = SectionManifest(id: "gate", title: "Gate", symbol: "circle.dotted.circle", needsKeys: [], needsOrigins: [])
    static func makeRoot(model: AppModel) -> AnyView { AnyView(GateView()) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, path.first == "breath" { GateStore.shared.breath = .still }
        return true
    }
    static func refresh(model: AppModel) async -> SectionRefresh {
        GateStore.shared.load()
        let due = GateStore.shared.dueCount
        return SectionRefresh(badge: due > 0 ? due : nil, notify: [])
    }
}

/// "One Breath" for Shortcuts and the Action button: opens the Gate on a single still breath.
struct GateOneBreathIntent: AppIntent {
    static let title: LocalizedStringResource = "One Breath"
    static let description: IntentDescription? = "Opens PL DEV's Gate on one still breath."
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentBridge.whenReady { IntentBridge.open?(.section(id: "gate", path: ["breath"], query: [:])) }
        return .result()
    }
}

// MARK: - the store

enum GateColor: String, Codable, CaseIterable, Identifiable {
    case still, green, red, white, purple
    var id: String { rawValue }
    var title: String { ["Still", "Green", "Red", "White", "Purple"][Self.allCases.firstIndex(of: self) ?? 0] }
    var line: String {
        switch self {
        case .still: "Think ten. Let the body go quiet."
        case .green: "Breathe green in. Push the charge down and out through your feet."
        case .red: "Breathe red in. Picture the act. Open your eyes and do it."
        case .white: "Palms up. White from above into your hands and through you."
        case .purple: "Send purple to the place. Heal, balance. Then see it whole."
        }
    }
    var color: Color {
        switch self {
        case .still: Candle.gold
        case .green: .green
        case .red: .red
        case .white: .white
        case .purple: .purple
        }
    }
}

struct GateBoxItem: Codable, Identifiable { var id = UUID(); var text: String; var at = Date(); var fear = ""; var emotion = ""; var clean = ""; var released: Date? }
struct GatePattern: Codable, Identifiable { var id = UUID(); var text: String; var obstacle: String; var move: String; var at = Date(); var until: Date; var happened: Bool? }
struct GateMission: Codable, Identifiable { var id = UUID(); var day: Bool; var text: String; var at = Date(); var came = "" }
struct GateQuestion: Codable, Identifiable { var id = UUID(); var text: String; var at = Date(); var answer = ""; var thanked: Date? }
struct GateTrial: Codable, Identifiable { var id = UUID(); var at = Date(); var target: String; var choices: [String]; var notes = ""; var picked: String? }

@MainActor @Observable final class GateStore {
    static let shared = GateStore()
    struct Saved: Codable {
        var box: [GateBoxItem] = []; var patterns: [GatePattern] = []; var missions: [GateMission] = []
        var questions: [GateQuestion] = []; var trials: [GateTrial] = []; var count: [String] = Array(repeating: "", count: 10)
    }
    private(set) var saved = Saved()
    private(set) var readable = true
    private var loaded = false
    var breath: GateColor?

    private static var url: URL { URL.applicationSupportDirectory.appending(path: "gate.json") }

    func load() {
        guard !loaded else { return }
        if FileManager.default.fileExists(atPath: Self.url.path) {
            guard let d = try? Data(contentsOf: Self.url), let s = try? JSONDecoder().decode(Saved.self, from: d) else { readable = false; return }
            saved = s
        }
        readable = true; loaded = true
    }

    func change(_ edit: (inout Saved) -> Void) {
        load()
        guard readable else { return }
        edit(&saved)
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: Self.url, options: [.atomic, .completeFileProtection])
    }

    /// Questions still open inside their three days, and sealed patterns whose date has come.
    var dueCount: Int {
        saved.questions.filter { $0.thanked == nil && $0.answer.isEmpty }.count + saved.patterns.filter { $0.happened == nil && $0.until <= .now }.count
    }
}

/// His archive, for the count and the viewing game (public pieces only).
struct GatePiece: Decodable, Identifiable, Hashable {
    let cr: String; let url: String; let thumb: String?; let title: String?; let shareable: Bool?
    var id: String { cr }
    var image: URL? { URL(string: thumb ?? url) }
    static func load() async -> [GatePiece] {
        struct M: Decodable { let pieces: [GatePiece] }
        guard let u = URL(string: "https://assets.psychedluxuries.com/manifest.json"),
              let r = try? await URLSession.shared.data(from: u), let m = try? JSONDecoder().decode(M.self, from: r.0) else { return [] }
        return m.pieces.filter { $0.shareable != false }
    }
}

// MARK: - the screen

struct GateView: View {
    @State private var store = GateStore.shared
    @State private var lab = FrequencyLog()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !store.readable { Text("Unlock the phone to open the Gate.").candleHint() }
                GateLadder(lab: lab)
                GateBreathCard(store: store)
                GateBoxCard(store: store)
                GatePatternCard(store: store)
                GateMissionCard(store: store)
                GateQuestionsCard(store: store)
                GateFiveCard()
                GateViewingCard(store: store)
                GateBodyCard()
                GateCountCard(store: store)
                GateRecordCard(lab: lab)
            }
            .frame(maxWidth: 640).padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: .infinity)
        }
        .background { CandleGround() }
        .preferredColorScheme(.dark)
        .tint(Candle.gold)
        .navigationTitle("Gate")
        .onAppear { store.load(); lab.load() }
        .sheet(item: $store.breath) { c in GateBreathSheet(color: c, rounds: c == .still ? 1 : 3) }
    }
}

// 10. The ladder: where he stands, from the Lab's own record.
private struct GateLadder: View {
    let lab: FrequencyLog
    var body: some View {
        let rungs: [(String, String, Bool)] = [
            ("Awake", "Conscious, everyday", true),
            ("Focus 3", "Breath and the hum, mind and brain together", lab.times(0) >= 1),
            ("Focus 10", "Body asleep, mind awake", lab.solidSinceFall >= 1 || lab.times(1) >= 1),
            ("Focus 12", "Wider. Patterning opens here", lab.patternOpen)]
        return PCard(title: "The ladder", hint: "Each rung holds before the next. Repetition is the advance.") {
            ForEach(rungs.indices.reversed(), id: \.self) { i in
                HStack(spacing: 12) {
                    Image(systemName: rungs[i].2 ? "circle.fill" : "circle").foregroundStyle(Candle.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rungs[i].0).font(Font.pl(size: 15, weight: .medium)).foregroundStyle(Candle.ink.opacity(rungs[i].2 ? 1 : 0.5))
                        Text(rungs[i].1).candleHint()
                    }
                }
                .frame(minHeight: 44, alignment: .leading)
            }
        }
    }
}

// 1. One breath.
private struct GateBreathCard: View {
    let store: GateStore
    var body: some View {
        PCard(title: "One breath", hint: "In Shortcuts, add One Breath to the Action button.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 8) {
                ForEach([GateColor.still, .green, .red, .white], id: \.self) { c in
                    Button(c.title) { store.breath = c }.buttonStyle(CandleGhost())
                }
            }
        }
    }
}

struct GateBreathSheet: View {
    let color: GateColor
    let rounds: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var size: CGFloat = 0.45
    @State private var word = "In"

    var body: some View {
        VStack(spacing: 24) {
            Text(color.line).font(Font.pl(size: 17)).foregroundStyle(Candle.ink).multilineTextAlignment(.center).padding(.horizontal, 24)
            ZStack {
                Circle().fill(color.color.opacity(0.25)).scaleEffect(reduce ? 1 : size).opacity(reduce ? Double(size) : 1)
                Circle().stroke(color.color, lineWidth: 3).scaleEffect(reduce ? 1 : size)
                Text(word).font(Font.pl(size: 18, weight: .semibold)).foregroundStyle(Candle.ink)
            }
            .frame(width: 220, height: 220)
            Button("Done") { dismiss() }.buttonStyle(CandleGhost())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { CandleGround() }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .task {
            for _ in 0..<rounds {
                if !(await step("In", 1, 4)) { return }
                if !(await step("Hold", 1, 2)) { return }
                if !(await step("Out", 0.45, 6)) { return }
            }
            word = "Done"
        }
    }

    private func step(_ w: String, _ to: CGFloat, _ s: Double) async -> Bool {
        word = w
        withAnimation(.easeInOut(duration: s)) { size = to }
        try? await Task.sleep(for: .seconds(s))
        return !Task.isCancelled
    }
}

// 2. The Energy Conversion Box, with Release and Recharge.
private struct GateBoxCard: View {
    let store: GateStore
    @State private var text = ""
    @State private var opening: GateBoxItem?

    var body: some View {
        let open = store.saved.box.filter { $0.released == nil }
        return PCard(title: "The box", hint: "Put in what you will not need for now. Close the lid, turn away. Open it later, one at a time.") {
            HStack {
                TextField("A worry, a symbol for it", text: $text).textFieldStyle(.roundedBorder)
                Button("In") {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.change { $0.box.append(GateBoxItem(text: t)) }
                    text = ""
                }
                .buttonStyle(CandleGhost()).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(open.isEmpty ? "The box is empty." : "\(open.count) in the box. The lid is closed.").candleHint()
            if let first = open.first {
                Button("Open the box: release and recharge") { opening = first }.buttonStyle(CandleButton())
            }
            let done = store.saved.box.filter { $0.released != nil }.count
            if done > 0 { Text("\(done) released so far.").candleHint() }
        }
        .sheet(item: $opening) { item in GateReleaseSheet(store: store, item: item) }
    }
}

private struct GateReleaseSheet: View {
    let store: GateStore
    let item: GateBoxItem
    @Environment(\.dismiss) private var dismiss
    @State private var stage = 0
    @State private var fear = ""
    @State private var emotion = ""
    @State private var clean = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.text).candleH2()
                switch stage {
                case 0:
                    Text("The first fear that comes up with it. Name it, then let it float up and away like a bubble in water.").candleHint()
                    TextField("The fear (optional)", text: $fear, axis: .vertical).textFieldStyle(.roundedBorder)
                    Button("It floated away") { stage = 1 }.buttonStyle(CandleButton())
                case 1:
                    Text("The feeling the fear was covering. Let it go the same way.").candleHint()
                    TextField("The feeling (optional)", text: $emotion, axis: .vertical).textFieldStyle(.roundedBorder)
                    Button("Gone") { stage = 2 }.buttonStyle(CandleButton())
                default:
                    Text("What was there before, clean. A memory, or how you were before this. Pull it back in.").candleHint()
                    TextField("The clean energy (optional)", text: $clean, axis: .vertical).textFieldStyle(.roundedBorder)
                    Button("Pulled back in") {
                        store.change { s in
                            if let i = s.box.firstIndex(where: { $0.id == item.id }) {
                                s.box[i].fear = fear; s.box[i].emotion = emotion; s.box[i].clean = clean; s.box[i].released = .now
                            }
                        }
                        dismiss()
                    }
                    .buttonStyle(CandleButton())
                }
                Spacer()
            }
            .padding(20)
            .background { CandleGround() }
            .preferredColorScheme(.dark)
            .navigationTitle("Release and recharge").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

// 3. Patterning, with the manual's own rules on the screen.
private struct GatePatternCard: View {
    let store: GateStore
    @State private var text = ""
    @State private var obstacle = ""
    @State private var move = ""
    @State private var days = 30

    private var t: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var checks: [(String, Bool)] {
        let low = " " + t.lowercased() + " "
        return [("Says I", low.contains(" i ") || low.contains(" i'm ") || low.contains(" my ")),
                ("Present tense, not will or going to", !low.contains(" will ") && !low.contains(" going to ") && !t.isEmpty),
                ("Specific: a clear picture", t.split(separator: " ").count >= 6)]
    }

    var body: some View {
        PCard(title: "Patterning", hint: "Build it, release it, leave it in the water. It opens again on its date.") {
            TextField("I am now…", text: $text, axis: .vertical).textFieldStyle(.roundedBorder)
            ForEach(checks, id: \.0) { c in
                Label(c.0, systemImage: c.1 ? "checkmark.circle.fill" : "circle").candleHint()
            }
            Text("Start small enough to believe. Ask that it work for the good of your whole self.").candleHint()
            TextField("The one thing in its way", text: $obstacle).textFieldStyle(.roundedBorder)
            TextField("Your move when it shows up", text: $move).textFieldStyle(.roundedBorder)
            Picker("Cycle", selection: $days) { Text("A week").tag(7); Text("A month").tag(30); Text("A year").tag(365) }.pickerStyle(.segmented)
            Button("Release it") {
                store.change { $0.patterns.append(GatePattern(text: t, obstacle: obstacle, move: move, until: Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now)) }
                text = ""; obstacle = ""; move = ""
            }
            .buttonStyle(CandleButton()).disabled(!checks.allSatisfy(\.1))
            ForEach(store.saved.patterns.reversed()) { p in
                if p.until > .now {
                    Label("Sealed until \(p.until.formatted(date: .abbreviated, time: .omitted))", systemImage: "lock.fill").candleHint()
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.text).font(Font.pl(size: 14)).foregroundStyle(Candle.ink)
                        if let h = p.happened { Text(h ? "Happened" : "Not this time").candleHint() } else {
                            HStack {
                                Button("Happened") { mark(p.id, true) }.buttonStyle(CandleGhost())
                                Button("Not this time") { mark(p.id, false) }.buttonStyle(CandleGhost())
                            }
                        }
                    }
                }
            }
            let judged = store.saved.patterns.compactMap(\.happened)
            if !judged.isEmpty { Text("\(judged.filter { $0 }.count) of \(judged.count) happened.").candleHint() }
        }
    }

    private func mark(_ id: UUID, _ yes: Bool) { store.change { s in if let i = s.patterns.firstIndex(where: { $0.id == id }) { s.patterns[i].happened = yes } } }
}

// 4. Mission Day and Mission Night.
private struct GateMissionCard: View {
    let store: GateStore
    @State private var dayText = ""
    @State private var nightText = ""
    @State private var counting = false
    @State private var came = ""

    var body: some View {
        let lastNight = store.saved.missions.last { !$0.day && $0.came.isEmpty && Date.now.timeIntervalSince($0.at) > 3 * 3600 }
        return PCard(title: "Missions", hint: "Day: see the shift's goal done, in pictures and feeling. Night: set what sleep is for, then count into it.") {
            if let n = lastNight {
                Text("Last night: \(n.text)").font(Font.pl(size: 14)).foregroundStyle(Candle.ink)
                TextField("What came?", text: $came, axis: .vertical).textFieldStyle(.roundedBorder)
                Button("Keep it") {
                    store.change { s in if let i = s.missions.firstIndex(where: { $0.id == n.id }) { s.missions[i].came = came } }
                    came = ""
                }
                .buttonStyle(CandleGhost()).disabled(came.isEmpty)
            }
            TextField("Mission Day: this shift's goal, done", text: $dayText, axis: .vertical).textFieldStyle(.roundedBorder)
            Button("Set the day") { store.change { $0.missions.append(GateMission(day: true, text: dayText)) }; dayText = "" }
                .buttonStyle(CandleGhost()).disabled(dayText.isEmpty)
            TextField("Mission Night: a dream, a problem, a message", text: $nightText, axis: .vertical).textFieldStyle(.roundedBorder)
            Button("Count me to sleep") { store.change { $0.missions.append(GateMission(day: false, text: nightText)) }; counting = true }
                .buttonStyle(CandleButton()).disabled(nightText.isEmpty)
        }
        .fullScreenCover(isPresented: $counting) { GateSleepCount(intent: nightText) { counting = false; nightText = "" } }
    }
}

private struct GateSleepCount: View {
    let intent: String
    let done: () -> Void
    @State private var n = 0
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Text(n == 0 ? intent : "\(n)").font(Font.pl(size: n == 0 ? 18 : 44, weight: .light)).foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
                Button("Close") { done() }.foregroundStyle(.white.opacity(0.3)).frame(minWidth: 44, minHeight: 44)
            }
        }
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            try? await Task.sleep(for: .seconds(8))
            for i in 1...20 {
                n = i
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
            }
            done()
        }
    }
}

// 6. The answer inbox.
private struct GateQuestionsCard: View {
    let store: GateStore
    @State private var text = ""
    @State private var answers: [UUID: String] = [:]

    var body: some View {
        PCard(title: "Send a question out", hint: "Breathe in, think twelve, ask it, let it go on the out-breath. The answer comes in its own way and time.") {
            TextField("What is the question?", text: $text, axis: .vertical).textFieldStyle(.roundedBorder)
            Button("Send it out") { store.change { $0.questions.append(GateQuestion(text: text)) }; text = "" }
                .buttonStyle(CandleGhost()).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            ForEach(store.saved.questions.reversed()) { q in
                VStack(alignment: .leading, spacing: 4) {
                    Text(q.text).font(Font.pl(size: 14)).foregroundStyle(Candle.ink)
                    if q.thanked != nil {
                        Text(q.answer.isEmpty ? "Sealed with thanks." : q.answer).candleHint()
                    } else if Date.now.timeIntervalSince(q.at) < 3 * 86400 {
                        Text("Did it come?").candleHint()
                        TextField("The answer, in any form", text: Binding(get: { answers[q.id] ?? "" }, set: { answers[q.id] = $0 }), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Button("Thanks") {
                            let a = answers[q.id] ?? ""
                            store.change { s in if let i = s.questions.firstIndex(where: { $0.id == q.id }) { s.questions[i].answer = a; s.questions[i].thanked = .now } }
                        }
                        .buttonStyle(CandleGhost())
                    } else {
                        Text("Three days passed. Still open, or ask it differently.").candleHint()
                    }
                }
            }
        }
    }
}

// 5. The five questions and the five messages, asked by GlyphBot's interviewer into his record.
private struct GateFiveCard: View {
    var body: some View {
        PCard(title: "Five questions", hint: "Who am I. Where and who was I before this. What is my purpose here. What can I do now to serve it. What is the most important message for me now. Then five messages, fifth most important first.") {
            Text("They are queued for GlyphBot's interviewer. Sit down with it and they come up; every answer is kept word for word.").candleHint()
            Button("Open GlyphBot, Sit") { AppModel.shared.route = .section(id: "glyphbot", path: ["sit"], query: [:]) }.buttonStyle(CandleGhost())
        }
    }
}

// 7. A fair viewing game from his own archive.
private struct GateViewingCard: View {
    let store: GateStore
    @State private var pieces: [GatePiece] = []
    @State private var notes = ""
    @State private var choosing = false

    private var current: GateTrial? { store.saved.trials.last { $0.picked == nil } }

    var body: some View {
        let done = store.saved.trials.filter { $0.picked != nil }
        let hits = done.filter { $0.picked == $0.target }.count
        return PCard(title: "Viewing game", hint: "The app seals one of your pieces before you start. Describe or sketch it, then pick it from four. Chance is one in four.") {
            if let trial = current {
                Text("Sealed at \(trial.at.formatted(date: .omitted, time: .shortened)).").candleHint()
                TextField("Shapes, colours, textures, feelings", text: $notes, axis: .vertical).textFieldStyle(.roundedBorder)
                Button("Show the four") { store.change { s in if let i = s.trials.firstIndex(where: { $0.id == trial.id }) { s.trials[i].notes = notes } }; choosing = true }
                    .buttonStyle(CandleButton())
            } else {
                Button("Seal a target") { Task { await seal() } }.buttonStyle(CandleButton())
            }
            if !done.isEmpty {
                Text("\(hits) of \(done.count) found. Chance alone would be about \(String(format: "%.1f", Double(done.count) / 4)).").candleHint()
            }
        }
        .sheet(isPresented: $choosing) {
            if let trial = current { GateChoose(store: store, trial: trial, pieces: pieces) { choosing = false; notes = "" } }
        }
        .task { if pieces.isEmpty { pieces = await GatePiece.load() } }
    }

    private func seal() async {
        if pieces.isEmpty { pieces = await GatePiece.load() }
        let four = Array(pieces.shuffled().prefix(4))
        guard four.count == 4, let target = four.randomElement() else { return }
        store.change { $0.trials.append(GateTrial(target: target.cr, choices: four.map(\.cr).shuffled())) }
    }
}

private struct GateChoose: View {
    let store: GateStore
    let trial: GateTrial
    let pieces: [GatePiece]
    let done: () -> Void
    @State private var picked: String?

    var body: some View {
        let byId = Dictionary(pieces.map { ($0.cr, $0) }, uniquingKeysWith: { a, _ in a })
        VStack(spacing: 14) {
            Text(picked == nil ? "Which one was sealed?" : picked == trial.target ? "Found it." : "Not this one. The sealed piece is marked.").candleH2()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(trial.choices, id: \.self) { cr in
                    Button {
                        guard picked == nil else { return }
                        picked = cr
                        store.change { s in if let i = s.trials.firstIndex(where: { $0.id == trial.id }) { s.trials[i].picked = cr } }
                    } label: {
                        AsyncImage(url: byId[cr]?.image) { $0.resizable().scaledToFill() } placeholder: { Candle.card }
                            .frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay { if picked != nil && cr == trial.target { RoundedRectangle(cornerRadius: 10).stroke(Candle.gold, lineWidth: 4) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(byId[cr]?.title ?? cr)
                }
            }
            Button("Done") { done() }.buttonStyle(CandleGhost())
        }
        .padding(20)
        .background { CandleGround() }
        .preferredColorScheme(.dark)
    }
}

// 8. The body map with colour breathing (also opened from the check-in).
private struct GateBodyCard: View {
    @State private var open = false
    var body: some View {
        PCard(title: "Body map", hint: "Tap where it feels off, pick a colour, and breathe it there.") {
            Button("Open the body map") { open = true }.buttonStyle(CandleGhost())
        }
        .sheet(isPresented: $open) { GateBodyMap() }
    }
}

struct GateBodyMap: View {
    @Environment(\.dismiss) private var dismiss
    @State private var place = "Chest"
    @State private var color = GateColor.purple
    @State private var breathing = false
    private static let places = ["Head", "Neck and shoulders", "Chest", "Belly", "Back", "Arms and hands", "Hips", "Legs and feet"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Where", selection: $place) { ForEach(Self.places, id: \.self) { Text($0).tag($0) } }
                Picker("Colour", selection: $color) {
                    Text("Purple: heal, balance").tag(GateColor.purple)
                    Text("Green: calm the charge").tag(GateColor.green)
                    Text("Red: strength").tag(GateColor.red)
                    Text("White: fresh energy").tag(GateColor.white)
                }
                Button("Breathe it into the \(place.lowercased())") { breathing = true }
            }
            .scrollContentBackground(.hidden)
            .background { CandleGround() }
            .preferredColorScheme(.dark)
            .navigationTitle("Body map").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $breathing) { GateBreathSheet(color: color, rounds: 3) }
        }
    }
}

// 9. His own count, landscaped with his own pieces.
private struct GateCountCard: View {
    let store: GateStore
    @State private var pieces: [GatePiece] = []
    @State private var slot: Int?
    @State private var running = false

    var body: some View {
        PCard(title: "Your count", hint: "Pick a piece of yours for each number. Going down to ten is a walk through your own work.") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(0..<10, id: \.self) { i in
                    Button { slot = i } label: {
                        ZStack {
                            if let u = URL(string: store.saved.count[i]), !store.saved.count[i].isEmpty {
                                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Candle.card }
                            } else { Candle.card }
                            Text("\(i + 1)").font(Font.pl(size: 14, weight: .semibold)).foregroundStyle(Candle.ink).shadow(radius: 2)
                        }
                        .frame(height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Number \(i + 1)")
                }
            }
            Button("Count down to ten") { running = true }.buttonStyle(CandleButton())
        }
        .task { if pieces.isEmpty { pieces = await GatePiece.load() } }
        .sheet(item: Binding(get: { slot.map { GateSlot(n: $0) } }, set: { slot = $0?.n })) { s in
            GatePiecePicker(pieces: pieces) { url in store.change { $0.count[s.n] = url }; slot = nil }
        }
        .fullScreenCover(isPresented: $running) { GateCountRun(images: store.saved.count) { running = false } }
    }
}

private struct GateSlot: Identifiable { let n: Int; var id: Int { n } }

private struct GatePiecePicker: View {
    let pieces: [GatePiece]
    let picked: (String) -> Void
    @State private var search = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 6) {
                    ForEach(pieces.filter { search.isEmpty || ($0.title ?? $0.cr).localizedCaseInsensitiveContains(search) }) { p in
                        Button { picked(p.thumb ?? p.url) } label: {
                            AsyncImage(url: p.image) { $0.resizable().scaledToFill() } placeholder: { Candle.card }
                                .frame(height: 96).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(p.title ?? p.cr)
                    }
                }
                .padding(8)
            }
            .searchable(text: $search, prompt: "Title or PL number")
            .navigationTitle("Choose a piece").navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct GateCountRun: View {
    let images: [String]
    let done: () -> Void
    @State private var n = 1
    @State private var down = true
    private static let lines = ["", "", "One, two, three: mind and brain together.", "Feet and toes. Let go, sleep.", "Each leg, hip to foot. Let go.",
                                "Each hip. Let go.", "Belly and everything in it. Let go.", "Chest, heart, lungs. Let go.", "Up and down your back. Let go.",
                                "Arms, hands, shoulders. Ten. Body asleep, mind awake."]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let u = URL(string: images[n - 1]), !images[n - 1].isEmpty {
                AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { Color.black }.opacity(0.85).id(n).transition(.opacity)
            }
            VStack {
                Spacer()
                Text("\(n)").font(Font.pl(size: 54, weight: .light)).foregroundStyle(.white)
                Text(down ? Self.lines[n - 1] : "Coming back. All your senses clear.").font(Font.pl(size: 16)).foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center).padding(.horizontal, 30).frame(minHeight: 50)
                Button("Back now") { done() }.foregroundStyle(.white.opacity(0.5)).frame(minWidth: 44, minHeight: 44)
            }
            .padding(.bottom, 30)
        }
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            do {
                for i in 1...10 { withAnimation(.easeInOut(duration: 1.5)) { n = i }; try await Task.sleep(for: .seconds(i < 3 ? 6 : 18)) }
                try await Task.sleep(for: .seconds(120))
                down = false
                for i in stride(from: 10, through: 1, by: -1) { withAnimation(.easeInOut(duration: 1)) { n = i }; try await Task.sleep(for: .seconds(3)) }
            } catch { return }
            done()
        }
    }
}

// 10 (cont.). The record sheet, filled in on its own from the Lab's sessions.
private struct GateRecordCard: View {
    let lab: FrequencyLog
    var body: some View {
        let runs = Array(lab.saved.runs.suffix(8).reversed())
        return PCard(title: "Record", hint: "The workbook's sheet: time, moon, mood before and after. Filled in by each Lab session.") {
            if runs.isEmpty { Text("No sessions yet. Practice, Today, Frequency Lab.").candleHint() }
            ForEach(runs.indices, id: \.self) { i in
                let r = runs[i]
                Text("\(r.at.formatted(date: .abbreviated, time: .shortened)) · \(Self.moon(r.at)) · \(r.before.title) to \(r.after.title)")
                    .candleHint()
            }
        }
    }

    /// The moon's phase from a known new moon (6 Jan 2000, 18:14 UTC) and the 29.53-day cycle.
    static func moon(_ d: Date) -> String {
        let age = (d.timeIntervalSince1970 - 947_182_440).truncatingRemainder(dividingBy: 29.530_59 * 86_400) / 86_400
        let a = age < 0 ? age + 29.530_59 : age
        switch a {
        case ..<1.85: return "new moon"
        case ..<5.54: return "waxing crescent"
        case ..<9.23: return "first quarter"
        case ..<12.92: return "waxing gibbous"
        case ..<16.61: return "full moon"
        case ..<20.3: return "waning gibbous"
        case ..<23.99: return "last quarter"
        case ..<27.68: return "waning crescent"
        default: return "new moon"
        }
    }
}
