import SwiftUI
import UIKit

// The site's human check (Cloudflare Turnstile). It only runs in a browser, so on the phone it runs in Apple's secure sheet
// (`SafariSheet`) on the site's own page, never in a web view of ours (his ruling 11-13). A form that needs the check keeps what
// the visitor typed on the pasteboard and opens the matching page; a signed-in member needs no check (the session is the proof).

/// The words that tell the visitor where the check happens. Nothing is shown when the site runs without a check.
struct HumanGate: View {
    let siteKey: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if !siteKey.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.shield").foregroundStyle(Bone.gold).accessibilityHidden(true)
                Text("The site checks that you are a person. That check opens in Apple\u{2019}s secure sheet on the site\u{2019}s own page.")
                    .font(SiteFont.body(12)).foregroundStyle(Bone.inkFaint(scheme)).lineSpacing(3)
            }
        }
    }
}

extension UIPasteboard {
    /// Keeps what a visitor typed so it can be pasted on the site\u{2019}s page after the human check.
    static func keep(_ text: String) { if !text.isEmpty { UIPasteboard.general.string = text } }
}

/// The request ballot's configuration, from the site: the check's public key and the forms a piece can be asked for.
struct SiteBallot: Decodable {
    let siteKey: String?
    let products: [String]?
    let authed: Bool?
    let weeksAvailable: Int?
    let votedThisWeek: Bool?

    static let defaultProducts = ["shirt", "hoodie", "crop_top", "crop_hoodie", "sticker", "poster"]

    @MainActor static func load(email: String? = nil, cr: String? = nil) async -> SiteBallot? {
        var q: [String: String] = [:]
        if let email, !email.isEmpty { q["email"] = email }
        if let cr { q["cr"] = cr }
        return try? await Site.get("api/request", SiteBallot.self, query: q)
    }
}
