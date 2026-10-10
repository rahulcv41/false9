import Foundation

struct ShadeResult {
    var perPanelLoss: [Double] = []         // 0…1 annual beam-energy lost to shade
    var monthlyKWhNoShade: [Double] = Array(repeating: 0, count: 12)
    var monthlyKWh: [Double] = Array(repeating: 0, count: 12)
    var shadeGrid: [[Double]] = []          // [month][solar hour] fraction of panels shaded; -1 = night
    var horizon: HorizonProfile = HorizonProfile(points: [])

    var annualKWh: Double { monthlyKWh.reduce(0, +) }
    var annualKWhNoShade: Double { monthlyKWhNoShade.reduce(0, +) }
    var annualShadeLossPct: Double {
        annualKWhNoShade > 0 ? (1 - annualKWh / annualKWhNoShade) * 100 : 0
    }
}

enum ShadeAnalysis {
    /// Sun-path based shading + clear-sky yield simulation for every panel.
    /// Beam shading comes from (a) the surveyed skyline and (b) roof obstacles casting shadow polygons.
    /// A panel is sampled at 5 points (centre + corners); shaded fraction scales its beam energy.
    static func run(_ p: Project, _ layout: Layout) -> ShadeResult {
        var r = ShadeResult()
        r.horizon = HorizonProfile(points: p.horizon)
        let n = layout.panels.count
        r.perPanelLoss = Array(repeating: 0, count: n)
        r.shadeGrid = Array(repeating: Array(repeating: -1, count: 24), count: 12)
        guard n > 0 else { return r }

        let obstacles = p.obstacles.map { (corners: p.obstacleCorners($0), height: $0.height) }
        let kWpPanel = p.panel.watt / 1000
        let scale = p.clearnessFactor * p.performanceRatio
        let tr = layout.tiltDeg * .pi / 180
        let samplePts: [[Pt]] = layout.panels.map { $0.corners + [$0.center] }

        var beamAll = [Double](repeating: 0, count: n)
        var beamLost = [Double](repeating: 0, count: n)

        for m in 0..<12 {
            let days = Solar.daysInMonth[m]
            let start = Solar.date(month: m).addingTimeInterval(-p.longitude / 15 * 3600)
            var gridSum = [Double](repeating: 0, count: 24)
            var gridCnt = [Double](repeating: 0, count: 24)

            for k in 0..<96 {
                let sun = Solar.sunPosition(date: start.addingTimeInterval(Double(k) * 900),
                                            latitude: p.latitude, longitude: p.longitude)
                guard sun.elevation > 0 else { continue }
                let cs = Solar.clearSky(elevation: sun.elevation)
                let cosInc = Solar.cosIncidence(sun: sun, tiltDeg: layout.tiltDeg, panelAzimuthDeg: layout.azimuthDeg)
                let beam = cs.dni * max(0, cosInc)
                let diffuse = cs.dhi * (1 + cos(tr)) / 2
                let skyBlocked = sun.elevation <= r.horizon.elevation(at: sun.azimuth)

                var shadows: [[Pt]] = []
                if !skyBlocked {
                    shadows = obstacles.map { shadowPolygon($0.corners, height: $0.height, sun: sun) }
                }

                let w = 0.25 * days * scale * kWpPanel / 1000     // W/m² → kWh per kWp-panel for this step
                var shadedSum = 0.0
                for i in 0..<n {
                    var frac = 1.0
                    if !skyBlocked {
                        if shadows.isEmpty { frac = 0 } else {
                            let hit = samplePts[i].filter { q in shadows.contains { Geo.contains($0, q) } }.count
                            frac = Double(hit) / Double(samplePts[i].count)
                        }
                    }
                    beamAll[i] += beam
                    beamLost[i] += beam * frac
                    r.monthlyKWhNoShade[m] += (beam + diffuse) * w
                    r.monthlyKWh[m] += (beam * (1 - frac) + diffuse) * w
                    shadedSum += frac
                }
                let hour = min(23, k / 4)
                gridSum[hour] += shadedSum / Double(n)
                gridCnt[hour] += 1
            }
            for h in 0..<24 where gridCnt[h] > 0 { r.shadeGrid[m][h] = gridSum[h] / gridCnt[h] }
        }
        for i in 0..<n where beamAll[i] > 0 { r.perPanelLoss[i] = beamLost[i] / beamAll[i] }
        return r
    }

    static func shadowPolygon(_ corners: [Pt], height: Double, sun: SunPosition) -> [Pt] {
        let len = min(60, height / tan(max(sun.elevation, 0.5) * .pi / 180))
        let az = sun.azimuth * .pi / 180
        let dir = Pt(-sin(az), -cos(az))
        return Geo.hull(corners + corners.map { $0 + dir * len })
    }
}

struct Economics {
    var annualKWh = 0.0
    var specificYield = 0.0     // kWh/kWp/yr
    var savingsPerYear = 0.0
    var systemCost = 0.0
    var paybackYears = 0.0
    var co2Tonnes = 0.0

    init(project p: Project, kWp: Double, annualKWh: Double) {
        self.annualKWh = annualKWh
        specificYield = kWp > 0 ? annualKWh / kWp : 0
        savingsPerYear = annualKWh * p.tariffPerKWh
        systemCost = kWp * p.costPerKWp
        paybackYears = savingsPerYear > 0 ? systemCost / savingsPerYear : 0
        co2Tonnes = annualKWh * p.gridEmissionFactor / 1000
    }
}
