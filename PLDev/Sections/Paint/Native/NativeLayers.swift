import CoreGraphics
import Foundation
import UIKit

/// The laptop's 26 blend names (the 17 a browser canvas has, and `blend.js`'s nine). On screen the 15 Core Animation has are drawn live;
/// the nine PSD-only ones (`x-...`) are shown as Normal for now and are named in the layer's row so they are not lost on save.
enum NativeBlend {
    struct Mode: Identifiable { let id: String; let label: String; let filter: String?; let cg: CGBlendMode? }
    static let modes: [Mode] = [
        Mode(id: "source-over", label: "Normal", filter: nil, cg: .normal),
        Mode(id: "multiply", label: "Multiply", filter: "multiplyBlendMode", cg: .multiply),
        Mode(id: "screen", label: "Screen", filter: "screenBlendMode", cg: .screen),
        Mode(id: "overlay", label: "Overlay", filter: "overlayBlendMode", cg: .overlay),
        Mode(id: "darken", label: "Darken", filter: "darkenBlendMode", cg: .darken),
        Mode(id: "lighten", label: "Lighten", filter: "lightenBlendMode", cg: .lighten),
        Mode(id: "color-dodge", label: "Colour Dodge", filter: "colorDodgeBlendMode", cg: .colorDodge),
        Mode(id: "color-burn", label: "Colour Burn", filter: "colorBurnBlendMode", cg: .colorBurn),
        Mode(id: "hard-light", label: "Hard Light", filter: "hardLightBlendMode", cg: .hardLight),
        Mode(id: "soft-light", label: "Soft Light", filter: "softLightBlendMode", cg: .softLight),
        Mode(id: "difference", label: "Difference", filter: "differenceBlendMode", cg: .difference),
        Mode(id: "exclusion", label: "Exclusion", filter: "exclusionBlendMode", cg: .exclusion),
        Mode(id: "hue", label: "Hue", filter: "hueBlendMode", cg: .hue),
        Mode(id: "saturation", label: "Saturation", filter: "saturationBlendMode", cg: .saturation),
        Mode(id: "color", label: "Colour", filter: "colorBlendMode", cg: .color),
        Mode(id: "luminosity", label: "Luminosity", filter: "luminosityBlendMode", cg: .luminosity),
        Mode(id: "x-linear-burn", label: "Linear Burn", filter: nil, cg: nil),
        Mode(id: "x-darker-color", label: "Darker Colour", filter: nil, cg: nil),
        Mode(id: "x-lighter-color", label: "Lighter Colour", filter: nil, cg: nil),
        Mode(id: "x-vivid-light", label: "Vivid Light", filter: nil, cg: nil),
        Mode(id: "x-linear-light", label: "Linear Light", filter: nil, cg: nil),
        Mode(id: "x-pin-light", label: "Pin Light", filter: nil, cg: nil),
        Mode(id: "x-hard-mix", label: "Hard Mix", filter: nil, cg: nil),
        Mode(id: "x-subtract", label: "Subtract", filter: nil, cg: nil),
        Mode(id: "x-divide", label: "Divide", filter: nil, cg: nil),
    ]
    static func mode(_ id: String?) -> Mode { modes.first { $0.id == id } ?? modes[0] }
}

extension NativeDoc {
    private func groupRecord(of l: NativeLayer) -> [String: Any]? {
        let gid = l.meta["grp"] as? Int ?? 0
        guard gid != 0 else { return nil }
        return groups.first { ($0["id"] as? Int) == gid }
    }
    /// A layer is shown when it and its group are on; its opacity is its own times its group's (the laptop's `shown` and `grpOf(L).op`).
    func isShown(_ l: NativeLayer) -> Bool { l.visible && (groupRecord(of: l)?["vis"] as? Bool ?? true) }
    func shownOpacity(_ l: NativeLayer) -> Double {
        let g = groupRecord(of: l)
        let go = (g?["op"] as? Double) ?? Double(g?["op"] as? Int ?? 1)
        return l.opacity * go
    }
    /// The layer a clipped layer is clipped to: the nearest one below that is not itself clipped.
    func clipBase(of i: Int) -> Int? {
        guard layers.indices.contains(i), layers[i].meta["clip"] as? Bool == true else { return nil }
        var j = i - 1
        while j >= 0 { if layers[j].meta["clip"] as? Bool != true { return j }; j -= 1 }
        return nil
    }

    /// The flat picture: every layer in order with its blend, mask, group and clip, over the background (transparent when it is hidden).
    func flatImage() -> CGImage? { compositeBuffer()?.heldImage() }
}
