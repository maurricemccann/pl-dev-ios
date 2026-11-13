import SwiftUI
import WebKit

// The site's human check (Cloudflare Turnstile) on the phone. The site's public forms ask a visitor to prove they are a person;
// that used to send every form to a Safari sheet. The widget is the site's own, loaded from Cloudflare into a small web view that
// carries the site's address as its origin (the check is bound to it), and its token comes back to a native form. The widget
// stays invisible unless Cloudflare decides a challenge is needed, exactly as on the site (`appearance: interaction-only`).
// A signed-in member needs no check: the site accepts the session as the proof (the request ballot).

struct HumanCheck: UIViewRepresentable {
    let siteKey: String
    @Binding var token: String
    @Binding var interactive: Bool
    @Binding var failed: Bool
    var generation: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "turnstile")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.isAccessibilityElement = false
        context.coordinator.generation = generation
        context.coordinator.load(web, key: siteKey)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.generation != generation {
            context.coordinator.generation = generation
            context.coordinator.load(web, key: siteKey)
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "turnstile")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: HumanCheck
        var generation = 0
        init(_ parent: HumanCheck) { self.parent = parent }

        @MainActor func load(_ web: WKWebView, key: String) {
            // the key is the site's public one; it is escaped to be safe inside the script's string
            let safe = key.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            let html = """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>html,body{margin:0;background:transparent}</style></head><body><div id="w"></div>
            <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" async defer></script>
            <script>
            function post(s){ try{ window.webkit.messageHandlers.turnstile.postMessage(s) }catch(e){} }
            var tries = 0;
            var t = setInterval(function(){
              tries++;
              if (window.turnstile) {
                clearInterval(t);
                window.turnstile.render('#w', { sitekey: '\(safe)', theme: 'light', appearance: 'interaction-only',
                  callback: function(tok){ post('ok:' + tok) },
                  'before-interactive-callback': function(){ post('show') },
                  'after-interactive-callback': function(){ post('hide') },
                  'expired-callback': function(){ post('reset') },
                  'error-callback': function(){ post('error') } });
              } else if (tries > 150) { clearInterval(t); post('error') }
            }, 100);
            </script></body></html>
            """
            web.loadHTMLString(html, baseURL: Site.base)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let s = message.body as? String else { return }
            Task { @MainActor in
                if s.hasPrefix("ok:") { parent.token = String(s.dropFirst(3)); parent.failed = false }
                else if s == "show" { parent.interactive = true }
                else if s == "hide" { parent.interactive = false }
                else if s == "reset" { parent.token = "" }
                else if s == "error" { parent.token = ""; parent.failed = true }
            }
        }
    }
}

/// The check, with its own words: invisible when Cloudflare is satisfied, a small box when it is not, a retry when it did not load.
/// `siteKey` empty means the site runs without a check (it fails open by design), so nothing is shown.
struct HumanGate: View {
    let siteKey: String
    @Binding var token: String
    @Binding var generation: Int
    @State private var interactive = false
    @State private var failed = false

    var body: some View {
        if !siteKey.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HumanCheck(siteKey: siteKey, token: $token, interactive: $interactive, failed: $failed, generation: generation)
                    .frame(width: 300, height: interactive ? 70 : 1)
                    .opacity(interactive ? 1 : 0.01)
                    .accessibilityHidden(!interactive)
                if failed {
                    Button { failed = false; generation += 1 } label: { Text("The human check did not load. Try again.").siteLabel(10).frame(minHeight: 44, alignment: .leading) }
                        .buttonStyle(.plain)
                } else if token.isEmpty && !interactive {
                    Text("Checking that you are a person\u{2026}").siteLabel(10)
                }
            }
        }
    }
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
