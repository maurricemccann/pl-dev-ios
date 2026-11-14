import Foundation
import SwiftUI
import UIKit

/// Brush colours and Colourways (the laptop's `qcSlots`, `qcValue`, `qcWays`, `qcApply`). A brush that paints in more than one colour (a companion
/// line, a filled middle, a channel) shows a swatch per colour. Tap a swatch and the picker edits that colour; tap a colourway and every colour of
/// the brush changes at once. A colourway is a palette's colours, as many as the brush has, the lightest in the middle slot.
enum NativeBrushColours {
    struct Slot: Identifiable { let id: String; let label: String; let key: String }
    struct Way: Identifiable { let name: String; let cols: [String]; var id: String { name } }

    private static let key = "plpn-brushcols"
    /// What he changed on a built-in brush, by brush id, kept on this phone (a Mine brush keeps it in the brush itself).
    nonisolated(unsafe) static var overrides: [String: [String: String]] = {
        guard let d = UserDefaults.standard.data(forKey: key), let o = try? JSONDecoder().decode([String: [String: String]].self, from: d) else { return [:] }
        return o
    }()
    static func save() { if let d = try? JSONEncoder().encode(overrides) { UserDefaults.standard.set(d, forKey: key) } }

    /// The brush with his colour changes laid over it.
    static func apply(_ b: Brush) -> Brush {
        guard let o = overrides[b.id] else { return b }
        var out = b
        for (k, v) in o { out = out.setting(k, v) }
        return out
    }

    static func slots(_ B: Brush) -> [Slot] {
        var s = [Slot(id: "main", label: "Main", key: "color")]
        if B.n("twin") > 0 || B.n("lines") > 1 || !B.t("color2").isEmpty { s.append(Slot(id: "accent", label: B.n("twin") > 0 ? "Companion" : "Second", key: "color2")) }
        if B.n("lines") > 1 && B.t("gapFill") == "colour" { s.append(Slot(id: "fill", label: "Middle", key: "gapFillColor")) }
        func glows(_ f: String) -> Bool { f.contains("colour") || f.contains("glow") || f.contains("shadow") }
        if B.n("channel") > 0 && glows(B.t("channelFill")) { s.append(Slot(id: "ch", label: "Channel", key: "channelColor")) }
        if B.n("channel2") > 0 && glows(B.t("channel2Fill")) { s.append(Slot(id: "ch2", label: "Outer channel", key: "channel2Color")) }
        return s
    }

    @MainActor static func value(_ B: Brush, _ key: String, canvas: NativeCanvasModel) -> String {
        let primary = UIColor(canvas.color).hex, secondary = UIColor(canvas.color2).hex
        switch key {
        case "color": return canvas.brushColors && !B.t("color").isEmpty ? B.t("color") : primary
        case "color2": return canvas.brushColors && !B.t("color2").isEmpty ? B.t("color2") : secondary
        default: return !B.t(key).isEmpty ? B.t(key) : (canvas.brushColors && !B.t("color2").isEmpty ? B.t("color2") : secondary)
        }
    }

    /// One colourway per palette, as many colours as the brush has; the House palette (all his colours) is a box of paints, not a colourway.
    static func ways(_ n: Int) -> [Way] {
        func lum(_ c: String) -> Double { Hex.rgb(c).map { $0.0 * 0.3 + $0.1 * 0.59 + $0.2 * 0.11 } ?? 0 }
        var out: [Way] = []
        for p in NativeToolkit.palettes where !p.house && !p.name.hasPrefix("Random:") {
            var seen = Set<String>()
            let cols = p.colors.filter { seen.insert($0).inserted }
            if cols.count < n || cols.count > 8 { continue }
            let sorted = cols.sorted { lum($0) > lum($1) }
            let mid = sorted[sorted.count / 2]
            let pick = Array(([mid] + sorted.filter { $0 != mid }).prefix(n))
            out.append(Way(name: p.name, cols: pick))
            if out.count >= 12 { break }
        }
        return out
    }
}

@MainActor extension NativeCanvasModel {
    /// Sets one colour of the brush in hand and keeps it (a Mine brush in its file, a built-in one on this phone).
    func setBrushColour(_ key: String, _ hex: String) {
        if key == "color" {
            if brushColors && !brush.t("color").isEmpty { brush = brush.setting("color", hex); keepBrushColours() }
            setColour(hex: hex)
        } else {
            brush = brush.setting(key, hex)
            if key == "color2", let c = Hex.rgb(hex) { color2 = Color(red: c.0, green: c.1, blue: c.2) }
            keepBrushColours()
        }
    }

    func applyColourway(_ cols: [String]) {
        for (i, s) in NativeBrushColours.slots(brush).enumerated() where cols.indices.contains(i) {
            let c = cols[i]
            if s.key == "color" { if brushColors && !brush.t("color").isEmpty { brush = brush.setting("color", c) }; setColour(hex: c) }
            else {
                brush = brush.setting(s.key, c)
                if s.key == "color2", let r = Hex.rgb(c) { color2 = Color(red: r.0, green: r.1, blue: r.2) }
            }
        }
        keepBrushColours()
        say("Colourway on \(brush.name).")
    }

    private func keepBrushColours() {
        if NativeMine.brushes.contains(where: { $0.id == brush.id }) { NativeMine.upsert(brush) }
        else {
            var o: [String: String] = [:]
            for s in NativeBrushColours.slots(brush) where !brush.t(s.key).isEmpty { o[s.key] = brush.t(s.key) }
            NativeBrushColours.overrides[brush.id] = o; NativeBrushColours.save()
        }
        savePrefs()
    }
}

/// This brush's colours and the colourways, at the top of the Colour card.
struct NativeBrushColourCard: View {
    @Bindable var canvas: NativeCanvasModel
    @State private var slot = "main"

    var body: some View {
        let B = canvas.brush, slots = NativeBrushColours.slots(B)
        if slots.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                Text("This brush: \(B.name)").font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach(slots) { s in
                        let hex = NativeBrushColours.value(B, s.key, canvas: canvas)
                        Button { slot = s.id } label: {
                            VStack(spacing: 3) {
                                Circle().fill(Color(plHex: hex)).frame(width: 34, height: 34).overlay(Circle().stroke(slot == s.id ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: slot == s.id ? 3 : 1))
                                Text(s.label).font(.caption2).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    if let s = slots.first(where: { $0.id == slot }) {
                        ColorPicker("\(s.label) colour", selection: Binding(get: { Color(plHex: NativeBrushColours.value(B, s.key, canvas: canvas)) },
                                                                             set: { canvas.setBrushColour(s.key, UIColor($0).hex) }), supportsOpacity: false).labelsHidden()
                    }
                }
                let ways = NativeBrushColours.ways(slots.count)
                if !ways.isEmpty {
                    Text("Colourways").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ways) { w in
                                Button { canvas.applyColourway(w.cols) } label: {
                                    HStack(spacing: 0) { ForEach(Array(w.cols.enumerated()), id: \.offset) { _, c in Rectangle().fill(Color(plHex: c)).frame(width: 22, height: 30) } }
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                                }.buttonStyle(.plain).accessibilityLabel("Colourway \(w.name)")
                            }
                        }
                    }
                }
            }
            .padding(10).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private extension Color {
    init(plHex: String) { let c = Hex.rgb(plHex) ?? (0, 0, 0); self.init(red: c.0, green: c.1, blue: c.2) }
}
