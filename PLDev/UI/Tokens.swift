import SwiftUI
import UIKit

/// The spacing scale, in points. Use these, not loose numbers.
enum PLSpace {
    static let hair: CGFloat = 2
    static let tight: CGFloat = 4
    static let gap: CGFloat = 8
    static let snug: CGFloat = 10
    static let pad: CGFloat = 12
    static let margin: CGFloat = 16
    static let roomy: CGFloat = 20
    static let block: CGFloat = 36
}

/// Corner radii, always with the continuous curve.
enum PLRadius {
    static let card: CGFloat = 28
    static let sheet: CGFloat = 32
    static let row: CGFloat = 14
    static let list: CGFloat = 26
}

enum PLMetric {
    static let touch: CGFloat = 44   // the smallest thing a finger is asked to hit
}

/// Neutral colour roles. All are Apple's system colours, so light, dark and Increase Contrast come for free.
/// The only colour a theme pack can change is the accent (and the tile wash that is mixed from it).
enum PLTone {
    static let canvas = Color(uiColor: .systemGroupedBackground)          // behind everything
    static let surface = Color(uiColor: .secondarySystemGroupedBackground) // a card or tile on the canvas
    static let plate = Color(uiColor: .systemFill)
    static let well = Color(uiColor: .tertiarySystemFill)
    static let hairline = Color(uiColor: .separator)
    static let good = Color(uiColor: .systemGreen)
    static let bad = Color(uiColor: .systemRed)
    static let warn = Color(uiColor: .systemOrange)
    static let quiet = Color(uiColor: .systemGray)

    /// The tint for controls and marks: the theme pack's accent when one is loaded, else the asset catalog's.
    @MainActor static var accent: Color { ThemePack.shared.accent ?? Color.accentColor }

    /// The wash on a home tile: the pack's "tile" colour, else the accent.
    @MainActor static var tileWash: Color { ThemePack.shared.colors["tile"] ?? accent }
}
