import Foundation

/// Where a shared item can go (Plans/SPEC — PL DEV SMART CAPTURE (S348), his words 11-14). Plain logic only, tested on Linux in CI.
public enum CaptureRoute: String, CaseIterable, Identifiable, Sendable {
    case board   // the board's inbox, for Claude
    case quote   // the intake as a quote
    case seed    // the board's inbox, tagged SEED (his ruling 11-14: seeds go to the board inbox; a session files them)
    case art     // the intake as artwork (an image)
    case tile    // a new Backend tile (the "PWA" tile)
    case thought // raw, into the vault's THOUGHTS.md (his ruling 11-17)
    case task    // a task for a session: THOUGHTS.md tagged TASK, which /pl-open turns into a QUEUE item
    case today   // a line on the board's TODAY.md task list (capture selector, his words 11-17)
    case claude  // an item in for-claude.md, the inbox every session drains first

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .board: return "Board"
        case .quote: return "Quote"
        case .seed: return "Seed"
        case .art: return "Art"
        case .tile: return "Make a tile"
        case .thought: return "Thought"
        case .task: return "Task"
        case .today: return "Today"
        case .claude: return "For Claude"
        }
    }

    public var symbol: String {
        switch self {
        case .board: return "tray.and.arrow.up"
        case .quote: return "quote.opening"
        case .seed: return "leaf"
        case .art: return "paintpalette"
        case .tile: return "square.grid.2x2"
        case .thought: return "bubble.left"
        case .task: return "checklist"
        case .today: return "sun.max"
        case .claude: return "text.bubble"
        }
    }

    /// The Obsidian note this route writes to, or nil when it goes elsewhere (the board, the intake, the Backend page).
    /// A vault route draws in the house violet instead of gold; its note has a live view on the phone.
    public var vaultNote: VaultNote? {
        switch self {
        case .thought, .task: return VaultNote(key: "thoughts", file: "THOUGHTS.md")
        case .today: return VaultNote(key: "today", file: "TODAY.md")
        case .claude: return VaultNote(key: "claude", file: "for-claude.md")
        default: return nil
        }
    }

    public var isVault: Bool { vaultNote != nil }

    /// What pl-cron's `/api/widget/capture` is sent for a vault route: the source, and the target note's key when the route is not one of the two original ones.
    public var wire: (source: String, target: String?)? {
        switch self {
        case .thought: return ("pl-thought", nil)
        case .task: return ("pl-task", nil)
        case .today: return ("pl-note", "today")
        case .claude: return ("pl-note", "claude")
        default: return nil
        }
    }

    /// The route a queued item's kind names, when that kind is a vault route.
    public static func vault(kind: String) -> CaptureRoute? {
        guard let r = CaptureRoute(rawValue: kind), r.isVault else { return nil }
        return r
    }
}

/// A vault note he can capture into. `key` is the target pl-cron and the PC sync use; `file` is for his eyes.
public struct VaultNote: Equatable, Sendable {
    public let key: String
    public let file: String
}

public enum SmartCapture {
    /// The choices that make sense for what was shared.
    /// `hasText`: a link that also carries text he highlighted on the page, which can be a quote or a seed.
    public static func available(kind: String, url: String?, hasText: Bool = false) -> [CaptureRoute] {
        switch kind {
        case "image": return [.art]   // an image always goes to the intake; "Board" would do the same thing
        case "url":
            var out: [CaptureRoute] = [.board]
            if hasText { out += [.quote, .seed] }
            if let url, BackendTemplates.host(of: url) != nil { out.append(.tile) }   // a tile needs an https address
            return out + [.thought, .task, .today, .claude]
        default: return [.board, .quote, .seed, .thought, .task, .today, .claude]
        }
    }

    /// The likely destination, by rules and no model: an image is art; a link to a known backend site is a tile, any other link goes to
    /// the board; a short line with an attribution is a quote; a short plain line is a seed; anything longer goes to the board.
    public static func suggest(kind: String, text: String?, url: String?) -> CaptureRoute {
        switch kind {
        case "image": return .art
        case "url":
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return suggest(kind: "text", text: t, url: nil) }   // text highlighted on the page leads, as a quote, a seed or the board
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
