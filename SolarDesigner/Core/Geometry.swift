import Foundation
import CoreGraphics

/// 2D point. In "world" space: x = east (m), y = north (m). In "pixel" space: image pixels, y down.
struct Pt: Codable, Hashable {
    var x: Double
    var y: Double
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    var cg: CGPoint { CGPoint(x: x, y: y) }
    static func + (a: Pt, b: Pt) -> Pt { Pt(a.x + b.x, a.y + b.y) }
    static func - (a: Pt, b: Pt) -> Pt { Pt(a.x - b.x, a.y - b.y) }
    static func * (a: Pt, k: Double) -> Pt { Pt(a.x * k, a.y * k) }
}

enum Geo {
    static func contains(_ poly: [Pt], _ p: Pt) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y),
               p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    static func distToSegment(_ p: Pt, _ a: Pt, _ b: Pt) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let l2 = dx * dx + dy * dy
        if l2 == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Smallest distance from `p` to any edge of the closed polygon.
    static func edgeDistance(_ poly: [Pt], _ p: Pt) -> Double {
        guard poly.count >= 2 else { return .infinity }
        var best = Double.infinity
        for i in 0..<poly.count {
            best = min(best, distToSegment(p, poly[i], poly[(i + 1) % poly.count]))
        }
        return best
    }

    static func area(_ poly: [Pt]) -> Double {
        guard poly.count >= 3 else { return 0 }
        var s = 0.0
        for i in 0..<poly.count {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            s += a.x * b.y - b.x * a.y
        }
        return abs(s) / 2
    }

    static func centroid(_ pts: [Pt]) -> Pt {
        guard !pts.isEmpty else { return Pt(0, 0) }
        let sx = pts.reduce(0) { $0 + $1.x }, sy = pts.reduce(0) { $0 + $1.y }
        return Pt(sx / Double(pts.count), sy / Double(pts.count))
    }

    static func bounds(_ pts: [Pt]) -> (min: Pt, max: Pt) {
        guard let f = pts.first else { return (Pt(0, 0), Pt(0, 0)) }
        var mn = f, mx = f
        for p in pts {
            mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
            mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
        }
        return (mn, mx)
    }

    /// Convex hull (monotone chain).
    static func hull(_ input: [Pt]) -> [Pt] {
        let pts = input.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard pts.count > 2 else { return pts }
        func cross(_ o: Pt, _ a: Pt, _ b: Pt) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [Pt] = []
        for p in pts {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [Pt] = []
        for p in pts.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        lower.removeLast(); upper.removeLast()
        return lower + upper
    }

    /// Rectangle corners (w along local x, d along local y), rotated CCW by `rotation` radians about `center`.
    static func rect(center: Pt, w: Double, d: Double, rotation: Double = 0) -> [Pt] {
        let c = cos(rotation), s = sin(rotation)
        return [(-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)].map { (x, y) in
            Pt(center.x + x * c - y * s, center.y + x * s + y * c)
        }
    }

    /// Separating-axis overlap test for two convex polygons.
    static func overlap(_ a: [Pt], _ b: [Pt]) -> Bool {
        for poly in [a, b] {
            for i in 0..<poly.count {
                let p1 = poly[i], p2 = poly[(i + 1) % poly.count]
                let axis = Pt(-(p2.y - p1.y), p2.x - p1.x)
                func project(_ q: [Pt]) -> (Double, Double) {
                    let v = q.map { $0.x * axis.x + $0.y * axis.y }
                    return (v.min() ?? 0, v.max() ?? 0)
                }
                let pa = project(a), pb = project(b)
                if pa.1 < pb.0 || pb.1 < pa.0 { return false }
            }
        }
        return true
    }
}
