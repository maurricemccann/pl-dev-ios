import Foundation

public enum Readiness: Sendable, Equatable {
    case ready
    case missingKeys([String])
    case missingOrigins([String])
    case notListed
}

/// What a section declares about itself: pure data, no UI.
public struct SectionManifest: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var symbol: String          // SF Symbol name
    public var needsKeys: [String]
    public var needsOrigins: [String]

    public init(id: String, title: String, symbol: String, needsKeys: [String] = [], needsOrigins: [String] = []) {
        self.id = id; self.title = title; self.symbol = symbol
        self.needsKeys = needsKeys; self.needsOrigins = needsOrigins
    }

    /// Order of checks: not listed, then origins, then keys.
    public func readiness(in config: PLDevConfig) -> Readiness {
        guard config.sections.contains(id) else { return .notListed }
        let noOrigins = needsOrigins.filter { config.origin($0) == nil }
        if !noOrigins.isEmpty { return .missingOrigins(noOrigins) }
        let noKeys = needsKeys.filter { config.key($0) == nil }
        if !noKeys.isEmpty { return .missingKeys(noKeys) }
        return .ready
    }
}
