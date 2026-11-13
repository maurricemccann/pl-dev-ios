import Foundation

public enum RequestPlanError: Error, Equatable, CustomStringConvertible {
    case unknownOrigin(String)
    case badURL(String)
    case missingKey(String)

    public var description: String {
        switch self {
        case .unknownOrigin(let n): return "The config has no address named \"\(n)\"."
        case .badURL(let n): return "The address for \"\(n)\" could not be built into a request."
        case .missingKey(let k): return "The key \"\(k)\" is not set."
        }
    }
}

public struct PlannedRequest: Sendable, Equatable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?
    public var certName: String?       // the server name to accept, when it differs from the URL host

    public init(url: URL, method: String, headers: [String: String] = [:], body: Data? = nil, certName: String? = nil) {
        self.url = url; self.method = method; self.headers = headers; self.body = body; self.certName = certName
    }
}

/// A request described without URLSession, so it tests on Linux.
public struct RequestPlan: Sendable, Equatable {
    public var origin: String
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]
    public var body: Data?

    public init(origin: String, method: String = "GET", path: String = "", query: [String: String] = [:],
                headers: [String: String] = [:], body: Data? = nil) {
        self.origin = origin; self.method = method; self.path = path
        self.query = query; self.headers = headers; self.body = body
    }

    /// Primary base first, then the fallbackIp base if the origin has one.
    public func urlRequests(config: PLDevConfig) throws -> [PlannedRequest] {
        guard let o = config.origin(origin) else { throw RequestPlanError.unknownOrigin(origin) }

        var h = headers
        if let auth = o.auth {
            guard let k = config.key(auth.key) else { throw RequestPlanError.missingKey(auth.key) }
            h[auth.header] = auth.scheme.map { "\($0) \(k)" } ?? k
        }

        let rel = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var comps = URLComponents(string: o.base + rel) else { throw RequestPlanError.badURL(origin) }
        if !query.isEmpty { comps.percentEncodedQuery = Self.encodeQuery(query) }
        guard let primary = comps.url else { throw RequestPlanError.badURL(origin) }
        var out = [PlannedRequest(url: primary, method: method, headers: h, body: body, certName: o.certName)]

        if let ip = o.fallbackIp?.trimmingCharacters(in: .whitespaces), !ip.isEmpty {
            var f = comps
            f.host = ip
            if let u = f.url {
                // The certificate belongs to the name, not the address, so keep the name to check.
                out.append(PlannedRequest(url: u, method: method, headers: h, body: body, certName: o.certName ?? comps.host))
            }
        }
        return out
    }

    /// Sorted, strictly percent-encoded (unreserved characters only) so the result is the same everywhere.
    static func encodeQuery(_ q: [String: String]) -> String {
        q.sorted { $0.key < $1.key }.map { "\(PLEncode.component($0.key))=\(PLEncode.component($0.value))" }.joined(separator: "&")
    }
}

enum PLEncode {
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    static func component(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "" }
}

public enum RetryPolicy {
    public static let maxRetries = 4

    /// Seconds to wait after the given failed attempt (1-based): 1, 2, 4, 8, then capped at 15.
    public static func delay(attempt: Int) -> Double {
        if attempt <= 1 { return 1 }
        if attempt > 5 { return 15 }
        return min(15, Double(1 << (attempt - 1)))
    }

    /// `attempt` is the 1-based attempt that just failed. status nil = no response (network error).
    public static func shouldRetry(status: Int?, attempt: Int, idempotent: Bool) -> Bool {
        guard idempotent, attempt >= 1, attempt <= maxRetries else { return false }
        guard let s = status else { return true }
        return s == 408 || s == 429 || s >= 500
    }
}
