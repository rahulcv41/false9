import Foundation

struct SunPosition {
    var azimuth: Double    // degrees clockwise from north
    var elevation: Double  // degrees above horizon
}

enum Solar {
    static let daysInMonth: [Double] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// Low-precision solar position (≈0.01° — plenty for shading studies).
    static func sunPosition(date: Date, latitude: Double, longitude: Double) -> SunPosition {
        let jd = date.timeIntervalSince1970 / 86400.0 + 2440587.5
        let n = jd - 2451545.0
        let L = fmod(280.460 + 0.9856474 * n, 360)
        let g = fmod(357.528 + 0.9856003 * n, 360) * .pi / 180
        let lam = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * .pi / 180
        let eps = (23.439 - 0.0000004 * n) * .pi / 180
        let ra = atan2(cos(eps) * sin(lam), cos(lam))
        let dec = asin(sin(eps) * sin(lam))
        let gmst = fmod(280.46061837 + 360.98564736629 * n, 360)
        let h = (gmst + longitude) * .pi / 180 - ra
        let lat = latitude * .pi / 180
        let sinEl = sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h)
        let el = asin(max(-1, min(1, sinEl)))
        let y = -cos(dec) * sin(h)
        let x = sin(dec) * cos(lat) - cos(dec) * sin(lat) * cos(h)
        var az = atan2(y, x) * 180 / .pi
        if az < 0 { az += 360 }
        return SunPosition(azimuth: az, elevation: el * 180 / .pi)
    }

    /// Simple clear-sky model (Meinel air-mass attenuation). Returns W/m² on normal / horizontal-diffuse.
    static func clearSky(elevation e: Double) -> (dni: Double, dhi: Double) {
        guard e > 0 else { return (0, 0) }
        let er = e * .pi / 180
        let am = 1.0 / (sin(er) + 0.50572 * pow(6.07995 + e, -1.6364))
        let dni = 1353 * pow(0.7, pow(am, 0.678))
        return (dni, 0.1 * dni)
    }

    static func cosIncidence(sun: SunPosition, tiltDeg: Double, panelAzimuthDeg: Double) -> Double {
        let e = sun.elevation * .pi / 180, t = tiltDeg * .pi / 180
        let d = (sun.azimuth - panelAzimuthDeg) * .pi / 180
        return sin(e) * cos(t) + cos(e) * sin(t) * cos(d)
    }

    /// Sun elevation at solar noon on the winter solstice (design case for row spacing).
    static func winterNoonElevation(_ latitude: Double) -> Double {
        90 - abs(latitude) - 23.44
    }

    /// 00:00 UTC on the 15th of the given month (0-based), year 2025.
    static func date(month: Int, day: Int = 15) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2025, month: month + 1, day: day)) ?? Date()
    }

    /// Sun track for a day, stepped in 15 min of solar time. Only points above horizon.
    static func sunPath(month: Int, day: Int, latitude: Double, longitude: Double) -> [SunPosition] {
        let start = date(month: month, day: day).addingTimeInterval(-longitude / 15 * 3600)
        return (0..<96).compactMap { k in
            let s = sunPosition(date: start.addingTimeInterval(Double(k) * 900), latitude: latitude, longitude: longitude)
            return s.elevation > 0 ? s : nil
        }
    }
}

/// Skyline seen from the roof: elevation of obstructions for every azimuth degree.
struct HorizonProfile {
    private(set) var bins = [Double](repeating: 0, count: 360)

    init(points: [HorizonPoint]) {
        let pts = points.sorted { $0.azimuth < $1.azimuth }
        guard !pts.isEmpty else { return }
        for p in pts {
            let c = Int(p.azimuth.rounded())
            let hw = max(0, Int(p.halfWidth))
            for d in -hw...hw { raise(c + d, to: p.elevation) }
        }
        // connect neighbouring marks that are less than 20° apart
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            var gap = b.azimuth - a.azimuth
            if gap <= 0 { gap += 360 }
            guard gap <= 20 else { continue }
            for s in 0...Int(gap) {
                let f = Double(s) / gap
                raise(Int((a.azimuth + f * gap).rounded()), to: a.elevation + f * (b.elevation - a.elevation))
            }
        }
    }

    private mutating func raise(_ idx: Int, to el: Double) {
        let i = ((idx % 360) + 360) % 360
        bins[i] = max(bins[i], el)
    }

    func elevation(at azimuth: Double) -> Double {
        let i = ((Int(azimuth.rounded()) % 360) + 360) % 360
        return bins[i]
    }
}
