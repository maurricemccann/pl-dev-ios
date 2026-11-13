import SwiftUI
import UserNotifications

/// Pick: the Design Kit palettes as swatches, one tap and "This one" casts an anonymous vote for the next colourway.
/// Needs no key: it reads the gallery's kit.json and posts to the cron's public color-pick route.
@MainActor enum PickSection: PLSection {
    static let manifest = SectionManifest(id: "pick", title: "Pick", symbol: "paintpalette", needsKeys: [], needsOrigins: ["cron", "gallery"])
    static let state = PickModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(PickView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool { true }
    static func refresh(model: AppModel) async -> SectionRefresh { SectionRefresh(badge: nil, notify: []) }
}

struct Palette: Decodable, Identifiable, Equatable {
    let name, ground, text, key, accent: String
    var id: String { name }
}

private struct Kit: Decodable {
    struct Colors: Decodable { let palettes: [Palette] }
    let colors: Colors
}

extension Color {
    /// "#rrggbb" to a colour; nil for anything else.
    init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

@MainActor @Observable final class PickModel {
    var palettes: [Palette] = []
    var tally: [String: Int] = [:]
    var selected: String?
    var message: String?
    var loading = false
    var sending = false
    var thanks = false
    var showResults = false

    private static func nameOK(_ s: String) -> Bool {
        (2...40).contains(s.count) && s.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }

    func load(model: AppModel) async {
        guard let http = model.http, !loading else { return }
        loading = true; defer { loading = false }
        do {
            let data = try await http.send(RequestPlan(origin: "gallery", path: "kit.json"))
            let kit = try JSONDecoder().decode(Kit.self, from: data)
            palettes = kit.colors.palettes.filter {
                Color(hex: $0.ground) != nil && Color(hex: $0.key) != nil && Self.nameOK($0.name)
            }
            message = palettes.isEmpty ? "No colourways in the kit." : nil
        } catch {
            message = "Could not load the colourways. Pull down to try again."
        }
    }

    func loadTally(model: AppModel) async {
        guard let http = model.http else { return }
        struct Out: Decodable { struct T: Decodable { let total: Int }; let tally: [String: T]? }
        if let data = try? await http.send(RequestPlan(origin: "cron", path: "api/color-pick")),
           let out = try? JSONDecoder().decode(Out.self, from: data) {
            tally = (out.tally ?? [:]).mapValues(\.total)
        }
    }

    func vote(model: AppModel) async {
        guard let http = model.http, let pick = selected, !sending else { return }
        sending = true; message = nil; defer { sending = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["palette": pick, "source": "pl-dev"])
            _ = try await http.send(RequestPlan(origin: "cron", method: "POST", path: "api/color-pick",
                                                headers: ["content-type": "application/json"], body: body), idempotent: false)
            thanks = true
            try? await Task.sleep(for: .seconds(3))
            thanks = false; selected = nil
        } catch {
            message = "Not saved. Try again in a moment."
        }
    }

    var ranked: [Palette] { palettes.sorted { (tally[$0.name] ?? 0) > (tally[$1.name] ?? 0) } }
    var totalVotes: Int { tally.values.reduce(0, +) }
}

/// Two curves on the palette's ground, the same control points as the web swatch.
struct Swatch: View {
    let p: Palette
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 160, sy = size.height / 200
            func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: p.ground) ?? .black))
            var k = Path(); k.move(to: pt(-10, 150)); k.addCurve(to: pt(170, 70), control1: pt(40, 40), control2: pt(110, 210))
            ctx.stroke(k, with: .color(Color(hex: p.key) ?? .gray), style: StrokeStyle(lineWidth: 26 * sx, lineCap: .round))
            var a = Path(); a.move(to: pt(-10, 118)); a.addCurve(to: pt(170, 40), control1: pt(50, 20), control2: pt(100, 170))
            ctx.stroke(a, with: .color(Color(hex: p.accent) ?? .gray), style: StrokeStyle(lineWidth: 5 * sx, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: 123 * sx, y: 159 * sy, width: 18 * sx, height: 18 * sy)), with: .color(Color(hex: p.text) ?? .white))
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }
}

struct PickView: View {
    let model: AppModel
    let state: PickModel
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(state.showResults ? "The vote so far." : "Pick the next colourway.").font(.largeTitle.bold())
                    Text(state.showResults ? "\(state.totalVotes) \(state.totalVotes == 1 ? "pick" : "picks"), most first."
                                           : "One tap. The most picked becomes the next piece.").foregroundStyle(.secondary)
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(state.showResults ? state.ranked : state.palettes) { p in
                            Button { if !state.showResults { state.selected = p.name } } label: {
                                Swatch(p: p)
                                    .overlay(alignment: .topTrailing) {
                                        if state.showResults {
                                            Text("\(state.tally[p.name] ?? 0)").font(.title2.bold())
                                                .foregroundStyle(Color(hex: p.text) ?? .white).padding(10)
                                        }
                                    }
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.yellow, lineWidth: state.selected == p.name ? 3 : 0))
                                    .scaleEffect(state.selected == p.name ? 1.02 : 1)
                                    .animation(.spring(duration: 0.25), value: state.selected)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Colourway \(p.name)")
                            .accessibilityAddTraits(state.selected == p.name ? .isSelected : [])
                        }
                    }
                    if let m = state.message { Text(m).foregroundStyle(.red).frame(maxWidth: .infinity) }
                }
                .padding(PLSpace.margin)
                .padding(.bottom, 90)
            }
            .refreshable { await state.load(model: model); await state.loadTally(model: model) }
            .sensoryFeedback(PLHaptic.select, trigger: state.selected)
            .sensoryFeedback(PLHaptic.success, trigger: state.thanks)

            if !state.showResults {
                VStack {
                    Spacer()
                    Button { Task { await state.vote(model: model) } } label: {
                        Text(state.selected == nil ? "Pick one above" : "This one").font(.title3.bold())
                            .padding(.horizontal, 34).frame(minHeight: 52)
                    }
                    .glassControl(tint: state.selected == nil ? nil : .yellow)
                    .disabled(state.selected == nil || state.sending)
                    .padding(.bottom, 16)
                }
            }
            if state.thanks {
                Color.black.ignoresSafeArea().overlay(
                    VStack(spacing: 8) {
                        Text("Kept.").font(.system(size: 64, weight: .bold))
                        Text("Your pick is in. Thank you.").foregroundStyle(.secondary)
                    })
                    .transition(.opacity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(state.showResults ? "Vote" : "Results") {
                    state.showResults.toggle()
                    if state.showResults { Task { await state.loadTally(model: model) } }
                }
            }
        }
        .navigationTitle("Pick").navigationBarTitleDisplayMode(.inline)
        .task { if state.palettes.isEmpty { await state.load(model: model) } }
    }
}
