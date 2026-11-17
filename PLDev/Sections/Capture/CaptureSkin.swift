import SwiftUI

/// Capture wears pl-os's skin (`HouseSkin.swift`: PLOS tokens, OSCard, OSPanel, OSRow, OSPill, OSKpis), because the web app it
/// twins is pl-os Intake. This file adds only what Intake has that House does not: the room bar, the input, the gold button, the badge.

/// The room bar: `.o-tabbar` set at the top, under the header. Glass capsule, gold on the room you are in, a badge where something waits.
struct CaptureRoomBar: View {
    @Binding var room: CaptureRoom
    var badges: [CaptureRoom: Int] = [:]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 6) {
                ForEach(CaptureRoom.allCases) { r in item(r) }
            }
            .padding(6)
            .plGlass(in: Capsule())
        }
    }

    private func item(_ r: CaptureRoom) -> some View {
        let on = room == r
        return Button { withAnimation(.snappy) { room = r } } label: {
            VStack(spacing: 3) {
                Image(systemName: r.symbol).font(.system(size: 17, weight: .medium))
                Text(r == .trail ? "Trail" : r.title).osEyebrow(8)
            }
            .foregroundStyle(on ? Color.black : PLOS.dim(scheme))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background { if on { Capsule().fill(PLOS.gold) } }
            .overlay(alignment: .topTrailing) {
                if let n = badges[r], n > 0 {
                    Text("\(n)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.black)
                        .padding(.horizontal, 5).padding(.vertical, 1).background(PLOS.gold, in: Capsule())
                        .overlay { Capsule().strokeBorder(.black.opacity(0.3)) }
                        .offset(x: -8, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(r.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

extension View {
    /// One full-width row of the room list: clear, no separator, the screen's own side margins.
    func captureRow() -> some View {
        listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
    }
}

/// The small box that names a capture's state (pl-os CaptureTrail's `tone`).
struct CaptureBadge: View {
    let label: String
    var tone: CaptureState.Tone = .plain
    var saving = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let gold = saving || tone == .pool
        Text(label).osEyebrow(9)
            .foregroundStyle(gold ? PLOS.gold : (tone == .dim ? PLOS.dim(scheme) : PLOS.text(scheme)))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(gold ? PLOS.gold.opacity(0.12) : PLOS.surface2(scheme).opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(gold ? PLOS.gold.opacity(0.4) : PLOS.line(scheme), lineWidth: 0.8) }
            .fixedSize()
    }
}
