import SwiftUI

// Orders: the signed-in account's list, one order in full (`/orders/<id>`: the tracker, the line items, the totals, where it ships),
// and the tracker itself, which the guest lookup shows too. The detail reads `api/account/orders/<id>`, session-gated, exactly as the
// site's page does; line items and the address come from Square on the site's side.

/// A number the site sends as a number or as a string.
struct FlexNumber: Decodable {
    let value: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let x = try? c.decode(Double.self) { value = x }
        else if let s = try? c.decode(String.self), let x = Double(s) { value = x }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a number") }
    }
}

enum OrderStep {
    static let names = ["Confirmed", "In production", "Shipped", "Delivered"]

    /// The step an order has reached (the site's `stepIndex`).
    static func reached(status: String?, shipped: String?, delivered: String?, tracking: String?) -> Int {
        if delivered != nil { return 3 }
        if shipped != nil || tracking != nil { return 2 }
        let s = (status ?? "").uppercased()
        if s.range(of: "SHIP|DELIVER", options: .regularExpression) != nil { return 2 }
        if s.range(of: "PRODUCTION|PREPAR|COMPLETE|CONFIRM", options: .regularExpression) != nil { return 1 }
        return 0
    }
}

/// Four dots on a hairline, the reached ones gold, as the site draws them.
struct OrderTracker: View {
    let step: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            // the hairline runs from the first dot's centre to the last one's, gold as far as the step reached
            GeometryReader { g in
                let w = g.size.width / CGFloat(OrderStep.names.count)
                Rectangle().fill(Bone.line(scheme)).frame(width: w * CGFloat(OrderStep.names.count - 1), height: 1).offset(x: w / 2, y: 5)
                Rectangle().fill(Bone.gold).frame(width: w * CGFloat(step), height: 1).offset(x: w / 2, y: 5)
            }
            .frame(height: 11)
            HStack(alignment: .top, spacing: 0) {
                ForEach(OrderStep.names.indices, id: \.self) { i in
                    VStack(spacing: 8) {
                        Circle().fill(i <= step ? Bone.gold : Bone.line(scheme)).frame(width: 11, height: 11)
                        Text(OrderStep.names[i]).font(SiteFont.body(11, relativeTo: .caption)).textCase(.uppercase).tracking(0.6)
                            .foregroundStyle(i <= step ? Bone.ink(scheme) : Bone.inkFaint(scheme)).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Order status: \(OrderStep.names[step]), step \(step + 1) of \(OrderStep.names.count)")
    }
}

// MARK: - His orders

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
                            NavigationLink { OrderDetailView(id: o.friendlyId ?? "") } label: { row(o) }
                                .disabled(o.friendlyId == nil)
                                .swipeActions(edge: .trailing) {
                                    if let u = o.trackingUrl, let url = URL(string: u), url.scheme == "https" {
                                        Button("Track") { web = WebPage(url) }.tint(.blue)
                                    }
                                }
                        }
                    }
                    .siteList()
                }
            } else {
                EmptyNote(symbol: "person.crop.circle", title: "Sign in to see your orders", detail: "Orders placed with your site account show here. Sign in from the Congregation.")
            }
        }
        .plScreenTitle("Your orders")
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }

    private func row(_ o: Order) -> some View {
        HStack(spacing: PLSpace.pad) {
            Color.clear.frame(width: 56, height: 56).overlay { FlatImage(url: o.itemImage.flatMap { ShopCatalogue.isFlat($0) ? URL(string: $0) : nil }, padding: 2) }
                .background(Bone.line(.light).opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(o.itemName ?? "Order \(o.friendlyId ?? "")").plFont(.headline)
                Text(status(o)).plFont(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    if let t = o.total { Text(Money.text(Int((t * 100).rounded()))).monospacedDigit() }
                    Text("\u{00B7}"); Ago(text: o.createdAt)
                }.plFont(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func status(_ o: Order) -> String {
        if o.deliveredAt != nil { return "Delivered" }
        if o.shippedAt != nil { return "Shipped" + (o.carrier.map { " with \($0)" } ?? "") }
        return (o.status ?? "Processing").capitalized
    }
}

// MARK: - One order

struct OrderDetailView: View {
    let id: String

    struct Line: Decodable, Identifiable {
        let name: String
        let variation: String?
        let quantity: String?
        let amount: Int?
        var id: String { name + (variation ?? "") }
    }
    struct Address: Decodable {
        let name: String?
        let line1: String?
        let line2: String?
        let city: String?
        let state: String?
        let zip: String?
    }
    struct Detail: Decodable {
        let id: String
        let status: String?
        let total: FlexNumber?
        let createdAt: String?
        let trackingNumber: String?
        let carrier: String?
        let trackingUrl: String?
        let shippedAt: String?
        let deliveredAt: String?
        let lineItems: [Line]?
        let shippingCents: Int?
        let address: Address?
    }
    private struct Reply: Decodable { let order: Detail? }

    @State private var web: WebPage?
    @Environment(\.colorScheme) private var scheme

    private func addressText(_ a: Address) -> String {
        var lines: [String] = []
        if let n = a.name { lines.append(n) }
        if let l1 = a.line1 { lines.append(l1 + (a.line2.map { ", " + $0 } ?? "")) }
        let tail = [a.city, [a.state, a.zip].compactMap { $0 }.joined(separator: " ")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        if !tail.isEmpty { lines.append(tail) }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        Loaded(load: { () async throws -> Detail in
            guard let o = try await Site.get("api/account/orders/\(id)", Reply.self).order else {
                throw Site.Problem.refused("This order is not here.")
            }
            return o
        }) { o, _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Order \(o.id.prefix(8).uppercased())").siteLabel()
                        if let d = ArchiveDate.text(o.createdAt) { Text(d).font(SiteFont.body(13)).foregroundStyle(Bone.inkFaint(scheme)) }
                    }
                    OrderTracker(step: OrderStep.reached(status: o.status, shipped: o.shippedAt, delivered: o.deliveredAt, tracking: o.trackingNumber))
                    VStack(spacing: 6) {
                        if let u = o.trackingUrl, let url = URL(string: u), url.scheme == "https", o.deliveredAt == nil {
                            Button { web = WebPage(url) } label: { Text("Track your order \u{2192}").siteLabel(11).foregroundStyle(Bone.gold).frame(minHeight: 44) }.buttonStyle(.plain)
                        }
                        if let n = o.trackingNumber {
                            Text((o.carrier.map { "\($0) \u{00B7} " } ?? "") + n).font(SiteFont.body(12)).foregroundStyle(Bone.inkFaint(scheme)).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    if let lines = o.lineItems, !lines.isEmpty {
                        VStack(spacing: 0) {
                            SiteRule()
                            ForEach(lines) { li in
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(li.name).font(SiteFont.display(20)).foregroundStyle(Bone.ink(scheme))
                                        if let v = li.variation { Text(v).font(SiteFont.body(13)).foregroundStyle(Bone.inkFaint(scheme)) }
                                        if let q = li.quantity, q != "1" { Text("\u{00D7}\(q)").font(SiteFont.body(13)).foregroundStyle(Bone.inkFaint(scheme)) }
                                    }
                                    Spacer()
                                    if let a = li.amount { Text(Money.text(a)).font(SiteFont.body(15)).foregroundStyle(Bone.inkSoft(scheme)).monospacedDigit() }
                                }
                                .padding(.vertical, 16)
                                SiteRule()
                            }
                        }
                    }

                    VStack(spacing: 8) {
                        if let s = o.shippingCents {
                            HStack { Text("Shipping" + (o.carrier.map { " \u{2014} \($0)" } ?? "")); Spacer(); Text(Money.text(s)).monospacedDigit() }
                                .font(SiteFont.body(14)).foregroundStyle(Bone.inkSoft(scheme))
                        }
                        if let t = o.total {
                            HStack(alignment: .firstTextBaseline) { Text("Total").siteLabel(); Spacer(); Text(Money.text(Int((t.value * 100).rounded()))).font(SiteFont.display(28)).foregroundStyle(Bone.ink(scheme)).monospacedDigit() }
                        }
                    }

                    if let a = o.address, a.line1 != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            SiteRule()
                            Text("Ships to").siteLabel().padding(.top, 8)
                            Text(addressText(a))
                                .siteBody(14).textSelection(.enabled)
                        }
                    }
                }
                .padding(24)
            }
            .siteScreen()
        }
        .siteScreen()
        .plScreenTitle("Order")
        .sheet(item: $web) { SafariSheet(url: $0.url).ignoresSafeArea() }
    }
}
