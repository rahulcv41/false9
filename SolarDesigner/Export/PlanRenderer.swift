import UIKit

struct PlanOptions {
    var showImage = true
    var showShade = false
    var showStrings = true
    var showDimensions = true
}

enum Draw {
    static func text(_ s: String, at p: CGPoint, size: CGFloat = 10, bold: Bool = false,
                     color: UIColor = .black, align: NSTextAlignment = .left) {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
            .foregroundColor: color, .paragraphStyle: para
        ]
        let str = s as NSString
        let sz = str.size(withAttributes: attrs)
        var origin = p
        if align == .center { origin.x -= sz.width / 2 } else if align == .right { origin.x -= sz.width }
        str.draw(at: origin, withAttributes: attrs)
    }

    static func line(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, width: CGFloat = 1, color: UIColor = .black, dash: [CGFloat]? = nil) {
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(width)
        if let d = dash { ctx.setLineDash(phase: 0, lengths: d) }
        ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        ctx.restoreGState()
    }

    static func polygon(_ ctx: CGContext, _ pts: [CGPoint], fill: UIColor?, stroke: UIColor?, width: CGFloat = 1) {
        guard let f = pts.first else { return }
        ctx.saveGState()
        ctx.move(to: f)
        for p in pts.dropFirst() { ctx.addLine(to: p) }
        ctx.closePath()
        if let fill = fill { ctx.setFillColor(fill.cgColor) }
        if let stroke = stroke { ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(width) }
        switch (fill != nil, stroke != nil) {
        case (true, true): ctx.drawPath(using: .fillStroke)
        case (true, false): ctx.fillPath()
        case (false, true): ctx.strokePath()
        default: ctx.beginPath()
        }
        ctx.restoreGState()
    }
}

/// Draws the roof, panels and obstacles to scale into `rect` (works for screen images and PDF pages).
enum PlanRenderer {
    static let stringColors: [UIColor] = [
        .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemTeal, .systemPink,
        .systemIndigo, .systemBrown, .systemMint, .systemCyan, .systemRed, .systemYellow
    ]

    static func shadeColor(_ loss: Double) -> UIColor {
        switch loss {
        case ..<0.03: return UIColor.systemGreen
        case ..<0.10: return UIColor.systemYellow
        case ..<0.25: return UIColor.systemOrange
        default: return UIColor.systemRed
        }
    }

