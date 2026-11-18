import Foundation
import simd

/// The palette owner. Rooms read the look, they never decide it. Vividness is a SATURATION factor: 0.5 at page 1 climbing to 0.7 at page 10,
/// 1.0 once the Embrace is done, 1.1 in free play (the hub after the Embrace). Colours are never multiplied toward black, and fog is the page hue.
enum PLWPalette {
    static func vividness(_ area: PLWArea, _ save: PLWSave) -> Float {
        let embraced = save.completed.contains(.p11) || save.dream == .embraced
        switch area {
        case .hub: return embraced ? 1.1 : 0.7
        case .p11: return embraced ? 1.0 : 0.7
        default:
            guard let p = area.page else { return 0.7 }
            return 0.5 + 0.2 * Float(p - 1) / 9
        }
    }

    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xff), Float((hex >> 8) & 0xff), Float(hex & 0xff)) / 255
    }

    /// The hub has no page colour of its own: it keeps the green of his ring drawing (the disc), whose water and gold come from lane B.
    static func look(_ area: PLWArea, _ save: PLWSave) -> PLWLook {
        let base: SIMD3<Float> = area.page.map { rgb(PLWRing.pageHex[$0 - 1]) } ?? SIMD3(0.36, 0.66, 0.40)
        return PLWLook(pageRGB: base, fogRGB: base, saturation: vividness(area, save), exposure: 1)
    }

    /// Scales the saturation of a colour around its own luminance, never toward black. Rooms copy this one-liner or call it.
    static func saturate(_ c: SIMD3<Float>, _ s: Float) -> SIMD3<Float> {
        let l = simd_dot(c, SIMD3<Float>(0.2126, 0.7152, 0.0722))
        return simd_clamp(SIMD3(repeating: l) + (c - SIMD3(repeating: l)) * s, SIMD3(repeating: 0), SIMD3(repeating: 1))
    }
}
