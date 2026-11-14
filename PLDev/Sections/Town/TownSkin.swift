import SwiftUI
import CoreText
import UIKit

/// Task Town's own skin, from the web page (`app/town/page.tsx` in the gallery): the dark brown night behind the street, the gold chips with
/// their hard offset shadow, the cream dialog box with its dark rim, the cyan live line. The page sets these in "Press Start 2P"; the native
/// twin is VT323 from his Design Kit (`vt323.ttf`, bundled here, registered once at first use), a pixel terminal face drawn narrower than
/// Press Start 2P, so sizes are scaled by `TownFace.k`. If the file cannot load, Menlo bold stands in.
enum TownFace {
    static let k: CGFloat = 1.5
    static let ready: Bool = {
        guard let url = Bundle.main.url(forResource: "vt323", withExtension: "ttf") else { return false }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return UIFont(name: "VT323-Regular", size: 12) != nil
    }()
    static var name: String { ready ? "VT323-Regular" : "Menlo-Bold" }
    static var scale: CGFloat { ready ? k : 1 }
    static func ui(_ size: CGFloat) -> UIFont { UIFont(name: name, size: size * scale) ?? .monospacedSystemFont(ofSize: size, weight: .heavy) }
}

enum TownInk {
    static let ground = Color(hex: 0x120c06)
    static let panel = Color(hex: 0x2a1a10)
    static let gold = Color(hex: 0xffe07a)
    static let goldDeep = Color(hex: 0x9a6a1c)
    static let text = Color(hex: 0xf8ecd0)
    static let paper = Color(hex: 0xf8f0d8)
    static let cyan = Color(hex: 0x9fe8ff)
    static let red = Color(hex: 0xd04a3a)
    static let warn = Color(hex: 0x5a1a12)
    static let dim = Color(hex: 0x8a7a60)
    static let hud = Color(red: 20 / 255, green: 12 / 255, blue: 4 / 255).opacity(0.82)

    static func px(_ size: CGFloat, relativeTo style: Font.TextStyle = .caption) -> Font { .custom(TownFace.name, size: size * TownFace.scale, relativeTo: style) }
}

/// The web's `chip(on)`: a square button with a 2 pt dark rim and a hard 2 pt shadow, gold when on, dark when off.
struct TownChipStyle: ButtonStyle {
    var on = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TownInk.px(9))
            .foregroundStyle(on ? TownInk.panel : TownInk.gold)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background {
                ZStack {
                    Rectangle().fill(on ? TownInk.goldDeep : TownInk.gold).offset(x: 2, y: 2)
                    Rectangle().fill(on ? TownInk.gold : TownInk.panel)
                    Rectangle().strokeBorder(TownInk.panel, lineWidth: 2)
                }
            }
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
            .contentShape(Rectangle())
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// The screen behind the town: the page's dark brown, edge to edge.
    func townScreen() -> some View {
        background(TownInk.ground.ignoresSafeArea()).preferredColorScheme(.dark).tint(TownInk.gold)
    }

    /// A panel in the list sheet: the dark brown card with the gold rim, as the page's dialog and HUD chips.
    func townPanel() -> some View {
        padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(TownInk.panel)
            .overlay(Rectangle().strokeBorder(TownInk.gold.opacity(0.9), lineWidth: 2))
    }
}
