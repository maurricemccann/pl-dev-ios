import SwiftUI

// The composed check-in screen (S355, spec "PL DEV PICKS ON THE PHONE" in the vault; his ruling 11-27 "Compose and write"): the
// phone's model proposes parts and a few words, GenRules (PLDevCore) holds them to the band, GenVariety shuffles by seed, and the
// theme packs lend card style, corners, type, wall and pace. Colours are only the band's tested ones. Anything that fails or is
// slow leaves the rule screen, and a screen already on show never changes.

@MainActor @Observable final class RisingGen {
    static let shared = RisingGen()

    var on = UserDefaults.standard.object(forKey: "pldev.rising.generate") as? Bool ?? true {
        didSet { UserDefaults.standard.set(on, forKey: "pldev.rising.generate") }
    }
    private var decided: Date?          // the tap whose screen is settled, composed or not
    private var composed: GenScreen?
    private var resetFor: Date?
    @ObservationIgnored private var busy: Date?
    @ObservationIgnored private(set) var pack: PLThemePreset?
    @ObservationIgnored private(set) var wallPack: PLThemePreset?

    /// The theme packs lending this screen its layers: Heavy and Hot borrow only from the quiet ones.
    private func borrow(_ screen: GenScreen, calm: Bool) {
        let all = PLThemePreset.all.filter { $0.id != "daily" }
        let quiet = all.filter { $0.calm || $0.pace > 1 }
        let packs = calm && !quiet.isEmpty ? quiet : all
        pack = packs.isEmpty ? nil : packs[screen.pack % packs.count]
        let walls = packs.filter { $0.wall.hasPrefix("mask|") || $0.wall.hasPrefix("invert|") }
        wallPack = walls.isEmpty ? nil : walls[screen.pack % walls.count]
    }

    /// Still waiting on the model for this tap (at most 3 seconds).
    func pending(_ tap: CheckIn) -> Bool { on && PLIntelligence.isReady && decided != tap.at }

    func screen(for tap: CheckIn) -> GenScreen? { on && decided == tap.at && resetFor != tap.at ? composed : nil }

    var showsBuddy: Bool {
        guard let tap = RisingScale.shared.current, RisingScale.shared.showWords, let s = screen(for: tap) else { return false }
        return s.blocks.contains { $0.part == .buddy }
    }

    /// Back to today's rule screen for this tap.
    func reset(_ tap: CheckIn) { resetFor = tap.at }

    func compose(_ tap: CheckIn) async {
        guard on, decided != tap.at, busy != tap.at else { return }
        busy = tap.at
        defer { busy = nil }
        let rising = RisingScale.shared
        let band = tap.band.rawValue
        let d = UserDefaults.standard
        let history = d.array(forKey: "pldev.rising.genHistory") as? [[String]] ?? []
        guard let proposal = await PLIntelligence.compose(summary(tap, history: history)) else {
            composed = nil
            decided = tap.at
            rising.markScreen("rules", written: nil)
            return
        }
        let hasNote = !rising.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var fitted = GenRules.fit(proposal, band: band, hasNote: hasNote, hasVision: !Self.pieces.isEmpty)
        // the move list already shows his note on the low bands, so it is not drawn twice
        if fitted.blocks.contains(where: { $0.part == .move }) { fitted.blocks.removeAll { $0.part == .note } }
        let crowned = RisingStep.of(tap.band).lines.first ?? ""
        let words = GenRules.written(heading: proposal.heading, line: proposal.line, band: band, crowned: crowned, banned: PLIntelligence.composeBanned)
        fitted.heading = words.heading
        fitted.line = words.line
        let seed = GenVariety.seed("\(RisingScale.shiftDay(tap.at))/\(Int(tap.at.timeIntervalSince1970))/\(band)")
        let screen = GenVariety.distinct(fitted, band: band, seed: seed, recent: history)
        d.set(Array((history + [GenVariety.signature(screen)]).suffix(8)), forKey: "pldev.rising.genHistory")
        borrow(screen, calm: tap.band <= .hot)
        composed = screen
        decided = tap.at
        resetFor = nil
        rising.markScreen("generated", written: [words.heading, words.line].compactMap { $0 }.joined(separator: " | "))
    }

