import Foundation

/// The one config file the owner loads at run time. Every address and key lives here, never in source.
public struct PLDevConfig: Codable, Sendable, Equatable {
    public var v: Int
    public var sections: [String]
    public var origins: [String: Origin]
    public var keys: [String: String]
    public var theme: Theme?
    public var capture: Capture?
    public var slash: [Slash]?
    public var words: [String]?

    public struct Origin: Codable, Sendable, Equatable {
        public var base: String
        public var certName: String?
        public var fallbackIp: String?      // an IPv4 address or host name, no port
        public var auth: Auth?
        public struct Auth: Codable, Sendable, Equatable {
            public var key: String          // a name in `keys`
            public var header: String
            public var scheme: String?      // "Bearer", or nil for a bare header value
            public init(key: String, header: String, scheme: String? = nil) {
                self.key = key; self.header = header; self.scheme = scheme
            }
        }
        public init(base: String, certName: String? = nil, fallbackIp: String? = nil, auth: Auth? = nil) {
            self.base = base; self.certName = certName; self.fallbackIp = fallbackIp; self.auth = auth
        }
    }

    public struct Theme: Codable, Sendable, Equatable {
        public var fontFamily: String?
        public var palette: String?
        public var handTitle: Bool?
        public init(fontFamily: String? = nil, palette: String? = nil, handTitle: Bool? = nil) {
            self.fontFamily = fontFamily; self.palette = palette; self.handTitle = handTitle
        }
    }

    public struct Capture: Codable, Sendable, Equatable {
        public var defaultTarget: String?
        public init(defaultTarget: String? = nil) { self.defaultTarget = defaultTarget }
    }

    public struct Slash: Codable, Sendable, Equatable {
        public var label: String
        public var send: String
        public init(label: String, send: String) { self.label = label; self.send = send }
    }

    public init(v: Int = 1, sections: [String], origins: [String: Origin] = [:], keys: [String: String] = [:],
                theme: Theme? = nil, capture: Capture? = nil, slash: [Slash]? = nil, words: [String]? = nil) {
        self.v = v; self.sections = sections; self.origins = origins; self.keys = keys
        self.theme = theme; self.capture = capture; self.slash = slash; self.words = words
    }

    // Custom decode so a config without origins or keys still loads and fails on the real rule instead.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decode(Int.self, forKey: .v)
        sections = try c.decodeIfPresent([String].self, forKey: .sections) ?? []
        origins = try c.decodeIfPresent([String: Origin].self, forKey: .origins) ?? [:]
        keys = try c.decodeIfPresent([String: String].self, forKey: .keys) ?? [:]
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme)
        capture = try c.decodeIfPresent(Capture.self, forKey: .capture)
        slash = try c.decodeIfPresent([Slash].self, forKey: .slash)
        words = try c.decodeIfPresent([String].self, forKey: .words)
    }

    public static func load(_ data: Data) throws -> PLDevConfig {
        var c: PLDevConfig
        do { c = try JSONDecoder().decode(PLDevConfig.self, from: data) } catch { throw ConfigError.notJSON }
        guard c.v == 1 else { throw ConfigError.wrongVersion(c.v) }
        guard !c.sections.isEmpty else { throw ConfigError.emptySections }
        for (name, origin) in c.origins.sorted(by: { $0.key < $1.key }) {
            var o = origin
            o.base = o.base.trimmingCharacters(in: .whitespacesAndNewlines)
            guard o.base.lowercased().hasPrefix("https://") else { throw ConfigError.originNotHTTPS(name) }
            if !o.base.hasSuffix("/") { o.base += "/" }
            if let auth = o.auth, c.keys[auth.key] == nil {
                throw ConfigError.unknownAuthKey(origin: name, key: auth.key)
            }
            c.origins[name] = o
        }
        return c
    }

    /// A key's value, or nil when it is missing or blank.
    public func key(_ name: String) -> String? {
        guard let k = keys[name], !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return k
    }

    public func origin(_ name: String) -> Origin? { origins[name] }

    /// The only form ever written to the App Group: same config, no key values.
    public var publicCopy: PLDevConfig {
        var c = self
        c.keys = [:]
        return c
    }
}

public enum ConfigError: Error, Equatable, CustomStringConvertible {
    case notJSON
    case wrongVersion(Int)
    case originNotHTTPS(String)
    case emptySections
    case unknownAuthKey(origin: String, key: String)

    public var description: String {
        switch self {
        case .notJSON: return "That file is not a PL DEV config. It needs to be a JSON file."
        case .wrongVersion(let n): return "This config is version \(n); this app reads version 1."
        case .originNotHTTPS(let name): return "The address for \"\(name)\" must start with https://."
        case .emptySections: return "The config lists no sections, so there is nothing to show."
        case .unknownAuthKey(let origin, let key): return "The address \"\(origin)\" asks for a key named \"\(key)\" that the config does not hold."
        }
    }
}
