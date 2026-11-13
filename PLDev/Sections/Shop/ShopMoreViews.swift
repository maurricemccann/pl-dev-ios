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
            } footer: { Text("Checkout, sign-up and the signal form run on the site, behind its human check. They open in a sheet here.") }
        }
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

// MARK: - His orders (the signed-in account's own)

struct MyOrdersView: View {
    struct Order: Decodable, Identifiable {
        let friendlyId: String?
        let status: String?
        let total: Double?
        let currency: String?
        let createdAt: String?
        let itemName: String?
        let itemImage: String?
        let itemCount: Int?
        let trackingNumber: String?
        let carrier: String?
        let trackingUrl: String?
        let shippedAt: String?
        let deliveredAt: String?
        var id: String { friendlyId ?? createdAt ?? UUID().uuidString }
    }
    struct Orders: Decodable { let orders: [Order] }
    @State private var web: WebPage?
    private let account = SiteAccount.shared

    var body: some View {
        Group {
            if account.signedIn {
                Loaded(load: { try await Site.get("api/account/orders", Orders.self).orders }) { orders, _ in
                    List {
                        if orders.isEmpty { ContentUnavailableView("No orders yet", systemImage: "shippingbox", description: Text("Orders placed with this account appear here.")).listRowBackground(Color.clear) }
                        ForEach(orders) { o in
                            HStack(spacing: PLSpace.pad) {
                                Color.clear.frame(width: 56, height: 56).overlay { FlatImage(url: o.itemImage.flatMap { ShopCatalogue.isFlat($0) ? URL(string: $0) : nil }, padding: 2) }
                                    .background(PLTone.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(o.itemName ?? "Order \(o.friendlyId ?? "")").plFont(.headline)
                                    Text(status(o)).plFont(.footnote).foregroundStyle(.secondary)
                                    HStack(spacing: 4) {
                                        if let t = o.total { Text(Money.text(Int((t * 100).rounded()))).monospacedDigit() }
                                        Text("·"); Ago(text: o.createdAt)
                                    }.plFont(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .swipeActions(edge: .trailing) {
                                if let u = o.trackingUrl, let url = URL(string: u), url.scheme == "https" {
                                    Button("Track") { web = WebPage(url) }.tint(.blue)
                                }
                            }
                        }
                    }
                }
            } else {
                EmptyNote(symbol: "person.crop.circle", title: "Sign in to see your orders", detail: "Orders placed with your site account show here. Sign in from the Congregation.")
            }
        }
        .plScreenTitle("Your orders")
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }

    private func status(_ o: Order) -> String {
        if o.deliveredAt != nil { return "Delivered" }
        if o.shippedAt != nil { return "Shipped" + (o.carrier.map { " with \($0)" } ?? "") }
        return (o.status ?? "Processing").capitalized
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
                        Button { if let url = Site.page(l.path) { web = WebPage(url) } } label: { Label(l.title, systemImage: l.symbol) }
                    }
                }
            }
        }
        .plScreenTitle("Pages")
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }
}
