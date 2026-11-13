import SwiftUI

/// More: the signal, order tracking, the site's status and the site's other pages.
struct ShopMoreView: View {
    let model: AppModel
    @Bindable var state: ShopModel

    var body: some View {
        List {
            Section {
                ForEach(ShopRoom.moreRooms) { room in
                    NavigationLink { room.view(model) } label: { Label(room.title, systemImage: room.symbol) }
                }
            } footer: { Text("Checkout, gift cards and the signal form run on the site, behind its human check. They open in a sheet here.") }
        }
        .siteList()
    }
}

// MARK: - The signal

struct SignalView: View {
    @State private var web: WebPage?

    var body: some View {
        List {
            Section {
                Text("The signal goes out as the work does. Sign up with an email and you are the first to see what arrives.").plReading()
                Button {
                    if let url = Site.page("transmission") { web = WebPage(url) }
                } label: { Label("Receive the signal", systemImage: "antenna.radiowaves.left.and.right").frame(minHeight: PLMetric.touch) }
            } footer: { Text("The form opens on the site, which checks a person is signing up.") }
        }
        .siteList()
        .plScreenTitle("The signal")
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }
}

// MARK: - Track an order (no account: email and order number, as the site's own page does)

struct TrackOrderView: View {
    @State private var email = ""
    @State private var orderId = ""
    @State private var busy = false
    @State private var result: Found?
    @State private var line: String?
    @State private var web: WebPage?

    struct Found: Decodable {
        let status: String?
        let createdAt: String?
        let total: String?
        let currency: String?
        let trackingNumber: String?
        let carrier: String?
        let trackingUrl: String?
        let shippedAt: String?
        let deliveredAt: String?
    }

    var body: some View {
        Form {
            Section {
                TextField("Email on the order", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Order number", text: $orderId).textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button { Task { await look() } } label: {
                    HStack { Text("Look it up"); if busy { Spacer(); ProgressView() } }.frame(minHeight: PLMetric.touch)
                }
                .disabled(busy || email.isEmpty || orderId.isEmpty)
                ResultLine(text: line)
            } footer: { Text("The order number is in the confirmation email.") }
            if let r = result {
                Section {
                    OrderTracker(step: OrderStep.reached(status: r.status, shipped: r.shippedAt, delivered: r.deliveredAt, tracking: r.trackingNumber)).padding(.vertical, 8)
                }
                Section("Your order") {
                    LabeledContent("Status", value: (r.status ?? "processing").capitalized)
                    if let t = r.total { LabeledContent("Total", value: Money.text(Int(((Double(t) ?? 0) * 100).rounded()))) }
                    if let c = r.createdAt { LabeledContent("Placed") { Ago(text: c) } }
                    if let c = r.carrier { LabeledContent("Carrier", value: c) }
                    if let n = r.trackingNumber { LabeledContent("Tracking", value: n).textSelection(.enabled) }
                    if let s = r.shippedAt { LabeledContent("Shipped") { Ago(text: s) } }
                    if let d = r.deliveredAt { LabeledContent("Delivered") { Ago(text: d) } }
                    if let u = r.trackingUrl, let url = URL(string: u), url.scheme == "https" {
                        Button { web = WebPage(url) } label: { Label("Follow it with the carrier", systemImage: "shippingbox") }
                    }
                }
            }
        }
        .siteList()
        .plScreenTitle("Track an order")
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        .sensoryFeedback(PLHaptic.success, trigger: result?.status)
    }

    private func look() async {
        busy = true; line = nil
        defer { busy = false }
        do {
            let r = try await Site.post("api/orders/lookup", ["email": email.trimmingCharacters(in: .whitespaces), "orderId": orderId.trimmingCharacters(in: .whitespaces)])
            result = try? JSONDecoder().decode(Found.self, from: r.data)
            if result == nil { line = "Not found. The site answered in a shape this app does not know." }
        } catch { result = nil; line = "Not found. \(error.localizedDescription)" }
    }
}

// MARK: - The site's status

struct SiteStatusView: View {
    struct Creator: Decodable { let status: String; let label: String; let updated: String? }
    @State private var web: WebPage?
    private let store = ShopStore.shared

    var body: some View {
        Loaded(load: { try await Site.get("api/creator-status", Creator.self) }) { c, _ in
            List {
                Section("The creator") {
                    Label(c.label, systemImage: c.status == "awake" ? "sun.max" : "moon")
                    if let u = c.updated { LabeledContent("Changed") { Ago(text: u) } }
                }
                Section("The shop") {
                    LabeledContent("Pieces listed", value: "\(store.pieces.count)")
                    LabeledContent("In stock", value: "\(store.pieces.filter(\.inStock).count) of \(store.pieces.count)")
                    if let at = store.loadedAt { LabeledContent("List read") { Text(at, format: .relative(presentation: .named)) } }
                }
                Section {
                    Button { if let url = Site.page("") { web = WebPage(url) } } label: { Label("Open psychedluxuries.com", systemImage: "safari") }
                }
            }
            .siteList()
        }
        .plScreenTitle("The site")
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
        .task { await store.load() }
    }
}

// MARK: - The site's other pages

struct SitePagesView: View {
    struct PageLink: Identifiable { let title: String; let symbol: String; let path: String; var id: String { path } }
    struct PageGroup: Identifiable { let name: String; let links: [PageLink]; var id: String { name } }
    private let groups: [PageGroup] = [
        PageGroup(name: "The house", links: [PageLink(title: "The brand", symbol: "seal", path: "the-brand"), PageLink(title: "The Three Truths", symbol: "triangle", path: "the-three-truths"),
                                             PageLink(title: "Three bodies of work", symbol: "square.stack.3d.up", path: "three-bodies"), PageLink(title: "The Forge", symbol: "hammer", path: "the-forge")]),
        PageGroup(name: "Help", links: [PageLink(title: "Contact", symbol: "envelope", path: "contact"), PageLink(title: "Gift cards", symbol: "giftcard", path: "gift-card"),
                                        PageLink(title: "Returns", symbol: "arrow.uturn.backward", path: "returns")]),
        PageGroup(name: "The fine print", links: [PageLink(title: "Terms", symbol: "doc.text", path: "terms"), PageLink(title: "Privacy", symbol: "hand.raised", path: "privacy")]),
    ]
    @State private var web: WebPage?

    var body: some View {
        List {
            ForEach(groups) { group in
                Section(group.name) {
                    ForEach(group.links) { l in
                        if l.path == "contact" {
                            NavigationLink { ContactView() } label: { Label(l.title, systemImage: l.symbol) }
                        } else if l.path == "gift-card" {   // Square's gift cards are bought through the site's checkout
                            Button { if let url = Site.page(l.path) { web = WebPage(url) } } label: { Label(l.title, systemImage: l.symbol) }
                        } else {
                            NavigationLink { SiteReaderView(path: l.path, title: l.title) } label: { Label(l.title, systemImage: l.symbol) }
                        }
                    }
                }
            }
        }
        .siteList()
        .plScreenTitle("Pages")
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }
}
