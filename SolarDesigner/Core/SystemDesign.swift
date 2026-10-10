import Foundation

/// Electrical sizing for the layout. Indicative only — a licensed engineer must verify before construction.
struct SystemDesign {
    var panelCount = 0
    var dcKWp = 0.0
    var inverterCount = 0
    var panelsPerString = 0
    var stringCount = 0
    var stringsPerInverter = 0
    var minPerString = 0
    var maxPerString = 0
    var stringVoc = 0.0          // at cold
    var stringVmp = 0.0          // at STC
    var stringIsc = 0.0
    var acKWTotal = 0.0
    var acCurrentPerInverter = 0.0
    var acBreakerA = 0
    var acCableMM2 = 0.0
    var dcCableMM2 = 4.0
    var warnings: [String] = []

    static let coldTempC = 5.0
    static let hotCellTempC = 70.0
    static let breakers = [6, 10, 16, 20, 25, 32, 40, 50, 63, 80, 100, 125, 160, 200]

    /// Computes the design and trims the layout so panels divide into equal strings.
    static func make(project p: Project, layout: inout Layout) -> SystemDesign {
        var d = SystemDesign()
        let count = layout.panels.count
        let pan = p.panel, inv = p.inverter
        guard count > 0, pan.voc > 0, pan.vmp > 0 else { return d }

        let vocCold = pan.voc * (1 + abs(pan.tempCoeffVocPct) / 100 * (25 - coldTempC))
        let vmpHot = pan.vmp * (1 - 0.0035 * (hotCellTempC - 25))
        let maxN = max(1, min(Int(inv.maxDCV / vocCold), Int(inv.mpptMax / pan.vmp)))
        let minN = max(1, Int((inv.mpptMin / vmpHot).rounded(.up)))
        d.minPerString = minN; d.maxPerString = maxN
        if minN > maxN { d.warnings.append("Panel/inverter voltage window does not allow a valid string. Pick a different inverter.") }

        // Prefer the largest string length that divides the panel count evenly (dropping ≤4 panels if needed).
        var chosen: (n: Int, keep: Int)?
        outer: for k in 0...min(4, max(0, count - 1)) {
            let lo = max(minN, maxN - 6)
            if lo > maxN { break }
            for n in stride(from: maxN, through: lo, by: -1) where (count - k) % n == 0 && count - k >= n {
                chosen = (n, count - k); break outer
            }
        }
        let n: Int, keep: Int
        if let c = chosen { n = c.n; keep = c.keep } else {
            n = min(maxN, count); keep = (count / n) * n
        }
        layout.trim(to: keep)
        layout.assignStrings(perString: n)

        d.panelCount = keep
        d.dcKWp = Double(keep) * pan.watt / 1000
        d.panelsPerString = n
        d.stringCount = keep / n
        d.stringVoc = vocCold * Double(n)
        d.stringVmp = pan.vmp * Double(n)
        d.stringIsc = pan.isc
        if n < minN { d.warnings.append("String of \(n) panels is below the MPPT minimum (\(minN) needed).") }

        d.inverterCount = max(1, Int((d.dcKWp / (inv.acKW * 1.3)).rounded(.up)))
        d.stringsPerInverter = Int((Double(d.stringCount) / Double(d.inverterCount)).rounded(.up))
        let capacity = inv.mpptCount * inv.stringsPerMPPT
        if d.stringsPerInverter > capacity {
            d.warnings.append("\(d.stringsPerInverter) strings per inverter exceeds \(capacity) MPPT inputs — add inverters or choose a larger one.")
        }
        let perMPPT = Int((Double(d.stringsPerInverter) / Double(inv.mpptCount)).rounded(.up))
        if Double(perMPPT) * pan.isc * 1.25 > inv.maxCurrentPerMPPT * 1.0 && perMPPT > 1 {
            d.warnings.append("Parallel strings on one MPPT may exceed its current limit (\(inv.maxCurrentPerMPPT) A).")
        }

        d.acKWTotal = Double(d.inverterCount) * inv.acKW
        let v = inv.threePhase ? 415.0 * 3.0.squareRoot() : 230.0
        d.acCurrentPerInverter = inv.acKW * 1000 / v
        d.acBreakerA = breakers.first { Double($0) >= d.acCurrentPerInverter * 1.25 } ?? 250
        d.acCableMM2 = cableSize(forBreaker: d.acBreakerA)
        let ratio = d.dcKWp / max(0.1, d.acKWTotal)
        if ratio > 1.4 { d.warnings.append(String(format: "DC/AC ratio %.2f is high; expect clipping.", ratio)) }
        return d
    }

    static func cableSize(forBreaker a: Int) -> Double {
        switch a {
        case ..<17: return 2.5
        case ..<26: return 4
        case ..<33: return 6
        case ..<41: return 10
        case ..<64: return 16
        case ..<81: return 25
        case ..<101: return 35
        case ..<126: return 50
        case ..<161: return 70
        default: return 95
        }
    }
}