    static func render(size: CGSize, project: Project, layout: Layout, shade: ShadeResult?,
                       image: UIImage?, options: PlanOptions) -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 2
        return UIGraphicsImageRenderer(size: size, format: f).image { rc in
            UIColor.white.setFill()
            rc.fill(CGRect(origin: .zero, size: size))
            draw(in: rc.cgContext, rect: CGRect(origin: .zero, size: size), project: project, layout: layout,
                 shade: shade, image: image, options: options)
        }
    }

    static func draw(in ctx: CGContext, rect: CGRect, project p: Project, layout: Layout, shade: ShadeResult?,
                     image: UIImage?, options: PlanOptions) {
        let roof = p.roofWorld
        guard roof.count >= 3 else {
            Draw.text("Draw the roof outline first", at: CGPoint(x: rect.midX, y: rect.midY), size: 14, color: .gray, align: .center)
            return
        }
        let b = Geo.bounds(roof)
        let margin = 0.06 * max(b.max.x - b.min.x, b.max.y - b.min.y)
        let minX = b.min.x - margin, maxX = b.max.x + margin, minY = b.min.y - margin, maxY = b.max.y + margin
        let w = maxX - minX, h = maxY - minY
        let s = min(rect.width / w, rect.height / h)
        let ox = rect.minX + (rect.width - w * s) / 2, oy = rect.minY + (rect.height - h * s) / 2
        func map(_ q: Pt) -> CGPoint { CGPoint(x: ox + (q.x - minX) * s, y: oy + (maxY - q.y) * s) }

        ctx.saveGState()
        ctx.clip(to: rect)

        if options.showImage, let img = image, p.isCalibrated {
            ctx.saveGState()
            let o = map(Pt(0, 0))
            ctx.translateBy(x: o.x, y: o.y)
            ctx.rotate(by: CGFloat(p.imageNorthBearing * .pi / 180))
            let k = CGFloat(p.metersPerPixel * s)
            ctx.scaleBy(x: k, y: k)
            ctx.setAlpha(0.85)
            img.draw(in: CGRect(x: 0, y: 0, width: p.imageWidth, height: p.imageHeight))
            ctx.restoreGState()
        }

        Draw.polygon(ctx, roof.map(map), fill: UIColor.systemGray.withAlphaComponent(options.showImage && image != nil ? 0.10 : 0.22),
                     stroke: .black, width: 1.8)

        // obstacles
        for o in p.obstacles {
            let pts = p.obstacleCorners(o).map(map)
            Draw.polygon(ctx, pts, fill: UIColor.systemRed.withAlphaComponent(0.35), stroke: .systemRed, width: 1)
            Draw.text(String(format: "%@ %.1fm", o.kind.rawValue.components(separatedBy: " ").first ?? "", o.height),
                      at: map(p.toWorld(o.centerPx)), size: 6, color: .black, align: .center)
        }

        // panels
        for (i, pn) in layout.panels.enumerated() {
            var fill = UIColor.systemBlue.withAlphaComponent(0.55)
            if options.showShade, let sh = shade, i < sh.perPanelLoss.count {
                fill = shadeColor(sh.perPanelLoss[i]).withAlphaComponent(0.7)
            } else if options.showStrings {
                fill = stringColors[pn.string % stringColors.count].withAlphaComponent(0.6)
            }
            Draw.polygon(ctx, pn.corners.map(map), fill: fill, stroke: UIColor.black.withAlphaComponent(0.7), width: 0.4)
        }

        // dimensions
        if options.showDimensions {
            for i in 0..<roof.count {
                let a = roof[i], c = roof[(i + 1) % roof.count]
                let len = hypot(c.x - a.x, c.y - a.y)
                guard len > 0.5 else { continue }
                let mid = map(Pt((a.x + c.x) / 2, (a.y + c.y) / 2))
                Draw.text(String(format: "%.1f m", len), at: CGPoint(x: mid.x, y: mid.y - 6), size: 7, bold: true,
                          color: .darkGray, align: .center)
            }
        }

        // north arrow
        let na = CGPoint(x: rect.maxX - 26, y: rect.minY + 40)
        Draw.polygon(ctx, [CGPoint(x: na.x, y: na.y - 22), CGPoint(x: na.x - 8, y: na.y + 8), CGPoint(x: na.x, y: na.y + 3), CGPoint(x: na.x + 8, y: na.y + 8)],
                     fill: .black, stroke: nil)
        Draw.text("N", at: CGPoint(x: na.x, y: na.y - 38), size: 11, bold: true, align: .center)

        // scale bar
        let candidates: [Double] = [1, 2, 5, 10, 20, 50]
        let bar = candidates.last { $0 * s <= rect.width * 0.3 } ?? 1
        let bx = rect.minX + 12, by = rect.maxY - 14
        Draw.line(ctx, CGPoint(x: bx, y: by), CGPoint(x: bx + bar * s, y: by), width: 2)
        Draw.line(ctx, CGPoint(x: bx, y: by - 4), CGPoint(x: bx, y: by + 4), width: 1.5)
        Draw.line(ctx, CGPoint(x: bx + bar * s, y: by - 4), CGPoint(x: bx + bar * s, y: by + 4), width: 1.5)
        Draw.text("\(Int(bar)) m", at: CGPoint(x: bx, y: by - 16), size: 8, bold: true)
        ctx.restoreGState()
    }
}