    /// What the model is told: the tap, the quick answers, the hour and the shapes it should not repeat. No note, no words of his.
    private func summary(_ tap: CheckIn, history: [[String]]) -> String {
        var lines = ["Feeling: \(tap.band.title). Aim one step up."]
        if tap.tiredBody { lines.append("Body is tired.") }
        if let e = tap.energy { lines.append("Energy: " + ["empty", "some", "plenty"][min(2, max(0, e))] + ".") }
        if let c = tap.control { lines.append("In their hands: " + ["no", "partly", "yes"][min(2, max(0, c))] + ".") }
        if let a = tap.about { lines.append("It is about: \(a).") }
        lines.append("Hour: \(Calendar.current.component(.hour, from: tap.at)).")
        if let lift = RisingScale.shared.liftLine { lines.append("What has lifted them: \(lift)") }
        let recent = history.suffix(3).map { sig in sig.prefix { !$0.hasPrefix("shape") }.map { String($0.split(separator: ".")[0].split(separator: ":")[1]) }.joined(separator: ", ") }
        if !recent.isEmpty { lines.append("Recent screens, do not repeat: " + recent.joined(separator: " / ")) }
        return lines.joined(separator: "\n")
    }

    /// His chosen pieces from the Gate's count.
    static var pieces: [URL] {
        GateStore.shared.load()
        return GateStore.shared.saved.count.compactMap { $0.isEmpty ? nil : URL(string: $0) }
    }
}

struct RisingGenView: View {
    let screen: GenScreen
    let tap: CheckIn
    @State private var rising = RisingScale.shared
    @State private var buddy = BuddyModel()
    @State private var breathing = false
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var calm: Bool { tap.band <= .hot }

    // picked once when the screen is composed: building the pack list is far too dear to repeat on every redraw
    private var pack: PLThemePreset? { RisingGen.shared.pack }
    private var wallPack: PLThemePreset? { RisingGen.shared.wallPack }

    private var colors: [Color] { rising.genColors(tap.band) }
    private var surface: Color { colors.count > 4 ? colors[1] : Color(.secondarySystemBackground) }
    private var ink: Color { colors.count > 4 ? colors[2] : .primary }
    private var muted: Color { colors.count > 4 ? colors[3] : .secondary }
    private var accent: Color { colors.count > 4 ? colors[4] : PLTone.accent }

    private var drafted: Bool { screen.heading != nil || screen.line != RisingStep.of(tap.band).lines.first }
    /// His crowned lines for this band, less the one already at the top.
    private var spare: [String] { RisingStep.of(tap.band).lines.filter { $0 != screen.line } }

    private var corner: CGFloat { max(6, CGFloat(pack?.radius ?? 1) * [10, 14, 18, 22][screen.shape % 4]) }
    private var gap: CGFloat { [6, 10, 16][screen.spacing % 3] }

    private func headingFont() -> Font {
        if let face = pack?.face, face.hasPrefix("bundle:") { return .custom(String(face.dropFirst(7)), size: 24, relativeTo: .title2) }
        return .title2.weight(.semibold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            card(0) {
                VStack(alignment: .leading, spacing: 4) {
                    if let h = screen.heading { Text(h).font(headingFont()) }
                    if let l = screen.line { Text(l).plFont(.callout) }
                    // marked only when the phone wrote it: a rejected line falls back to his own
                    if drafted { Text("phone's draft").plFont(.caption2).foregroundStyle(muted) }
                }
            }
            ForEach(Array(screen.blocks.enumerated()), id: \.offset) { i, block in
                if block.part == .wall {
                    wall(block).entrance(shown, i + 1, step: step)
                } else {
                    card(i + 1) { part(block) }
                }
            }
        }
        .foregroundStyle(ink)
        .tint(accent)
        .onAppear {
            buddy.playState(RisingStep.of(tap.band).face)
            shown = true
        }
    }

    /// Seconds between one part arriving and the next; nil = everything is simply there.
    private var step: Double? {
        reduce || screen.motion == 0 ? nil : (screen.motion == 1 ? 0.12 : 0.07) * (pack?.pace ?? 1)
    }

    /// The borrowed card style on the band's own surface, never see-through enough to cost contrast.
    private func card(_ i: Int, @ViewBuilder _ content: () -> some View) -> some View {
        let style = pack?.card ?? .solid
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(surface.opacity(style == .clear ? 0.86 : style == .frosted ? 0.9 : 1), in: shape)
            .overlay { if style == .outline || style == .frosted { shape.strokeBorder(accent.opacity(style == .outline ? 0.7 : 0.25), lineWidth: 1) } }
            .entrance(shown, i, step: step)
    }

