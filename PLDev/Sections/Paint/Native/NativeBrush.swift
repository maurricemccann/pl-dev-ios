import CoreGraphics
import Foundation

/// P1's one round brush: the toolkit's "Round" (Basics pack): spacing 0.1, hardness 0.7, flow 0.5, pressure to size 0.72 with curve 0.8.
/// P2 replaces this with the full 66-parameter brush read from the toolkit. These numbers are the toolkit defaults (`C:\dev\pl-toolkit`).
struct RoundBrush: Sendable {
    var id = "round"
    var spacing = 0.1, hard = 0.7, flow = 0.5
    var pressSize = 0.72, pressOp = 0.0, pressCurve = 0.8

    func radius(size: Double, pressure p: Double) -> Double {
        max(0.6, size / 2 * (1 - pressSize + pressSize * pow(max(0, min(1, p)), pressCurve)))
    }
    func alpha(pressure p: Double) -> Double { flow * (1 - pressOp + pressOp * pow(max(0, min(1, p)), pressCurve)) }
}

struct Stamp: Equatable, Sendable { var x: Double, y: Double, r: Double, a: Double }

/// Turns pen points into stamps spaced along the path. Pure, so it can be checked without a device.
/// Pressure is averaged half and half with the last value, as the laptop's `pAvg`, and the log keeps the averaged value.
struct Stroker: Sendable {
    let brush: RoundBrush
    let size: Double
    private var last: (x: Double, y: Double, r: Double, p: Double)?
    private var carry = 0.0
    private var pAvg: Double?
    init(brush: RoundBrush, size: Double) { self.brush = brush; self.size = size }

    /// Smoothed pressure for this point (what goes in the log).
    mutating func smooth(_ p: Double) -> Double { let v = pAvg.map { $0 * 0.5 + p * 0.5 } ?? p; pAvg = v; return v }

    mutating func add(x: Double, y: Double, p: Double) -> [Stamp] {
        let r = brush.radius(size: size, pressure: p)
        guard let l = last else {
            last = (x, y, r, p); carry = max(1, brush.spacing * r * 2)
            return [Stamp(x: x, y: y, r: r, a: brush.alpha(pressure: p))]
        }
        let dx = x - l.x, dy = y - l.y, dist = (dx * dx + dy * dy).squareRoot()
        guard dist > 0 else { return [] }
        var out: [Stamp] = []
        var pos = carry
        while pos <= dist {
            let t = pos / dist
            let rr = l.r + (r - l.r) * t
            let step = max(1, brush.spacing * rr * 2)
            out.append(Stamp(x: l.x + dx * t, y: l.y + dy * t, r: rr, a: brush.alpha(pressure: l.p + (p - l.p) * t)))
            pos += step
        }
        carry = pos - dist
        last = (x, y, r, p)
        return out
    }
}
