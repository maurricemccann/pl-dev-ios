import CoreGraphics
import Foundation

/// Facet and Curve (the laptop's `facetPath`): a stroke that ends is drawn again as straight segments with rounded corners, so a faceted
/// run and a curved one sit in the same line. On the laptop Shift does it for one stroke; here "Facet next stroke" does, and "All strokes
/// faceted" makes it the rule. The corner rounding is a quarter of the brush wide at most, a third of each segment at most.
extension NativeCanvasModel {
    /// The clean path for a stroke's pen points, or nil when it is too short to have a corner.
    func facetPath(_ pts: [CGPoint], size: Double) -> [CGPoint]? {
        guard pts.count >= 3 else { return nil }
        var len = 0.0
        for i in 1..<pts.count { len += hypot(Double(pts[i].x - pts[i - 1].x), Double(pts[i].y - pts[i - 1].y)) }
        let poly = douglasPeucker(pts, max(size * 1.2, len * 0.012))
        guard poly.count >= 3 else { return nil }
        var out: [CGPoint] = [poly[0]]
        for i in 1..<(poly.count - 1) {
            let a = poly[i - 1], b = poly[i], c = poly[i + 1]
            let l1 = max(1e-9, hypot(Double(b.x - a.x), Double(b.y - a.y))), l2 = max(1e-9, hypot(Double(c.x - b.x), Double(c.y - b.y)))
            let f = min(size * 0.5, l1 / 3, l2 / 3)
            let p1 = CGPoint(x: Double(b.x) + Double(a.x - b.x) / l1 * f, y: Double(b.y) + Double(a.y - b.y) / l1 * f)
            let p2 = CGPoint(x: Double(b.x) + Double(c.x - b.x) / l2 * f, y: Double(b.y) + Double(c.y - b.y) / l2 * f)
            out.append(p1)
            for t in 1..<4 {
                let u = Double(t) / 4
                out.append(CGPoint(x: (1 - u) * (1 - u) * Double(p1.x) + 2 * u * (1 - u) * Double(b.x) + u * u * Double(p2.x),
                                   y: (1 - u) * (1 - u) * Double(p1.y) + 2 * u * (1 - u) * Double(b.y) + u * u * Double(p2.y)))
            }
            out.append(p2)
        }
        out.append(poly[poly.count - 1])
        return out
    }

    /// Called as a paint stroke ends: lays it down again along the faceted path.
    func facetApply(_ s: inout Live, _ d: NativeDoc) {
        let pts = s.pts.map { CGPoint(x: Self.num($0[0]), y: Self.num($0[1])) }
        guard let np = facetPath(pts, size: s.size) else { return }
        relay(&s, path: np, d)
    }

    func toggleFacetNext() {
        facetNext.toggle()
        say(facetNext ? "Facet: the next stroke is straight segments with rounded corners." : "Facet off for the next stroke.")
    }
}
