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
    @MainActor static var accent: Color { ThemePack.shared.accent ?? HouseKit.shared.palette.keyColor }   // the PL remix: his palette, not Apple's blue

    /// The wash on a home tile: the pack's "tile" colour, else the accent.
    @MainActor static var tileWash: Color { ThemePack.shared.colors["tile"] ?? accent }
}

/// Good, warn, bad: one shared tint for a number whose meaning is known (his note 11-14 on the PC tiles: "the number and percent
/// that's green to be green when good and red when bad, and so should most of any information: a slight red tint when it is bad,
/// a slight green tint when it is good"). The value takes the full tone, its tile a faint wash of it and the name a slight hint
/// of it. A number whose good and bad are not known is passed as nil and wears no tint at all: never guess a threshold.
enum PLStatus: Equatable {
    case good, warn, bad

    var tone: Color { switch self { case .good: return PLTone.good; case .warn: return PLTone.warn; case .bad: return PLTone.bad } }

    /// A reading where a LOWER number is worse (free RAM, free disk): under `bad` is red, under `warn` is amber.
    static func lowerIsWorse(_ v: Double, warn: Double, bad: Double) -> PLStatus { v < bad ? .bad : v < warn ? .warn : .good }
    /// A reading where a HIGHER number is worse (heat, load, kernel pool): from `bad` is red, from `warn` is amber.
    static func higherIsWorse(_ v: Double, warn: Double, bad: Double) -> PLStatus { v >= bad ? .bad : v >= warn ? .warn : .good }
    /// A count of things waiting: none is good; any is `whenAny` (amber for "waiting on a tap", red for "owed").
    static func waiting(_ n: Int, whenAny: PLStatus = .warn) -> PLStatus { n <= 0 ? .good : whenAny }
}

extension View {
    /// The value text of a number in its tone (full strength), or untouched when no level is known.
    func plStatusValue(_ level: PLStatus?) -> some View { foregroundStyle(level?.tone ?? Color.primary) }
    /// The name of a number: secondary, with a slight hint of the tone.
    func plStatusName(_ level: PLStatus?) -> some View {
        foregroundStyle(level.map { Color(uiColor: .secondaryLabel).mix(with: $0.tone, by: 0.45) } ?? Color(uiColor: .secondaryLabel))
    }
    /// A tile for one number: a faint wash of its tone and a hairline of it. No level, no tile (the number sits as it did).
    func plStatusTile(_ level: PLStatus?, radius: CGFloat = PLRadius.row) -> some View {
        background {
            if let level {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(level.tone.opacity(0.13))
                    .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(level.tone.opacity(0.28), lineWidth: 0.7) }
            }
        }
    }
}
