import UIKit

/// Everything the exporters need, computed once.
struct DesignBundle {
    var project: Project
    var layout: Layout
    var design: SystemDesign
    var shade: ShadeResult
    var roofImage: UIImage?
    var economics: Economics

    @MainActor
    static func make(project: Project, store: ProjectStore) -> DesignBundle {
        var layout = LayoutEngine.generate(project)
        let design = SystemDesign.make(project: project, layout: &layout)
        let shade = ShadeAnalysis.run(project, layout)
        let eco = Economics(project: project, kWp: design.dcKWp, annualKWh: shade.annualKWh)
        return DesignBundle(project: project, layout: layout, design: design, shade: shade,
                            roofImage: store.image(for: project), economics: eco)
    }
}

enum ReportPDF {
    static let page = CGSize(width: 595, height: 842)   // A4 @72dpi

    static func makePDF(_ b: DesignBundle, url: URL) throws {
        let r = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: page))
        try r.writePDF(to: url) { rc in
            let p = b.project
            // ---------- Page 1: summary ----------
            rc.beginPage()
            var y = header(rc.cgContext, "Solar PV Project Report", p)
            y = section("Key results", y)
            let e = b.economics
            let rows: [(String, String)] = [
                ("System size (DC)", String(format: "%.2f kWp  (%d × %.0f Wp)", b.design.dcKWp, b.design.panelCount, p.panel.watt)),
                ("Inverter", "\(b.design.inverterCount) × \(p.inverter.name)"),
                ("Annual generation (est.)", String(format: "%.0f kWh", e.annualKWh)),
                ("Specific yield", String(format: "%.0f kWh/kWp/yr", e.specificYield)),
                ("Shading loss", String(format: "%.1f %%", b.shade.annualShadeLossPct)),
                ("Roof area / array area", String(format: "%.0f m² / %.0f m²", p.roofAreaM2, Double(b.design.panelCount) * p.panel.lengthM * p.panel.widthM)),
                ("Estimated cost", money(p, e.systemCost)),
                ("Annual savings", money(p, e.savingsPerYear)),
                ("Simple payback", e.paybackYears > 0 ? String(format: "%.1f years", e.paybackYears) : "—"),
                ("CO₂ avoided", String(format: "%.1f t / year", e.co2Tonnes))
            ]
            for (k, v) in rows { y = row(k, v, y) }
            y += 12
            y = section("Site", y)
            y = row("Location", String(format: "%.5f°, %.5f°", p.latitude, p.longitude), y)
            y = row("Address", p.address.isEmpty ? "—" : p.address, y)
            y = row("Roof type", p.roofType.rawValue, y)
            y = row("Tilt / azimuth", String(format: "%.0f° / %.0f° (180° = south)", p.tiltDeg, p.azimuthDeg), y)
            y = row("Obstacles on roof", "\(p.obstacles.count)   ·   skyline marks: \(p.horizon.count)", y)

            // ---------- Page 2: layout ----------
            rc.beginPage()
            var y2 = header(rc.cgContext, "Array layout", p)
            let plan = CGRect(x: 40, y: y2, width: page.width - 80, height: 560)
            PlanRenderer.draw(in: rc.cgContext, rect: plan, project: p, layout: b.layout, shade: nil, image: b.roofImage,
                              options: PlanOptions(showImage: true, showShade: false, showStrings: true, showDimensions: true))
            y2 = plan.maxY + 12
            Draw.text("Colours = electrical strings (\(b.design.stringCount) × \(b.design.panelsPerString) modules). Red = roof obstacles.", at: CGPoint(x: 40, y: y2), size: 9, color: .darkGray)

            // ---------- Page 3: shade & yield ----------
            rc.beginPage()
            var y3 = header(rc.cgContext, "Shade & energy analysis", p)
            y3 = section("Monthly energy (kWh)", y3)
            barChart(rc.cgContext, CGRect(x: 40, y: y3, width: page.width - 80, height: 180), b.shade)
            y3 += 195
            Draw.text(String(format: "Annual: %.0f kWh with shading, %.0f kWh without (%.1f %% loss). Clear-sky model × %.2f clearness × %.2f PR.",
                             b.shade.annualKWh, b.shade.annualKWhNoShade, b.shade.annualShadeLossPct, p.clearnessFactor, p.performanceRatio),
                      at: CGPoint(x: 40, y: y3), size: 9, color: .darkGray)
            y3 += 24
            y3 = section("Shade by panel", y3)
            let plan3 = CGRect(x: 40, y: y3, width: page.width - 80, height: 300)
            PlanRenderer.draw(in: rc.cgContext, rect: plan3, project: p, layout: b.layout, shade: b.shade, image: b.roofImage,
                              options: PlanOptions(showImage: false, showShade: true, showStrings: false, showDimensions: false))
            Draw.text("Green < 3 %   Yellow < 10 %   Orange < 25 %   Red ≥ 25 % annual beam loss", at: CGPoint(x: 40, y: plan3.maxY + 6), size: 9, color: .darkGray)

            // ---------- Page 4: design & BoM ----------
            rc.beginPage()
            var y4 = header(rc.cgContext, "System design & bill of materials", p)
            let d = b.design
            y4 = section("Electrical design", y4)
            y4 = row("Strings", "\(d.stringCount) × \(d.panelsPerString) modules in series (limits \(d.minPerString)–\(d.maxPerString))", y4)
            y4 = row("String Voc (cold) / Vmp", String(format: "%.0f V / %.0f V", d.stringVoc, d.stringVmp), y4)
            y4 = row("AC output per inverter", String(format: "%.1f A → %d A MCB, %g mm² Cu", d.acCurrentPerInverter, d.acBreakerA, d.acCableMM2), y4)
            for w in d.warnings { y4 = row("⚠︎ Warning", w, y4) }
            y4 += 12
            y4 = section("Indicative bill of materials", y4)
            let stringRun = 25.0, acRun = 20.0
            let bom: [(String, String)] = [
                ("PV modules — \(p.panel.name)", "\(d.panelCount) nos"),
                ("Solar inverter — \(p.inverter.name)", "\(d.inverterCount) nos"),
                ("Mounting structure (GI/Al, \(Int(p.tiltDeg))° tilt)", String(format: "%.0f kWp", d.dcKWp)),
                ("DC cable 4 mm² PV1-F", String(format: "%.0f m", Double(d.stringCount) * stringRun * 2)),
                ("AC cable \(String(format: "%g", d.acCableMM2)) mm² Cu", String(format: "%.0f m", Double(d.inverterCount) * acRun)),
                ("DCDB (isolator, SPD, fuses)", "\(d.inverterCount) nos"),
                ("ACDB (MCB, RCCB, SPD)", "\(d.inverterCount) nos"),
                ("Earthing kit + lightning arrestor", "1 set"),
                ("Net meter", "1 no")
            ]
            for (k, v) in bom { y4 = row(k, v, y4) }
            y4 += 20
            y4 = section("Assumptions & disclaimer", y4)
            let notes = """
            • Yield uses a clear-sky model (Meinel air-mass) scaled by a clearness factor; replace with measured irradiation data (e.g. PVGIS / Meteonorm) for bankable numbers.
            • Shading uses the surveyed skyline and roof obstacle shadows sampled at 5 points per panel; partial-shading electrical mismatch is not modelled.
            • Roof geometry comes from a satellite/map image and a scale calibration — verify dimensions on site.
            • Electrical sizing (strings, breakers, cables) is indicative and must be verified by a licensed engineer against local code and utility requirements.
            """
            (notes as NSString).draw(in: CGRect(x: 40, y: y4, width: page.width - 80, height: 200),
                                     withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
        }
    }

    // MARK: helpers

    private static func money(_ p: Project, _ v: Double) -> String {
        "\(p.currency) " + NumberFormatter.localizedString(from: NSNumber(value: v.rounded()), number: .decimal)
    }

    private static func header(_ ctx: CGContext, _ title: String, _ p: Project) -> CGFloat {
        UIColor.systemOrange.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: page.width, height: 8))
        Draw.text(title, at: CGPoint(x: 40, y: 28), size: 22, bold: true)
        Draw.text("\(p.name)  ·  \(p.client.isEmpty ? "—" : p.client)  ·  \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none))",
                  at: CGPoint(x: 40, y: 58), size: 10, color: .darkGray)
        Draw.line(ctx, CGPoint(x: 40, y: 78), CGPoint(x: page.width - 40, y: 78), width: 0.8, color: .lightGray)
        return 92
    }

    private static func section(_ t: String, _ y: CGFloat) -> CGFloat {
        Draw.text(t, at: CGPoint(x: 40, y: y), size: 13, bold: true, color: .systemOrange)
        return y + 22
    }

    private static func row(_ k: String, _ v: String, _ y: CGFloat) -> CGFloat {
        Draw.text(k, at: CGPoint(x: 40, y: y), size: 10, bold: true)
        let rect = CGRect(x: 230, y: y, width: page.width - 270, height: 40)
        (v as NSString).draw(in: rect, withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.black])
        let lines = max(1, Int(ceil(Double(v.count) / 62)))
        return y + CGFloat(lines) * 13 + 3
    }

    private static func barChart(_ ctx: CGContext, _ r: CGRect, _ s: ShadeResult) {
        let maxV = max(1, s.monthlyKWhNoShade.max() ?? 1)
        let bw = r.width / 12
        Draw.line(ctx, CGPoint(x: r.minX, y: r.maxY - 16), CGPoint(x: r.maxX, y: r.maxY - 16), width: 0.8, color: .gray)
        for m in 0..<12 {
            let hFull = CGFloat(s.monthlyKWhNoShade[m] / maxV) * (r.height - 34)
            let hShade = CGFloat(s.monthlyKWh[m] / maxV) * (r.height - 34)
            let x = r.minX + CGFloat(m) * bw + 4
            UIColor.systemGray4.setFill()
            ctx.fill(CGRect(x: x, y: r.maxY - 16 - hFull, width: bw - 8, height: hFull))
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: x, y: r.maxY - 16 - hShade, width: bw - 8, height: hShade))
            Draw.text(Solar.monthNames[m], at: CGPoint(x: x + (bw - 8) / 2, y: r.maxY - 13), size: 8, align: .center)
            Draw.text(String(format: "%.0f", s.monthlyKWh[m]), at: CGPoint(x: x + (bw - 8) / 2, y: r.maxY - 28 - hFull), size: 7, color: .darkGray, align: .center)
        }
    }
}

