import CoreGraphics
import CoreText
import SwiftUI
import UIKit

/// An optional look the owner drops into the app's Documents folder through Files: `theme.json`, and beside it
/// a title font file and a tile image if the json names them. Nothing of it ships in this repo.
/// With no pack the app runs on Apple's system colours and fonts and is complete.
///
/// theme.json: { "colors": { "accent": "#RRGGBB", "tile": "#RRGGBB" }, "palette": ["#RRGGBB"], "titleFont": "Title.ttf", "tile": "tile.png" }
@MainActor @Observable final class ThemePack {
    static let shared = ThemePack()

    private(set) var isLoaded = false
    private(set) var problem: String?                // one plain sentence when a pack is present but unusable
    private(set) var colors: [String: Color] = [:]
    private(set) var palette: [Color] = []
    private(set) var tile: UIImage?
    private var titleFontName: String?

    var titleAllowed = true                          // the config can turn the pack's title font off

    var accent: Color? { colors["accent"] }
    var titleFont: String? { titleAllowed ? (titleFontName ?? HouseKit.shared.titleFont) : nil }   // no pack: his hand from the Design Kit (the PL remix)

    private struct File: Decodable {
        var colors: [String: String]?
        var palette: [String]?
        var titleFont: String?
        var tile: String?
    }

    private init() {
        assert(Self.components(hex: "#FF0000")?.red == 1 && Self.components(hex: "00ff0080")?.green == 1 && Self.components(hex: "#12") == nil, "hex colours")
    }

    /// Reads the pack again. Called at launch and from Settings.
    /// shortcut: read on the main thread, the files are a few kilobytes; move off it if a pack ever carries large images.
    func load() {
        isLoaded = false
        problem = nil
        colors = [:]
        palette = []
        tile = nil
        titleFontName = nil
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let json = folder.appendingPathComponent("theme.json")
        guard let data = try? Data(contentsOf: json) else { return }   // no pack: the system look
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            problem = "theme.json is in Documents but is not valid."
            return
        }
        for (name, hex) in file.colors ?? [:] {
            if let color = Self.color(hex: hex) { colors[name] = color }
        }
        palette = (file.palette ?? []).compactMap { Self.color(hex: $0) }
        if let name = file.tile {
            tile = UIImage(contentsOfFile: Self.inside(folder, name).path)
        }
        if let name = file.titleFont {
            titleFontName = Self.register(font: Self.inside(folder, name))
            if titleFontName == nil { problem = "The title font named in theme.json could not be read." }
        }
        isLoaded = true
    }

    /// Only a bare file name beside theme.json is honoured, never a path out of the folder.
    private static func inside(_ folder: URL, _ name: String) -> URL {
        folder.appendingPathComponent((name as NSString).lastPathComponent)
    }

    /// Registers the font for this process and returns the name SwiftUI finds it by.
    private static func register(font url: URL) -> String? {
        guard let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider),
              let name = font.postScriptName as String? else { return nil }
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)   // false only means it was already registered
        return name
    }

    nonisolated static func components(hex: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let rgb = text.count == 8 ? value >> 8 : value
        let alpha = text.count == 8 ? Double(value & 0xFF) / 255 : 1
        return (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255, alpha)
    }

    nonisolated static func color(hex: String) -> Color? {
        guard let parts = components(hex: hex) else { return nil }
        return Color(.sRGB, red: parts.red, green: parts.green, blue: parts.blue, opacity: parts.alpha)
    }
}
