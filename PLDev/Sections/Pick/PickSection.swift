import SwiftUI
import TipKit
import UserNotifications

/// Pick: the Design Kit palettes as swatches, one tap and "This one" casts an anonymous vote for the next colourway.
/// Needs no key: it reads the gallery's kit.json and posts to the cron's public color-pick route (the same doors the web page uses).
/// Twin of `pl-curves-gallery/public/pick/index.html`: same words, same swatch, same order; the phone adds what a browser could not
/// (a vote made offline waits and goes in later, a closer look at each colourway, a widget, Siri and Spotlight).
@MainActor enum PickSection: PLSection {
    static let manifest = SectionManifest(id: "pick", title: "Pick", symbol: "paintpalette", needsKeys: [], needsOrigins: ["cron", "gallery"])
    static let state = PickModel()

    static func makeRoot(model: AppModel) -> AnyView { AnyView(PickView(model: model, state: state)) }
    static func probes(model: AppModel) -> [ProbeModel.Item] { [] }
    static func settingsRows(model: AppModel) -> AnyView? { nil }
    static func notificationCategories() -> Set<UNNotificationCategory> { [] }
    static func handle(link: DeepLink, model: AppModel) -> Bool {
        if case .section(_, let path, _) = link, let first = path.first, let room = PickRoom(rawValue: first) { PickNav.shared.room = room }
        return true
    }
    static func refresh(model: AppModel) async -> SectionRefresh {
        await state.loadTally(model: model)
        await state.flushPending(model: model)
        return SectionRefresh(badge: nil, notify: [])
    }
}

/// The two rooms of the page: the swatches to choose from, and the vote so far (`?results` on the web).
enum PickRoom: String, CaseIterable, Identifiable {
    case vote, results
    var id: String { rawValue }
    var title: String { self == .vote ? "Vote" : "Results" }
    var line: String { self == .vote ? "Choose the next colourway" : "The vote so far, most picked first" }
    var symbol: String { self == .vote ? "paintpalette" : "chart.bar.xaxis" }
}

struct Palette: Decodable, Identifiable, Equatable {
    let name, ground, text, key, accent: String
    var id: String { name }
}

private struct Kit: Decodable {
    struct Colors: Decodable { let palettes: [Palette] }
    let colors: Colors
}

/// One colourway's votes, by the door each came through (the cron's own breakdown).
struct PickTally: Decodable, Equatable {
    var total = 0, library = 0, r1 = 0, link = 0
    /// Votes from this app count in the total only (source "pl-dev" has no column of its own).
    var app: Int { max(0, total - library - r1 - link) }
}

@MainActor @Observable final class PickModel {
    var palettes: [Palette] = []
    var tally: [String: PickTally] = [:]
    var selected: String?
    var message: String?
    var loading = false
    var sending = false
    var thanks = false
    var showResults = false
    var looking: Palette?
    var mine: String? = UserDefaults.standard.string(forKey: "pick.mine")
    private(set) var pending: String? = UserDefaults.standard.string(forKey: "pick.pending")

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
            if palettes.isEmpty { message = "Could not load the colourways. Pull down to try again." }
        }
        await loadTally(model: model)
        await flushPending(model: model)
    }

    func loadTally(model: AppModel) async {
        guard let http = model.http else { return }
        struct Out: Decodable { let tally: [String: PickTally]? }
        if let data = try? await http.send(RequestPlan(origin: "cron", path: "api/color-pick")),
           let out = try? JSONDecoder().decode(Out.self, from: data) {
            tally = out.tally ?? [:]
            publishGlance()
        }
    }

    private func post(_ name: String, model: AppModel) async throws {
        guard let http = model.http else { throw URLError(.notConnectedToInternet) }
        let body = try JSONSerialization.data(withJSONObject: ["palette": name, "source": "pl-dev"])
        _ = try await http.send(RequestPlan(origin: "cron", method: "POST", path: "api/color-pick",
                                            headers: ["content-type": "application/json"], body: body), idempotent: false)
    }

    private static func offline(_ e: Error) -> Bool {
        guard let u = e as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .timedOut, .cannotConnectToHost].contains(u.code)
    }

    func vote(model: AppModel) async {
        guard let pick = selected, !sending else { return }
        sending = true; message = nil; defer { sending = false }
        do {
            try await post(pick, model: model)
            remember(pick)
            thanks = true
            await loadTally(model: model)
            try? await Task.sleep(for: .seconds(3))
            thanks = false; selected = nil
        } catch let f as HTTPClient.Failure where f == .http(429) {
            message = "Too many picks just now. Try again in a few minutes."
        } catch where Self.offline(error) {
            setPending(pick); remember(pick)
            message = "Saved. It goes in when you are back online."
            selected = nil
        } catch {
            message = "Not saved. Try again in a moment."
        }
    }

    /// A pick made offline goes in the next time the phone can reach the cron.
    func flushPending(model: AppModel) async {
        guard let name = pending, !sending else { return }
        do {
            try await post(name, model: model)
            setPending(nil); message = "Your pick went in."
            await loadTally(model: model)
        } catch {}
    }

    private func setPending(_ s: String?) {
        pending = s
        if let s { UserDefaults.standard.set(s, forKey: "pick.pending") } else { UserDefaults.standard.removeObject(forKey: "pick.pending") }
    }

    private func remember(_ name: String) { mine = name; UserDefaults.standard.set(name, forKey: "pick.mine") }

    var ranked: [Palette] { palettes.sorted { votes($0) > votes($1) } }
    var totalVotes: Int { tally.values.reduce(0) { $0 + $1.total } }
    func votes(_ p: Palette) -> Int { tally[p.name]?.total ?? 0 }
    func number(_ p: Palette) -> Int { (palettes.firstIndex(of: p) ?? 0) + 1 }

    /// The widget's numbers.
    func publishGlance() {
        guard !tally.isEmpty else { return }
        let lead = ranked.first
        SharedState.writePick(PickGlance(leader: lead?.name, leaderVotes: lead.map(votes) ?? 0, total: totalVotes,
                                         ground: lead?.ground, key: lead?.key, accent: lead?.accent, text: lead?.text,
                                         mine: mine, updatedAt: .now))
    }
}

