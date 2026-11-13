import Foundation

/// pldev://section/<id>/<path...>?k=v, pldev://settings, pldev://home
public enum DeepLink: Sendable, Equatable {
    case section(id: String, path: [String], query: [String: String])
    case settings
    case home

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "pldev",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host?.lowercased() else { return nil }
        switch host {
        case "home": self = .home
        case "settings": self = .settings
        case "section":
            let segs = comps.percentEncodedPath.split(separator: "/").compactMap { String($0).removingPercentEncoding }
            guard let id = segs.first, !id.isEmpty else { return nil }
            var q: [String: String] = [:]
            for item in comps.queryItems ?? [] { q[item.name] = item.value ?? "" }
            self = .section(id: id, path: Array(segs.dropFirst()), query: q)
        default: return nil
        }
    }

    public var url: URL {
        let s: String
        switch self {
        case .home: s = "pldev://home"
        case .settings: s = "pldev://settings"
        case .section(let id, let path, let query):
            var out = "pldev://section/" + ([id] + path).map(PLEncode.component).joined(separator: "/")
            if !query.isEmpty { out += "?" + RequestPlan.encodeQuery(query) }
            s = out
        }
        return URL(string: s) ?? URL(string: "pldev://home")!   // the fallback literal is always valid
    }
}
