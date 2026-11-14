import SafariServices
import SwiftUI

/// The public site's calls, from the phone (lane A). Everything goes to the config's "site" origin. The site's own session
/// cookie is carried by hand (no cookie jar), so it can be kept in the Keychain and survives a relaunch. No console key is
/// involved: this is the same door the website uses, and what a visitor or a member could do there.
@MainActor enum Site {
    struct Reply {
        let status: Int
        let data: Data
        let cookies: [String: String]
        var json: [String: Any]? { try? JSONSerialization.jsonObject(with: data) as? [String: Any] }
        /// The site's own sentence for a refusal, when it sent one.
        var message: String? { (json?["message"] as? String) ?? (json?["error"] as? String) }
        var ok: Bool { (200..<300).contains(status) && (json?["ok"] as? Bool) != false }
    }

    enum Problem: LocalizedError {
        case notSetUp, unreachable, refused(String)
        var errorDescription: String? {
            switch self {
            case .notSetUp: return "Your config has no address for the site yet."
            case .unreachable: return "The site did not answer. Check your connection."
            case .refused(let why): return why
            }
        }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.timeoutIntervalForRequest = 25
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// The site's address from the loaded config, or nil.
    static var base: URL? {
        AppModel.shared.config?.origin("site").flatMap { URL(string: $0.base) }
    }

    /// An absolute URL on the site, for pages that open in Safari or get shared.
    static func page(_ path: String) -> URL? {
        guard let base else { return nil }
        let rel = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: rel, relativeTo: base)?.absoluteURL
    }

    static func call(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil, timeout: TimeInterval = 25) async throws -> Reply {
        guard let base else { throw Problem.notSetUp }
        let rel = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var comps = URLComponents(url: base.appendingPathComponent(rel), resolvingAgainstBaseURL: false) else { throw Problem.notSetUp }
        if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = comps.url else { throw Problem.notSetUp }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "accept")
        if let token = SiteAccount.shared.token { req.setValue("pl_session=\(token)", forHTTPHeaderField: "cookie") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw Problem.unreachable }
            var cookies: [String: String] = [:]
            if let fields = http.allHeaderFields as? [String: String] {
                for c in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) { cookies[c.name] = c.value }
            }
            return Reply(status: http.statusCode, data: data, cookies: cookies)
        } catch let p as Problem { throw p }
        catch { throw Problem.unreachable }
    }

    /// A read that decodes straight into the screen's type. A 401 on a members' route clears the saved session.
    static func get<T: Decodable>(_ path: String, _ type: T.Type, query: [String: String] = [:]) async throws -> T {
        // Offline for every app: the last answer is kept on the phone (signed-in and signed-out answers kept apart)
        // and served when the site cannot be reached or errs.
        let key = "site|\(SiteAccount.shared.token == nil ? "anon" : "member")|" + path + "?" + query.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        let data: Data
        do {
            let r = try await call("GET", path, query: query)
            if r.status == 401 { SiteAccount.shared.expire() }
            if r.status >= 500, let (saved, at) = OfflineCache.load(key) { OfflineState.servedCopy(from: at); data = saved }
            else {
                guard (200..<300).contains(r.status) else { throw Problem.refused(r.message ?? "The site could not answer that. Pull to try again.") }
                OfflineCache.save(r.data, for: key); data = r.data
            }
        } catch Problem.unreachable {
            guard let (saved, at) = OfflineCache.load(key) else { throw Problem.unreachable }
            OfflineState.servedCopy(from: at); data = saved
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw Problem.refused("The site answered in a shape this app does not know yet.") }
    }

    /// A write. Throws with the site's own sentence when it says no.
    @discardableResult
    static func post(_ path: String, _ body: [String: Any]) async throws -> Reply {
        let r = try await call("POST", path, body: body)
        if r.status == 401 { SiteAccount.shared.expire() }
        guard r.ok else { throw Problem.refused(r.message ?? "The site said no.") }
        return r
    }
}

/// The signed-in member, if any. The site's sign-in is email and password (its Google sign-in and sign-up need a browser, so
/// those open the site in a sheet). The session token lives in the Keychain, never on screen.
@MainActor @Observable final class SiteAccount {
    static let shared = SiteAccount()

    struct Me: Decodable, Equatable {
        let authenticated: Bool
        let email: String?
        let glyph: String?
        let pointsTier: String?
        let points: Int?
        let firstName: String?
        let brandColor: String?
        let handle: String?
        let isFounder: Bool?
        let isBeta: Bool?
    }

    private static let keyName = "site.session"
    private(set) var token: String?
    var me: Me?
    var checked = false

    var signedIn: Bool { me?.authenticated == true }
    var isFounder: Bool { me?.isFounder == true }

    private init() {
        if let d = KeyStore.load(account: Self.keyName), let t = String(data: d, encoding: .utf8), !t.isEmpty { token = t }
    }

    /// Asks the site who the saved session belongs to.
    func refresh() async {
        guard token != nil else { me = nil; checked = true; return }
        if let m = try? await Site.get("api/auth/me", Me.self) { me = m.authenticated ? m : nil; if !m.authenticated { expire() } }
        checked = true
    }

    /// Nil on success, else the site's sentence.
    func signIn(email: String, password: String) async -> String? {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, !password.isEmpty else { return "Enter your email and password." }
        do {
            let r = try await Site.call("POST", "api/auth/signin", body: ["email": e, "password": password])
            guard r.ok else { return r.message ?? "That did not work." }
            guard let t = r.cookies["pl_session"], !t.isEmpty else { return "The site signed you in but sent no session. Try again." }
            token = t
            try? KeyStore.save(Data(t.utf8), account: Self.keyName)
            await refresh()
            return signedIn ? nil : "The site did not recognise the session. Try again."
        } catch { return error.localizedDescription }
    }

    /// Google sign-in, his usual way in (11-14): the site ran Google and sent back pldev://auth?code=… ; swap that one-time
    /// code (2 minutes, works once) for this phone's own session. Nil on success, else the site's sentence.
    func finishGoogle(callback: URL) async -> String? {
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { return "Google did not finish. Try again." }
        do {
            let r = try await Site.call("POST", "api/auth/app-exchange", body: ["code": code])
            guard r.ok else { return r.message ?? "That did not work." }
            guard let t = r.cookies["pl_session"], !t.isEmpty else { return "The site signed you in but sent no session. Try again." }
            token = t
            try? KeyStore.save(Data(t.utf8), account: Self.keyName)
            await refresh()
            return signedIn ? nil : "The site did not recognise the session. Try again."
        } catch { return error.localizedDescription }
    }

    func signOut() async {
        _ = try? await Site.call("POST", "api/auth/logout")
        expire()
    }

    /// The session is gone (signed out, or the site refused it).
    func expire() {
        token = nil
        me = nil
        KeyStore.delete(account: Self.keyName)
    }
}

/// A page of the site in Apple's own browser sheet. Used where the site needs a human check or a payment page (checkout,
/// sign-up, the signal form, voting), which a native screen cannot do for it.
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// A page waiting to open in `SafariSheet`; `.sheet(item:)` needs something Identifiable.
struct WebPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
    init(_ url: URL) { self.url = url }
}
