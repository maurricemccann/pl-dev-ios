import SwiftUI
import UIKit

/// Home page 3: backend sites as tiles (Plans/SPEC — PL DEV BACKEND PAGE (S348), his rulings 11-14). A tile opens the site inside PL DEV
/// with its own saved sign-in. More tiles come from a page he shared from Safari, or a pasted address.
struct BackendPage: View {
    let columns: [GridItem]
    let reduce: Bool
    var embedded = false
    @State private var store = BackendStore.shared
    @State private var open: BackendTemplate?
    @State private var adding: BackendTemplate?
    @State private var showAdd = false
    @State private var notice: String?
    @State private var safariPage: WebPage?

    var body: some View {
        VStack(alignment: .leading, spacing: PLSpace.roomy) {
            Text("Services").plLabel(11).foregroundStyle(.white.opacity(0.8)).padding(.top, embedded ? PLSpace.roomy : 0)
            if let notice { NoteLine(symbol: "checkmark.circle", tint: PLTone.accent, text: notice) }
            LazyVGrid(columns: columns, spacing: PLSpace.roomy + PLSpace.pad) {
                ForEach(store.tiles) { t in tile(t) }
                addTile
            }
        }
        .padding(.horizontal, embedded ? 0 : PLSpace.margin).padding(.top, embedded ? 0 : PLSpace.gap).padding(.bottom, embedded ? 0 : 120)
        .fullScreenCover(item: $open) { t in BackendWebScreen(template: t) }
        .sheet(item: $safariPage) { page in SafariSheet(url: page.url).ignoresSafeArea() }   // Apple's browser sheet: passkeys and security keys work here
        .sheet(isPresented: $showAdd) {
            BackendAddSheet(store: store, preset: adding) { line in notice = line }
                .presentationDetents([.medium, .large])
        }
    }

    private func tile(_ t: BackendTemplate) -> some View {
        Button {
            // a tap opens Apple's Safari view (his ruling 11-14: the in-app web view could not do his sign-ins; passkeys and iCloud Keychain work here)
            if t.isReady, let url = URL(string: t.startURL) { safariPage = WebPage(url) } else { adding = t; showAdd = true }   // a tile with no address yet asks for one
        } label: {
            BackendTile(symbol: t.symbol, name: t.name, ready: t.isReady)
        }
        .buttonStyle(PressableStyle(reduce: reduce))
        .contextMenu {
            if t.isReady {
                Button("Open in the PL DEV web view", systemImage: "rectangle.on.rectangle") { open = t }
            }
            Button("Remove", systemImage: "trash", role: .destructive) { store.remove(t.id) }
            Button("Bring back the built-in tiles", systemImage: "arrow.counterclockwise") { store.reset() }
        }
    }

    private var addTile: some View {
        Button {
            adding = nil
            showAdd = true
        } label: {
            BackendTile(symbol: "plus", name: "Add", ready: true)
        }
        .buttonStyle(PressableStyle(reduce: reduce))
        .accessibilityHint("Adds a site from a page you shared from Safari, or a pasted address")
    }
}

/// The icon plate, as the Apps page draws it: glass washed in the wallpaper's colour, a white glyph, the name under it.
private struct BackendTile: View {
    let symbol: String
    let name: String
    let ready: Bool
    @AppStorage("pldev.glassBlur") private var glass = true

    var body: some View {
        let icon = RoundedRectangle(cornerRadius: 15, style: .continuous)
        VStack(spacing: 6) {
            ZStack {
                Image(systemName: symbol).font(.system(size: 30, weight: .medium)).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white).shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                if !ready {
                    Image(systemName: "link.badge.plus").font(.caption.bold()).foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(6)
                }
            }
            .frame(width: 64, height: 64)
            .modifier(BackendGlass(shape: icon, on: glass))
            .opacity(ready ? 1 : 0.55)
            Text(name)
                .plFont(.caption)
                .foregroundStyle(.white.opacity(ready ? 1 : 0.7))
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                .lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ready ? name : name + ", needs its address")
        .accessibilityAddTraits(.isButton)
    }
}

private struct BackendGlass<S: Shape>: ViewModifier {
    let shape: S
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content.plGlass(tint: Wallpaper.line.opacity(0.45), in: shape)
        } else {
            content.background(Wallpaper.line.gradient, in: shape)
        }
    }
}

/// Adds a tile: the page he last shared from Safari (still on this phone), a pasted link, or a typed address. A built-in site
/// (Cloudflare, Printful, Horizon) gets its own name and icon; any other https page becomes a custom tile limited to its own site.
struct BackendAddSheet: View {
    let store: BackendStore
    let preset: BackendTemplate?
    let done: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var title = ""
    @State private var shared: SharedInbox.Item?

    private var result: BackendTemplate? {
        BackendTemplates.template(for: address, title: title.isEmpty ? preset?.name : title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://", text: $address)
                        .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                    Button("Paste a copied link", systemImage: "doc.on.clipboard") {
                        if let u = UIPasteboard.general.url { address = u.absoluteString }
                    }
                    if let s = shared, let u = s.url {
                        Button {
                            address = u
                            title = s.title ?? ""
                        } label: {
                            Label("Use the page you shared from Safari: " + (BackendTemplates.host(of: u) ?? u), systemImage: "safari")
                        }
                    }
                } header: {
                    Text(preset.map { "Address for \($0.name)" } ?? "The page")
                } footer: {
                    Text("Only https addresses. The site opens inside PL DEV; you sign in once and it is kept.")
                }
                Section("Becomes") {
                    if let r = result {
                        Label(r.name, systemImage: r.symbol)
                        Text(r.startURL).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Text(address.isEmpty ? "Paste or type an https address." : "That is not an https address.").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(preset == nil ? "Add a site" : preset?.name ?? "Add a site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let r = result { done(store.add(r)) }
                        dismiss()
                    }
                    .disabled(result == nil)
                }
            }
            .onAppear {
                shared = SharedInbox.all().filter { $0.source == "safari" && ($0.url ?? "").hasPrefix("https") }.max { $0.createdAt < $1.createdAt }
            }
        }
    }
}
