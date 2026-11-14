import SwiftUI

/// Curate's own values from the gallery's CurateDeck.tsx and globals.css (his ruling 11-13: each app looks like its web app).
/// The ground and the card read from GallerySkin (`PLG`); this file adds only what the deck itself draws: the three verdict
/// stamps, the orange wash and ring a card in Claude's own words (a cloud batch, an API render) gets, the keycap tray.
enum PLC {
    /// DIRS in CurateDeck.tsx: the stamp colours, drawn on a near-white chip.
    static let keep = Color(hex: 0x2f6b3a)
    static let cut = Color(hex: 0x7c1f1f)
    static let maybe = Color(hex: 0x8a6b1f)
    /// `--claude-wash` / `--claude-orange` (globals.css; the dark wash is the `data-psytheme="dark"` value).
    static func wash(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0x2a1d10) : Color(hex: 0xf8e1c8) }
    static func orange(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0xe0813a) : Color(hex: 0x9c4a0e) }
    /// The card's own ground: the web card is `--cream-surface`, bone over the page.
    static var bone: Color { PLCarry.tone(.ink, .dark, Color(hex: 0xece7da)) }
    static var ink: Color { PLCarry.tone(.ink, .light, Color(hex: 0x1a1510)) }
    /// The keycap tray: a black case the five caps sit edge to edge in (`#141210`, 8 pt corner).
    static var tray: Color { PLCarry.tone(.well, .dark, Color(hex: 0x141210)) }
}

extension TasteMark {
    /// What the card carried into the deck: nothing (unmarked), `fav`, or the verdict it holds.
    var prevName: String { isFav ? "fav" : v }
}
