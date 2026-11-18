import SwiftUI
import UIKit

/// The title and the hero pick. He chooses who walks (GlyphGuy or GlyphGirl, same rig and clips); the choice is saved with the progress.
/// Continue picks up at the last checkpoint. Start over asks first.
struct PLWHome: View {
    @State private var store: PLWSaveStore?
    @State private var hero: PLWHero = .glyphGuy
    @State private var playing = false
    @State private var confirmReset = false

    var body: some View {
        Group {
            if let store, playing {
                PLWView(store: store)
            } else if let store {
                title(store)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .task { if store == nil { let s = PLWSaveStore(); hero = s.save.hero; store = s } }
    }

    private func title(_ store: PLWSaveStore) -> some View {
        VStack(spacing: 26) {
            Spacer()
            Text("PL World").font(.system(size: 40, weight: .semibold, design: .serif)).foregroundStyle(PLG.gold)
            Text("Choose who walks.").font(.callout).foregroundStyle(.white.opacity(0.65))
            HStack(spacing: 18) {
                card(.glyphGuy, "GlyphGuy", sprite: "town-him-walk")
                card(.glyphGirl, "GlyphGirl", sprite: "town-her-walk")
            }
            Button {
                store.commit { $0.hero = hero }
                playing = true
            } label: {
                Text(store.existed ? "Continue" : "Begin").font(.headline).frame(maxWidth: 220).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).tint(PLG.gold).foregroundStyle(.black)
            .disabled(!PLWHeroFigure.available(hero))
            if store.existed {
                Button("Start over") { confirmReset = true }.font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .confirmationDialog("Start over?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Start over", role: .destructive) { store.reset(hero: hero) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your progress in PL World is cleared.") }
    }

    private func card(_ h: PLWHero, _ name: String, sprite: String) -> some View {
        let here = PLWHeroFigure.available(h), on = hero == h
        return Button { if here { hero = h } } label: {
            VStack(spacing: 8) {
                Group {
                    if let img = Self.sprite(sprite) { Image(uiImage: img).resizable().scaledToFit() } else { Color.clear }
                }
                .frame(width: 120, height: 150)
                Text(name).font(.subheadline.weight(.medium))
                if !here { Text("Coming").font(.caption2).foregroundStyle(.white.opacity(0.5)) }
            }
            .padding(12).foregroundStyle(.white.opacity(here ? 1 : 0.45))
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(on ? 0.12 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(on ? PLG.gold : .white.opacity(0.15), lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain).disabled(!here)
        .accessibilityLabel(name).accessibilityAddTraits(on ? .isSelected : [])
    }

    private static func sprite(_ name: String) -> UIImage? {
        let b = Bundle.main
        let url = b.url(forResource: name, withExtension: "png") ?? b.url(forResource: name, withExtension: "png", subdirectory: "Models")
            ?? b.url(forResource: name, withExtension: "png", subdirectory: "Models/Clips")
        return url.flatMap { UIImage(contentsOfFile: $0.path) }
    }
}
