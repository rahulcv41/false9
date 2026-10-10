import UIKit

/// Single-line diagram (A3 landscape) generated from the system design.
enum SLDRenderer {
    static let pageSize = CGSize(width: 1191, height: 842)

    static func makePDF(project p: Project, design d: SystemDesign, url: URL) throws {
        let r = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        try r.writePDF(to: url) { rc in
            rc.beginPage()
            draw(in: rc.cgContext, project: p, design: d)
        }
    }

    static func render(project p: Project, design d: SystemDesign) -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 2
        return UIGraphicsImageRenderer(size: pageSize, format: f).image { rc in
            UIColor.white.setFill(); rc.fill(CGRect(origin: .zero, size: pageSize))
            draw(in: rc.cgContext, project: p, design: d)
        }
    }

    private static func box(_ ctx: CGContext, _ r: CGRect, _ title: String, _ lines: [String] = [], fill: UIColor = .white) {
        Draw.polygon(ctx, [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)],
                     fill: fill, stroke: .black, width: 1.4)
        Draw.text(title, at: CGPoint(x: r.midX, y: r.minY + 5), size: 9, bold: true, align: .center)
        for (i, l) in lines.enumerated() {
            Draw.text(l, at: CGPoint(x: r.midX, y: r.minY + 19 + CGFloat(i) * 11), size: 8, align: .center)
        }
    }

    static func draw(in ctx: CGContext, project p: Project, design d: SystemDesign) {
        let W = pageSize.width, H = pageSize.height
        Draw.polygon(ctx, [CGPoint(x: 15, y: 15), CGPoint(x: W - 15, y: 15), CGPoint(x: W - 15, y: H - 15), CGPoint(x: 15, y: H - 15)],
                     fill: nil, stroke: .black, width: 2)
        Draw.text("SINGLE LINE DIAGRAM — \(String(format: "%.2f", d.dcKWp)) kWp GRID-TIED SOLAR PV SYSTEM", at: CGPoint(x: W / 2, y: 28), size: 16, bold: true, align: .center)

        // ---- PV strings (left) ----
        let shown = min(d.stringCount, 4)
        let stringW: CGFloat = 150, stringH: CGFloat = 52
        let x0: CGFloat = 50
        let top: CGFloat = 110
        let gapY: CGFloat = 78
        let perInv = max(1, d.stringsPerInverter)
        Draw.text("PV ARRAY (per inverter: \(perInv) string\(perInv == 1 ? "" : "s"))", at: CGPoint(x: x0, y: 80), size: 10, bold: true)
        var ys: [CGFloat] = []
        for i in 0..<max(shown, 1) {
            let y = top + CGFloat(i) * gapY
            ys.append(y + stringH / 2)
            box(ctx, CGRect(x: x0, y: y, width: stringW, height: stringH), "STRING \(i + 1)",
                ["\(d.panelsPerString) × \(Int(p.panel.watt)) Wp", String(format: "Voc %.0f V · Isc %.1f A", d.stringVoc, d.stringIsc)],
                fill: UIColor.systemBlue.withAlphaComponent(0.12))
        }
        if d.stringCount > shown {
            Draw.text("… +\(d.stringCount - shown) more strings (identical)", at: CGPoint(x: x0, y: top + CGFloat(shown) * gapY - 8), size: 9)
        }

        // ---- DCDB ----
        let dcdb = CGRect(x: 300, y: top - 10, width: 170, height: CGFloat(max(shown, 1)) * gapY + 20)
        box(ctx, dcdb, "DCDB", ["DC isolator \(Int((d.stringVoc * 1.1 / 50).rounded(.up)) * 50) V / \(Int(d.stringIsc * 1.25 + 1)) A", "String fuse / MCB", "Type-2 DC SPD", ""])
        for y in ys {
            Draw.line(ctx, CGPoint(x: x0 + stringW, y: y), CGPoint(x: dcdb.minX, y: y), width: 1.6, color: .systemRed)
            Draw.text("+ −  \(d.dcCableMM2 == 4 ? "4" : String(d.dcCableMM2)) mm² PV1-F", at: CGPoint(x: (x0 + stringW + dcdb.minX) / 2, y: y - 12), size: 7, align: .center)
        }

        // ---- Inverter ----
        let inv = CGRect(x: 560, y: dcdb.midY - 55, width: 170, height: 110)
        let invMid = CGPoint(x: dcdb.maxX, y: dcdb.midY)
        Draw.line(ctx, invMid, CGPoint(x: inv.minX, y: inv.midY), width: 1.8, color: .systemRed)
        Draw.text("DC", at: CGPoint(x: (invMid.x + inv.minX) / 2, y: inv.midY - 14), size: 8, bold: true, align: .center)
        box(ctx, inv, "SOLAR INVERTER", [p.inverter.name, String(format: "%.0f kW AC · %@", p.inverter.acKW, p.inverter.threePhase ? "3-ph" : "1-ph"),
                                          "MPPT \(Int(p.inverter.mpptMin))–\(Int(p.inverter.mpptMax)) V", "Qty: \(d.inverterCount)"],
            fill: UIColor.systemYellow.withAlphaComponent(0.25))

        // ---- ACDB ----
        let acdb = CGRect(x: 820, y: inv.midY - 55, width: 150, height: 110)
        Draw.line(ctx, CGPoint(x: inv.maxX, y: inv.midY), CGPoint(x: acdb.minX, y: acdb.midY), width: 1.8, color: .systemBlue)
        Draw.text("\(String(format: "%g", d.acCableMM2)) mm² Cu · \(p.inverter.threePhase ? "4C" : "2C")", at: CGPoint(x: (inv.maxX + acdb.minX) / 2, y: inv.midY - 16), size: 7, align: .center)
        box(ctx, acdb, "ACDB", ["MCB \(d.acBreakerA) A \(p.inverter.threePhase ? "4P" : "2P")", "RCCB 30 mA", "AC SPD", "Isolator"])

        // ---- Meter / grid ----
        let meter = CGRect(x: 1030, y: acdb.midY - 55, width: 120, height: 50)
        Draw.line(ctx, CGPoint(x: acdb.maxX, y: acdb.midY), CGPoint(x: meter.minX, y: acdb.midY - 30), width: 1.8, color: .systemBlue)
        box(ctx, meter, "NET METER", ["Bi-directional"])
        let grid = CGRect(x: 1030, y: acdb.midY + 15, width: 120, height: 50)
        Draw.line(ctx, CGPoint(x: meter.midX, y: meter.maxY), CGPoint(x: grid.midX, y: grid.minY), width: 1.8, color: .systemBlue)
        box(ctx, grid, "LT PANEL / GRID", [p.inverter.threePhase ? "415 V 3-ph" : "230 V 1-ph"], fill: UIColor.systemGray5)

        // ---- Earthing ----
        let ey = dcdb.maxY + 70
        Draw.line(ctx, CGPoint(x: 60, y: ey), CGPoint(x: 1000, y: ey), width: 1.6, color: .systemGreen, dash: [6, 3])
        Draw.text("EARTHING BUS — structure, DCDB, inverter, ACDB  (GI/Cu strip to 2 × earth pits; separate LA earth)", at: CGPoint(x: 60, y: ey + 6), size: 9, color: .systemGreen)
        for x in [dcdb.midX, inv.midX, acdb.midX] {
            Draw.line(ctx, CGPoint(x: x, y: (x == dcdb.midX ? dcdb.maxY : (x == inv.midX ? inv.maxY : acdb.maxY))), CGPoint(x: x, y: ey), width: 1.2, color: .systemGreen, dash: [4, 3])
        }

        // ---- Design data table ----
        let tx: CGFloat = 50, ty = ey + 40
        Draw.text("DESIGN DATA", at: CGPoint(x: tx, y: ty), size: 11, bold: true)
        let rows = [
            ("PV modules", "\(d.panelCount) × \(p.panel.name) (\(Int(p.panel.watt)) Wp)"),
            ("DC capacity", String(format: "%.2f kWp", d.dcKWp)),
            ("Strings", "\(d.stringCount) × \(d.panelsPerString) modules  (allowed \(d.minPerString)–\(d.maxPerString))"),
            ("String Voc (cold) / Vmp", String(format: "%.0f V / %.0f V", d.stringVoc, d.stringVmp)),
            ("Inverters", "\(d.inverterCount) × \(p.inverter.name)"),
            ("AC capacity", String(format: "%.1f kW, %.1f A per inverter", d.acKWTotal, d.acCurrentPerInverter)),
            ("Tilt / azimuth", String(format: "%.0f° / %.0f°", p.tiltDeg, p.azimuthDeg))
        ]
        for (i, r) in rows.enumerated() {
            Draw.text(r.0, at: CGPoint(x: tx, y: ty + 20 + CGFloat(i) * 14), size: 9, bold: true)
            Draw.text(r.1, at: CGPoint(x: tx + 160, y: ty + 20 + CGFloat(i) * 14), size: 9)
        }
        if !d.warnings.isEmpty {
            for (i, w) in d.warnings.enumerated() {
                Draw.text("⚠︎ " + w, at: CGPoint(x: 560, y: ty + 20 + CGFloat(i) * 14), size: 9, color: .systemRed)
            }
        }

        // ---- Title block ----
        let tb = CGRect(x: W - 345, y: H - 105, width: 330, height: 90)
        Draw.polygon(ctx, [CGPoint(x: tb.minX, y: tb.minY), CGPoint(x: tb.maxX, y: tb.minY), CGPoint(x: tb.maxX, y: tb.maxY), CGPoint(x: tb.minX, y: tb.maxY)], fill: nil, stroke: .black, width: 1.5)
        Draw.text("PROJECT: \(p.name)", at: CGPoint(x: tb.minX + 8, y: tb.minY + 8), size: 10, bold: true)
        Draw.text("CLIENT: \(p.client)", at: CGPoint(x: tb.minX + 8, y: tb.minY + 24), size: 9)
        Draw.text("SITE: \(p.address)", at: CGPoint(x: tb.minX + 8, y: tb.minY + 38), size: 9)
        Draw.text(String(format: "LAT/LON: %.5f, %.5f", p.latitude, p.longitude), at: CGPoint(x: tb.minX + 8, y: tb.minY + 52), size: 9)
        Draw.text("DATE: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none))   DWG: SLD-01   NOT TO SCALE", at: CGPoint(x: tb.minX + 8, y: tb.minY + 68), size: 8)
        Draw.text("Indicative design — verify with a licensed engineer & local utility rules before construction.", at: CGPoint(x: 50, y: H - 32), size: 8, color: .gray)
    }
}
