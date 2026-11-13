import SwiftUI
import WidgetKit

/// What the Pick widget shows: who leads the colourway vote and what he picked himself. Names and counts only.
struct PickGlance: Codable, Equatable, Sendable {
    var leader: String?
    var leaderVotes: Int
    var total: Int
    var ground: String?, key: String?, accent: String?, text: String?   // the leader's colours, for the swatch
    var mine: String?
    var updatedAt: Date
}

extension PLDevKinds {
    static let pickWidget = "com.psychedluxuries.dev.pick"
}

extension SharedState {
    static func writePick(_ g: PickGlance) {
        guard let id = groupID, let store = UserDefaults(suiteName: id), let data = try? JSONEncoder().encode(g) else { return }
        var before = readPick()
        before?.updatedAt = g.updatedAt
        store.set(data, forKey: "pick")
        if before != g { WidgetCenter.shared.reloadTimelines(ofKind: PLDevKinds.pickWidget) }
    }

    static func readPick() -> PickGlance? {
        guard let id = groupID, let data = UserDefaults(suiteName: id)?.data(forKey: "pick") else { return nil }
        return try? JSONDecoder().decode(PickGlance.self, from: data)
    }
}

extension Color {
    /// "#rrggbb" to a colour; nil for anything else.
    init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

/// Two curves on the palette's ground, the same control points as the web swatch (`public/pick/index.html`).
struct PickSwatchArt: View {
    let ground, text, key, accent: String
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 160, sy = size.height / 200
            func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: ground) ?? .black))
            var k = Path(); k.move(to: pt(-10, 150)); k.addCurve(to: pt(170, 70), control1: pt(40, 40), control2: pt(110, 210))
            ctx.stroke(k, with: .color(Color(hex: key) ?? .gray), style: StrokeStyle(lineWidth: 26 * sx, lineCap: .round))
            var a = Path(); a.move(to: pt(-10, 118)); a.addCurve(to: pt(170, 40), control1: pt(50, 20), control2: pt(100, 170))
            ctx.stroke(a, with: .color(Color(hex: accent) ?? .gray), style: StrokeStyle(lineWidth: 5 * sx, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: 123 * sx, y: 159 * sy, width: 18 * sx, height: 18 * sy)), with: .color(Color(hex: text) ?? .white))
        }
    }
}