/// A swatch the way the page draws it, with its number bottom-left and, in the results, its count top-right.
struct Swatch: View {
    let p: Palette
    var number: Int? = nil
    var count: Int? = nil
    var mine = false
    var body: some View {
        PickSwatchArt(ground: p.ground, text: p.text, key: p.key, accent: p.accent)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                if let number { Text("\(number)").plHand(15, relativeTo: .footnote).foregroundStyle(Color(hex: p.text) ?? .white).padding(.leading, 10).padding(.bottom, 8) }
            }
            .overlay(alignment: .topTrailing) {
                if let count { Text("\(count)").plHand(24, relativeTo: .title2).contentTransition(.numericText()).foregroundStyle(Color(hex: p.text) ?? .white).padding(10) }
            }
            .overlay(alignment: .bottomTrailing) {
                if mine { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: p.text) ?? .white).padding(8).accessibilityLabel("Your pick") }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }
}

struct PickView: View {
    let model: AppModel
    @Bindable var state: PickModel
    @State private var nav = PickNav.shared
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 14)]
    @Environment(\.colorScheme) private var scheme

    private func isError(_ m: String) -> Bool { m.hasPrefix("Not") || m.hasPrefix("Could") || m.hasPrefix("Too") }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(state.showResults ? "The vote so far." : "Pick the next colourway.").plHand(34, relativeTo: .largeTitle).foregroundStyle(PLG.ink(scheme))
                    Text(state.showResults ? "\(state.totalVotes) \(state.totalVotes == 1 ? "pick" : "picks"), most first."
                                           : "One tap. The most picked becomes the next piece.").plHand(15, relativeTo: .subheadline).foregroundStyle(PLG.goldDim(scheme))
                    if !state.showResults { TipView(PickLookTip()) }
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(state.showResults ? state.ranked : state.palettes) { p in
                            Button {
                                if state.showResults { state.looking = p } else { state.selected = p.name }
                            } label: {
                                Swatch(p: p, number: state.number(p), count: state.showResults ? state.votes(p) : nil, mine: state.mine == p.name)
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(PLG.gold, lineWidth: state.selected == p.name ? 3 : 0))
                                    .scaleEffect(state.selected == p.name ? 1.02 : 1)
                                    .animation(.spring(duration: 0.25), value: state.selected)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { state.looking = p } label: { Label("Look closer", systemImage: "eye") }
                                Button { UIPasteboard.general.string = "\(p.name)  \(p.ground) \(p.key) \(p.accent) \(p.text)" } label: { Label("Copy the colours", systemImage: "doc.on.doc") }
                                ShareLink(item: URL(string: "https://pl-curve-library.psychedluxuries.workers.dev/pick/")!, subject: Text("Pick the next colourway")) { Label("Share the vote", systemImage: "square.and.arrow.up") }
                            }
                            .accessibilityLabel("Colourway \(state.number(p)), \(p.name)" + (state.showResults ? ", \(state.votes(p)) picks" : ""))
                            .accessibilityAddTraits(state.selected == p.name ? .isSelected : [])
                        }
                    }
                    if state.palettes.isEmpty && state.message == nil { ProgressView().frame(maxWidth: .infinity).padding(.top, 30) }
                    if let m = state.message {
                        Label(m, systemImage: isError(m) ? "exclamationmark.triangle" : "checkmark.circle")
                            .font(.footnote).foregroundStyle(isError(m) ? PLG.red : PLG.goldDim(scheme))
                            .frame(maxWidth: .infinity)
                    }
                    if state.pending != nil { Text("One pick is waiting to go in.").font(.footnote).foregroundStyle(PLG.dim(scheme)).frame(maxWidth: .infinity) }
                }
                .padding(PLSpace.margin)
                .padding(.bottom, 90)
            }
            .refreshable { await state.load(model: model) }
            .sensoryFeedback(PLHaptic.select, trigger: state.selected)
            .sensoryFeedback(PLHaptic.success, trigger: state.thanks)

            if !state.showResults {
                VStack {
                    Spacer()
                    Button { Task { await state.vote(model: model) } } label: {
                        Text(state.selected == nil ? "Pick one above" : "This one").plHand(22, relativeTo: .title3)
                            .foregroundStyle(state.selected == nil ? PLG.dim(scheme) : PLG.ink(scheme))
                            .padding(.horizontal, 34).frame(minHeight: 52)
                    }
                    .glassControl(tint: state.selected == nil ? nil : PLG.gold)
                    .disabled(state.selected == nil || state.sending)
                    .padding(.bottom, 16)
                }
            }
            if state.thanks {
                PLG.bg(.dark).ignoresSafeArea().overlay(
                    VStack(spacing: 8) {
                        Text("Kept.").plHand(64, relativeTo: .largeTitle).foregroundStyle(PLG.gold)
                        Text("Your pick is in. Thank you.").plHand(18, relativeTo: .body).foregroundStyle(PLG.dim(.dark))
                    })
                    .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Room", selection: $state.showResults) {
                Text("Vote").tag(false)
                Text("Results").tag(true)
            }
            .pickerStyle(.segmented).padding(.horizontal, PLSpace.margin).padding(.vertical, 8)
            .background(.bar)
        }
        .sensoryFeedback(PLHaptic.select, trigger: state.showResults)
        .background { GalleryGround() }.tint(PLG.gold)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("Pick").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $state.looking) { p in PickLook(state: state, p: p) }
        .task { if state.palettes.isEmpty { await state.load(model: model) } else { await state.loadTally(model: model) } }
        .onChange(of: state.showResults) { _, on in if on { Task { await state.loadTally(model: model) } } }
        .onChange(of: nav.room) { _, room in apply(room) }
        .onAppear { apply(nav.room) }
    }

    private func apply(_ room: PickRoom?) {
        guard let room else { return }
        state.showResults = room == .results
        nav.room = nil
    }
}

