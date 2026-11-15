import Foundation

/// A backend site PL DEV opens in its own web view (Plans/SPEC — PL DEV BACKEND PAGE (S348), his rulings 11-14).
/// Plain logic only: no UIKit, no network, so it is tested on Linux in CI.
public struct BackendTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var symbol: String          // an SF Symbol name
    public var startURL: String        // empty = not set yet (the Horizon tile waits for his first Safari share, premise 4)
    public var allowedHosts: [String]  // the site itself; a host or any subdomain of one

    public init(id: String, name: String, symbol: String, startURL: String, allowedHosts: [String]) {
        self.id = id; self.name = name; self.symbol = symbol; self.startURL = startURL; self.allowedHosts = allowedHosts
    }

    public var isReady: Bool { URL(string: startURL)?.scheme?.lowercased() == "https" }

    /// The same tile with one more site allowed (his tap on "Allow here" when a sign-in bounced somewhere new).
    public func allowing(_ host: String) -> BackendTemplate {
        let h = host.lowercased()
        guard !h.isEmpty, !allowedHosts.contains(h) else { return self }
        var t = self
        t.allowedHosts.append(h)
        return t
    }
}

public enum BackendTemplates {
    /// The starting set (premise 1). Horizon's address was never guessed: he gave it 11-15 (developers.meta.com).
    public static let builtIn: [BackendTemplate] = [
        BackendTemplate(id: "cloudflare", name: "Cloudflare", symbol: "cloud", startURL: "https://dash.cloudflare.com/", allowedHosts: ["cloudflare.com"]),
        BackendTemplate(id: "printful", name: "Printful", symbol: "shippingbox", startURL: "https://www.printful.com/dashboard", allowedHosts: ["printful.com"]),
        BackendTemplate(id: "pinterest", name: "Pinterest", symbol: "pin", startURL: "https://www.pinterest.com/business/hub/", allowedHosts: ["pinterest.com", "pinimg.com"]),   // his pick N23, 11-14
        BackendTemplate(id: "horizon", name: "Meta Horizon Creator Club", symbol: "visionpro", startURL: "https://developers.meta.com/", allowedHosts: ["meta.com", "facebook.com", "oculus.com", "fb.com", "fb.me", "instagram.com", "messenger.com"]),
    ]

    /// Sign-in providers a site may bounce through, allowed in every tile so a Google, Apple, Microsoft or GitHub sign-in does not leave the app.
    /// Google's sign-in hops across google.com and youtube.com (accounts.youtube.com sets the session), so both are listed (his Cloudflare-with-Google report 11-14).
    public static let signInHosts: [String] = ["google.com", "youtube.com", "apple.com", "microsoftonline.com", "live.com", "github.com"]

    /// The lower-cased host of an https address, or nil for anything else (http, a file, no host).
    public static func host(of address: String) -> String? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let h = url.host?.lowercased(), !h.isEmpty else { return nil }
        return h
    }

    /// True when the host is one of the tile's sites (or a subdomain of one) or a sign-in provider.
    /// A host that merely ends in the same letters (evil-cloudflare.com) is refused: the match is on a dot boundary.
    public static func allows(_ host: String, for template: BackendTemplate) -> Bool {
        let h = host.lowercased()
        return (template.allowedHosts + signInHosts).contains { h == $0 || h.hasSuffix("." + $0) }
    }

    /// The built-in tile whose site this address belongs to.
    public static func match(_ address: String) -> BackendTemplate? {
        guard let h = host(of: address) else { return nil }
        return builtIn.first { t in t.allowedHosts.contains { h == $0 || h.hasSuffix("." + $0) } }
    }

    /// A tile for any other https page he shares: named from the page title (else the host), starting at that page, limited to its host.
    public static func custom(address: String, title: String?) -> BackendTemplate? {
        guard let h = host(of: address) else { return nil }
        let base = h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
        let clean = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return BackendTemplate(id: "custom-" + base, name: clean.isEmpty ? base : String(clean.prefix(40)), symbol: "globe",
                               startURL: address.trimmingCharacters(in: .whitespacesAndNewlines), allowedHosts: [base])
    }

    /// A saved list read back after an update: each built-in tile takes the current name, symbol and allowed sites from the code
    /// (keeping any extra site he allowed and any address he set); tiles he added are kept as they are.
    /// Built-ins added in a later version show up once for a phone that saved its tiles before them; one he removed stays removed.
    public static func addingNew(_ tiles: [BackendTemplate], seen: Set<String>) -> [BackendTemplate] {
        tiles + builtIn.filter { b in !seen.contains(b.id) && !tiles.contains { $0.id == b.id } }
    }

    public static func refreshed(_ saved: [BackendTemplate]) -> [BackendTemplate] {
        saved.map { s in
            guard let code = builtIn.first(where: { $0.id == s.id }) else { return s }
            var t = code
            t.startURL = s.isReady ? s.startURL : code.startURL
            for h in s.allowedHosts where !t.allowedHosts.contains(h) { t.allowedHosts.append(h) }
            return t
        }
    }

    /// The template an address should become: its built-in one with that address as the start (when the built-in has none yet),
    /// else a custom one. Nil when the address is not https.
    public static func template(for address: String, title: String?) -> BackendTemplate? {
        guard host(of: address) != nil else { return nil }
        if var t = match(address) {
            if !t.isReady { t.startURL = address.trimmingCharacters(in: .whitespacesAndNewlines) }
            return t
        }
        return custom(address: address, title: title)
    }
}
