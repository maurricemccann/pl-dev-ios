import SwiftUI
import UIKit
import WebKit
import CryptoKit

/// One backend site in its own web view (Plans/SPEC — PL DEV BACKEND PAGE (S348)).
/// Rules: its own persistent data store per tile (the sign-in is kept, and one site never sees another's); no script bridge to the app,
/// so no page can reach a key; navigation stays on the tile's own sites (`BackendTemplates.allows`), anything else opens in Safari.
@MainActor final class BackendWebController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    private(set) var template: BackendTemplate
    let webView: WKWebView
    @Published var blocked: URL?   // a redirect or popup to a site this tile does not allow: shown with Allow here / Safari
    @Published var title = ""
    @Published var canGoBack = false
    @Published var isLoading = false

    init(template: BackendTemplate) {
        self.template = template
        let config = WKWebViewConfiguration()
        // ONE shared store for every tile (his ask 11-14: "a one time Google login for all accounts"): sign in to Google once and each site's
        // "Continue with Google" is one tap. Cookies stay scoped to their own site, so tiles still cannot read each other's sign-in.
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.storeID("shared"))
        // Google refuses sign-in in a web view that does not identify as Safari ("disallowed_useragent"); this is the standard Safari-style suffix.
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    /// A fixed id for a store name, so it always gets the same saved sign-in.
    static func storeID(_ tileID: String) -> UUID {
        let d = Array(SHA256.hash(data: Data(("pldev.backend." + tileID).utf8)))
        return UUID(uuid: (d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11], d[12], d[13], d[14], d[15]))
    }

    func loadStart() {
        guard webView.url == nil, let url = URL(string: template.startURL), url.scheme?.lowercased() == "https" else { return }
        webView.load(URLRequest(url: url))
    }

    private func sync(_ w: WKWebView) {
        title = w.title ?? ""
        canGoBack = w.canGoBack
        isLoading = w.isLoading
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { sync(webView) }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { sync(webView) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { sync(webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { sync(webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { sync(webView) }

    /// His "Allow here": the site joins this tile for good, and the blocked page loads.
    func allowBlocked() {
        guard let url = blocked, let host = url.host else { return }
        template = BackendStore.shared.allow(host: host, in: template.id) ?? template.allowing(host)
        blocked = nil
        webView.load(URLRequest(url: url))
    }

    func openBlockedInSafari() {
        guard let url = blocked else { return }
        blocked = nil
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func goBack() { webView.goBack() }
    func reload() { webView.reload() }

    // MARK: navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" || scheme == "blob" || scheme == "data" { return .allow }   // frames and downloads inside a page
        guard scheme == "https" else { return .cancel }                                   // no http, no custom schemes, no javascript:
        if navigationAction.targetFrame?.isMainFrame == false { return .allow }           // a frame inside the page (a captcha, a payment form)
        if let host = url.host, BackendTemplates.allows(host, for: template) { return .allow }
        if navigationAction.navigationType == .linkActivated {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)            // a link he tapped to another site opens in Safari
        } else {
            blocked = url                                                                   // a redirect (a sign-in hop): ask, do not drop him out of the app
        }
        return .cancel
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank and window.open: stay in this view when it is the tile's own site, else Safari
        if let url = navigationAction.request.url, url.scheme?.lowercased() == "https", let host = url.host {
            if BackendTemplates.allows(host, for: template) { webView.load(navigationAction.request) } else { blocked = url }
        }
        return nil
    }
}

struct BackendWebView: UIViewRepresentable {
    let controller: BackendWebController
    func makeUIView(context: Context) -> WKWebView { controller.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// The tile opened full screen: a bar with Home, Back and Reload, then the site.
struct BackendWebScreen: View {
    let template: BackendTemplate
    @StateObject private var web: BackendWebController
    @Environment(\.dismiss) private var dismiss

    init(template: BackendTemplate) {
        self.template = template
        _web = StateObject(wrappedValue: BackendWebController(template: template))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { dismiss() } label: { Image(systemName: "house").font(Font.pl(.title3)) }
                    .accessibilityLabel("Home")
                Button { web.goBack() } label: { Image(systemName: "chevron.backward").font(Font.pl(.title3)) }
                    .disabled(!web.canGoBack)
                    .accessibilityLabel("Back")
                Text(web.title.isEmpty ? template.name : web.title)
                    .font(Font.pl(.subheadline).weight(.semibold)).lineLimit(1).frame(maxWidth: .infinity)
                if web.isLoading { ProgressView().controlSize(.small) }
                Button { web.reload() } label: { Image(systemName: "arrow.clockwise").font(Font.pl(.title3)) }
                    .accessibilityLabel("Reload")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.bar)
            if let url = web.blocked {
                HStack(spacing: 10) {
                    Text("Blocked a redirect to \(url.host ?? "another site").").font(Font.pl(.footnote)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Allow here") { web.allowBlocked() }.buttonStyle(.borderedProminent)
                    Button("Safari") { web.openBlockedInSafari() }.buttonStyle(.bordered)
                    Button { web.blocked = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss")
                }
                .controlSize(.small)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.thinMaterial)
            }
            BackendWebView(controller: web)
        }
        .task { web.loadStart() }
    }
}