    @ViewBuilder private func part(_ block: GenBlock) -> some View {
        switch block.part {
        case .move: RisingAction(band: tap.band).id(tap.at)
        case .breath: breath
        case .walk: done("I walked ten minutes", "figure.walk", records: "Walk 10 minutes, past trees")
        case .plan:
            if rising.current?.did == true { Label("Done. That counts.", systemImage: "checkmark.circle.fill").frame(minHeight: 44) }
            else { RisingPlan(fields: ["The first step is"]) { rising.markDone("Do the first step") } }
        case .buddy: buddyPart(block)
        case .week: week(block)
        case .vision: vision(block)
        case .note:
            VStack(alignment: .leading, spacing: 4) {
                Text("From you, on a good night").plFont(.caption).foregroundStyle(muted)
                Text(rising.note).plFont(.callout)
            }
        case .text:
            Text(RisingAsk.nudge(tap) ?? (spare.isEmpty ? "Take the one small move." : spare[block.variant % spare.count]))
                .plFont(block.size == 2 ? .headline : .callout)
        case .wall: EmptyView()
        }
    }

    @ViewBuilder private var breath: some View {
        let hot = tap.band == .hot
        let name = tap.band == .heavy ? "Breathe with me" : hot ? "Cool down, 2 minutes" : "Breathe slow, 2 minutes"
        if breathing {
            BreathRing(rounds: tap.band == .heavy ? 3 : 12, box: false, inS: tap.band == .heavy ? 0 : hot ? 3 : 4, outS: tap.band == .heavy ? 0 : hot ? 7 : 6,
                       done: { breathing = false; rising.markDone(name) }, stop: { breathing = false })
        } else {
            Button { breathing = true } label: { Label(name, systemImage: "wind").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
                .buttonStyle(.bordered)
        }
    }

    private func done(_ title: String, _ symbol: String, records move: String) -> some View {
        Button { rising.markDone(move) } label: { Label(title, systemImage: symbol).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
            .buttonStyle(.bordered)
    }

    /// Buddy with one of his crowned lines; the variant moves him left or right and in or out of his hole.
    private func buddyPart(_ block: GenBlock) -> some View {
        let head = BuddyHead(model: buddy, side: [84, 110, 140][block.size % 3], hole: block.variant == 0)
        // no second copy of the line at the top: then he is simply there
        let said = Text(spare.isEmpty ? "" : spare[block.variant % spare.count]).plFont(.callout).frame(maxWidth: .infinity, alignment: .leading)
        return HStack(alignment: .center, spacing: 8) {
            if block.variant == 1 { head; said } else { said; head }
        }
    }

    /// A piece of a pack's wall, turned and zoomed by the seed, drawn in the band's accent. No words sit on it.
    @ViewBuilder private func wall(_ block: GenBlock) -> some View {
        if let spec = wallPack?.wall {
            ThemeWall(spec: spec, key: accent, strength: calm ? 0.1 : 0.35)
                .scaleEffect(screen.wallZoom)
                .rotationEffect(.degrees(Double(screen.wallAngle)))
                .scaleEffect(screen.wallAngle % 90 == 0 ? 1 : 1.5)
                .frame(maxWidth: .infinity)
                .frame(height: [64, 104, 150][block.size % 3])
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    /// Seven days as bars, dots or blocks; height is the step, so it reads without the colour.
    private func week(_ block: GenBlock) -> some View {
        let days = rising.days(7)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(days.indices, id: \.self) { i in
                let h = days[i].step.map { 8 + CGFloat($0) * [4, 6, 8][block.size % 3] } ?? 4
                let fill = days[i].step == nil ? muted.opacity(0.4) : accent
                VStack(spacing: 4) {
                    switch block.variant {
                    case 1: Circle().fill(fill).frame(width: 8, height: 8).padding(.bottom, h - 4)
                    case 2: RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 18, height: h)
                    default: Capsule().fill(fill).frame(width: 10, height: h)
                    }
                    Text(days[i].letter).plFont(.caption2).foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last seven days: " + days.map { d in d.step.map { Band(rawValue: Int($0.rounded()))?.title ?? "" } ?? "no tap" }.joined(separator: ", "))
    }

    private func vision(_ block: GenBlock) -> some View {
        let side = [64.0, 96.0, 140.0][block.size % 3]
        return VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(RisingGen.pieces, id: \.self) { u in
                        AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { muted.opacity(0.2) }
                            .frame(width: side, height: side)
                            .clipShape(block.variant == 1 ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: corner / 2)))
                    }
                }
            }
            .accessibilityLabel("Your chosen pieces")
            Text("Hold one picture. Name the one thing in its way, and your move.").plFont(.footnote).foregroundStyle(muted)
        }
    }
}

private extension View {
    /// Parts arrive one after another, upward; with no step they are just there.
    func entrance(_ shown: Bool, _ i: Int, step: Double?) -> some View {
        opacity(step == nil || shown ? 1 : 0)
            .offset(y: step == nil || shown ? 0 : 14)
            .animation(step.map { .easeOut(duration: 0.35).delay(Double(i) * $0) }, value: shown)
    }
}
