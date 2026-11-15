import SwiftUI
import UIKit
import WebKit
import CryptoKit

/// One backend site in its own web view (Plans/SPEC — PL DEV BACKEND PAGE (S348)).
/// Rules: its own persistent data store per tile (the sign-in is kept, and one site never sees another's); no script bridge to the app,
/// so no page can reach a key; navigation stays on the tile's own sites (`BackendTemplates.allows`), anything else opens in Safari.
@MainActor final class BackendWebController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let template: BackendTemplate
    let webView: WKWebView
    @Published var title = ""
    @Published var canGoBack = false
    @Published var isLoading = false

    init(template: BackendTemplate) {
        self.template = template
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.storeID(template.id))
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    /// A fixed id per tile, so the same tile always gets the same saved sign-in.
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
        UIApplication.shared.open(url, options: [:], completionHandler: nil)                // a page on another site opens in Safari
        return .cancel
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank and window.open: stay in this view when it is the tile's own site, else Safari
        if let url = navigationAction.request.url, url.scheme?.lowercased() == "https", let host = url.host {
            if BackendTemplates.allows(host, for: template) { webView.load(navigationAction.request) } else { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
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
                Button { dismiss() } label: { Image(systemName: "house").font(.title3) }
                    .accessibilityLabel("Home")
                Button { web.goBack() } label: { Image(systemName: "chevron.backward").font(.title3) }
                    .disabled(!web.canGoBack)
                    .accessibilityLabel("Back")
                Text(web.title.isEmpty ? template.name : web.title)
                    .font(.subheadline.weight(.semibold)).lineLimit(1).frame(maxWidth: .infinity)
                if web.isLoading { ProgressView().controlSize(.small) }
                Button { web.reload() } label: { Image(systemName: "arrow.clockwise").font(.title3) }
                    .accessibilityLabel("Reload")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.bar)
            BackendWebView(controller: web)
        }
        .task { web.loadStart() }
    }
}
