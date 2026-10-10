import Foundation

struct PanelInstance: Identifiable {
    let id: Int
    var corners: [Pt]       // world footprint (m)
    var center: Pt
    var row: Int
    var col: Int
    var string = 0          // 0-based string index
}

struct Layout {
    var panels: [PanelInstance] = []
    var tiltDeg = 0.0
    var azimuthDeg = 180.0
    var uSize = 0.0         // panel size across the row (m)
    var slope = 0.0         // panel size up the slope (m)
    var footprintDepth = 0.0
    var rowPitch = 0.0
    var panelWatt = 0.0

    var kWp: Double { Double(panels.count) * panelWatt / 1000 }

    /// Keep only the first `n` panels (in string order).
    mutating func trim(to n: Int) {
        if n < panels.count { panels = Array(panels.prefix(n)) }
    }

    mutating func assignStrings(perString: Int) {
        guard perString > 0 else { return }
        for i in panels.indices { panels[i].string = i / perString }
    }
}

enum LayoutEngine {
    static func generate(_ p: Project) -> Layout {
        var layout = Layout()
        layout.tiltDeg = p.tiltDeg
        layout.azimuthDeg = p.azimuthDeg
        layout.panelWatt = p.panel.watt
        let roof = p.roofWorld
        guard roof.count >= 3, p.isCalibrated else { return layout }

        let landscape = p.orientation == .landscape
        let u = landscape ? p.panel.lengthM : p.panel.widthM
        let slope = landscape ? p.panel.widthM : p.panel.lengthM
        let tr = p.tiltDeg * .pi / 180
        let depth = slope * cos(tr)
        var gap = 0.03
        if p.roofType == .flat && p.tiltDeg > 1 {
            let minEl = max(8, Solar.winterNoonElevation(p.latitude))
            gap = max(0.03, slope * sin(tr) / tan(minEl * .pi / 180))
        }
        layout.uSize = u; layout.slope = slope; layout.footprintDepth = depth; layout.rowPitch = depth + gap

        let g = p.azimuthDeg * .pi / 180
        func toLocal(_ q: Pt) -> Pt { Pt(q.x * cos(g) - q.y * sin(g), q.x * sin(g) + q.y * cos(g)) }
        func toWorld(_ q: Pt) -> Pt { Pt(q.x * cos(g) + q.y * sin(g), -q.x * sin(g) + q.y * cos(g)) }

        let b = Geo.bounds(roof.map(toLocal))
        let blocked = p.obstacles.map { p.obstacleCorners($0, clearance: p.obstacleClearanceM) }
        let stepU = u + 0.02, stepV = depth + gap

        var best: [PanelInstance] = []
        for ou in [0.0, 1.0 / 3, 2.0 / 3] {
            for ov in [0.0, 1.0 / 3, 2.0 / 3] {
                var out: [PanelInstance] = []
                var row = 0
                var v = b.min.y + ov * stepV
                while v + depth <= b.max.y {
                    var rowPanels: [PanelInstance] = []
                    var col = 0
                    var x = b.min.x + ou * stepU
                    while x + u <= b.max.x {
                        let corners = [Pt(x, v), Pt(x + u, v), Pt(x + u, v + depth), Pt(x, v + depth)].map(toWorld)
                        if fits(corners, roof: roof, setback: p.setbackM, blocked: blocked) {
                            rowPanels.append(PanelInstance(id: 0, corners: corners, center: Geo.centroid(corners), row: row, col: col))
                        }
                        x += stepU; col += 1
                    }
                    if row % 2 == 1 { rowPanels.reverse() }   // snake order for stringing
                    out += rowPanels
                    v += stepV; row += 1
                }
                if out.count > best.count { best = out }
            }
        }
        layout.panels = best.enumerated().map { i, pn in
            var q = pn
            q = PanelInstance(id: i, corners: q.corners, center: q.center, row: q.row, col: q.col)
            return q
        }
        return layout
    }

    private static func fits(_ corners: [Pt], roof: [Pt], setback: Double, blocked: [[Pt]]) -> Bool {
        for c in corners {
            if !Geo.contains(roof, c) || Geo.edgeDistance(roof, c) < setback { return false }
        }
        for o in blocked where Geo.overlap(corners, o) { return false }
        return true
    }
}
