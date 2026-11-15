import Foundation

/// Where a shared item can go (Plans/SPEC — PL DEV SMART CAPTURE (S348), his words 11-14). Plain logic only, tested on Linux in CI.
public enum CaptureRoute: String, CaseIterable, Identifiable, Sendable {
    case board   // the board's inbox, for Claude
    case quote   // the intake as a quote
    case seed    // the board's inbox, tagged SEED (his ruling 11-14: seeds go to the board inbox; a session files them)
    case art     // the intake as artwork (an image)
    case tile    // a new Backend tile (the "PWA" tile)

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .board: return "Board"
        case .quote: return "Quote"
        case .seed: return "Seed"
        case .art: return "Art"
        case .tile: return "Make a tile"
        }
    }

    public var symbol: String {
        switch self {
        case .board: return "tray.and.arrow.up"
        case .quote: return "quote.opening"
        case .seed: return "leaf"
        case .art: return "paintpalette"
        case .tile: return "square.grid.2x2"
        }
    }
}

public enum SmartCapture {
    /// The choices that make sense for what was shared.
    public static func available(kind: String, url: String?) -> [CaptureRoute] {
        switch kind {
        case "image": return [.art]   // an image always goes to the intake; "Board" would do the same thing
        case "url":
            var out: [CaptureRoute] = [.board]
            if let url, BackendTemplates.host(of: url) != nil { out.append(.tile) }   // a tile needs an https address
            return out
        default: return [.board, .quote, .seed]
        }
    }

    /// The likely destination, by rules and no model: an image is art; a link to a known backend site is a tile, any other link goes to
    /// the board; a short line with an attribution is a quote; a short plain line is a seed; anything longer goes to the board.
    public static func suggest(kind: String, text: String?, url: String?) -> CaptureRoute {
        switch kind {
        case "image": return .art
        case "url":
            if let url, BackendTemplates.match(url) != nil { return .tile }
            return .board
        default:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty || t.contains("http://") || t.contains("https://") { return .board }
            let words = t.split(whereSeparator: { $0.isWhitespace }).count
            if words <= 40, hasAttribution(t) { return .quote }
            if words <= 25, !t.contains("\n\n") { return .seed }
            return .board
        }
    }

    /// "line — Name" (an em dash, en dash, tilde or spaced hyphen, then a short capitalised name with no sentence punctuation).
    static func hasAttribution(_ text: String) -> Bool {
        for dash in ["—", "–", "~", " - "] {
            guard let r = text.range(of: dash, options: .backwards) else { continue }
            let head = text[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = text[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if head.count >= 12, tail.count >= 2, tail.count <= 40, tail.first?.isUppercase == true,
               !tail.contains(where: { ".!?".contains($0) }) { return true }
        }
        return false
    }

    /// The text the board receives for a seed: tagged, so a session can find and file it.
    public static func seedText(_ text: String) -> String {
        "SEED: " + text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