/// A closer look at one colourway: the swatch large, its four colours (tap to copy) and how it has been voted, by door.
struct PickLook: View {
    let state: PickModel
    let p: Palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var copied: String?

    var body: some View {
        let t = state.tally[p.name] ?? PickTally()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Swatch(p: p, number: state.number(p), count: nil, mine: state.mine == p.name).frame(maxWidth: 320).frame(maxWidth: .infinity)
                    Text(p.name).plHand(30, relativeTo: .title).foregroundStyle(PLG.ink(scheme))
                    VStack(spacing: 0) {
                        ForEach([("Ground", p.ground), ("Key", p.key), ("Accent", p.accent), ("Mark", p.text)], id: \.0) { role, hex in
                            Button { UIPasteboard.general.string = hex; copied = hex } label: {
                                HStack(spacing: 12) {
                                    Circle().fill(Color(hex: hex) ?? .gray).frame(width: 28, height: 28).overlay(Circle().strokeBorder(.white.opacity(0.25)))
                                    Text(role).font(.body)
                                    Spacer()
                                    Text(hex.uppercased()).gMono(13).foregroundStyle(PLG.dim(scheme))
                                    Image(systemName: copied == hex ? "checkmark" : "doc.on.doc").font(.footnote).foregroundStyle(PLG.goldDim(scheme))
                                }
                                .padding(.vertical, 10).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if role != "Mark" { Divider() }
                        }
                    }
                    .gCard(padding: 14)
                    VStack(alignment: .leading, spacing: 8) {
                        GalleryHeader(text: "The vote")
                        Text("\(t.total) \(t.total == 1 ? "pick" : "picks")").font(.title2.bold()).contentTransition(.numericText())
                        if t.total > 0 {
                            HStack(spacing: 8) {
                                if t.library > 0 { GalleryChip(title: "Library", count: t.library) }
                                if t.r1 > 0 { GalleryChip(title: "R1", count: t.r1) }
                                if t.link > 0 { GalleryChip(title: "Link", count: t.link) }
                                if t.app > 0 { GalleryChip(title: "This app", count: t.app) }
                            }
                        } else {
                            Text("Nobody has picked it yet.").font(.footnote).foregroundStyle(PLG.dim(scheme))
                        }
                    }
                    .gCard(padding: 14)
                    if !state.showResults {
                        Button { state.selected = p.name; dismiss() } label: {
                            Text("This one").plHand(22, relativeTo: .title3).foregroundStyle(PLG.ink(scheme)).frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .glassControl(tint: PLG.gold)
                    }
                }
                .padding(PLSpace.margin)
            }
            .background { GalleryGround() }.tint(PLG.gold)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .navigationTitle("Colourway \(state.number(p))").navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .sensoryFeedback(PLHaptic.select, trigger: copied)
    }
}