enum LayoutDrawingPDF {
    static let size = CGSize(width: 1191, height: 842)

    static func makePDF(_ b: DesignBundle, url: URL) throws {
        let r = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        try r.writePDF(to: url) { rc in
            rc.beginPage()
            let ctx = rc.cgContext, p = b.project
            Draw.polygon(ctx, [CGPoint(x: 15, y: 15), CGPoint(x: size.width - 15, y: 15), CGPoint(x: size.width - 15, y: size.height - 15), CGPoint(x: 15, y: size.height - 15)],
                         fill: nil, stroke: .black, width: 2)
            Draw.text("ROOFTOP SOLAR PV LAYOUT PLAN — \(String(format: "%.2f", b.design.dcKWp)) kWp", at: CGPoint(x: size.width / 2, y: 26), size: 16, bold: true, align: .center)
            PlanRenderer.draw(in: ctx, rect: CGRect(x: 30, y: 55, width: size.width - 330, height: size.height - 160),
                              project: p, layout: b.layout, shade: nil, image: b.roofImage,
                              options: PlanOptions(showImage: true, showShade: false, showStrings: true, showDimensions: true))
            // legend / schedule
            let lx = size.width - 285
            Draw.text("SCHEDULE", at: CGPoint(x: lx, y: 70), size: 11, bold: true)
            let rows = [
                ("Modules", "\(b.design.panelCount) × \(Int(p.panel.watt)) Wp"),
                ("DC capacity", String(format: "%.2f kWp", b.design.dcKWp)),
                ("Strings", "\(b.design.stringCount) × \(b.design.panelsPerString)"),
                ("Tilt", String(format: "%.0f°", p.tiltDeg)),
                ("Azimuth", String(format: "%.0f°", p.azimuthDeg)),
                ("Row pitch", String(format: "%.2f m", b.layout.rowPitch)),
                ("Edge setback", String(format: "%.2f m", p.setbackM)),
                ("Roof area", String(format: "%.0f m²", p.roofAreaM2)),
                ("Obstacles", "\(p.obstacles.count)")
            ]
            for (i, rw) in rows.enumerated() {
                Draw.text(rw.0, at: CGPoint(x: lx, y: 92 + CGFloat(i) * 15), size: 9, bold: true)
                Draw.text(rw.1, at: CGPoint(x: lx + 95, y: 92 + CGFloat(i) * 15), size: 9)
            }
            Draw.text("STRINGS", at: CGPoint(x: lx, y: 250), size: 11, bold: true)
            for i in 0..<min(b.design.stringCount, 14) {
                let col = PlanRenderer.stringColors[i % PlanRenderer.stringColors.count].withAlphaComponent(0.6)
                Draw.polygon(ctx, [CGPoint(x: lx, y: 272 + CGFloat(i) * 15), CGPoint(x: lx + 14, y: 272 + CGFloat(i) * 15), CGPoint(x: lx + 14, y: 282 + CGFloat(i) * 15), CGPoint(x: lx, y: 282 + CGFloat(i) * 15)], fill: col, stroke: .black, width: 0.5)
                Draw.text("String \(i + 1)", at: CGPoint(x: lx + 22, y: 271 + CGFloat(i) * 15), size: 9)
            }
            let tb = CGRect(x: size.width - 345, y: size.height - 95, width: 330, height: 80)
            Draw.polygon(ctx, [CGPoint(x: tb.minX, y: tb.minY), CGPoint(x: tb.maxX, y: tb.minY), CGPoint(x: tb.maxX, y: tb.maxY), CGPoint(x: tb.minX, y: tb.maxY)], fill: nil, stroke: .black, width: 1.5)
            Draw.text("PROJECT: \(p.name)", at: CGPoint(x: tb.minX + 8, y: tb.minY + 8), size: 10, bold: true)
            Draw.text("CLIENT: \(p.client)", at: CGPoint(x: tb.minX + 8, y: tb.minY + 25), size: 9)
            Draw.text("SITE: \(p.address)", at: CGPoint(x: tb.minX + 8, y: tb.minY + 40), size: 9)
            Draw.text("DWG: LAY-01   DATE: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none))", at: CGPoint(x: tb.minX + 8, y: tb.minY + 56), size: 8)
        }
    }
}
