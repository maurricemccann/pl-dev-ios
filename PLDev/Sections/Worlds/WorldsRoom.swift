import SwiftUI
import TipKit

// The worlds, wave 4 (his order 11-13: no web views). Four rooms, all native RealityKit scenes built from his converted models
// and his archive: The Haul, The Money Room, The Weight (the Defiance worlds) and the walk-through archive.
// System add-ons (DESIGN.md §6): every world in Spotlight with its own deep link, a tip for the two-thumb controls and for the
// hall, a haptic when a work opens or a caption appears. Not fitting: a widget (these are places, not numbers), a Live Activity
// (nothing here starts and ends), notification buttons (nothing here ever pushes). The Library's widget, Siri and Spotlight
// already cover the Library as a whole; the worlds add their own rooms to Spotlight below.

enum WorldRoom: String, CaseIterable, Identifiable, Hashable {
    case haul, money, weight, space
    var id: String { rawValue }
    var title: String {
        switch self {
        case .haul: return "The Haul"; case .money: return "The Money Room"; case .weight: return "The Weight"; case .space: return "Walk the archive"
        }
    }
    var eyebrow: String { self == .space ? "Archive" : "Defiance" }
    var line: String {
        switch self {
        case .haul: return "Archive art on the walls of a room you walk"
        case .money: return "GlyphGuy dancing in falling cash"
        case .weight: return "A field of floating works"
        case .space: return "Every work in one long hall, the oldest at the far end"
        }
    }
    var symbol: String {
        switch self {
        case .haul: return "shippingbox"; case .money: return "banknote"; case .weight: return "circle.hexagongrid"; case .space: return "view.3d"
        }
    }
    /// Which archive works stand in for the room on its row.
    var thumbIndex: Int {
        switch self { case .haul: return 12; case .money: return 333; case .weight: return 777; case .space: return 964 }
    }

    @MainActor @ViewBuilder func view(_ model: AppModel) -> some View {
        switch self {
        case .haul: HaulWorld(model: model)
        case .money: MoneyRoomWorld()
        case .weight: WeightWorld(model: model)
        case .space: ArchiveSpaceWorld(model: model)
        }
    }
}

/// Where a link, Spotlight or Siri wants the worlds to go.
@MainActor @Observable final class WorldsNav {
    static let shared = WorldsNav()
    var room: WorldRoom?
}

// MARK: - The hub: the Library's "The Defiance worlds" room, and the archive walk beside it

struct WorldsRoom: View {
    let model: AppModel
    @State private var archive = WorldArchive.shared
    @State private var nav = WorldsNav.shared
    @State private var open: WorldRoom?

    var body: some View {
        List {
            Section {
                ForEach([WorldRoom.haul, .money, .weight]) { row($0) }
            } header: {
                Text("Rooms you walk, made from the archive and his models.")
            }
            Section {
                row(.space)
            } header: {
                Text("The archive as a room.")
            }
            if archive.failed {
                Section {
                    Text("The archive did not load, so the frames stay gold.").font(.footnote).foregroundStyle(.secondary)
                    Button("Try again") { Task { await archive.load(model: model, force: true) } }
                }
            }
        }
        .gScreen()
        .navigationTitle("The Defiance worlds")
        .navigationDestination(item: $open) { $0.view(model) }
        .task {
            await archive.load(model: model)
            if let r = nav.room { open = r; nav.room = nil }
        }
        .onChange(of: nav.room) { _, r in if let r { open = r; nav.room = nil } }
    }

    private func row(_ r: WorldRoom) -> some View {
        Button { open = r } label: {
            HStack(spacing: 14) {
                thumb(r)
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.eyebrow).gEyebrow(10).foregroundStyle(PLG.goldDim(.dark))
                    Text(r.title).gTitle(22)
                    Text(r.line).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.title). \(r.line)")
        .accessibilityAddTraits(.isButton)
    }

    /// One of his works stands in for the room; until the archive is in, the room's own mark does.
    @ViewBuilder private func thumb(_ r: WorldRoom) -> some View {
        let works = archive.pieces
        let url = works.isEmpty ? nil : works[r.thumbIndex % works.count].thumbURL
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x1a1610))
            if let url {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Image(systemName: r.symbol).foregroundStyle(PLG.gold.opacity(0.6)) }
            } else {
                Image(systemName: r.symbol).font(.title3).foregroundStyle(PLG.gold.opacity(0.6))
            }
        }
        .frame(width: 58, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(PLG.gold.opacity(0.25), lineWidth: 0.8))
        .accessibilityHidden(true)
    }
}

// MARK: - Tips (only for what cannot be seen)

struct WorldMoveTip: Tip {
    var title: Text { Text("Walk with your thumbs") }
    var message: Text? { Text("The left thumb walks, wherever it lands. The right thumb looks. A work shows its name when you stand near it.") }
    var image: Image? { Image(systemName: "hand.draw") }
}

struct WorldHallTip: Tip {
    var title: Text { Text("The hall runs back in time") }
    var message: Text? { Text("Drag to slide across the lanes. Pinch to walk down the hall. Tap a work to open it, or jump to a year below.") }
    var image: Image? { Image(systemName: "view.3d") }
}

/// A tip pinned under the title, over the scene.
struct WorldTipLine<T: Tip>: View {
    let tip: T
    var body: some View {
        VStack {
            TipView(tip).tint(PLG.gold).environment(\.colorScheme, .dark).padding(.horizontal, 16).padding(.top, 52)
            Spacer()
        }
    }
}

