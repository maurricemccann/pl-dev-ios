import CoreText
import SwiftUI
import UIKit

// THE PL REMIX (his ask 11-13: "give it the PL UI/UX remix with full Apple experience and capabilities").
// Apple's structure, behaviours and capabilities stay whole; the house is laid over them where he ruled it for the R1 (S347):
// his hand on titles, Courier Prime on panel labels, his palettes for colour (Apple's colours only for status dots), his curve
// tile under everything. Every asset comes from the Design Kit on the gallery at run time (kit.json, /fonts/, the psyground
// stencil) and is cached on the phone, so none of his art or type ships in this public repo.

struct HousePalette: Codable, Hashable, Identifiable {
    let name: String
    let ground: String
    let text: String
    let key: String
    let accent: String
    var id: String { name }
    var groundColor: Color { Color(hex: ground) ?? .black }
    var textColor: Color { Color(hex: text) ?? .white }
    var keyColor: Color { Color(hex: key) ?? .orange }
    var accentColor: Color { Color(hex: accent) ?? .orange }
    var title: String { name.replacingOccurrences(of: "-", with: " ").capitalized }

    /// His own Home Screen (the 11-13 reference: orange curves on deep brown, sampled), the default until he picks another.
    static let homeScreen = HousePalette(name: "home-screen", ground: "#5a1f0e", text: "#efe9dc", key: "#b85536", accent: "#f0a070")
}

@MainActor @Observable final class HouseKit {
    static let shared = HouseKit()
    private(set) var palettes: [HousePalette] = [.homeScreen]
    private(set) var titleFont: String?          // his hand, V1 (main), once registered
    var paletteName: String = UserDefaults.standard.string(forKey: "pldev.palette") ?? "home-screen" {
        didSet { UserDefaults.standard.set(paletteName, forKey: "pldev.palette"); apply() }
    }
    var palette: HousePalette { palettes.first { $0.name == paletteName } ?? .homeScreen }

    private let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("house", isDirectory: true)

    private init() {
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: cache.appendingPathComponent("palettes.json")), let p = try? JSONDecoder().decode([HousePalette].self, from: d), !p.isEmpty { palettes = [.homeScreen] + p.filter { $0.name != HousePalette.homeScreen.name } }
        registerFont(at: cache.appendingPathComponent("hand-v1.ttf"))
        apply()
    }

    /// Once per launch: the palettes from kit.json and his hand from /fonts/, both cached for the next cold start and offline.
    func refresh(model: AppModel) async {
        guard let http = model.http else { return }
        struct Kit: Decodable { struct C: Decodable { let palettes: [HousePalette]? }; let colors: C? }
        if let d = try? await http.send(RequestPlan(origin: "gallery", path: "kit.json"), timeout: 40),
           let p = try? JSONDecoder().decode(Kit.self, from: d).colors?.palettes, !p.isEmpty {
            palettes = [.homeScreen] + p.filter { $0.name != HousePalette.homeScreen.name }
            try? JSONEncoder().encode(p).write(to: cache.appendingPathComponent("palettes.json"))
        }
        let fontURL = cache.appendingPathComponent("hand-v1.ttf")
        if titleFont == nil, let d = try? await http.send(RequestPlan(origin: "gallery", path: "fonts/MaurriceMccannPsychedHandwrit-Regular.ttf"), timeout: 40) {
            try? d.write(to: fontURL)
            registerFont(at: fontURL)
        }
        apply()
    }

    private func registerFont(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path), let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider),
              let name = font.postScriptName as String? else { return }
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        titleFont = name
    }

    /// Pushes the house into UIKit's shared chrome: his hand on every navigation title, the palette's key as the window tint,
    /// and the palette to the widgets (App Group) so the Lock Screen and Home Screen wear the same colour.
    func apply() {
        if let name = titleFont {
            let nav = UINavigationBarAppearance()
            nav.configureWithDefaultBackground()
            if let large = UIFont(name: name, size: 38) { nav.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)] }
            if let small = UIFont(name: name, size: 22) { nav.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: small)] }
            UINavigationBar.appearance().standardAppearance = nav
            UINavigationBar.appearance().compactAppearance = nav
            let edge = UINavigationBarAppearance(); edge.configureWithTransparentBackground()
            edge.largeTitleTextAttributes = nav.largeTitleTextAttributes; edge.titleTextAttributes = nav.titleTextAttributes
            UINavigationBar.appearance().scrollEdgeAppearance = edge
        }
        SharedState.writeHouseTint(palette.key, ground: palette.ground)
    }
}

extension PLTone {
    /// The house key colour of the chosen palette (a theme pack's accent still wins when one is loaded).
    @MainActor static var house: Color { HouseKit.shared.palette.keyColor }
}

/// The ground under every app's screens: the palette's ground with his curve tile drawn faintly in its text colour (dark), or the
/// palette's cream with the tile in ink (light). The psyground of the Design Kit: about 11 %, so the glass and the cards stand out.
struct HouseGround: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduce
    @State private var kit = HouseKit.shared
    var body: some View {
        let p = kit.palette
        ZStack {
            if scheme == .dark { p.groundColor } else { ZStack { Color(uiColor: .systemGroupedBackground); p.textColor.opacity(0.45) } }
            if !reduce, let tile = Wallpaper.stencil {
                Image(uiImage: tile).renderingMode(.template).resizable(resizingMode: .tile)
                    .foregroundStyle(scheme == .dark ? p.textColor.opacity(0.07) : p.groundColor.opacity(0.06))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// A screen on the house ground: the list's own grey goes, the cards stay Apple's (they read as glass over the tile).
    func plGround() -> some View {
        scrollContentBackground(.hidden).background { HouseGround() }
    }
}
